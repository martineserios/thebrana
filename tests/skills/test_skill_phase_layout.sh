#!/usr/bin/env bash
# Structural test for the big-four phase-split layout (t-1942).
# Written BEFORE the transformation (TDD) — encodes the target end-state:
#   - slim SKILL.md (≤500 lines) with a machine-readable PHASES registry,
#     a step-boundary Read rule, and a resume-after-compression protocol
#   - per-phase sub-files ≤400 lines, all registered, no orphans
#   - monolith system/procedures/{name}.md deleted
#   - Challenger Gate extracted to _shared/ (no orphaned forward refs)
#   - test_skill_inline_layout.sh allowlist emptied
# Run: bash tests/skills/test_skill_phase_layout.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/system/skills"
BIG_FOUR="build close backlog reconcile"

PASS=0
FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== test_skill_phase_layout.sh ==="

for name in $BIG_FOUR; do
    sk="$SKILLS_DIR/$name/SKILL.md"
    phases_dir="$SKILLS_DIR/$name/phases"

    # 1. Slim SKILL.md exists, is not a stub, and is ≤500 lines
    if [ ! -f "$sk" ]; then
        bad "$name: SKILL.md missing"
        continue
    fi
    if grep -q "PROCEDURE_FILE" "$sk"; then
        bad "$name: SKILL.md is still a stub (PROCEDURE_FILE marker present)"
    else
        ok "$name: SKILL.md is not a stub"
    fi
    lines=$(wc -l < "$sk")
    if [ "$lines" -le 500 ]; then
        ok "$name: SKILL.md is $lines lines (≤500)"
    else
        bad "$name: SKILL.md is $lines lines (>500)"
    fi

    # 2. PHASES registry block present and machine-readable
    if grep -q "<!-- PHASES -->" "$sk" && grep -q "<!-- /PHASES -->" "$sk"; then
        ok "$name: PHASES registry markers present"
    else
        bad "$name: PHASES registry markers missing (<!-- PHASES --> ... <!-- /PHASES -->)"
        continue
    fi

    # Extract registered phase files: table rows between markers, second column
    registered=$(sed -n '/<!-- PHASES -->/,/<!-- \/PHASES -->/p' "$sk" \
        | grep -oE 'phases/[a-z0-9-]+\.md' | sort -u)
    if [ -z "$registered" ]; then
        bad "$name: PHASES registry lists no phase files"
        continue
    fi

    # 3. Step-boundary Read rule + resume protocol in SKILL.md
    if grep -qi "read.*phase file\|read the next phase\|read its phase file" "$sk"; then
        ok "$name: step-boundary Read rule present"
    else
        bad "$name: no step-boundary Read rule (model will free-run from memory)"
    fi
    if grep -qiE "resum(e|ing).*(read|load)|after compression.*read" "$sk"; then
        ok "$name: resume-after-compression protocol present"
    else
        bad "$name: no resume protocol (mid-procedure resume executes from empty context)"
    fi

    # 4. Every registered phase file exists and is ≤400 lines
    while IFS= read -r rel; do
        pf="$SKILLS_DIR/$name/$rel"
        if [ ! -f "$pf" ]; then
            bad "$name: registered phase file missing: $rel"
            continue
        fi
        plines=$(wc -l < "$pf")
        if [ "$plines" -le 400 ]; then
            ok "$name: $rel is $plines lines (≤400)"
        else
            bad "$name: $rel is $plines lines (>400 — split further)"
        fi
    done <<< "$registered"

    # 5. No orphan phase files (present on disk but not in the registry)
    if [ -d "$phases_dir" ]; then
        for pf in "$phases_dir"/*.md; do
            [ -f "$pf" ] || continue
            rel="phases/$(basename "$pf")"
            if ! echo "$registered" | grep -qx "$rel"; then
                bad "$name: orphan phase file not in registry: $rel"
            fi
        done
    fi

    # 6. Monolith procedure file deleted
    if [ -f "$REPO_ROOT/system/procedures/$name.md" ]; then
        bad "$name: monolith system/procedures/$name.md still exists"
    else
        ok "$name: monolith procedure file removed"
    fi

    # 7. No orphaned cross-strategy forward references in phase files
    if [ -d "$phases_dir" ] && grep -rq "Full procedure defined in" "$phases_dir"; then
        bad "$name: orphaned 'Full procedure defined in' forward reference in phases/"
    else
        ok "$name: no orphaned forward references"
    fi
done

# 8. Challenger Gate extracted to _shared/ and referenced from build phases
CG="$SKILLS_DIR/_shared/challenger-gate.md"
if [ -f "$CG" ]; then
    ok "challenger-gate.md exists in _shared/"
    cg_lines=$(wc -l < "$CG")
    if [ "$cg_lines" -le 400 ]; then
        ok "challenger-gate.md is $cg_lines lines (≤400)"
    else
        bad "challenger-gate.md is $cg_lines lines (>400)"
    fi
    if grep -rq "challenger-gate.md" "$SKILLS_DIR/build/"; then
        ok "build skill references _shared/challenger-gate.md"
    else
        bad "build skill never references _shared/challenger-gate.md (gate lost in split)"
    fi
else
    bad "_shared/challenger-gate.md missing (Challenger Gate not extracted)"
fi

# 9. Inline-layout allowlist emptied (big-four exception over)
ALLOW_LINE=$(grep -E '^ALLOWLIST=' "$SCRIPT_DIR/test_skill_inline_layout.sh" || true)
if [ "$ALLOW_LINE" = 'ALLOWLIST=""' ]; then
    ok "test_skill_inline_layout.sh allowlist is empty"
else
    bad "test_skill_inline_layout.sh allowlist not emptied: $ALLOW_LINE"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
