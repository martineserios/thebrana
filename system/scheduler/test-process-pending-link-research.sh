#!/usr/bin/env bash
# Tests for process-pending-link-research.sh (t-2306)
#
# Uses stub `brana`/`claude` binaries (controlled via env vars) so tests never
# invoke the real CLI or burn real model usage.
#
# Usage: bash system/scheduler/test-process-pending-link-research.sh

set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/process-pending-link-research.sh"

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1 -- $2"; ((FAIL++)) || true; }

setup_scratch() { mktemp -d; }

make_stub_brana() {
  local dir="$1" tasks_json="$2"
  cat > "$dir/brana" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "backlog query")
    cat <<'JSON'
$tasks_json
JSON
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$dir/brana"
}

make_stub_claude() {
  local dir="$1"
  cat > "$dir/claude" <<'STUB'
#!/usr/bin/env bash
echo "CLAUDE_CALLED $*" >> "$STUB_CALL_LOG"
if [[ "${STUB_CLAUDE_FAIL:-0}" == "1" ]]; then
  exit 1
fi
exit 0
STUB
  chmod +x "$dir/claude"
}

echo "=== process-pending-link-research.sh ==="
echo ""

# Test 1: no pending tasks -- exits cleanly, no claude invocation
SCRATCH="$(setup_scratch)"
make_stub_brana "$SCRATCH" "[]"
make_stub_claude "$SCRATCH"
STUB_CALL_LOG="$SCRATCH/calls.log"
if BRANA_BIN="$SCRATCH/brana" CLAUDE_BIN="$SCRATCH/claude" STUB_CALL_LOG="$SCRATCH/calls.log" bash "$SCRIPT" >/dev/null 2>&1; then
  pass "no pending tasks: exits cleanly"
else
  fail "no pending tasks: exits cleanly" "non-zero exit"
fi
if [[ ! -f "$SCRATCH/calls.log" ]]; then
  pass "no pending tasks: claude never invoked"
else
  fail "no pending tasks: claude never invoked" "calls.log exists unexpectedly"
fi
rm -rf "$SCRATCH"

# Test 2: fewer pending tasks than cap -- all get processed
SCRATCH="$(setup_scratch)"
TASKS='[{"id":"t-1","context":"URL: https://example.com/a"},{"id":"t-2","context":"URL: https://example.com/b"}]'
make_stub_brana "$SCRATCH" "$TASKS"
make_stub_claude "$SCRATCH"
LINK_RESEARCH_MAX=5 BRANA_BIN="$SCRATCH/brana" CLAUDE_BIN="$SCRATCH/claude" STUB_CALL_LOG="$SCRATCH/calls.log" bash "$SCRIPT" >/dev/null 2>&1
if [[ -f "$SCRATCH/calls.log" ]] && [[ "$(wc -l < "$SCRATCH/calls.log")" -eq 2 ]]; then
  pass "fewer than cap: all pending tasks processed"
else
  fail "fewer than cap: all pending tasks processed" "expected 2 claude calls, got $(wc -l < "$SCRATCH/calls.log" 2>/dev/null || echo 0)"
fi
rm -rf "$SCRATCH"

# Test 3 (boundary): more pending tasks than cap -- only MAX_PER_RUN processed
SCRATCH="$(setup_scratch)"
TASKS='[{"id":"t-1","context":"URL: https://example.com/a"},{"id":"t-2","context":"URL: https://example.com/b"},{"id":"t-3","context":"URL: https://example.com/c"},{"id":"t-4","context":"URL: https://example.com/d"}]'
make_stub_brana "$SCRATCH" "$TASKS"
make_stub_claude "$SCRATCH"
LINK_RESEARCH_MAX=2 BRANA_BIN="$SCRATCH/brana" CLAUDE_BIN="$SCRATCH/claude" STUB_CALL_LOG="$SCRATCH/calls.log" bash "$SCRIPT" >/dev/null 2>&1
if [[ "$(wc -l < "$SCRATCH/calls.log" 2>/dev/null || echo 0)" -eq 2 ]]; then
  pass "more than cap: only MAX_PER_RUN processed"
else
  fail "more than cap: only MAX_PER_RUN processed" "expected 2 claude calls, got $(wc -l < "$SCRATCH/calls.log" 2>/dev/null || echo 0)"
fi
rm -rf "$SCRATCH"

# Test 4 (boundary): a task with no URL in its context is skipped, not passed to claude
SCRATCH="$(setup_scratch)"
TASKS='[{"id":"t-1","context":"no url here"},{"id":"t-2","context":"URL: https://example.com/b"}]'
make_stub_brana "$SCRATCH" "$TASKS"
make_stub_claude "$SCRATCH"
LINK_RESEARCH_MAX=5 BRANA_BIN="$SCRATCH/brana" CLAUDE_BIN="$SCRATCH/claude" STUB_CALL_LOG="$SCRATCH/calls.log" bash "$SCRIPT" >/dev/null 2>&1
if [[ "$(wc -l < "$SCRATCH/calls.log" 2>/dev/null || echo 0)" -eq 1 ]] && grep -q "example.com/b" "$SCRATCH/calls.log"; then
  pass "task without URL: skipped, only the valid one researched"
else
  fail "task without URL: skipped, only the valid one researched" "unexpected call count/content"
fi
rm -rf "$SCRATCH"

# Test 5: --dry-run makes no claude calls at all
SCRATCH="$(setup_scratch)"
TASKS='[{"id":"t-1","context":"URL: https://example.com/a"}]'
make_stub_brana "$SCRATCH" "$TASKS"
make_stub_claude "$SCRATCH"
BRANA_BIN="$SCRATCH/brana" CLAUDE_BIN="$SCRATCH/claude" STUB_CALL_LOG="$SCRATCH/calls.log" bash "$SCRIPT" --dry-run >/dev/null 2>&1
if [[ ! -f "$SCRATCH/calls.log" ]]; then
  pass "--dry-run: no claude calls made"
else
  fail "--dry-run: no claude calls made" "calls.log exists unexpectedly"
fi
rm -rf "$SCRATCH"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
