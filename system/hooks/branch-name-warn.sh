#!/usr/bin/env bash
# Branch Name Warn — PreToolUse hook for Bash (git branch creation)
#
# Warns when a new branch name does not match the project convention:
#   {epic-slug}/{work-type}/t-{NNN}-{description-slug}
#
# Advisory only (continue: true). Escalate to hard-block once existing
# branches are migrated (see t-1620).
#
# Intercepts: git switch -c, git checkout -b, git branch <name>
# Skips: main, master, docs/*, hotfix/* (special branches)
# Escape hatch: --force-name anywhere in the command

cd /tmp 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
if ! hook_should_run "standard" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

pass_through() {
    echo '{"continue": true}'
    exit 0
}

warn() {
    local branch="$1"
    cat >&2 <<WARN
⚠  branch-name-warn: '$branch' does not match convention.
   Expected: {epic-slug}/{work-type}/t-{NNN}-{description}
   work-type ∈ feat|fix|chore|research|test|docs|refactor
   Example:  session/fix/t-1700-epic-scoped-assertion
   Use --force-name to suppress this warning.
WARN
    echo '{"continue": true}'
    exit 0
}

# Only intercept Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
[ "$TOOL_NAME" = "Bash" ] || pass_through

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -n "$COMMAND" ] || pass_through

# Escape hatch
echo "$COMMAND" | grep -q '\-\-force-name' && pass_through

# Extract new branch name from creation commands
# Handles: git switch -c <name>, git checkout -b <name>, git branch <name>
BRANCH=""
if echo "$COMMAND" | grep -qE 'git\s+(switch\s+-c|checkout\s+-b)\s'; then
    BRANCH=$(echo "$COMMAND" | sed -n 's/.*git[[:space:]]\+\(switch[[:space:]]\+-c\|checkout[[:space:]]\+-b\)[[:space:]]\+\([^[:space:]]*\).*/\2/p')
elif echo "$COMMAND" | grep -qE 'git\s+branch\s+[^-]'; then
    # git branch <name> [start-point] — first non-flag arg is the name
    BRANCH=$(echo "$COMMAND" | sed -n 's/.*git[[:space:]]\+branch[[:space:]]\+\([^-][^[:space:]]*\).*/\1/p')
fi

[ -n "$BRANCH" ] || pass_through

# Skip special branches
case "$BRANCH" in
    main|master) pass_through ;;
    docs/*|hotfix/*) pass_through ;;
esac

# Validate against convention: {epic}/{work-type}/t-{N}-
CONVENTION='^[a-z0-9][a-z0-9-]+/(feat|fix|chore|research|test|docs|refactor)/t-[0-9]+-'
echo "$BRANCH" | grep -qE "$CONVENTION" && pass_through

warn "$BRANCH"
