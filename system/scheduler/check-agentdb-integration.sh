#!/usr/bin/env bash
# Check if claude-flow + AgentDB integration has shipped.
# Monitors: claude-flow npm versions, agentdb npm versions, GitHub issue #829.
# Writes result to stdout for scheduler log capture.

set -uo pipefail

echo "=== AgentDB Integration Watch ($(date +%F)) ==="

# Current installed version
source "$HOME/.claude/scripts/cf-env.sh"
CURRENT=$($CF --version 2>/dev/null | grep -oP 'v\K.*' || echo "unknown")
echo "Installed claude-flow: $CURRENT"

# Latest available
LATEST=$(npm view claude-flow version 2>/dev/null || echo "fetch-failed")
echo "Latest claude-flow:    $LATEST"

if [ "$CURRENT" != "$LATEST" ] && [ "$LATEST" != "fetch-failed" ]; then
    echo "UPDATE AVAILABLE: $CURRENT → $LATEST"
fi

# Check agentdb version
AGENTDB_VER=$(npm view agentdb version 2>/dev/null || echo "fetch-failed")
echo "Latest agentdb:        $AGENTDB_VER"

# Check if claude-flow now depends on agentdb
CF_DEPS=$(npm view claude-flow dependencies 2>/dev/null | grep -c "agentdb" || true)
if [ "$CF_DEPS" -gt 0 ]; then
    echo ""
    echo "*** INTEGRATION DETECTED: claude-flow now depends on agentdb ***"
    echo "*** Action: resume ms-007 in thebrana tasks.json ***"
fi

# Check issue #829 status via gh CLI
if command -v gh &>/dev/null; then
    ISSUE_STATE=$(gh issue view 829 --repo ruvnet/claude-flow --json state -q '.state' 2>/dev/null || echo "fetch-failed")
    echo "Issue #829 state:      $ISSUE_STATE"
    if [ "$ISSUE_STATE" = "CLOSED" ]; then
        echo ""
        echo "*** ISSUE #829 CLOSED — integration may have shipped ***"
        echo "*** Action: check changelog, resume ms-007 ***"
    fi
fi

echo ""
echo "Done."
