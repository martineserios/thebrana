#!/usr/bin/env bash
# Regression guard (t-2807, follow-up to t-2796): run_knowledge_backup() in
# system/skills/_shared/backup-knowledge-invoke.md fixed the 4 known raw
# invocations of backup-knowledge.sh (which discarded the WARNING text on
# integrity-check failure via `2>/dev/null || true`), but nothing stops a
# future skill author from writing a fresh raw invocation instead of using
# the helper. Mirrors the test-no-raw-global-active-epic-read.sh pattern:
# guards against a NEW raw call site reintroducing the silent-failure bug,
# not just the two known-allowed ones.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."
PASS=0
FAIL=0

echo "== no raw backup-knowledge.sh invocation outside the helper =="

# The bad pattern: a path-qualified invocation of backup-knowledge.sh (a
# preceding "/" distinguishes an actual call site from a bare filename
# mention in prose, e.g. "backup-knowledge.sh in metadata-and-memory.md").
# The "}" is optional to also match the ${VAR:-default} form used inside
# run_knowledge_backup() itself.
ALLOWED_FILES=(
  "$REPO_ROOT/system/skills/_shared/backup-knowledge-invoke.md"
  "$REPO_ROOT/system/cli/aliases.sh"
)

HITS=$(grep -rlE '/backup-knowledge\.sh\}?"' "$REPO_ROOT/system" --include="*.md" --include="*.sh" 2>/dev/null || true)

# Filter out the allowed files.
if [ -n "$HITS" ]; then
    for allowed in "${ALLOWED_FILES[@]}"; do
        HITS=$(echo "$HITS" | grep -vF "$allowed" || true)
    done
fi

if [ -z "$HITS" ]; then
    PASS=1
    echo "  PASS: no file outside backup-knowledge-invoke.md / aliases.sh invokes backup-knowledge.sh directly"
else
    FAIL=1
    echo "  FAIL: raw backup-knowledge.sh invocation found in:"
    echo "$HITS" | sed 's/^/    /'
fi

echo ""
[ "$FAIL" -eq 0 ]
