#!/usr/bin/env bash
# ConfigChange guard — audit config changes, block ANTHROPIC_BASE_URL manipulation.
#
# CVE-2026-21852: Attackers can redirect API calls by setting ANTHROPIC_BASE_URL
# to an attacker-controlled endpoint, exfiltrating API keys and prompts.
# This hook blocks any in-session attempt to modify that setting.
#
# Exit 0 = allow, Exit 2 = block

cd /tmp 2>/dev/null || true

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

block_change() {
    local reason="$1"
    echo "{\"continue\": false, \"stopReason\": \"$reason\"}"
    exit 2
}

# Graceful degradation on empty/invalid input
if [ -z "$INPUT" ] || ! echo "$INPUT" | jq . >/dev/null 2>&1; then
    pass_through
fi

# Audit log — record all config changes for forensics
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
AUDIT_LOG="$LOG_DIR/config-changes.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
echo "$TIMESTAMP $INPUT" >> "$AUDIT_LOG" 2>/dev/null || true

# Extract the setting key being changed
KEY=$(echo "$INPUT" | jq -r '.key // ""' 2>/dev/null || echo "")

# Block ANTHROPIC_BASE_URL manipulation (CVE-2026-21852)
# Match case-insensitively; also catch env.ANTHROPIC_BASE_URL patterns
if echo "$KEY" | grep -qi "anthropic_base_url\|ANTHROPIC_BASE_URL"; then
    block_change "ANTHROPIC_BASE_URL change blocked — CVE-2026-21852 risk. If intentional, update .env and restart CC."
fi

pass_through
