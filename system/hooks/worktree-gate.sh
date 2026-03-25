#!/usr/bin/env bash
# PreToolUse: Worktree Enforcement Gate + Commit Safety
#
# Intercepts Bash tool calls to enforce:
#   A. Worktree discipline: denies `git checkout -b` / `git switch -c` when dirty or worktrees active
#   B. Pre-commit disk check: blocks `git commit` when /tmp is >95% full (prevents silent ENOSPC)
#   C. Cross-session file warning: warns when staged files weren't written by this session
#
# Always passes through non-Bash tools, non-git commands, and non-git dirs.

# Profile gate: standard tier (skipped in minimal mode)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
if ! hook_should_run "standard" 2>/dev/null; then
    echo '{"continue": true}'
    exit 0
fi

INPUT=$(cat)

# Helper: pass through
pass_through() {
    echo '{"continue": true}'
    exit 0
}

# Helper: pass through with warning (additionalContext)
warn() {
    local message="$1"
    local escaped
    escaped=$(echo "$message" | jq -Rs '.' 2>/dev/null) || escaped='"warning"'
    echo "{\"continue\": true, \"additionalContext\": $escaped}"
    exit 0
}

# Helper: deny with reason
deny() {
    local reason="$1"
    local escaped
    escaped=$(echo "$reason" | sed 's/"/\\"/g')
    cat <<DENY_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$escaped"
  }
}
DENY_JSON
    exit 0
}

# Step 1: Parse input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || pass_through

# Step 2: Only intercept Bash
[ "$TOOL_NAME" = "Bash" ] || pass_through

# Step 3: Extract command
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || pass_through
[ -n "$CMD" ] || pass_through

# Detect command type
IS_CHECKOUT=false
IS_COMMIT=false
echo "$CMD" | grep -qE '(git\s+checkout\s+.*-b\s|git\s+switch\s+.*-c\s|git\s+checkout\s+.*-b$|git\s+switch\s+.*-c$)' && IS_CHECKOUT=true
echo "$CMD" | grep -qE 'git\s+commit' && IS_COMMIT=true

# Neither checkout nor commit — nothing to guard
[ "$IS_CHECKOUT" = true ] || [ "$IS_COMMIT" = true ] || pass_through

# Step 4: Find git root from CWD
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || pass_through
[ -n "$CWD" ] || pass_through

GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || pass_through
[ -n "$GIT_ROOT" ] || pass_through

# ════════════════════════════════════════════════════════════
# GATE A: Commit safety (disk check + cross-session warning)
# ════════════════════════════════════════════════════════════

if [ "$IS_COMMIT" = true ]; then

    # A1: Pre-commit disk check — block at >95% /tmp usage
    # Session-start already warns at 80%. This is the last-resort safety net
    # that prevents silent ENOSPC failures (exit 134, no error message).
    TMP_USE_PCT=$(df /tmp 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}') || true
    if [ -n "$TMP_USE_PCT" ] && [ "$TMP_USE_PCT" -ge 95 ] 2>/dev/null; then
        TMP_AVAIL=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $4}') || TMP_AVAIL="unknown"
        deny "BLOCKED: /tmp is ${TMP_USE_PCT}% full (${TMP_AVAIL} free). Commits will fail silently with ENOSPC (exit 134). Free space first: du -sh /tmp/claude-* | sort -rh"
    fi

    # A2: Cross-session file warning — detect staged files not written by this session
    # Reads the session JSONL log to find files this session touched (Write/Edit),
    # then compares against staged files. Warns (not blocks) on mismatches.
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
    SESSION_LOG="/tmp/brana-session-${SESSION_ID}.jsonl"

    if [ -n "$SESSION_ID" ] && [ -f "$SESSION_LOG" ]; then
        # Get staged files
        STAGED=$(git -C "$GIT_ROOT" diff --cached --name-only 2>/dev/null) || true

        if [ -n "$STAGED" ]; then
            # Extract files this session wrote/edited from JSONL log
            # Format: {"ts":..., "tool":"Write"|"Edit", "detail":"filepath", ...}
            SESSION_FILES=$(jq -r 'select(.tool == "Write" or .tool == "Edit") | .detail // empty' "$SESSION_LOG" 2>/dev/null | sort -u) || true

            # Find staged files not in session log
            FOREIGN_FILES=""
            while IFS= read -r staged_file; do
                [ -z "$staged_file" ] && continue
                # Convert to absolute path for comparison, then check both relative and absolute
                FOUND=false
                while IFS= read -r session_file; do
                    [ -z "$session_file" ] && continue
                    # Match if staged file is a suffix of session file (abs path ends with rel path)
                    # or if they're identical
                    if [ "$staged_file" = "$session_file" ] || [[ "$session_file" == *"/$staged_file" ]]; then
                        FOUND=true
                        break
                    fi
                done <<< "$SESSION_FILES"
                if [ "$FOUND" = false ]; then
                    FOREIGN_FILES="${FOREIGN_FILES:+$FOREIGN_FILES, }$staged_file"
                fi
            done <<< "$STAGED"

            if [ -n "$FOREIGN_FILES" ]; then
                warn "[Cross-session warning] These staged files were NOT written by this session: ${FOREIGN_FILES}. They may have been left by a concurrent session on another branch. Verify they belong in this commit."
            fi
        fi
    fi

    # Commit passed all checks
    pass_through
fi

# ════════════════════════════════════════════════════════════
# GATE B: Worktree enforcement (checkout/switch)
# ════════════════════════════════════════════════════════════

# Step 5: Check for uncommitted changes (dirty tree or staged)
DIRTY=""
if ! git -C "$GIT_ROOT" diff --quiet 2>/dev/null; then
    DIRTY="unstaged changes"
elif ! git -C "$GIT_ROOT" diff --cached --quiet 2>/dev/null; then
    DIRTY="staged changes"
fi

# Step 6: Check for active worktrees (beyond the main one)
WORKTREE_COUNT=$(git -C "$GIT_ROOT" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || echo "0")

# Step 7: Extract branch name from the command for the suggestion
BRANCH_NAME=$(echo "$CMD" | grep -oP '(checkout\s+-b|switch\s+-c)\s+\K\S+' 2>/dev/null || echo "branch-name")

# Step 8: Decide
if [ -n "$DIRTY" ]; then
    deny "Worktree required: $DIRTY detected. Use \`git worktree add ../<repo>-${BRANCH_NAME} -b ${BRANCH_NAME}\` or \`claude --worktree ${BRANCH_NAME}\` instead of \`git checkout -b\`. See git-discipline rule."
elif [ "$WORKTREE_COUNT" -gt 1 ]; then
    WT_LIST=$(git -C "$GIT_ROOT" worktree list --porcelain 2>/dev/null | grep '^worktree ' | sed 's/^worktree /  /' | head -5)
    deny "Worktree required: ${WORKTREE_COUNT} worktrees already active on this repo. Use \`git worktree add ../<repo>-${BRANCH_NAME} -b ${BRANCH_NAME}\` instead of checkout to avoid conflicts. Active worktrees:\n${WT_LIST}"
fi

# Clean state, no other worktrees — allow
pass_through
