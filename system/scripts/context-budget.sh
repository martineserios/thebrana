#!/usr/bin/env bash
#
# context-budget.sh — single source of truth for the always-loaded context budget.
#
# validate.sh (Check 5) and the pre-commit hook both call this so the two
# enforcement points can never drift — that duplication was the root cause of
# the t-2174 miscount. (t-2177 / epic t-2176.)
#
# TWO POOLS, GATED INDEPENDENTLY (t-2505)
# ---------------------------------------
# The always-loaded content splits by WHO CAUSES IT TO GROW:
#
#   AUTHORED          CLAUDE.md + rules with `always-load: true`.
#                     Someone deliberately writes every byte.
#
#   ROUTING METADATA  skill + agent `description:` lines.
#                     Grows automatically with every new skill or agent —
#                     nobody decides to spend these bytes.
#
# They used to share one cap. The consequence, measured 2026-07-28: routing
# metadata had reached 8545 of 28653 bytes (~30%) and the budget stood at 19
# bytes of headroom, so adding any hand-written rule required first compressing
# an existing one. Automatic growth was silently evicting deliberate writing.
# Separate caps mean neither pool can consume the other, and each is answerable
# for its own growth.
#
# WHY AN AGGREGATE CAP ON DESCRIPTIONS, NOT A PER-ITEM ONE (t-2505 decision).
# Measured over the real tree: 35 skills, 5875 bytes, ~168B mean, flat
# distribution with no fat tail. A 200B per-item cap reclaims 411B total;
# reaching ~1.8KB means rewriting 31 of 35 descriptions. And no per-item cap
# bounds the AGGREGATE — every new skill adds ~168B whatever the cap is, which
# is precisely the failure mode. Only an aggregate cap bounds aggregate growth.
# Structural follow-up (should always-loaded rules carry full guidance at all,
# or only a trigger line?) routes through the context-economy epic t-2484.
#
# Modes:
#   --report (default)  print per-pool breakdown + totals; exit 1 if either is over
#   --check             silent on success; on failure print report + remedy to stderr; exit 1
#   --total             print only the combined integer total; exit 1 if either is over
#
# Env overrides (for hermetic tests):
#   SYSTEM_DIR      default: <git toplevel>/system
#   AUTHORED_LIMIT  default: 22528  (22KB — CLAUDE.md + always-load rules)
#   DESC_LIMIT      default: 10240  (10KB — skill + agent descriptions)

set -uo pipefail

MODE="${1:---report}"
SYSTEM_DIR="${SYSTEM_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)/system}"
AUTHORED_LIMIT="${AUTHORED_LIMIT:-22528}"
DESC_LIMIT="${DESC_LIMIT:-10240}"

authored=0
routing=0
authored_breakdown=""
routing_breakdown=""
authored_max=0
authored_max_label=""
routing_max=0
routing_max_label=""

add_authored() {  # add_authored <size> <label>
    authored=$((authored + $1))
    authored_breakdown="${authored_breakdown}$(printf '%7d  %s' "$1" "$2")
"
    if [ "$1" -gt "$authored_max" ]; then
        authored_max="$1"; authored_max_label="$2"
    fi
}

add_routing() {  # add_routing <size> <label>
    routing=$((routing + $1))
    routing_breakdown="${routing_breakdown}$(printf '%7d  %s' "$1" "$2")
"
    if [ "$1" -gt "$routing_max" ]; then
        routing_max="$1"; routing_max_label="$2"
    fi
}

# ── AUTHORED pool ────────────────────────────────────────────────────────────

# CLAUDE.md — always loaded.
[ -f "$SYSTEM_DIR/CLAUDE.md" ] && add_authored "$(wc -c < "$SYSTEM_DIR/CLAUDE.md")" "CLAUDE.md"

# Rules with always-load: true. README.md is the rules-dir authoring contract
# (docs), not a loaded rule — exclude by name so neither its bytes nor its
# example frontmatter ever count (the t-2174 bug).
for rf in "$SYSTEM_DIR"/rules/*.md; do
    [ -f "$rf" ] || continue
    [ "$(basename "$rf")" = "README.md" ] && continue
    if grep -qE '^always-load:[[:space:]]+true' "$rf" 2>/dev/null; then
        add_authored "$(wc -c < "$rf")" "rules/$(basename "$rf")"
    fi
done

# ── ROUTING METADATA pool ────────────────────────────────────────────────────

# Skill descriptions (the description: line only, frontmatter-scoped like the
# agents loop below — a bare whole-file grep also matches "description:" lines
# inside documentation examples in a skill's body, e.g. acquire-skills' own
# template snippet, inflating the count with non-routing text).
skills_total=0
for sd in "$SYSTEM_DIR"/skills/*/; do
    [ "$(basename "$sd")" = "acquired" ] && continue
    sf="${sd}SKILL.md"
    [ -f "$sf" ] || continue
    fm=$(sed -n '/^---$/,/^---$/p' "$sf")
    skills_total=$((skills_total + $(echo "$fm" | grep '^description:' | wc -c)))
done
[ "$skills_total" -gt 0 ] && add_routing "$skills_total" "skill descriptions (all)"

# Agent descriptions (description: line in frontmatter; type:reference excluded).
agents_total=0
for af in "$SYSTEM_DIR"/agents/*.md; do
    [ -f "$af" ] || continue
    fm=$(sed -n '/^---$/,/^---$/p' "$af")
    echo "$fm" | grep -q '^type: reference' && continue
    agents_total=$((agents_total + $(echo "$fm" | grep '^description:' | wc -c)))
done
[ "$agents_total" -gt 0 ] && add_routing "$agents_total" "agent descriptions (all)"

# ── Verdict ──────────────────────────────────────────────────────────────────

authored_over=0
routing_over=0
[ "$authored" -gt "$AUTHORED_LIMIT" ] && authored_over=1
[ "$routing"  -gt "$DESC_LIMIT" ]     && routing_over=1

over=0
if [ "$authored_over" -eq 1 ] || [ "$routing_over" -eq 1 ]; then
    over=1
fi

combined=$((authored + routing))

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
    echo "Context budget (always-loaded, GATED) — two independent pools:"
    echo ""
    echo "  AUTHORED  (CLAUDE.md + always-load rules — every byte deliberately written)"
    printf '%s' "$authored_breakdown" | sort -rn
    echo "  -------"
    echo "  Total: ${authored} / ${AUTHORED_LIMIT} bytes  (headroom: $((AUTHORED_LIMIT - authored)))"
    echo ""
    echo "  ROUTING METADATA  (skill + agent descriptions — grows with every new skill/agent)"
    printf '%s' "$routing_breakdown" | sort -rn
    echo "  -------"
    echo "  Total: ${routing} / ${DESC_LIMIT} bytes  (headroom: $((DESC_LIMIT - routing)))"
    echo ""
    echo "  Combined always-loaded: ${combined} bytes"
    echo ""
    echo "  --- informational: the larger UNGATED baseline (per 31-assurance.md; audit: t-2181) ---"
    echo "  MCP servers configured: ${mcp_count}  (tool definitions ~30-70K tokens/session; Tool Search reduces ~85%)"
    echo "  Compaction buffer: ~33-45K tokens reserved"
    echo "  Note: the gated budget above is ~7K tokens — these dwarf it. Govern there too (t-2181)."
}

# Name the specific remedy, not just the breakdown (t-2505 AC2): which pool
# blew, how many bytes must come back, and the single biggest thing to cut.
print_remedy() {
    echo ""
    echo "REMEDY:"
    if [ "$authored_over" -eq 1 ]; then
        echo "  AUTHORED pool is over by $((authored - AUTHORED_LIMIT)) bytes."
        echo "    -> reclaim $((authored - AUTHORED_LIMIT)) bytes from always-load rules."
        echo "       Largest item: ${authored_max_label} (${authored_max} B)."
        echo "       Options: compress its prose; add 'paths:' frontmatter to scope it to"
        echo "       matching files; or move detail into a skill that loads on demand."
    fi
    if [ "$routing_over" -eq 1 ]; then
        echo "  ROUTING METADATA pool is over by $((routing - DESC_LIMIT)) bytes."
        echo "    -> reclaim $((routing - DESC_LIMIT)) bytes from skill/agent descriptions."
        echo "       Largest item: ${routing_max_label} (${routing_max} B)."
        echo "       Options: shorten the longest 'description:' lines, or retire an unused"
        echo "       skill/agent. A per-item cap will NOT help much — the distribution is"
        echo "       flat; the driver is the COUNT of skills, not their individual size."
    fi
    echo "  Governance: system/rules/README.md; context-economy epic t-2484."
}

case "$MODE" in
    --total)
        echo "$combined"
        ;;
    --check)
        [ "$over" -eq 1 ] && { echo "❌ Context budget exceeded:"; print_report; print_remedy; } >&2
        ;;
    --report|*)
        print_report
        [ "$over" -eq 1 ] && print_remedy
        ;;
esac

exit "$over"
