#!/usr/bin/env bash
# Structural test for ADR-034 amendment (t-1941): 1:1 SKILL.md→procedure
# indirection is collapsed. Only the big four keep stubs until t-1942.
#
# Usage: test_skill_inline_layout.sh [system-dir]
#   Default system-dir is <repo>/system. Pass the deployed plugin cache
#   (~/.claude/plugins/cache/brana/brana/1.0.0) to verify the deployed state.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYSTEM_DIR="${1:-$REPO_ROOT/system}"

ALLOWLIST="build close backlog reconcile"

pass=0; fail=0

ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
bad() { echo "  FAIL: $1"; fail=$((fail+1)); }

in_allowlist() {
    local name="$1"
    for a in $ALLOWLIST; do [ "$a" = "$name" ] && return 0; done
    return 1
}

echo "=== Skill inline layout (t-1941) — $SYSTEM_DIR ==="

[ -d "$SYSTEM_DIR/skills" ] || { echo "  FAIL: $SYSTEM_DIR/skills not found"; exit 1; }

# 1. No stub outside the big-four allowlist (native + acquired)
for sk in "$SYSTEM_DIR"/skills/*/SKILL.md "$SYSTEM_DIR"/skills/acquired/*/SKILL.md; do
    [ -f "$sk" ] || continue
    name="$(basename "$(dirname "$sk")")"
    if grep -q "PROCEDURE_FILE" "$sk"; then
        if in_allowlist "$name"; then
            ok "$name: allowlisted stub (big four, pending t-1942)"
        else
            bad "$name: stub outside big-four allowlist — inline its procedure body"
        fi
    fi
done

# 2. Every allowlisted stub still resolves
for name in $ALLOWLIST; do
    sk="$SYSTEM_DIR/skills/$name/SKILL.md"
    [ -f "$sk" ] || { bad "$name: SKILL.md missing"; continue; }
    if grep -q "PROCEDURE_FILE" "$sk"; then
        if [ -f "$SYSTEM_DIR/procedures/$name.md" ]; then
            ok "$name: stub resolves to procedures/$name.md"
        else
            bad "$name: stub points at missing procedures/$name.md"
        fi
    else
        ok "$name: already inlined (allowlist entry obsolete — shrink it)"
    fi
done

# 3. No orphaned 1:1 procedure file: a procedures/{name}.md whose name matches
#    a skill dir must belong to the big four (everything else was inlined+deleted)
for proc in "$SYSTEM_DIR"/procedures/*.md; do
    [ -f "$proc" ] || continue
    name="$(basename "$proc" .md)"
    if { [ -d "$SYSTEM_DIR/skills/$name" ] || [ -d "$SYSTEM_DIR/skills/acquired/$name" ]; } && ! in_allowlist "$name"; then
        bad "procedures/$name.md still exists alongside skills/$name/ — should be inlined and deleted"
    fi
done

# 4. Inlined SKILL.md files have intact frontmatter (two --- delimiters, name: present)
for sk in "$SYSTEM_DIR"/skills/*/SKILL.md "$SYSTEM_DIR"/skills/acquired/*/SKILL.md; do
    [ -f "$sk" ] || continue
    name="$(basename "$(dirname "$sk")")"
    grep -q "PROCEDURE_FILE" "$sk" && continue
    if [ "$(head -1 "$sk")" = "---" ] && awk 'NR>1 && /^---$/{found=1; exit} END{exit !found}' "$sk" \
       && sed -n '2,/^---$/p' "$sk" | grep -q "^name:"; then
        ok "$name: frontmatter intact"
    else
        bad "$name: frontmatter malformed after inline"
    fi
done

echo ""
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && { echo "ALL TESTS PASSED"; exit 0; } || { echo "TESTS FAILED"; exit 1; }
