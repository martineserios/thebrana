#!/usr/bin/env bash
#
# no-attribution-commit.sh — PreToolUse hook for Bash
#
# Blocks `git commit` and `gh pr create` calls that contain forbidden attribution
# trailers (Co-Authored-By, Signed-off-by, "Claude Code", "🤖 Generated", etc.).
#
# This is a HARD enforcement layer for the rule in system/rules/git-discipline.md
# "Commit attribution — HARD RULE". Past sessions have repeatedly violated the
# soft rule; this hook is the safety net.
#
# Exit codes:
#   0 — no violation, allow the call
#   2 — violation found, block the call (CC will surface stderr to the model)
#
# Input: PreToolUse hook receives JSON on stdin with the tool call info.
# Reads: tool_input.command for Bash calls.

set -uo pipefail

# Read JSON from stdin
input=$(cat)

# Test-mode sentinel bypass — skip hook during test harness runs.
# touch /tmp/brana-test-mode before running hook tests that contain forbidden
# tokens in their payloads (e.g. echo '{"command":"git commit -m \"Claude Code\""}').
# Same pattern as /tmp/brana-memory-write-active and /tmp/brana-close-active.
[ -f /tmp/brana-test-mode ] && exit 0

# Extract the bash command (handles both .tool_input.command and .input.command)
command=$(echo "$input" | jq -r '.tool_input.command // .input.command // empty' 2>/dev/null)

# Only inspect git commit / gh pr create / gh pr edit calls
case "$command" in
    *"git commit"*|*"gh pr create"*|*"gh pr edit"*|*"gh release create"*)
        ;;
    *)
        # Not a commit/PR-creating call, allow
        exit 0
        ;;
esac

# Forbidden patterns — case-insensitive fixed strings.
# Match structural attribution forms only, not bare product/company names.
# Bare "Anthropic" was removed (E2026-06-08-5): it false-positived on
# legitimate subjects like "fix: update per Anthropic safety guidelines".
# anthropic.com and co-authorship trailers already cover the real cases.
forbidden_patterns=(
    "Co-Authored-By"
    "Co-authored-by"
    "co-authored-by"
    "Signed-off-by"
    "🤖 Generated with"
    "Generated with Claude"
    "Generated with Anthropic"
    "Powered by Anthropic"
    "Claude Code"
    "Claude AI"
    "claude.ai/code"
    "anthropic.com"
)

violations=()
for pattern in "${forbidden_patterns[@]}"; do
    if echo "$command" | grep -qiF "$pattern"; then
        violations+=("$pattern")
    fi
done

if [ ${#violations[@]} -gt 0 ]; then
    {
        echo ""
        echo "BLOCKED: Commit/PR contains forbidden attribution trailer(s)."
        echo ""
        echo "Found:"
        for v in "${violations[@]}"; do
            echo "  - $v"
        done
        echo ""
        echo "Per system/rules/git-discipline.md (Commit attribution — HARD RULE):"
        echo "  No Co-Authored-By, Signed-off-by, AI attribution, or 'Generated with'"
        echo "  trailers in commit messages or PR descriptions. No exceptions."
        echo ""
        echo "Rewrite the commit message without the trailer and try again."
        echo ""
    } >&2
    exit 2
fi

# No violations, allow
exit 0
