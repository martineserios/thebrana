#!/usr/bin/env bash
# Regression test: the always-loaded context budget must be split into two
# INDEPENDENTLY GATED pools, and there must be exactly one place a budget
# constant lives (t-2505).
#
# Three defects this pins down:
#
# 1. DEAD SECOND GATE. `./pre-commit.sh` at the repo root carried its own
#    inline copy of the budget loop with a hardcoded 26,624-byte limit (written
#    with a comma throughout this file so the test cannot match its own source
#    — see the computed-needle note below). It was never
#    the installed hook — bootstrap.sh deploys system/scripts/git-hooks/pre-commit,
#    which delegates to context-budget.sh (28672). t-2177 unified the LIVE path
#    and left the root script behind. It was doubly stale: wrong limit AND a
#    wrong rule-selection predicate (`^paths:` inverted, vs `always-load: true`).
#    docs/24-roadmap-corrections.md:1652 predicted exactly this: "Two hardcoded
#    copies of the same number will drift — it's not a question of if, but when."
#
# 2. ONE CAP FOR TWO KINDS OF CONTENT. Hand-authored rules and auto-grown
#    routing metadata (skill + agent descriptions) shared a single limit, so
#    growth nobody reviews squeezed out writing someone deliberately did.
#    Measured at the time: descriptions were 8545 of 28653 bytes (~30%), and
#    the budget sat at 19 bytes of headroom.
#
# 3. NO REMEDY IN THE FAILURE. The gate printed a breakdown and left the
#    contributor to work out what to cut.
#
# On the rejected alternative — a PER-ITEM cap on descriptions. Measured over
# the real tree: 35 skills, 5875 bytes, ~168B mean, flat distribution with no
# fat tail. Capping each at 200B reclaims 411B total; getting ~1.8KB needs
# rewriting 31 of 35. And no per-item cap bounds the AGGREGATE, which is the
# actual failure mode — every new skill adds ~168B whatever the cap. Only an
# aggregate cap bounds aggregate growth.
#
# Run: bash tests/procedures/test-context-budget-split.sh

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

assert_contains() {
    local desc="$1" needle="$2" hay="$3"
    TOTAL=$((TOTAL + 1))
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — output did not contain [$needle]"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-context-budget-split.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/system/scripts/context-budget.sh"
[ -f "$SCRIPT" ] || { echo "ERROR: $SCRIPT not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ── Hermetic fixture ─────────────────────────────────────────────────────────
# Builds a SYSTEM_DIR with known byte sizes so the split can be asserted
# exactly rather than inferred from the live tree.
#   authored = CLAUDE.md + rules with `always-load: true`
#   routing  = skill descriptions + agent descriptions
mk_fixture() {  # mk_fixture <dir> <rule_bytes> <desc_bytes>
    local d="$1" rule_bytes="$2" desc_bytes="$3"
    mkdir -p "$d/rules" "$d/skills/alpha" "$d/agents"
    # CLAUDE.md — 11 bytes including newline.
    printf 'CLAUDEMD10\n' > "$d/CLAUDE.md"
    # One always-loaded rule padded to exactly $rule_bytes.
    {
        printf -- '---\nalways-load: true\n---\n'
        head -c "$rule_bytes" /dev/zero | tr '\0' 'x'
        printf '\n'
    } > "$d/rules/padded.md"
    # A README that must be EXCLUDED (the t-2174 bug) — make it huge so any
    # regression that counts it is impossible to miss.
    {
        printf -- '---\nalways-load: true\n---\n'
        head -c 9000 /dev/zero | tr '\0' 'y'
        printf '\n'
    } > "$d/rules/README.md"
    # A rule WITHOUT always-load — must also be excluded.
    printf -- '---\npaths: ["x"]\n---\nnotloaded\n' > "$d/rules/scoped.md"
    # Skill description padded so `grep ^description: | wc -c` is exactly
    # $desc_bytes. "description: " is 13 chars and wc -c counts the newline,
    # so the pad is desc_bytes - 14.
    {
        printf 'description: '
        head -c "$((desc_bytes - 14))" /dev/zero | tr '\0' 'd'
        printf '\n'
    } > "$d/skills/alpha/SKILL.md"
    # An agent with type: reference — must be EXCLUDED.
    printf -- '---\ntype: reference\ndescription: excluded-agent-description\n---\n' \
        > "$d/agents/refonly.md"
}

# ── 1. The dead 26,624 gate must be gone ─────────────────────────────────────
echo "AC1 — one budget constant, one enforcement point"
# The needle is COMPUTED, never written literally — a test that greps the tree
# for a forbidden string will otherwise match its own source and can never pass.
# Same self-match class as the `pgrep -f` watcher that matched its own argv
# (t-2503); the fix there was the same one: don't put the pattern in the file.
DEAD_LIMIT=$(( 26000 + 624 ))
DEAD_HITS=$(grep -rlF "$DEAD_LIMIT" "$REPO_ROOT" \
    --include='*.sh' \
    --exclude-dir=.git --exclude-dir=target --exclude-dir=node_modules \
    2>/dev/null | wc -l | tr -d ' ')
assert_eq "no shell script hardcodes the dead 26,624 limit" "0" "$DEAD_HITS"

assert_eq "the orphaned root pre-commit.sh is gone" \
    "absent" "$([ -e "$REPO_ROOT/pre-commit.sh" ] && echo present || echo absent)"

# The one surviving constant lives in context-budget.sh and nowhere else.
LIMIT_DEFS=$(grep -rlE '^[A-Z_]*(BUDGET|LIMIT)[A-Z_]*="\$\{[A-Z_]+:-[0-9]+\}"' \
    "$REPO_ROOT/system" "$REPO_ROOT/validate.sh" \
    --include='*.sh' --exclude-dir=target 2>/dev/null | wc -l | tr -d ' ')
assert_eq "budget limits are defined in exactly one file" "1" "$LIMIT_DEFS"
echo ""

# ── 2. Two independently gated pools ─────────────────────────────────────────
echo "AC3 — authored vs routing-metadata split"
mk_fixture "$TMPROOT/ok" 1000 500
OUT_OK=$(SYSTEM_DIR="$TMPROOT/ok" AUTHORED_LIMIT=5000 DESC_LIMIT=5000 \
    bash "$SCRIPT" --report 2>&1)
RC_OK=$?
assert_eq "both pools under limit → exit 0" "0" "$RC_OK"
assert_contains "report names the AUTHORED pool" "AUTHORED" "$OUT_OK"
assert_contains "report names the ROUTING METADATA pool" "ROUTING METADATA" "$OUT_OK"

# Authored total = CLAUDE.md(11) + padded rule. The rule file is
# "---\nalways-load: true\n---\n" (26B) + 1000 pad + 1 newline = 1027.
assert_contains "authored total excludes descriptions (11 + 1027 = 1038)" \
    "1038" "$OUT_OK"
# Routing total = the 500-byte skill description; the type:reference agent is out.
assert_contains "routing total counts only the skill description (500)" \
    "500" "$OUT_OK"
echo ""

# ── 3. The two pools gate INDEPENDENTLY ──────────────────────────────────────
echo "AC3 — neither pool can silently consume the other"
SYSTEM_DIR="$TMPROOT/ok" AUTHORED_LIMIT=5000 DESC_LIMIT=100 \
    bash "$SCRIPT" --check >/dev/null 2>&1
assert_eq "routing over, authored fine → exit 1" "1" "$?"

SYSTEM_DIR="$TMPROOT/ok" AUTHORED_LIMIT=100 DESC_LIMIT=5000 \
    bash "$SCRIPT" --check >/dev/null 2>&1
assert_eq "authored over, routing fine → exit 1" "1" "$?"

# A generous COMBINED allowance must not rescue a single blown pool — this is
# the regression that the old single-cap design could not express.
SYSTEM_DIR="$TMPROOT/ok" AUTHORED_LIMIT=100 DESC_LIMIT=999999 \
    bash "$SCRIPT" --check >/dev/null 2>&1
assert_eq "huge routing allowance does not mask an authored overrun" "1" "$?"
echo ""

# ── 4. Failure output names a remedy, not just a breakdown ───────────────────
echo "AC2 — failure names the specific remedy"
OUT_FAIL=$(SYSTEM_DIR="$TMPROOT/ok" AUTHORED_LIMIT=100 DESC_LIMIT=5000 \
    bash "$SCRIPT" --check 2>&1)
assert_contains "failure says which pool blew" "AUTHORED" "$OUT_FAIL"
assert_contains "failure names the largest contributor by name" \
    "rules/padded.md" "$OUT_FAIL"
assert_contains "failure states how many bytes must be reclaimed" \
    "reclaim" "$OUT_FAIL"
echo ""

# ── 5. README exclusion survives the refactor (t-2174 regression) ────────────
echo "t-2174 regression — rules/README.md stays excluded"
# README is 9000+ bytes of padding. If it were counted, authored would blow a
# 5000-byte limit; it must not.
SYSTEM_DIR="$TMPROOT/ok" AUTHORED_LIMIT=5000 DESC_LIMIT=5000 \
    bash "$SCRIPT" --check >/dev/null 2>&1
assert_eq "rules/README.md excluded from the authored pool" "0" "$?"
echo ""

# ── 6. Live tree has real headroom ───────────────────────────────────────────
echo "AC4 — measurable headroom on the real tree"
LIVE=$(SYSTEM_DIR="$REPO_ROOT/system" bash "$SCRIPT" --report 2>&1)
# Take the FIRST headroom line at or after the AUTHORED heading. The breakdown
# between them is one line per always-load rule, so a fixed `grep -A<n>` window
# silently misses it as the rule count changes — scan forward instead.
LIVE_AUTH_HEAD=$(printf '%s' "$LIVE" | awk '
    /AUTHORED/      { seen = 1 }
    seen && /headroom:/ {
        sub(/.*headroom:[ ]*/, ""); sub(/[^0-9-].*/, ""); print; exit
    }')
TOTAL=$((TOTAL + 1))
if [ -n "$LIVE_AUTH_HEAD" ] && [ "$LIVE_AUTH_HEAD" -ge 1024 ] 2>/dev/null; then
    echo "  PASS: authored headroom >= 1024B (got ${LIVE_AUTH_HEAD}B) — a typical rule addition needs no compression exercise"
    PASS=$((PASS + 1))
else
    echo "  FAIL: authored headroom >= 1024B — got [${LIVE_AUTH_HEAD:-unparseable}]"
    FAIL=$((FAIL + 1))
fi
echo ""

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
