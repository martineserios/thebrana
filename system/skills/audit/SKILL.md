---
name: audit
description: "Security scan — secrets in CLAUDE.md, hook permissions, MCP count, dangerous settings, unencrypted .env. 5 checks, fast, zero dependencies. Run periodically or before sharing config."
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

5-check lightweight security scanner for brana harness configurations. Catches secrets, permission issues, and token tax before they cause problems.

## Usage

```
/brana:audit              — run all 5 checks on current project
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

### Details
{per-finding details with file:line and remediation}

### Recommendations
{ordered by severity}
```

## Rules

1. **Never print secrets.** Redact to first 4 chars + `***`. Report the pattern and location, not the value.
2. **5 checks only.** Don't scope-creep. Add new checks as explicit expansions.
3. **No auto-fix.** Report findings, let the user decide what to do.
4. **Fast.** All checks should complete in under 30 seconds. No network calls.
5. **Run periodically.** Recommend running before sharing configs, after adding MCP servers, or monthly.
