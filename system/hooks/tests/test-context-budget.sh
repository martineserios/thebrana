#!/usr/bin/env bash
# Tests for context-budget.sh (t-2177) — single source of truth for the
# always-loaded context budget. Verifies the GATED total sums the right sources
# and EXCLUDES the bug-prone ones: README.md (even with an always-load example
# in its body — the exact t-2174 miscount), path-scoped rules, skills/acquired,
# and type:reference agents. Also checks the --total/--check/--report modes and
# the over-limit exit code.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../scripts/context-budget.sh"
PASS=0; FAIL=0
ok() { if eval "$2"; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got: ${3:-})"; FAIL=$((FAIL+1)); fi; }

# --- hermetic fixture -------------------------------------------------------
FX=$(mktemp -d)
SYS="$FX/system"
mkdir -p "$SYS/rules" "$SYS/skills/alpha" "$SYS/skills/acquired/beta" "$SYS/agents"

printf 'CLAUDE stub line\n' > "$SYS/CLAUDE.md"                                  # COUNTED
printf -- '---\nalways-load: true\n---\n# Universal rule body text\n' > "$SYS/rules/universal.md"   # COUNTED
printf -- '---\npaths: ["src/**"]\n---\n# Scoped rule body padding padding padding\n' > "$SYS/rules/scoped.md"  # NOT counted
# README has an always-load:true EXAMPLE in its BODY — must NOT be counted:
printf '# Authoring Contract\n\nExample:\n```\nalways-load: true\n```\npadding XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n' > "$SYS/rules/README.md"  # NOT counted
printf -- '---\nname: alpha\ndescription: Alpha skill does a thing.\n---\n# Alpha body\n' > "$SYS/skills/alpha/SKILL.md"  # desc COUNTED
printf -- '---\ndescription: acquired skill must be skipped.\n---\n' > "$SYS/skills/acquired/beta/SKILL.md"  # NOT counted
printf -- '---\nname: a1\ndescription: Agent one summary.\n---\n# A1 body\n' > "$SYS/agents/a1.md"  # desc COUNTED
printf -- '---\nname: ref\ntype: reference\ndescription: Reference, not an agent.\n---\n' > "$SYS/agents/calibration.md"  # NOT counted

# independent expected sum (only the COUNTED sources)
exp=0
exp=$((exp + $(wc -c < "$SYS/CLAUDE.md")))
exp=$((exp + $(wc -c < "$SYS/rules/universal.md")))
exp=$((exp + $(grep '^description:' "$SYS/skills/alpha/SKILL.md" | wc -c)))
exp=$((exp + $(sed -n '/^---$/,/^---$/p' "$SYS/agents/a1.md" | grep '^description:' | wc -c)))

got=$(SYSTEM_DIR="$SYS" BUDGET_LIMIT=999999 bash "$SCRIPT" --total 2>/dev/null)
ok "--total = expected (scoped/README/acquired/reference all excluded)" "[ \"$got\" = \"$exp\" ]" "$got vs $exp"

rdme=$(wc -c < "$SYS/rules/README.md")
ok "README body example never counted (t-2174 regression)" "[ \"$got\" = \"$exp\" ] && [ $rdme -gt 0 ]" "$got"

SYSTEM_DIR="$SYS" BUDGET_LIMIT=10 bash "$SCRIPT" --check >/dev/null 2>&1
ok "exit 1 when over limit" "[ $? -eq 1 ]"

SYSTEM_DIR="$SYS" BUDGET_LIMIT=999999 bash "$SCRIPT" --check > "$FX/chk.txt" 2>&1; rc=$?
ok "exit 0 when under limit" "[ $rc -eq 0 ]"
ok "--check silent on success" "[ ! -s '$FX/chk.txt' ]"

SYSTEM_DIR="$SYS" BUDGET_LIMIT=10 bash "$SCRIPT" --check > "$FX/chkfail.txt" 2>&1
ok "--check prints breakdown on failure" "grep -q 'Total:' '$FX/chkfail.txt'"

SYSTEM_DIR="$SYS" BUDGET_LIMIT=999999 bash "$SCRIPT" --report > "$FX/rep.txt" 2>&1
ok "--report shows Total line" "grep -q 'Total:' '$FX/rep.txt'"
ok "--report shows informational envelope pointer (t-2181)" "grep -q 't-2181' '$FX/rep.txt'"

rm -rf "$FX"
echo ""
echo "context-budget: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
