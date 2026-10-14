#!/usr/bin/env bash
# A suite run by run-test-suites.sh must never reach the live backlog ledger (t-3501, ADR-094).
# brana resolves tasks.json through the git COMMON root, so a linked worktree shares the live
# ledger with the main checkout and the runner's HOME scrub does not cover it. The runner now
# exports BRANA_TASKS_FILE into each suite's scratch HOME; this test runs a suite that does
# `brana backlog add` inside a throwaway repo and proves the repo's own ledger is untouched.
# Must-fire: the same suite run WITHOUT the runner does write the repo ledger.
# Run: bash tests/scripts/test-suite-ledger-isolation.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-suite-ledger-isolation.sh ==="
# the brana under test: this checkout's release build if present (CI puts it on PATH already)
[ -x "$ROOT/system/cli/rust/target/release/brana" ] && PATH="$ROOT/system/cli/rust/target/release:$PATH"
command -v brana >/dev/null 2>&1 || { if [ -n "${CI:-}" ]; then echo "  FAIL: no brana binary on PATH under CI — the must-fire can never fire"; exit 1; fi; echo "  SKIP: no brana binary on PATH"; echo "Results: 0 passed, 0 failed"; exit 0; }
echo "  brana under test: $(command -v brana) ($(brana --version 2>/dev/null | head -1))"
# This suite itself runs under the runner, which exports BRANA_TASKS_FILE: the control step
# below must NOT inherit it, or the control is contaminated and the must-fire can never fire.
T="$(mktemp -d)" || exit 2; trap 'rm -rf "$T"' EXIT
# throwaway repo with its own one-task ledger
mkdir -p "$T/repo/.claude" "$T/repo/tests/x"
( cd "$T/repo" && git init -q -b main . && git config user.email t@t && git config user.name t && echo x > f && git add f && git commit -qm init )
echo '{"tasks":[{"id":"t-1","subject":"keep","status":"pending","type":"task"}]}' > "$T/repo/.claude/tasks.json"
count() { python3 -I -c "import json,sys; t=json.load(open(sys.argv[1])); print(len(t['tasks'] if isinstance(t,dict) else t))" "$1"; }
cat > "$T/repo/tests/x/test-writes-ledger.sh" <<'SUITE'
#!/usr/bin/env bash
brana backlog add --subject "scratch-from-suite" --effort XS >/dev/null 2>&1 || true
echo "LEDGER_FILE=${BRANA_TASKS_FILE:-unset}"
echo "TOTAL_SEEN=$(brana backlog stats 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["total"])' 2>/dev/null || echo err)"
SUITE
chmod +x "$T/repo/tests/x/test-writes-ledger.sh"
# must-fire: WITHOUT the runner the suite writes the repo's own ledger
( cd "$T/repo" && env -u BRANA_TASKS_FILE bash tests/x/test-writes-ledger.sh >/dev/null 2>&1 )
assert "must-fire: without the runner (and without an inherited override), the suite's add lands in the repo ledger" 2 "$(count "$T/repo/.claude/tasks.json")"
echo '{"tasks":[{"id":"t-1","subject":"keep","status":"pending","type":"task"}]}' > "$T/repo/.claude/tasks.json"
# under the runner: the repo ledger must stay at 1 and the suite must see an isolated ledger
OUT="$( cd "$T/repo" && env -u BRANA_TASKS_FILE TEST_SUITE_KEEP_HOME=0 bash "$ROOT/system/scripts/run-test-suites.sh" tests/x/test-writes-ledger.sh 2>&1 )"
assert "under the runner, the repo ledger is untouched" 1 "$(count "$T/repo/.claude/tasks.json")"
assert "the suite was handed an explicit scratch ledger (BRANA_TASKS_FILE)" no "$(printf '%s' "$OUT" | grep -q 'LEDGER_FILE=unset' && echo yes || echo no)"
assert "the suite's own add went to that scratch ledger (total 1 there, not 2)" yes "$(printf '%s' "$OUT" | grep -q 'TOTAL_SEEN=1$' && echo yes || echo no)"
# keep-HOME mode (diagnosis only) must still hand out a scratch ledger: HOME isolation off never means ledger isolation off
echo '{"tasks":[{"id":"t-1","subject":"keep","status":"pending","type":"task"}]}' > "$T/repo/.claude/tasks.json"
OUT2="$( cd "$T/repo" && env -u CI -u BRANA_TASKS_FILE TEST_SUITE_KEEP_HOME=1 bash "$ROOT/system/scripts/run-test-suites.sh" tests/x/test-writes-ledger.sh 2>&1 )"
assert "TEST_SUITE_KEEP_HOME=1 still isolates the ledger (repo ledger untouched)" 1 "$(count "$T/repo/.claude/tasks.json")"
assert "and still hands the suite a scratch ledger" no "$(printf '%s' "$OUT2" | grep -q 'LEDGER_FILE=unset' && echo yes || echo no)"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
