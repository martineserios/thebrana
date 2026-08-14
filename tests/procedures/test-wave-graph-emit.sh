#!/usr/bin/env bash
# Regression test: wave_gate_chain_has_cycle() + wave_name_for_milestone() —
# the shared plan-time wave-graph emission primitives (ADR-080 §2, t-2843).
#
# THE REQUIREMENT. plan.md's WAVES step and decompose-mode.md's WAVES step both
# emit a wave graph (one wave per milestone) with a gate chain derived from
# blocked_by edges crossing milestones. ADR-080 §2 requires an emission-time
# cycle check (DFS) before WRITE — the runner's PREFLIGHT cycle-STOP (ADR-080 §3.1)
# is the last line of defense, not the first. If two call sites each hand-rolled
# their own cycle check, they could drift the same way resolve_branch_prefix's
# two mappings drifted (t-2494) — one shared, tested primitive instead.
#
# THE ALGORITHM. A wave's `gate` is a single wave id or null — the gate chain is
# a functional graph (out-degree <= 1 per node), so cycle detection reduces to:
# walk each node's gate chain; if the walk exceeds the total node count without
# hitting a dead end, some node was revisited (pigeonhole) — a cycle exists.
# Equivalent to DFS-with-visited-set for this restricted graph shape, without
# needing bash to track per-node visited sets.
#
# The functions under test are extracted from system/skills/_shared/wave-graph-emit.md
# so this test exercises the shipped source, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-wave-graph-emit.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_status() {
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

REPO_ROOT=$(git rev-parse --show-toplevel)
EMIT_MD="$REPO_ROOT/system/skills/_shared/wave-graph-emit.md"
TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

if [ ! -f "$EMIT_MD" ]; then
    echo "ERROR: $EMIT_MD does not exist — the shared wave-graph-emit block is missing"
    exit 1
fi

# Extract by NAMED MARKER, not by position or content substring (t-2493).
sed -n '/<!-- WAVE-GRAPH-EMIT-BLOCK -->/,/<!-- \/WAVE-GRAPH-EMIT-BLOCK -->/p' "$EMIT_MD" \
| sed '1d;$d' \
| sed '/^```/d' > "$TMPDIR_T/wave-graph-emit.sh"

if [ ! -s "$TMPDIR_T/wave-graph-emit.sh" ]; then
    echo "ERROR: WAVE-GRAPH-EMIT-BLOCK markers missing or empty in $EMIT_MD"
    exit 1
fi
if ! grep -q 'wave_gate_chain_has_cycle' "$TMPDIR_T/wave-graph-emit.sh"; then
    echo "ERROR: WAVE-GRAPH-EMIT-BLOCK does not contain wave_gate_chain_has_cycle() — markers drifted"
    exit 1
fi

source "$TMPDIR_T/wave-graph-emit.sh"

echo "=== wave_name_for_milestone: <epic-slug>-<ms-slug> (ADR-080 §2.5) ==="
assert_eq "epic backlog-drain + ms wave-graph-substrate" \
    "backlog-drain-wave-graph-substrate" \
    "$(wave_name_for_milestone backlog-drain wave-graph-substrate)"
assert_eq "epic cc-alignment + ms hook-consolidation" \
    "cc-alignment-hook-consolidation" \
    "$(wave_name_for_milestone cc-alignment hook-consolidation)"

echo "=== wave_gate_chain_has_cycle: acyclic chains pass (exit 0) ==="
printf 'wave-1\t\nwave-2\twave-1\nwave-3\twave-2\n' | wave_gate_chain_has_cycle
assert_status "linear chain wave-3->wave-2->wave-1->null" "0" "$?"

printf 'wave-1\t\nwave-2\t\nwave-3\t\n' | wave_gate_chain_has_cycle
assert_status "no gates at all (all ungated, order-free)" "0" "$?"

printf 'wave-a\twave-b\nwave-b\t\nwave-c\twave-b\n' | wave_gate_chain_has_cycle
assert_status "shared gate — two waves both gated on wave-b" "0" "$?"

echo "=== wave_gate_chain_has_cycle: cyclic chains fail (exit 1, diagnostic printed) ==="
printf 'wave-1\twave-2\nwave-2\twave-1\n' | wave_gate_chain_has_cycle >"$TMPDIR_T/cycle-out.txt"
assert_status "2-cycle: wave-1<->wave-2" "1" "$?"
TOTAL=$((TOTAL + 1))
if grep -qi 'cycle' "$TMPDIR_T/cycle-out.txt"; then
    echo "  PASS: 2-cycle diagnostic mentions 'cycle'"
    PASS=$((PASS + 1))
else
    echo "  FAIL: 2-cycle diagnostic missing — got: $(cat "$TMPDIR_T/cycle-out.txt")"
    FAIL=$((FAIL + 1))
fi

printf 'wave-1\twave-2\nwave-2\twave-3\nwave-3\twave-1\n' | wave_gate_chain_has_cycle
assert_status "3-cycle: wave-1->wave-2->wave-3->wave-1" "1" "$?"

printf 'wave-1\twave-1\n' | wave_gate_chain_has_cycle
assert_status "self-gate: wave-1->wave-1" "1" "$?"

echo "=== null literal is treated as no gate ==="
printf 'wave-1\tnull\nwave-2\twave-1\n' | wave_gate_chain_has_cycle
assert_status "gate field literal 'null' == ungated" "0" "$?"

echo "=== plan.md and decompose-mode.md reference the shared authority, not a restated check (AC parity with t-2494) ==="
PLAN_MD="$REPO_ROOT/system/skills/backlog/phases/plan.md"
DECOMPOSE_MODE_MD="$REPO_ROOT/system/skills/build/phases/decompose-mode.md"
for f in "$PLAN_MD" "$DECOMPOSE_MODE_MD"; do
    TOTAL=$((TOTAL + 1))
    if grep -q "wave-graph-emit.md" "$f"; then
        echo "  PASS: $(basename "$f") references wave-graph-emit.md"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $(basename "$f") does not reference the shared wave-graph-emit.md authority"
        FAIL=$((FAIL + 1))
    fi
done

echo "=== decompose-mode.md branches on resolve_epic_ancestor's exit status (Challenger finding, t-2843 iteration 1) ==="
# THE BUG. decompose-mode.md's first draft collapsed resolve_epic_ancestor's
# 3-way exit contract (slug+exit0 found / empty+exit0 real negative / exit1
# lookup FAILED — epic-ancestor-walk.md lines 28-31) into a bare empty-string
# check. A transient lookup failure would be indistinguishable from "no epic
# here" and silently skip the WAVES step for a genuinely epic-scoped
# decompose — the t-2263 failure class ("a dropped slug is how brana-v3-redesign
# went missing from a live close"). Every other caller of this shared
# primitive (start.md, session-state.md) branches on exit status; this one
# must too.
TOTAL=$((TOTAL + 1))
if grep -qi 'lookup failed' "$DECOMPOSE_MODE_MD"; then
    echo "  PASS: decompose-mode.md surfaces a lookup-failure diagnostic (does not conflate failure with no-epic)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: decompose-mode.md has no lookup-failure diagnostic — exit-status contract not honored"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))
if grep -qi 'non-zero exit' "$DECOMPOSE_MODE_MD"; then
    echo "  PASS: decompose-mode.md documents the non-zero-exit branch explicitly"
    PASS=$((PASS + 1))
else
    echo "  FAIL: decompose-mode.md does not document a non-zero-exit branch"
    FAIL=$((FAIL + 1))
fi

echo "=== gate chain is documented as cross-milestone only (Challenger finding, t-2843 iteration 1) ==="
for f in "$PLAN_MD" "$DECOMPOSE_MODE_MD"; do
    TOTAL=$((TOTAL + 1))
    if grep -qi 'cross-milestone' "$f"; then
        echo "  PASS: $(basename "$f") states the gate chain is cross-milestone only"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $(basename "$f") does not clarify cross-milestone-only, same-milestone self-gate risk undocumented"
        FAIL=$((FAIL + 1))
    fi
done

echo "=== contract interpolation carries quoting guidance (Challenger finding, t-2843 iteration 1) ==="
EMIT_QUOTING_TARGETS=("$PLAN_MD" "$DECOMPOSE_MODE_MD" "$EMIT_MD")
for f in "${EMIT_QUOTING_TARGETS[@]}"; do
    TOTAL=$((TOTAL + 1))
    if grep -qi 'quot' "$f"; then
        echo "  PASS: $(basename "$f") documents quoting for the --contract interpolation"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $(basename "$f") is missing quoting guidance for free-prose --contract interpolation"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
