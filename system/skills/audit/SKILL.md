---
name: audit
description: "Security scan — secrets in CLAUDE.md, hook permissions, MCP count, dangerous settings, unencrypted .env, acquired skill safety. 6 checks, fast, zero dependencies. Run periodically or before sharing config."
effort: low
keywords: [security, audit, secrets, hooks, permissions, mcp]
task_strategies: [investigation]
stream_affinity: [tech-debt]
group: brana
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
status: experimental
growth_stage: seed
---

# Audit — Security Scanner

6-check lightweight security scanner for brana harness configurations. Catches secrets, permission issues, token tax, and unsafe acquired skills before they cause problems.

## Usage

```
/brana:audit              — run all 6 checks on current project
/brana:audit --global     — also scan ~/.claude/ global config
```

## Checks

### Check 1: Secrets in config files

Scan CLAUDE.md, rules/, and skill frontmatter for leaked secrets.

**Patterns** (14 regexes from AgentShield):

```
# API keys and tokens
(sk|pk|api|key|token|secret|password|credential|auth)[-_]?[A-Za-z0-9]{16,}
(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}
AKIA[0-9A-Z]{16}
(xox[bpas]-[A-Za-z0-9-]{10,})
(sk-[A-Za-z0-9]{20,})
Bearer\s+[A-Za-z0-9\-._~+/]+=*
Basic\s+[A-Za-z0-9+/]+=+
-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----
(postgres|mysql|mongodb)://[^\s]+:[^\s]+@
(ANTHROPIC|OPENAI|STRIPE|GITHUB|AWS)_[A-Z_]*KEY[=:]\s*\S+
```

**Files to scan:**
- `CLAUDE.md`, `.claude/CLAUDE.md`
- `~/.claude/CLAUDE.md` (if --global)
- `~/.claude/rules/*.md` (if --global)
- `system/skills/*/SKILL.md`
- `system/hooks/*.sh`
- `system/agents/*.md`

**Action:** For each match, report the file, line number, and which pattern matched. Redact the actual value (show first 4 chars + `***`).

### Check 2: Hook permission escalation

Scan hook scripts for commands that modify permissions on non-hook files.

```bash
grep -rn "chmod\|chown\|setfacl" system/hooks/*.sh
```

**Flag if:**
- `chmod +x` targets any file outside `system/hooks/`
- `chmod 777` anywhere
- `chown` to root or another user

**Acceptable:** `chmod +x` on files within `system/hooks/` (hooks need to be executable).

### Check 3: MCP server count (token tax)

Count active MCP servers. Each server adds 4-17K tokens to every session.

```bash
# Check settings.json for mcpServers
jq '.mcpServers | length' ~/.claude/settings.json 2>/dev/null
# Check project settings
jq '.mcpServers | length' .claude/settings.local.json 2>/dev/null
```

**Traffic light:**
- **Green:** 0-5 servers
- **Yellow:** 6-10 servers (warn: "~60-170K tokens/session overhead")
- **Red:** 11+ servers (warn: "Consider disabling unused servers")

List each server with name and estimate token impact.

### Check 4: Dangerous mode settings

Check if `skipDangerousModePermissionPrompt` is enabled.

```bash
jq '.skipDangerousModePermissionPrompt' ~/.claude/settings.json 2>/dev/null
```

**Flag if true:** "Dangerous mode prompt is disabled. All tool calls execute without confirmation. This is convenient but removes a safety net for destructive operations (rm -rf, git push --force, etc.)."

**Also check:**
- `defaultMode` in permissions — warn if set to `"bypassPermissions"` or `"dangerouslyDisableSandbox"`
- `deny` list — report if empty (no deny rules configured)

### Check 5: Unencrypted credentials

Scan for `.env` files and credential files that should not be in git.

```bash
# Find .env files not in .gitignore
find . -name ".env*" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null
# Check if they're gitignored
git check-ignore -v .env .env.local .env.production 2>/dev/null
# Check for common credential files
find . -name "credentials.json" -o -name "service-account*.json" -o -name "*.pem" -o -name "*.key" 2>/dev/null
```

**Flag if:**
- Any `.env` file exists AND is not gitignored
- Any credential file exists AND is not gitignored
- `.env` files contain actual values (not just variable names)

### Check 6: Incoming skill scan

Scan `system/skills/acquired/*/SKILL.md` for third-party or incoming skills and flag safety concerns.

**Discovery:**

```bash
# Find all acquired skills
ls -d system/skills/acquired/*/SKILL.md 2>/dev/null
```

For each acquired skill found, run four sub-checks:

**6a — Dangerous Bash access (CRITICAL)**

Scan the skill's SKILL.md (frontmatter + body) for dangerous tool grants:

| Pattern | Severity | Why |
|---------|----------|-----|
| `Bash` with no command restriction | CRITICAL | Unrestricted shell — can do anything |
| `Bash(rm:*)` | CRITICAL | Arbitrary file deletion |
| `Bash(curl:*)` | CRITICAL | Arbitrary network access / exfiltration |
| `Bash(eval:*)` | CRITICAL | Arbitrary code execution |

Flag if `allowed-tools` contains bare `Bash` (not scoped like `Bash(git:*)`) or any of the dangerous patterns above.

**6b — Credential path references (WARNING)**

Grep the full SKILL.md content for references to sensitive paths or tokens:

```
~/.claude/settings.json
~/.env
credentials
secret
token
\.pem
\.key
```

Flag each match with the line number and surrounding context (redact any actual values).

**6c — Unknown MCP tool requests (WARNING)**

Scan `allowed-tools` for any `mcp__*` tool references. Compare against the known-safe list:

```
mcp__ruflo__memory_*
mcp__ruflo__agentdb_*
mcp__google-sheets__*
mcp__context7__*
```

Flag any `mcp__` tool that does not match a known-safe prefix.

**6d — Missing frontmatter (WARNING)**

Check that the YAML frontmatter contains these required fields:
- `name`
- `description`
- `allowed-tools`

Flag each missing field. A skill with no `allowed-tools` declaration is especially suspect — it may inherit broad defaults.

**Report per skill:**

```
skill-name/
  [CRITICAL] Unrestricted Bash access in allowed-tools
  [CRITICAL] Bash(curl:*) — arbitrary network access
  [WARNING]  References ~/.claude/settings.json on line 42
  [WARNING]  Missing frontmatter field: description
  [OK]       No unknown MCP tools
```

If `system/skills/acquired/` does not exist or is empty, report "No acquired skills found — check passed."

## Report

```markdown
## Security Audit — YYYY-MM-DD

| # | Check | Status | Findings |
|---|-------|--------|----------|
| 1 | Secrets in config | {pass/N findings} | {summary} |
| 2 | Hook permissions | {pass/N findings} | {summary} |
| 3 | MCP token tax | {green/yellow/red} | {N servers, ~NK tokens} |
| 4 | Dangerous settings | {pass/warn} | {summary} |
| 5 | Unencrypted creds | {pass/N findings} | {summary} |
| 6 | Incoming skill scan | {pass/N findings} | {summary} |

### Details
{per-finding details with file:line and remediation}

### Recommendations
{ordered by severity}
```

## Rules

1. **Never print secrets.** Redact to first 4 chars + `***`. Report the pattern and location, not the value.
2. **6 checks only.** Don't scope-creep. Add new checks as explicit expansions.
3. **No auto-fix.** Report findings, let the user decide what to do.
4. **Fast.** All checks should complete in under 30 seconds. No network calls.
5. **Run periodically.** Recommend running before sharing configs, after adding MCP servers, or monthly.
