#!/usr/bin/env bash
# No strict mode — hooks must never fail and block the session.

# Brana PreToolUse hook — Bash command risk classification (t-1112).
# Complements CC's native permission system with brana-specific context.
# Does NOT block — adds additionalContext with risk tier and reason so the
# model and user get a richer signal than CC's generic "approve?" prompt.
#
# Risk tiers:
#   T2 (risky)    — additionalContext warning, proceed after explicit confirmation
#   T3 (critical) — additionalContext critical alert for catastrophic patterns
#
# Input:  stdin JSON (session_id, tool_name, tool_input)
# Output: {"continue": true} or {"continue": true, "additionalContext": "..."}

cd /tmp 2>/dev/null || true

INPUT=$(cat) || true

pass_through() {
    echo '{"continue": true}'
    exit 0
}

command -v jq &>/dev/null || pass_through

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
[ "${TOOL_NAME:-}" != "Bash" ] && pass_through

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -z "$COMMAND" ] && pass_through

# ── T3: Critical — catastrophic-impact patterns ───────────────────
# These patterns can cause irreversible data loss at system scale.

TIER=0
RISK_REASON=""

# rm -rf targeting exactly / or ~/ or /* (not /some/path — those are T2)
# Match: "rm -rf /" or "rm -rf ~/" or "rm -rf /*" at end of token
if echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr)\s+(\/\s*$|~\/?\s*$|\/\*\s*$)' 2>/dev/null || \
   echo "$COMMAND" | grep -qE 'rm\s+--recursive\s+--force\s+(\/\s*$|~\/?\s*$|\/\*\s*$)' 2>/dev/null; then
    TIER=3
    RISK_REASON="CRITICAL: rm -rf targeting root (/) or home (~/) — catastrophic data loss"

# dd targeting physical disk (/dev/sd*, /dev/nvme*)
elif echo "$COMMAND" | grep -qE 'dd\s.*of=/dev/(sd|nvme|hd|mmcblk)' 2>/dev/null; then
    TIER=3
    RISK_REASON="CRITICAL: dd targeting physical disk device — data loss risk"

# ── T2: Risky — significant but recoverable impact ────────────────

# git push --force (outside of main-guard which covers main/master staging)
elif echo "$COMMAND" | grep -qE 'git\s+push\s+(--force|-f)' 2>/dev/null; then
    TIER=2
    RISK_REASON="RISKY: git push --force rewrites remote history. Confirm target branch and that no collaborators are affected."

# sudo rm (any sudo-escalated removal)
elif echo "$COMMAND" | grep -qE 'sudo\s+rm\b' 2>/dev/null; then
    TIER=2
    RISK_REASON="RISKY: sudo rm — elevated permissions for file deletion. Verify target paths."

# Writes to system directories (/etc, /usr, /bin, /sbin, /lib, /boot)
elif echo "$COMMAND" | grep -qE '(>|>>|tee|cp\s|mv\s|install\s|ln\s).*\/(etc|usr|bin|sbin|lib|boot)\/' 2>/dev/null; then
    TIER=2
    RISK_REASON="RISKY: writing to system directory ($(echo "$COMMAND" | grep -oE '\/(etc|usr|bin|sbin|lib|boot)\/[^\s]*' | head -1)). Requires sudo and may break system packages."

# SQL destructive DDL (DROP TABLE, DROP DATABASE, TRUNCATE)
elif echo "$COMMAND" | grep -iqE '(DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE)' 2>/dev/null; then
    TIER=2
    RISK_REASON="RISKY: destructive SQL DDL detected (DROP/TRUNCATE). Verify you have a backup or this is a dev/test database."

# kubectl delete (broad deletes)
elif echo "$COMMAND" | grep -qE 'kubectl\s+delete\s+(--all|namespace|all)' 2>/dev/null; then
    TIER=2
    RISK_REASON="RISKY: kubectl delete with broad scope. Verify namespace and cluster context with: kubectl config current-context"

# rm -rf on any non-trivial path (catches rm -rf /some/path, rm -rf $VAR, etc.)
elif echo "$COMMAND" | grep -qE 'rm\s+(-rf|-fr)\b' 2>/dev/null; then
    TARGET=$(echo "$COMMAND" | grep -oE 'rm\s+(-rf|-fr)\s+\S+' | awk '{print $NF}' | head -1)
    RISK_REASON="RISKY: rm -rf on ${TARGET:-unknown path}. Confirm the path is correct — variable expansions like \$DIR with a trailing space become rm -rf /."
    TIER=2
fi

[ "$TIER" -eq 0 ] && pass_through

# ── Emit additionalContext with risk classification ────────────────
ICON="⚠️"
[ "$TIER" -eq 3 ] && ICON="🚨"

MSG="${ICON} [brana risk-classifier T${TIER}] ${RISK_REASON}"

ESCAPED=$(echo "$MSG" | jq -Rs '.' 2>/dev/null) || ESCAPED="\"${MSG}\""
echo "{\"continue\": true, \"additionalContext\": $ESCAPED}"
