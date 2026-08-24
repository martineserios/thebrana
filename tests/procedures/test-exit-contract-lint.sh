#!/usr/bin/env bash
# Regression test: exit-contract-lint.sh — new callers of exit-status-contract
# helpers must branch on failure (t-2888).
#
# THE BUG CLASS. resolve_epic_ancestor's exit contract (empty+exit0 = no epic,
# exit1 = lookup failed) was independently dropped by THREE new call sites
# (t-2263, t-2843, t-2845's first draft) despite a bolded worked example in the
# helper's own doc. Each wrote a bare `VAR=$(resolve_epic_ancestor ...)` and
# routed on the string, collapsing "lookup failed" into "no epic". Documentation
# at the source does not stop new callers from dropping the contract.
#
# THE MITIGATION UNDER TEST. A diff-scoped lint, run at Challenger-gate time:
#   - discovers helpers carrying a multi-outcome exit contract by scanning
#     registry docs for a `# Exit contract` marker comment directly above the
#     function definition (self-maintaining registry — mark a new helper's
#     contract and the lint covers it, no hardcoded name list);
#   - flags ADDED diff lines that call such a helper without branching on its
#     exit status (`if`-wrapped call, `||` on the call line, or `$?` checked
#     within the next 2 added lines);
#   - skips test files (fixtures legitimately contain bare calls) and the
#     registry docs themselves (worked examples).
#
# Contract pinned here:
#   exit 0  clean (no violations in added lines)
#   exit 1  violations — one `path:line: helper ...` report line per violation
#   exit 2  registry empty/unreadable (fail CLOSED — a broken marker regex must
#           not silently turn the lint into a no-op)
#
# Run: bash tests/procedures/test-exit-contract-lint.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_exit() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected exit [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if grep -qF "$needle" <<<"$haystack"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — output missing [$needle]"
        FAIL=$((FAIL + 1))
    fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
LINT="$REPO_ROOT/system/scripts/exit-contract-lint.sh"
TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

if [ ! -f "$LINT" ]; then
    echo "ERROR: $LINT does not exist"
    echo "=== Summary ==="
    echo "Total: 1 | Passed: 0 | Failed: 1"
    exit 1
fi

# ── Fixture registry: one helper WITH the marker, one without ────────────────
REG="$TMPDIR_T/registry"
mkdir -p "$REG"
cat > "$REG/frob-widget.md" <<'EOF'
# Frob Widget (shared)

```bash
# Exit contract — three OUTCOMES, kept distinguishable:
#   value + exit 0   found
#   empty + exit 0   real negative
#   exit 1           lookup failed
frob_widget() {
  printf 'x'
}
EOF
cat > "$REG/plain-helper.md" <<'EOF'
# Plain Helper (shared)

```bash
# Always exits 0.
other_helper() {
  printf 'y'
}
EOF

# Minimal unified-diff wrapper around a set of added lines.
mkdiff() {
    local file="$1"; shift
    printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1,1 +1,%d @@\n' \
        "$file" "$file" "$file" "$file" "$#"
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
}

run_lint() {  # run_lint <diff-text>
    OUT=$(bash "$LINT" --stdin --registry-dir "$REG" <<<"$1" 2>&1)
    RC=$?
}

echo "=== the reported bug class: bare call on an added line is a violation ==="
run_lint "$(mkdiff system/skills/close/phases/foo.md '+EPIC=$(frob_widget "$id")')"
assert_exit "bare command substitution -> exit 1" 1 "$RC"
assert_contains "report names the helper" "frob_widget" "$OUT"
assert_contains "report names the file" "system/skills/close/phases/foo.md" "$OUT"
assert_contains "report cites the contract doc" "frob-widget.md" "$OUT"

echo "=== branched call sites are clean ==="
run_lint "$(mkdiff foo.md '+if ! EPIC=$(frob_widget "$id"); then' '+  echo fail' '+fi')"
assert_exit "if ! wrapped call -> exit 0" 0 "$RC"
run_lint "$(mkdiff foo.md '+EPIC=$(frob_widget "$id") || return 1')"
assert_exit "|| on the call line -> exit 0" 0 "$RC"
run_lint "$(mkdiff foo.md '+if frob_widget "$id"; then' '+  echo ok' '+fi')"
assert_exit "direct if on the call -> exit 0" 0 "$RC"
run_lint "$(mkdiff foo.md '+EPIC=$(frob_widget "$id")' '+if [ $? -ne 0 ]; then' '+  echo fail' '+fi')"
assert_exit "\$? checked within 2 added lines -> exit 0" 0 "$RC"

echo "=== codebase-derived clean shapes (pre-edit challenger finding #1) ==="
# backlog-reconcile.sh:173 — idiomatic UNNEGATED if-assignment branch. No `!`,
# no `||`, no literal `$?`, yet fully correct. Must NOT flag.
run_lint "$(mkdiff system/scripts/foo.sh '+if slug=$(frob_widget "$tid"); then' '+  ok=1' '+else' '+  echo "warn" >&2' '+fi')"
assert_exit "unnegated if-assignment (backlog-reconcile.sh shape) -> exit 0" 0 "$RC"
run_lint "$(mkdiff foo.sh '+SLUG=$(frob_widget "$id")' '+case $? in' '+  0) ok ;;' '+esac')"
assert_exit "case \$? in within window -> exit 0" 0 "$RC"

echo "=== prose mentions are not call sites (pre-edit challenger finding #2) ==="
# decompose-mode.md:42 class — helper named in doc prose, no invocation syntax.
run_lint "$(mkdiff system/skills/build/phases/doc.md '+Resolve the epic via frob_widget before branching (see the shared walk doc).')"
assert_exit "prose mention without invocation -> exit 0" 0 "$RC"
run_lint "$(mkdiff system/skills/build/phases/doc.md '+call \`frob_widget\` — check the exit status first')"
assert_exit "backticked name-only mention -> exit 0" 0 "$RC"

echo "=== direct calls in common positions (post-build challenger finding #1) ==="
# Indented direct call — the shape almost every real if/for/while body uses.
run_lint "$(mkdiff foo.sh '+    frob_widget "$id"')"
assert_exit "indented direct call, unbranched -> exit 1" 1 "$RC"
# Pipeline loop body — live shape at close/phases/gate-and-evidence.md:130.
run_lint "$(mkdiff foo.sh '+| while read -r id; do frob_widget "$id" 2>/dev/null; done')"
assert_exit "do-prefixed call in pipeline loop, unbranched -> exit 1" 1 "$RC"
# Indented if-wrapped call is still a branch — must stay clean.
run_lint "$(mkdiff foo.sh '+  if frob_widget "$id"; then' '+    ok=1' '+  fi')"
assert_exit "indented if-wrapped call -> exit 0" 0 "$RC"
# || BEFORE the call handles the previous command's failure, not this one's.
run_lint "$(mkdiff foo.sh '+prev_cmd || B=$(frob_widget "$id")')"
assert_exit "|| preceding the call -> exit 1 (call failure unhandled)" 1 "$RC"

# Call directly after a closing brace with no separator (iteration-2 low finding).
run_lint "$(mkdiff foo.sh '+}  frob_widget "$id"')"
assert_exit "call after closing brace, unbranched -> exit 1" 1 "$RC"

echo "=== exemption is registry-scoped, not any _shared/ (finding #2) ==="
run_lint "$(mkdiff some/other/_shared/foo.sh '+B=$(frob_widget "$id")')"
assert_exit "bare call in a foreign _shared/ dir -> exit 1 (not the registry)" 1 "$RC"

echo "=== success-only chaining does NOT handle failure ==="
run_lint "$(mkdiff foo.md '+EPIC=$(frob_widget "$id") && echo ok')"
assert_exit "&&-only chaining -> exit 1 (failure branch missing)" 1 "$RC"

echo "=== only ADDED lines are in scope ==="
run_lint "$(mkdiff foo.md ' EPIC=$(frob_widget "$id")')"
assert_exit "context (unchanged) line -> exit 0" 0 "$RC"
run_lint "$(mkdiff foo.md '-EPIC=$(frob_widget "$id")')"
assert_exit "removed line -> exit 0" 0 "$RC"

echo "=== non-call lines are not violations ==="
run_lint "$(mkdiff foo.md '+frob_widget() {' '+  printf x' '+}')"
assert_exit "function definition -> exit 0" 0 "$RC"
run_lint "$(mkdiff foo.md '+# frob_widget returns 1 on lookup failure')"
assert_exit "comment mentioning the helper -> exit 0" 0 "$RC"

echo "=== fixture and registry paths are exempt ==="
run_lint "$(mkdiff tests/procedures/test-something.sh '+EPIC=$(frob_widget "$id")')"
assert_exit "bare call under tests/ -> exit 0 (fixtures allowed)" 0 "$RC"
run_lint "$(mkdiff "registry/frob-widget.md" '+EPIC=$(frob_widget "$id")')"
assert_exit "bare call in a registry doc itself -> exit 0 (worked examples)" 0 "$RC"

echo "=== helpers without the marker are not policed ==="
run_lint "$(mkdiff foo.md '+VAL=$(other_helper "$id")')"
assert_exit "bare call to unmarked helper -> exit 0" 0 "$RC"

echo "=== multiple violations all reported ==="
run_lint "$(mkdiff foo.md '+A=$(frob_widget a)' '+echo unrelated' '+irrelevant=1' '+B=$(frob_widget b)')"
assert_exit "two bare calls -> exit 1" 1 "$RC"
TOTAL=$((TOTAL + 1))
NREPORTS=$(grep -cF 'frob_widget' <<<"$OUT")
if [ "$NREPORTS" -ge 2 ]; then
    echo "  PASS: both call sites reported ($NREPORTS report lines)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: expected >=2 report lines, got $NREPORTS"
    FAIL=$((FAIL + 1))
fi

echo "=== language-scoped: non-shell files are exempt from shell contracts (t-3212) ==="
# The registry is built from function NAMES only (extracted from a bash `#
# Exit contract` marker). A same-named function can exist in a completely
# different language with different semantics — e.g. a Rust tail-expression
# returning Option<String>, which has no exit-status/branch-on-failure concept
# at all (its own `?` operator already collapses failure into None). Such a
# line can accidentally satisfy the shell-syntax heuristics (start-of-line
# position, no guarding keyword) and get flagged as if it dropped a bash exit
# contract it was never subject to. Real-world case: resolve_epic_ancestor
# exists both as the marked bash helper (system/skills/_shared/epic-ancestor-walk.md)
# and as an unrelated Rust fn in brana-core/src/tasks/query.rs.
run_lint "$(mkdiff foo.rs '+    frob_widget(id)')"
assert_exit "same-named call in a .rs file -> exit 0 (not shell, not policed)" 0 "$RC"
run_lint "$(mkdiff foo.py '+    frob_widget(id)')"
assert_exit "same-named call in a .py file -> exit 0 (not shell, not policed)" 0 "$RC"

echo "=== registry failure is fail-CLOSED ==="
EMPTY="$TMPDIR_T/empty"; mkdir -p "$EMPTY"
OUT=$(bash "$LINT" --stdin --registry-dir "$EMPTY" <<<"$(mkdiff foo.md '+x=1')" 2>&1); RC=$?
assert_exit "registry with no marked helpers -> exit 2" 2 "$RC"
OUT=$(bash "$LINT" --stdin --registry-dir "$TMPDIR_T/nonexistent" <<<"$(mkdiff foo.md '+x=1')" 2>&1); RC=$?
assert_exit "missing registry dir -> exit 2" 2 "$RC"

echo "=== real repo: default registry discovers resolve_epic_ancestor ==="
# The lint's whole reason to exist — the shipped _shared registry must yield the
# helper whose contract was dropped three times, and a bare call must be caught.
OUT=$(bash "$LINT" --stdin <<<"$(mkdiff system/skills/foo/phases/bar.md '+EPIC=$(resolve_epic_ancestor "$TASK_ID")')" 2>&1); RC=$?
assert_exit "bare resolve_epic_ancestor call -> exit 1 (default registry)" 1 "$RC"
assert_contains "default registry names resolve_epic_ancestor" "resolve_epic_ancestor" "$OUT"
OUT=$(bash "$LINT" --stdin <<<"$(mkdiff system/skills/foo/phases/bar.md '+if ! EPIC=$(resolve_epic_ancestor "$TASK_ID"); then' '+  echo fail' '+fi')" 2>&1); RC=$?
assert_exit "branched resolve_epic_ancestor call -> exit 0 (default registry)" 0 "$RC"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
