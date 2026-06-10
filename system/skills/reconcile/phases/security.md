<!-- reconcile phase: Security scope: secrets, permissions, MCP tax, acquired-skill safety — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Security Domain (`--scope security`)

8 checks absorbed from `/brana:audit`. Fast, zero dependencies. Pass `--cvelist` to append a CVE status table.

### SEC-1: Secrets in config files

Scan CLAUDE.md, rules/, skill frontmatter, hook scripts, agent definitions for leaked secrets.

**Patterns** (16 regexes — includes CVE-2025-55284 exfiltration patterns):
```
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
# CVE-2025-55284: command chaining for credential exfiltration via network tools
(curl|wget|nc|ncat|socat)\s+.*\$\{?(API_KEY|TOKEN|PASSWORD|SECRET|BEARER|AUTH)\}?
(curl|wget)\s+.*--data.*\$\{?(API_KEY|TOKEN|PASSWORD|SECRET)\}?
# CVE-2025-55284: DNS-based exfiltration (encoding data in subdomain queries)
(nslookup|dig|host)\s+.*\$\{?(API_KEY|TOKEN|SECRET|PASSWORD)\}?
# Overly broad allowedTools that enables CVE-2025-55284 class bypass
"allowedTools"\s*:\s*\[.*"Bash".*\]
allowedTools.*\*
```

**Files:** `CLAUDE.md`, `.claude/CLAUDE.md`, `~/.claude/CLAUDE.md` (if --global), `~/.claude/rules/*.md`, `system/skills/*/SKILL.md`, `system/hooks/*.sh`, `system/agents/*.md`.

Report: file, line number, pattern matched. Redact values (first 4 chars + `***`).

### SEC-2: Hook permission escalation

```bash
grep -rn "chmod\|chown\|setfacl" system/hooks/*.sh
```

Flag: `chmod +x` outside `system/hooks/`, `chmod 777` anywhere, `chown` to root.

### SEC-3: MCP server count (token tax)

Count MCP servers in settings.json. Each adds 4-17K tokens/session. Flag if >5 servers active.

### SEC-4: Dangerous settings

Check `settings.json` for: `bypassPermissions: true`, `dangerouslyDisableSandbox: true`, `allowedTools: ["*"]`. Flag each with severity.

### SEC-5: Unencrypted credential files

```bash
find . -name ".env" -o -name "credentials.json" -o -name "*.pem" -o -name "*.key" 2>/dev/null
```

Flag any found outside `.gitignore`.

### SEC-6: Acquired skill safety

Scan `system/skills/` for skills not in the core set (compare against git-tracked skill list). For acquired skills, check: allowed-tools list for dangerous tools (Bash with no constraints), external URLs in skill body, hook registration.

### SEC-7: ADR-033 violations in `~/.claude.json`

**Automated:** `config-drift.sh` already checks this at every session start and surfaces violations in `DRIFT_CONTEXT`. If the session-start hook reported `[ADR-033]` warnings, they will appear here.

**Manual sweep:** If you want to inspect directly:
```bash
jq -r '
  (.mcpServers // {} | to_entries[] | select(.value.command // "" | test("npx|uvx")) | "top: \(.key): \(.value.command)"),
  (.projects // {} | to_entries[] | .key as $p | (.value.mcpServers // {}) | to_entries[] | select(.value.command // "" | test("npx|uvx")) | "project \($p): \(.key): \(.value.command)")
' ~/.claude.json
```

Fix: pin each flagged server to its installed binary path (see ADR-033).

### SEC-8: PreToolUse hook enforcement (McAllister Phase 2)

Verify that the spec-before-code gate (pre-tool-use.sh) is properly wired and functional. This is the McAllister Phase 2 "Pre-Execution Gate" check.

**Step 1 — Hook exists and is executable:**
```bash
ls -la system/hooks/pre-tool-use.sh
```
Flag CRITICAL if missing or not executable.

**Step 2 — Hook is wired in hooks.json under PreToolUse Write|Edit:**
```bash
jq '.hooks.PreToolUse[] | select(.matcher == "Write|Edit") | .hooks[].command' \
    system/hooks/hooks.json
```
Flag CRITICAL if `pre-tool-use.sh` is absent from the PreToolUse Write|Edit entry.

**Step 3 — Hook contains deny gate (not a pass-through stub):**
```bash
grep -n '"permissionDecision": "deny"' system/hooks/pre-tool-use.sh
```
Flag WARNING if the deny pattern is absent — the hook exists but doesn't enforce.

**Step 4 — system/* pass-through present (prevents false-positive blocks on brana system files):**
```bash
grep -n 'system/\*' system/hooks/pre-tool-use.sh
```
Flag INFO if absent — hook will prompt on system/ file edits.

**Step 5 — Hook fires on correct events (not too broad, not too narrow):**
Check `hooks.json` PreToolUse matcher is `"Write|Edit"` (not `""` which would fire on all tool calls).

### SEC-CVE: Known CVE status (`--cvelist` flag)

Only run when `--cvelist` is in ARGUMENTS.

Query the CC version: `claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'`

Report status of known Claude Code CVEs:

| CVE | Severity | Description | Fixed in | Status |
|-----|----------|-------------|----------|--------|
| CVE-2025-55284 | CVSS 7.1 | Command injection / DNS exfiltration via broad allowedTools bypass | 1.0.4 | Check version |
| CVE-2025-59536 | High | Hooks RCE — arbitrary code execution via malicious hook scripts | 1.0.111 | Check version |

For each CVE: compare current version to "Fixed in" — mark PATCHED or VULNERABLE. If version detection fails, mark UNKNOWN.

### SEC-REPORT

Present findings grouped by severity (CRITICAL / WARNING / INFO). No auto-fix — security issues require human judgment.

If `--cvelist` was passed, append the CVE status table from SEC-CVE after the findings.

---

