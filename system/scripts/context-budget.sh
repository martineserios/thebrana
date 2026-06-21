#!/usr/bin/env bash
#
# context-budget.sh — single source of truth for the always-loaded context budget.
#
# Computes the GATED budget (CLAUDE.md + always-load:true rules excluding the
# README authoring-contract doc + skill descriptions + agent descriptions) and
# reports the full baseline envelope. validate.sh (Check 5) and the pre-commit
# hook both call this so the two enforcement points can never drift — that
# duplication was the root cause of the t-2174 miscount. (t-2177 / epic t-2176.)
#
# Modes:
#   --report (default)  print per-source breakdown + total + envelope; exit 1 if over limit
#   --check             silent on success; on failure print breakdown to stderr; exit 1
#   --total             print only the integer total; exit 1 if over limit
#
# Env overrides (for hermetic tests):
#   SYSTEM_DIR     default: <git toplevel>/system
#   BUDGET_LIMIT   default: 28672  (mirrors validate.sh Check 5; see t-2179 re: re-baseline)

set -uo pipefail

MODE="${1:---report}"
SYSTEM_DIR="${SYSTEM_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)/system}"
BUDGET_LIMIT="${BUDGET_LIMIT:-28672}"

budget=0
breakdown=""

add() {  # add <size> <label>
    budget=$((budget + $1))
    breakdown="${breakdown}$(printf '%7d  %s' "$1" "$2")
"
}

# CLAUDE.md — always loaded.
[ -f "$SYSTEM_DIR/CLAUDE.md" ] && add "$(wc -c < "$SYSTEM_DIR/CLAUDE.md")" "CLAUDE.md"

# Rules with always-load: true. README.md is the rules-dir authoring contract
# (docs), not a loaded rule — exclude by name so neither its bytes nor its
# example frontmatter ever count (the t-2174 bug).
for rf in "$SYSTEM_DIR"/rules/*.md; do
    [ -f "$rf" ] || continue
    [ "$(basename "$rf")" = "README.md" ] && continue
    if grep -qE '^always-load:[[:space:]]+true' "$rf" 2>/dev/null; then
        add "$(wc -c < "$rf")" "rules/$(basename "$rf")"
    fi
done

# Skill descriptions (the description: line only; the acquired/ tree is excluded).
skills_total=0
for sd in "$SYSTEM_DIR"/skills/*/; do
    [ "$(basename "$sd")" = "acquired" ] && continue
    sf="${sd}SKILL.md"
    [ -f "$sf" ] || continue
    skills_total=$((skills_total + $(grep '^description:' "$sf" | wc -c)))
done
[ "$skills_total" -gt 0 ] && add "$skills_total" "skill descriptions (all)"

# Agent descriptions (description: line in frontmatter; type:reference excluded).
agents_total=0
for af in "$SYSTEM_DIR"/agents/*.md; do
    [ -f "$af" ] || continue
    fm=$(sed -n '/^---$/,/^---$/p' "$af")
    echo "$fm" | grep -q '^type: reference' && continue
    agents_total=$((agents_total + $(echo "$fm" | grep '^description:' | wc -c)))
done
[ "$agents_total" -gt 0 ] && add "$agents_total" "agent descriptions (all)"

over=0
[ "$budget" -gt "$BUDGET_LIMIT" ] && over=1

# Best-effort count of configured MCP servers (their tool definitions are the
# dominant, uncontrolled baseline cost — but only knowable at runtime).
mcp_count="?"
if command -v jq >/dev/null 2>&1; then
    n=0
    for cfg in "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"; do
        [ -f "$cfg" ] || continue
        k=$(jq -r '(.mcpServers // {}) | length' "$cfg" 2>/dev/null || echo 0)
        [ -n "$k" ] && [ "$k" -eq "$k" ] 2>/dev/null && n=$((n + k))
    done
    mcp_count="$n"
fi

print_report() {
    echo "Context budget (always-loaded, GATED):"
    printf '%s' "$breakdown" | sort -rn
    echo "  -------"
    echo "  Total: ${budget} / ${BUDGET_LIMIT} bytes  (headroom: $((BUDGET_LIMIT - budget)))"
    echo ""
    echo "  --- informational: the larger UNGATED baseline (per 31-assurance.md; audit: t-2181) ---"
    echo "  MCP servers configured: ${mcp_count}  (tool definitions ~30-70K tokens/session; Tool Search reduces ~85%)"
    echo "  Compaction buffer: ~33-45K tokens reserved"
    echo "  Note: the gated rule budget above is ~7K tokens — these dwarf it. Govern there too (t-2181)."
}

case "$MODE" in
    --total)
        echo "$budget"
        ;;
    --check)
        [ "$over" -eq 1 ] && { echo "❌ Context budget exceeded:"; print_report; } >&2
        ;;
    --report|*)
        print_report
        ;;
esac

exit "$over"
