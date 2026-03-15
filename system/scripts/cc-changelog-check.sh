#!/usr/bin/env bash
# CC Version Check — weekly comparison against cached version.
# Checks npm registry for @anthropic-ai/claude-code latest version.
# If version changed, writes a report file that session-start surfaces.
#
# Usage: ./cc-changelog-check.sh
# Output: ~/.claude/cc-changelog-report.md (if version changed)
# Cache:  ~/.claude/cc-version-cache

set -euo pipefail

CACHE_FILE="$HOME/.claude/cc-version-cache"
REPORT_FILE="$HOME/.claude/cc-changelog-report.md"

# Get current version from npm registry
CURRENT=$(npm view @anthropic-ai/claude-code version 2>/dev/null) || { echo "ERROR: npm view failed"; exit 1; }

[ -z "$CURRENT" ] && { echo "ERROR: empty version"; exit 1; }

# Get locally installed version
LOCAL=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || LOCAL="unknown"

if [ ! -f "$CACHE_FILE" ]; then
    # First run — cache and done
    echo "$CURRENT" > "$CACHE_FILE"
    echo "First run — cached CC version $CURRENT (local: $LOCAL)."
    rm -f "$REPORT_FILE"
    exit 0
fi

CACHED=$(cat "$CACHE_FILE" 2>/dev/null) || CACHED=""

if [ "$CURRENT" = "$CACHED" ]; then
    echo "CC version unchanged: $CURRENT"
    rm -f "$REPORT_FILE"
    exit 0
fi

# Version changed!
cat > "$REPORT_FILE" << EOF
# CC Version Update — $(date +%Y-%m-%d)

**Previous:** $CACHED
**Current:** $CURRENT
**Local installed:** $LOCAL

## Action Required

1. Review changelog: https://code.claude.com/docs/en/changelog
2. Run: \`/brana:research Claude Code changelog $CACHED to $CURRENT\`
3. Check for: new hook events, breaking changes, plugin API changes, new tools
4. Update local: \`npm update -g @anthropic-ai/claude-code\` (if local != current)
5. Delete this file when done: \`rm ~/.claude/cc-changelog-report.md\`
EOF

# Update cache
echo "$CURRENT" > "$CACHE_FILE"

echo "CC version changed: $CACHED → $CURRENT. Report at $REPORT_FILE"
