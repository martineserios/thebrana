#!/usr/bin/env bash
# SDD Spec Gate — advisory PreToolUse hook (t-2117)
#
# Warns once per branch when an M+ effort task begins editing implementation
# files without a feature spec in docs/architecture/features/.
#
# ADVISORY ONLY — never blocks (always exits 0).
# Fires once per branch via .git/brana-spec-gate-checked sentinel.
# Spec: docs/architecture/features/sdd-spec-gate.md

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

# Gate only on Write|Edit tool calls to impl paths
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) pass_through ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || pass_through
[ -z "$FILE_PATH" ] && pass_through

# Only trigger on impl paths — skip docs/, tests/, config files
case "$FILE_PATH" in
    */system/*|*/src/*|*/lib/*|*/bin/*) ;;
    *) pass_through ;;
esac

# Find git root (hook runs in CWD set by CC, not repo root)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || pass_through
cd "$GIT_ROOT" || pass_through

# Sentinel: fire once per branch to avoid advisory fatigue
SENTINEL=".git/brana-spec-gate-checked"
[ -f "$SENTINEL" ] && pass_through

# ── Task ID resolution (layered — C1 resolution) ──────────────────────────────

TASK_ID=""

# Layer 1: active-goal.json (written by /brana:backlog start)
GOAL_FILE="$HOME/.claude/run-state/active-goal.json"
if [ -f "$GOAL_FILE" ]; then
    TASK_ID=$(jq -r '.task_id // empty' "$GOAL_FILE" 2>/dev/null || true)
fi

# Layer 2: branch name regex fallback
if [ -z "$TASK_ID" ]; then
    BRANCH=$(git branch --show-current 2>/dev/null || true)
    TASK_ID=$(echo "$BRANCH" | grep -oP 't-\d+' | head -1 || true)
fi

# Layer 3: no task context — silent skip
if [ -z "$TASK_ID" ]; then
    touch "$SENTINEL"
    pass_through
fi

# ── Effort check ──────────────────────────────────────────────────────────────

EFFORT=$(brana backlog get "$TASK_ID" --field effort 2>/dev/null | tr -d '"' || true)
case "$EFFORT" in
    M|L|XL) ;;                     # M+ effort: check for spec
    *) touch "$SENTINEL"; pass_through ;;  # S/XS or unknown: exempt
esac

# ── Spec file check (C2 resolution: provenance-based, no frontmatter) ─────────

BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || true)
SPEC_FOUND=0
if [ -n "$BASE" ]; then
    SPEC=$(git diff --name-only "$BASE" HEAD 2>/dev/null \
           | grep "^docs/architecture/features/.*\.md$" \
           | head -1 || true)
    [ -n "$SPEC" ] && SPEC_FOUND=1
fi

touch "$SENTINEL"

if [ "$SPEC_FOUND" -eq 0 ]; then
    echo "⚠ Advisory: No spec file added in docs/architecture/features/ for $TASK_ID (effort: $EFFORT)." >&2
    echo "  Consider creating: docs/architecture/features/{slug}.md before implementing." >&2
    echo "  This warning fires once per branch. See: docs/architecture/features/sdd-spec-gate.md" >&2
fi

pass_through
