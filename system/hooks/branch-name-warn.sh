#!/usr/bin/env bash
# Branch Name Guard — PreToolUse hook for Bash (git branch creation)
#
# Hard-blocks when a new branch name does not match the project convention:
#   {epic-slug}/{work-type}/t-{NNN}-{description-slug}
#
# Shipped as advisory (t-1620). Upgraded to hard-block (t-1718).
#
# Intercepts: git switch -c, git checkout -b, git branch <name>,
#             git worktree add ... -b <name>
# Skips: main, master, docs/*, hotfix/* (special branches)
# Escape hatch: --force-name anywhere in the command
#
# t-2542 fixed three gaps:
#   1. The work-type set is now sourced from CLAUDE.md §Branch naming, which
#      includes `design` and `review`. `design` is emittable by
#      resolve_branch_prefix() (the t-2494 authority) and was being rejected
#      here, so a kind:design task could not be given a conforming branch.
#      system/hooks/tests/test-branch-name-warn.sh now cross-checks every
#      prefix the resolver can emit against this regex.
#   2. `git worktree add -b` is the branch-creation path git-discipline.md
#      MANDATES; it was unchecked, so the guard validated only the paths the
#      rules forbid.
#   3. Quoted spans are stripped before parsing. Previously a commit whose
#      MESSAGE quoted a bad branch name was blocked even when the real branch
#      was valid — which made documenting branch drift hardest in the very
#      commits that fix it.

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

block() {
    local branch="$1"
    local reason="branch-name-guard: '$branch' does not match convention. Expected: {epic-slug}/{work-type}/t-{NNN}-{description} | work-type ∈ feat|fix|chore|research|test|docs|refactor|review|design | Example: session/fix/t-1700-epic-scoped-assertion | No epic slug? The epic segment is mandatory and has no fallback (t-2540) — assign an epic to the task first: brana backlog set <id> parent <epic-id> | Use --force-name to bypass."
    local ESCAPED
    ESCAPED=$(echo "$reason" | jq -Rs '.' 2>/dev/null) || ESCAPED='"[branch-name-guard blocked]"'
    jq -n --argjson reason "$ESCAPED" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0
}

# Only intercept Bash tool
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
[ "$TOOL_NAME" = "Bash" ] || pass_through

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -n "$COMMAND" ] || pass_through

# Escape hatch
echo "$COMMAND" | grep -q '\-\-force-name' && pass_through

# Strip quoted spans before parsing (t-2542). A commit message that QUOTES a
# malformed branch name is documentation, not a branch creation — parsing inside
# quotes blocked the t-2539 commit while its actual branch was valid. Removing
# quoted spans first also leaves a real creation intact when the same command
# happens to carry a message (git switch -c <name> && git commit -m "...").
SCAN=$(echo "$COMMAND" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Extract new branch name from creation commands
# Handles: git switch -c <name>, git checkout -b <name>, git branch <name>,
#          git worktree add [path] -b <name>
BRANCH=""
if echo "$SCAN" | grep -qE 'git\s+worktree\s+add\s'; then
    # -b may sit anywhere after `add` (path usually precedes it).
    BRANCH=$(echo "$SCAN" | sed -n 's/.*git[[:space:]]\+worktree[[:space:]]\+add[[:space:]]\+.*-b[[:space:]]\+\([^[:space:]]*\).*/\1/p')
elif echo "$SCAN" | grep -qE 'git\s+(switch\s+-c|checkout\s+-b)\s'; then
    BRANCH=$(echo "$SCAN" | sed -n 's/.*git[[:space:]]\+\(switch[[:space:]]\+-c\|checkout[[:space:]]\+-b\)[[:space:]]\+\([^[:space:]]*\).*/\2/p')
elif echo "$SCAN" | grep -qE 'git\s+branch\s+[a-zA-Z0-9_]' && ! echo "$SCAN" | grep -qE '[|;&>]'; then
    # git branch <name> [start-point] — first non-flag arg is the name
    # Exclude piped/chained commands (git branch | grep ...) which are reads, not creates
    BRANCH=$(echo "$SCAN" | sed -n 's/.*git[[:space:]]\+branch[[:space:]]\+\([^-][^[:space:]]*\).*/\1/p')
fi

[ -n "$BRANCH" ] || pass_through

# Skip special branches
case "$BRANCH" in
    main|master) pass_through ;;
    docs/*|hotfix/*) pass_through ;;
esac

# Validate against convention: {epic}/{work-type}/t-{N}-
# Work-type set mirrors CLAUDE.md §Branch naming exactly. `design` is emittable
# by resolve_branch_prefix() and was missing here (t-2542); `review` is listed in
# CLAUDE.md but emitted by nothing — accepted so the guard never rejects a
# work-type the convention permits. test-branch-name-warn.sh asserts every
# resolver-emittable prefix passes this regex, so the sets cannot drift apart
# silently again (the gap t-2494's resolver→CLAUDE.md test left open).
CONVENTION='^[a-z0-9][a-z0-9-]+/(feat|fix|chore|research|test|docs|refactor|review|design)/t-[0-9]+-'
echo "$BRANCH" | grep -qE "$CONVENTION" && pass_through

block "$BRANCH"
