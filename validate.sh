#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
DOCS_DIR="$SCRIPT_DIR/docs"
KNOWLEDGE_DIR="$HOME/enter_thebrana/brana-knowledge"
SPEC_GRAPH="$DOCS_DIR/spec-graph.json"
ERRORS=0
WARNINGS=0

# Flags
RUN_ASSUMPTIONS_ONLY=false
RUN_SCALE_TRIGGERS=false
GRACE_DAYS=7

while [[ $# -gt 0 ]]; do
    case "$1" in
        --assumptions-only) RUN_ASSUMPTIONS_ONLY=true; shift ;;
        --scale-triggers) RUN_SCALE_TRIGGERS=true; shift ;;
        --grace-days) GRACE_DAYS="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

echo "=== Brana Validate ==="
echo ""

fail() { echo "  FAIL: $1"; ((ERRORS++)); }
warn() { echo "  WARN: $1"; ((WARNINGS++)); }
pass() { echo "  PASS: $1"; }

# ── Checks 1-14: Core validation ─────────────────────────────────────────
# Skip when running subset flags
if ! $RUN_ASSUMPTIONS_ONLY && ! $RUN_SCALE_TRIGGERS; then

# Check 1: Skill YAML frontmatter
echo "Checking skill frontmatter..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    # Skip acquired/ — it contains marketplace skills with their own subdirectories
    [ "$skill_name" = "acquired" ] && continue
    skill_file="$skill_dir/SKILL.md"

    if [ ! -f "$skill_file" ]; then
        fail "Missing SKILL.md in skills/$skill_name/"
        continue
    fi

    # Extract YAML frontmatter (only the first --- block, ignoring --- horizontal rules in body)
    frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$skill_file")
    if [ -z "$frontmatter" ]; then
        fail "No YAML frontmatter in skills/$skill_name/SKILL.md"
        continue
    fi

    if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
        fail "Invalid YAML in skills/$skill_name/SKILL.md"
        continue
    fi

    # Check name field matches directory
    yaml_name=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print(d.get('name',''))")
    if [ "$yaml_name" != "$skill_name" ]; then
        fail "Skill name mismatch: dir=$skill_name, yaml=$yaml_name"
    else
        pass "skills/$skill_name/ — valid frontmatter, name matches"
    fi
done
echo ""

# Check 2: Rule files (frontmatter optional)
echo "Checking rules..."
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    rule_name=$(basename "$rule_file")
    if head -1 "$rule_file" | grep -q '^---$'; then
        frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$rule_file")
        if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
            fail "Invalid YAML frontmatter in rules/$rule_name"
        else
            pass "rules/$rule_name — valid frontmatter"
        fi
    else
        pass "rules/$rule_name — no frontmatter (loads unconditionally)"
    fi
done
echo ""

# Check 3: JSON validity
echo "Checking JSON files..."
if [ -f "$SYSTEM_DIR/settings.json" ]; then
    if jq . "$SYSTEM_DIR/settings.json" > /dev/null 2>&1; then
        pass "settings.json — valid JSON"
    else
        fail "settings.json — invalid JSON"
    fi
else
    pass "settings.json — not present (OK since v1.0.0)"
fi
echo ""

# Check 4: Agent frontmatter
echo "Checking agents..."
for agent_file in "$SYSTEM_DIR"/agents/*.md; do
    agent_name=$(basename "$agent_file" .md)
    frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$agent_file")
    if [ -z "$frontmatter" ]; then
        fail "No YAML frontmatter in agents/$agent_name.md"
        continue
    fi

    has_name=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print('yes' if d.get('name') else 'no')")
    has_desc=$(echo "$frontmatter" | python3 -c "import sys, yaml; d=yaml.safe_load(sys.stdin); print('yes' if d.get('description') else 'no')")

    if [ "$has_name" != "yes" ]; then fail "agents/$agent_name.md missing 'name' field"; fi
    if [ "$has_desc" != "yes" ]; then fail "agents/$agent_name.md missing 'description' field"; fi
    if [ "$has_name" = "yes" ] && [ "$has_desc" = "yes" ]; then
        pass "agents/$agent_name.md — valid frontmatter"
    fi
done
echo ""

# Check 5: Context budget
echo "Checking context budget..."
BUDGET=0

# CLAUDE.md (always loaded)
if [ -f "$SYSTEM_DIR/CLAUDE.md" ]; then
    SIZE=$(wc -c < "$SYSTEM_DIR/CLAUDE.md")
    BUDGET=$((BUDGET + SIZE))
    echo "  CLAUDE.md: ${SIZE} bytes"
fi

# Rules without paths: field (always loaded)
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    if ! grep -q '^paths:' "$rule_file" 2>/dev/null; then
        SIZE=$(wc -c < "$rule_file")
        BUDGET=$((BUDGET + SIZE))
        echo "  $(basename "$rule_file"): ${SIZE} bytes (always loaded)"
    fi
done

# Skill descriptions (just the description line from frontmatter)
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    [ "$(basename "$skill_dir")" = "acquired" ] && continue
    skill_file="$skill_dir/SKILL.md"
    if [ -f "$skill_file" ]; then
        DESC_SIZE=$(grep '^description:' "$skill_file" | wc -c)
        BUDGET=$((BUDGET + DESC_SIZE))
    fi
done

# Agent descriptions (loaded into context — see 24-roadmap-corrections.md error #7)
for agent_file in "$SYSTEM_DIR"/agents/*.md; do
    if [ -f "$agent_file" ]; then
        AGENT_DESC_SIZE=$(sed -n '/^---$/,/^---$/p' "$agent_file" | grep '^description:' | wc -c)
        BUDGET=$((BUDGET + AGENT_DESC_SIZE))
        if [ "$AGENT_DESC_SIZE" -gt 0 ]; then
            echo "  $(basename "$agent_file") description: ${AGENT_DESC_SIZE} bytes"
        fi
    fi
done

echo "  Total always-loaded: ${BUDGET} bytes"
if [ "$BUDGET" -gt 28672 ]; then
    fail "Context budget exceeds 28KB (${BUDGET} bytes > 28672 bytes)"
else
    pass "Context budget OK (${BUDGET}/28672 bytes)"
fi

# Check 5b: Instruction density
echo "Checking instruction density..."
DIRECTIVE_PATTERN='(^- \*\*|^[0-9]+\. \*\*|^\* \*\*|^- (Always|Never|Use|Prefer|Avoid|Check|Run|Keep|Only|Do |Don.t|If |When |Before|After|Every|No |The |For |Set|Skip|Match|Create|Read|Write|Delete|Mark|Store|Spawn|Present|Wait|Include|Ensure|Reserve|Resist|Stop|Defer|Flag|Append|Insert)|^\| .+\| .+\|)'
DIRECTIVES=0

# CLAUDE.md directives
if [ -f "$SYSTEM_DIR/CLAUDE.md" ]; then
    c=$(grep -cE "$DIRECTIVE_PATTERN" "$SYSTEM_DIR/CLAUDE.md" || true)
    c=${c:-0}
    DIRECTIVES=$((DIRECTIVES + c))
fi

# Rule directives (unconditional only)
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    [ -f "$rule_file" ] || continue
    # Skip path-scoped rules (they don't always load)
    grep -q '^paths:' "$rule_file" 2>/dev/null && continue
    c=$(grep -cE "$DIRECTIVE_PATTERN" "$rule_file" || true)
    c=${c:-0}
    DIRECTIVES=$((DIRECTIVES + c))
done

# Skill descriptions (1 trigger directive each)
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    [ "$(basename "$skill_dir")" = "acquired" ] && continue
    [ -f "$skill_dir/SKILL.md" ] && DIRECTIVES=$((DIRECTIVES + 1))
done

# Agent descriptions (~2 boundary directives each)
for agent_file in "$SYSTEM_DIR"/agents/*.md; do
    [ -f "$agent_file" ] && DIRECTIVES=$((DIRECTIVES + 2))
done

echo "  Total always-present directives: ~${DIRECTIVES}"
if [ "$DIRECTIVES" -gt 300 ]; then
    fail "Instruction density critical (${DIRECTIVES} > 300 max)"
elif [ "$DIRECTIVES" -gt 200 ]; then
    warn "Instruction density high (${DIRECTIVES} > 200 warn threshold)"
else
    pass "Instruction density OK (~${DIRECTIVES}/200 warn, 300 max)"
fi
echo ""

# Check 6: No secrets
echo "Checking for secrets..."
SECRETS_FOUND=$(grep -rn -E '(API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY)\s*=' "$SYSTEM_DIR" 2>/dev/null | grep -v -E '(\.sh:|#|example|placeholder|never commit)' || true)
if [ -n "$SECRETS_FOUND" ]; then
    fail "Potential secrets found:"
    echo "$SECRETS_FOUND"
else
    pass "No secrets detected"
fi
echo ""

# Check 7: Duplicate skill names
echo "Checking for duplicate skill names..."
SKILL_NAMES=$(for f in "$SYSTEM_DIR"/skills/*/SKILL.md; do
    echo "$f" | grep -q '/acquired/' && continue
    sed -n '/^---$/,/^---$/p' "$f" | grep '^name:' | sed 's/name: *//'
done | sort)
DUPES=$(echo "$SKILL_NAMES" | uniq -d)
if [ -n "$DUPES" ]; then
    fail "Duplicate skill names: $DUPES"
else
    pass "No duplicate skill names"
fi
echo ""

# Check 8: File size sanity
echo "Checking file sizes..."
OVERSIZED=$(find "$SYSTEM_DIR" -type f -size +50k 2>/dev/null)
if [ -n "$OVERSIZED" ]; then
    fail "Files over 50KB found:"
    echo "$OVERSIZED"
else
    pass "All files under 50KB"
fi
echo ""

# Check 9: Hook scripts
echo "Checking hook scripts..."
KNOWN_EVENTS="PreToolUse PostToolUse PreToolUseFailure PostToolUseFailure Stop Notification SubagentStop SubagentNotification SessionStart SessionPause SessionEnd"

# Validate each .sh file in hooks/
for hook_script in "$SYSTEM_DIR"/hooks/*.sh; do
    if [ ! -f "$hook_script" ]; then continue; fi
    hook_name=$(basename "$hook_script")

    if [ ! -s "$hook_script" ]; then
        fail "hooks/$hook_name — empty file"
        continue
    fi

    if ! head -1 "$hook_script" | grep -qE '^#!/(usr/bin/env bash|bin/bash)'; then
        fail "hooks/$hook_name — missing or invalid shebang"
        continue
    fi

    if ! bash -n "$hook_script" 2>/dev/null; then
        fail "hooks/$hook_name — syntax error"
        continue
    fi

    pass "hooks/$hook_name — valid script"
done

# Validate hooks.json (plugin format — primary)
if [ -f "$SYSTEM_DIR/hooks/hooks.json" ]; then
    if jq . "$SYSTEM_DIR/hooks/hooks.json" > /dev/null 2>&1; then
        pass "hooks/hooks.json — valid JSON"
    else
        fail "hooks/hooks.json — invalid JSON"
    fi

    # Validate event names
    HJ_EVENTS=$(jq -r '.hooks // {} | keys[]' "$SYSTEM_DIR/hooks/hooks.json" 2>/dev/null || true)
    for event in $HJ_EVENTS; do
        if ! echo "$KNOWN_EVENTS" | grep -qw "$event"; then
            fail "hooks.json references unknown hook event: $event"
        elif echo "$event" | grep -qE '^Post(ToolUse|ToolUseFailure)$'; then
            warn "hooks.json has '$event' — CC v2.1.x does not dispatch this from plugins. Use settings.json via bootstrap.sh instead (CC issue #24529)"
        else
            pass "hooks.json hook event '$event' is valid"
        fi
    done

    # Validate commands use ${CLAUDE_PLUGIN_ROOT} and point to existing scripts
    HJ_CMDS=$(jq -r '.hooks // {} | .[][] | .hooks[]? | .command // empty' "$SYSTEM_DIR/hooks/hooks.json" 2>/dev/null || true)
    for cmd in $HJ_CMDS; do
        SCRIPT_NAME=$(basename "$cmd")
        if ! echo "$cmd" | grep -q '${CLAUDE_PLUGIN_ROOT}'; then
            fail "hooks.json command '$SCRIPT_NAME' does not use \${CLAUDE_PLUGIN_ROOT}"
        fi
        if [ ! -f "$SYSTEM_DIR/hooks/$SCRIPT_NAME" ]; then
            fail "hooks.json references hooks/$SCRIPT_NAME but file not found"
        elif [ ! -x "$SYSTEM_DIR/hooks/$SCRIPT_NAME" ]; then
            fail "hooks/$SCRIPT_NAME is not executable"
        else
            pass "hooks.json command '$SCRIPT_NAME' — exists, executable, uses plugin root"
        fi
    done
fi

# Validate settings.json hook event names (legacy — should be empty in v0.7.0+)
HOOK_EVENTS=$(jq -r '.hooks // {} | keys[]' "$SYSTEM_DIR/settings.json" 2>/dev/null || true)
if [ -n "$HOOK_EVENTS" ]; then
    warn "settings.json still has hooks — should be empty in v0.7.0+ (use hooks/hooks.json)"
    for event in $HOOK_EVENTS; do
        if ! echo "$KNOWN_EVENTS" | grep -qw "$event"; then
            fail "settings.json references unknown hook event: $event"
        fi
    done
fi
# Check 10: Commands
echo "Checking commands..."
if [ -d "$SYSTEM_DIR/commands" ]; then
    for cmd_file in "$SYSTEM_DIR"/commands/*; do
        [ -f "$cmd_file" ] || continue
        cmd_name=$(basename "$cmd_file")

        if [[ "$cmd_name" == *.md ]]; then
            # Markdown command — check YAML frontmatter
            frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$cmd_file")
            if [ -z "$frontmatter" ]; then
                fail "No YAML frontmatter in commands/$cmd_name"
                continue
            fi
            if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
                fail "Invalid YAML in commands/$cmd_name"
                continue
            fi
            pass "commands/$cmd_name — valid frontmatter"
        else
            # Shell script command — check shebang and syntax
            if ! head -1 "$cmd_file" | grep -qE '^#!/(usr/bin/env bash|bin/bash)'; then
                fail "commands/$cmd_name — missing or invalid shebang"
                continue
            fi
            if ! bash -n "$cmd_file" 2>/dev/null; then
                fail "commands/$cmd_name — syntax error"
                continue
            fi
            pass "commands/$cmd_name — valid script"
        fi
    done
else
    pass "No commands/ directory (optional)"
fi
echo ""

# Check 11: Shared scripts
echo "Checking shared scripts..."
if [ -d "$SYSTEM_DIR/scripts" ]; then
    for script_file in "$SYSTEM_DIR"/scripts/*.sh; do
        [ -f "$script_file" ] || continue
        script_name=$(basename "$script_file")

        if ! head -1 "$script_file" | grep -qE '^#!/(usr/bin/env bash|bin/bash)'; then
            fail "scripts/$script_name — missing or invalid shebang"
            continue
        fi

        if ! bash -n "$script_file" 2>/dev/null; then
            fail "scripts/$script_name — syntax error"
            continue
        fi

        pass "scripts/$script_name — valid script"
    done
else
    pass "No scripts/ directory (optional)"
fi
echo ""

# Check 12: Skill depends_on references
echo "Checking skill dependencies..."
SKILL_DIRS=$(for d in "$SYSTEM_DIR"/skills/*/; do basename "$d"; done | grep -v '^acquired$')
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    [ "$skill_name" = "acquired" ] && continue
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$skill_file")
    [ -z "$frontmatter" ] && continue

    deps=$(echo "$frontmatter" | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin)
deps = d.get('depends_on', [])
if deps:
    print('\n'.join(deps))
" 2>/dev/null) || true

    if [ -n "$deps" ]; then
        while IFS= read -r dep; do
            if ! echo "$SKILL_DIRS" | grep -qx "$dep"; then
                fail "skills/$skill_name depends_on '$dep' but no skills/$dep/ directory exists"
            fi
        done <<< "$deps"
    fi
done
pass "Skill dependency references checked"
echo ""

# Check 13: Count drift in reflection docs
echo "Checking for count drift in docs..."

# Count actual system components
ACTUAL_SKILLS=$(for d in "$SYSTEM_DIR"/skills/*/; do [ "$(basename "$d")" != "acquired" ] && echo 1; done | wc -l | tr -d ' ')
ACTUAL_RULES=$(ls "$SYSTEM_DIR"/rules/*.md 2>/dev/null | wc -l | tr -d ' ')
ACTUAL_AGENTS=$(ls "$SYSTEM_DIR"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')

# Scan reflection docs for hardcoded counts
# Match enumeration patterns: "(N skills:", "N rules —", "N skills," that count brana components
# Avoid contextual mentions like "76 agents with inconsistent metadata" or "3-5 agents"
COUNT_DRIFT=0
for doc in "$DOCS_DIR"/reflections/*.md; do
    [ -f "$doc" ] || continue
    docname=$(basename "$doc")

    while IFS=: read -r linenum num component; do
        [ -z "$component" ] && continue

        case "$component" in
            skills) actual=$ACTUAL_SKILLS ;;
            rules) actual=$ACTUAL_RULES ;;
            agents) actual=$ACTUAL_AGENTS ;;
            *) continue ;;
        esac

        # Skip subset counts (e.g., "8 agents — fast" is a per-model count, not total)
        # Only flag if within 30% of actual — close enough to be a stale total
        diff=$((num - actual))
        [ "$diff" -lt 0 ] && diff=$((-diff))
        threshold=$((actual * 30 / 100))
        [ "$threshold" -lt 2 ] && threshold=2
        [ "$diff" -ge "$threshold" ] && continue

        if [ "$num" != "$actual" ]; then
            warn "Count drift in $docname:$linenum — says '$num $component' but actual is $actual"
            COUNT_DRIFT=$((COUNT_DRIFT + 1))
        fi
    done < <(perl -ne '
        # Match patterns that enumerate brana system components:
        # "(13 rules:" or "13 rules —" or "13 rules," or "13 rules)" — enumeration context
        while (/\((\d+)\s+(skills|rules|agents)[:\s,)]/g) { print "$.:$1:$2\n" }
        # Also match "has/have N skills" or "deploys N agents"
        while (/(?:has|have|deploys?|includes?|contains?)\s+(\d+)\s+(skills|rules|agents)\b/g) { print "$.:$1:$2\n" }
    ' "$doc" 2>/dev/null || true)
done

if [ "$COUNT_DRIFT" -eq 0 ]; then
    pass "No count drift detected (skills=$ACTUAL_SKILLS, rules=$ACTUAL_RULES, agents=$ACTUAL_AGENTS)"
else
    echo "  Actual counts: skills=$ACTUAL_SKILLS, rules=$ACTUAL_RULES, agents=$ACTUAL_AGENTS"
fi
echo ""

# Check 14: Undocumented system files (spec-graph coverage)
echo "Checking spec-graph coverage..."
if [ -f "$SPEC_GRAPH" ]; then
    # Collect all system/ files that exist
    SYSTEM_FILES=$(find "$SYSTEM_DIR" -type f \( -name "*.md" -o -name "*.sh" -o -name "*.json" -o -name "*.py" \) | sed "s|^$SCRIPT_DIR/||" | sort)
    # Collect all system/ files referenced by at least one doc in the graph
    REFERENCED=$(jq -r '[.nodes[].impl_files[]? // empty] | unique[]' "$SPEC_GRAPH" 2>/dev/null | sort)

    UNDOCUMENTED=0
    while IFS= read -r sysfile; do
        # Skip non-essential files (hooks.json, __pycache__, etc.)
        case "$sysfile" in
            *__pycache__*|*hooks.json|*.claude-plugin/*) continue ;;
        esac
        if ! echo "$REFERENCED" | grep -qxF "$sysfile"; then
            UNDOCUMENTED=$((UNDOCUMENTED + 1))
            if [ "$UNDOCUMENTED" -le 5 ]; then
                warn "Undocumented system file: $sysfile (no doc references it in spec-graph)"
            fi
        fi
    done <<< "$SYSTEM_FILES"

    if [ "$UNDOCUMENTED" -gt 5 ]; then
        warn "...and $((UNDOCUMENTED - 5)) more undocumented system files"
    fi

    if [ "$UNDOCUMENTED" -eq 0 ]; then
        pass "All system files referenced by at least one doc"
    else
        echo "  Total undocumented: $UNDOCUMENTED (run: jq '.nodes | to_entries[] | select(.value.impl_files | length > 0)' docs/spec-graph.json)"
    fi
else
    pass "spec-graph.json not found — skipping coverage check"
fi
echo ""

# end of checks 1-14 conditional
fi

# ── Checks 15-18: Knowledge architecture fitness functions ───────────────
# Run when: no flags (full run) OR --assumptions-only
if ! $RUN_SCALE_TRIGGERS; then

# Check 15: Assumption freshness
echo "Check 15: Assumption freshness..."
STALE_ASSUMPTIONS=0
ASSUMPTION_CHECKED=0
NOW_EPOCH=$(date +%s)
GRACE_EPOCH=$((GRACE_DAYS * 86400))

# Scan all docs (docs/ + brana-knowledge/dimensions/) for ## Assumptions sections
# with Last Verified column
check_assumption_freshness() {
    local doc="$1"
    local label="$2"

    # Skip docs modified within grace period
    local mod_epoch
    mod_epoch=$(git -C "$SCRIPT_DIR" log --format=%at -1 -- "$doc" 2>/dev/null || echo "0")
    if [ "$mod_epoch" != "0" ]; then
        local age=$((NOW_EPOCH - mod_epoch))
        if [ "$age" -lt "$GRACE_EPOCH" ]; then
            return 0
        fi
    fi

    # Look for ## Assumptions section with Last Verified or last_verified dates
    # Extract dates from table rows or YAML-like assumption blocks
    local dates
    dates=$(perl -ne '
        $in_section = 1 if /^##\s+Assumptions/;
        $in_section = 0 if $in_section && /^##\s/ && !/^##\s+Assumptions/;
        if ($in_section) {
            # Table row: | ... | 2026-01-15 | (last column or near-last)
            if (/last.verified[:\s]*(\d{4}-\d{2}-\d{2})/i) {
                print "$1\n";
            }
            # YAML-style: last_verified: 2026-01-15
            elsif (/last_verified:\s*(\d{4}-\d{2}-\d{2})/) {
                print "$1\n";
            }
        }
    ' "$doc" 2>/dev/null)

    [ -z "$dates" ] && return 0

    while IFS= read -r verified_date; do
        [ -z "$verified_date" ] && continue
        ASSUMPTION_CHECKED=$((ASSUMPTION_CHECKED + 1))
        local verified_epoch
        verified_epoch=$(date -d "$verified_date" +%s 2>/dev/null || echo "0")
        [ "$verified_epoch" = "0" ] && continue
        # Default 6-month threshold (182 days)
        local threshold=$((182 * 86400))
        local staleness=$((NOW_EPOCH - verified_epoch))
        if [ "$staleness" -gt "$threshold" ]; then
            warn "Stale assumption in $label — last verified $verified_date (>6 months)"
            STALE_ASSUMPTIONS=$((STALE_ASSUMPTIONS + 1))
        fi
    done <<< "$dates"
}

# Scan docs/
for doc in "$DOCS_DIR"/**/*.md "$DOCS_DIR"/*.md; do
    [ -f "$doc" ] || continue
    label="${doc#$SCRIPT_DIR/}"
    check_assumption_freshness "$doc" "$label"
done

# Scan brana-knowledge/dimensions/
if [ -d "$KNOWLEDGE_DIR/dimensions" ]; then
    for doc in "$KNOWLEDGE_DIR"/dimensions/*.md; do
        [ -f "$doc" ] || continue
        label="brana-knowledge/dimensions/$(basename "$doc")"
        check_assumption_freshness "$doc" "$label"
    done
fi

if [ "$STALE_ASSUMPTIONS" -eq 0 ]; then
    pass "Check 15: PASS — Assumption freshness OK ($ASSUMPTION_CHECKED checked)"
else
    echo "  Check 15: WARN — $STALE_ASSUMPTIONS stale assumption(s) found ($ASSUMPTION_CHECKED checked)"
fi
echo ""

# Check 16: Changelog currency
echo "Check 16: Changelog currency..."
STALE_CHANGELOGS=0

check_changelog_currency() {
    local doc="$1"
    local label="$2"

    # Skip docs modified within grace period
    local mod_epoch
    mod_epoch=$(git -C "$SCRIPT_DIR" log --format=%at -1 -- "$doc" 2>/dev/null || echo "0")
    [ "$mod_epoch" = "0" ] && return 0
    local age=$((NOW_EPOCH - mod_epoch))
    if [ "$age" -lt "$GRACE_EPOCH" ]; then
        return 0
    fi

    # Check if doc has a ## Changelog section
    if ! grep -q '^## Changelog' "$doc" 2>/dev/null; then
        return 0
    fi

    # Get last commit date for the file
    local last_commit_date
    last_commit_date=$(git -C "$SCRIPT_DIR" log --format=%aI -1 -- "$doc" 2>/dev/null | cut -d'T' -f1)
    [ -z "$last_commit_date" ] && return 0

    # Get the most recent date from the Changelog section
    local last_changelog_date
    last_changelog_date=$(perl -ne '
        $in_cl = 1 if /^##\s+Changelog/;
        $in_cl = 0 if $in_cl && /^##\s/ && !/^##\s+Changelog/;
        if ($in_cl && /(\d{4}-\d{2}-\d{2})/) {
            print "$1\n";
        }
    ' "$doc" 2>/dev/null | sort -r | head -1)

    [ -z "$last_changelog_date" ] && return 0

    # Compare: if file was modified after the last changelog entry, flag it
    local commit_epoch
    commit_epoch=$(date -d "$last_commit_date" +%s 2>/dev/null || echo "0")
    local changelog_epoch
    changelog_epoch=$(date -d "$last_changelog_date" +%s 2>/dev/null || echo "0")

    if [ "$commit_epoch" -gt "$((changelog_epoch + 86400))" ]; then
        warn "Changelog stale in $label — last commit $last_commit_date, last changelog entry $last_changelog_date"
        STALE_CHANGELOGS=$((STALE_CHANGELOGS + 1))
    fi
}

for doc in "$DOCS_DIR"/**/*.md "$DOCS_DIR"/*.md; do
    [ -f "$doc" ] || continue
    label="${doc#$SCRIPT_DIR/}"
    check_changelog_currency "$doc" "$label"
done

if [ "$STALE_CHANGELOGS" -eq 0 ]; then
    pass "Check 16: PASS — Changelog currency OK"
else
    echo "  Check 16: WARN — $STALE_CHANGELOGS doc(s) with stale changelog"
fi
echo ""

# Check 17: Status consistency
echo "Check 17: Status consistency..."
STALE_ACTIVE=0
TWELVE_MONTHS=$((365 * 86400))

check_status_consistency() {
    local doc="$1"
    local label="$2"

    # Check for status: active in frontmatter
    local status
    status=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm && /^status:/{print $2}' "$doc" 2>/dev/null)
    [ "$status" != "active" ] && return 0

    # Get last modification time from git
    local mod_epoch
    mod_epoch=$(git -C "$SCRIPT_DIR" log --format=%at -1 -- "$doc" 2>/dev/null || echo "0")
    [ "$mod_epoch" = "0" ] && return 0

    local age=$((NOW_EPOCH - mod_epoch))
    if [ "$age" -gt "$TWELVE_MONTHS" ]; then
        local last_date
        last_date=$(date -d "@$mod_epoch" +%Y-%m-%d 2>/dev/null)
        warn "Status drift in $label — status: active but last modified $last_date (>12 months). Consider status: historic"
        STALE_ACTIVE=$((STALE_ACTIVE + 1))
    fi
}

for doc in "$DOCS_DIR"/**/*.md "$DOCS_DIR"/*.md; do
    [ -f "$doc" ] || continue
    label="${doc#$SCRIPT_DIR/}"
    check_status_consistency "$doc" "$label"
done

if [ "$STALE_ACTIVE" -eq 0 ]; then
    pass "Check 17: PASS — Status consistency OK"
else
    echo "  Check 17: WARN — $STALE_ACTIVE active doc(s) with no changes in 12+ months"
fi
echo ""

# Check 18: Graph integrity
echo "Check 18: Graph integrity..."
INTEGRITY_ISSUES=0

if [ -f "$SPEC_GRAPH" ]; then
    # Use Python via heredoc to avoid shell expansion issues with f-strings/regex
    INTEGRITY_ISSUES=$(python3 - "$SPEC_GRAPH" "$DOCS_DIR" <<'PYEOF'
import json, sys, os, re

spec_graph_path = sys.argv[1]
docs_dir = sys.argv[2]

with open(spec_graph_path) as f:
    graph = json.load(f)

nodes = set(graph.get('nodes', {}).keys())
typed_edges = graph.get('typed_edges', [])
issues = 0

# Check 1: orphaned typed edges (from/to reference non-existent nodes)
for edge in typed_edges:
    fr = edge.get('from', '')
    to = edge.get('to', '')
    # assumption: references are prefixed with 'assumption:' — not node paths
    if not to.startswith('assumption:') and to not in nodes:
        issues += 1
        print(f'  Orphaned edge target: {to} (from {fr})', file=sys.stderr)
    if fr not in nodes:
        issues += 1
        print(f'  Orphaned edge source: {fr}', file=sys.stderr)

# Check 2: assumption refs in typed_edges not in any doc's ## Assumptions
assumption_ids = set()
for edge in typed_edges:
    to = edge.get('to', '')
    if to.startswith('assumption:'):
        assumption_ids.add(to.replace('assumption:', ''))

# Scan docs for ## Assumptions sections and extract assumption slugs
found_assumptions = set()
for root, dirs, files in os.walk(docs_dir):
    for fname in files:
        if not fname.endswith('.md'):
            continue
        fpath = os.path.join(root, fname)
        in_section = False
        try:
            with open(fpath) as df:
                for line in df:
                    if re.match(r'^##\s+Assumptions', line):
                        in_section = True
                        continue
                    if in_section and re.match(r'^##\s', line) and not re.match(r'^##\s+Assumptions', line):
                        in_section = False
                    if in_section:
                        # Match table rows: | N | assumption text |
                        m = re.match(r'\|\s*\d+\s*\|\s*(.+?)\s*\|', line)
                        if m:
                            text = m.group(1).strip().lower()
                            slug = re.sub(r'[^a-z0-9]+', '-', text).strip('-')
                            found_assumptions.add(slug)
                        # Match YAML claim lines
                        m = re.match(r'\s*-?\s*claim:\s*["\']?(.+?)["\']?\s*$', line)
                        if m:
                            text = m.group(1).strip().lower()
                            slug = re.sub(r'[^a-z0-9]+', '-', text).strip('-')
                            found_assumptions.add(slug)
        except Exception:
            pass

# Check each assumption ID against found assumptions (fuzzy match)
for aid in assumption_ids:
    aid_terms = set(aid.split('-'))
    matched = False
    for fa in found_assumptions:
        fa_terms = set(fa.split('-'))
        overlap = len(aid_terms & fa_terms)
        if overlap >= len(aid_terms) * 0.5:
            matched = True
            break
    if not matched:
        issues += 1
        print(f'  Assumption in typed_edges not found in any doc: {aid}', file=sys.stderr)

print(issues)
PYEOF
2>&1)

    # Parse: last line is the count, preceding lines are details
    ISSUE_COUNT=$(echo "$INTEGRITY_ISSUES" | tail -1)
    ISSUE_DETAILS=$(echo "$INTEGRITY_ISSUES" | head -n -1)

    if [ -n "$ISSUE_DETAILS" ]; then
        echo "$ISSUE_DETAILS"
    fi

    if [ "$ISSUE_COUNT" = "0" ] 2>/dev/null; then
        pass "Check 18: PASS — Graph integrity OK"
    else
        warn "Check 18: WARN — $ISSUE_COUNT graph integrity issue(s)"
    fi
else
    pass "Check 18: PASS — spec-graph.json not found, skipping"
fi
echo ""

fi  # end of checks 15-18 conditional (! $RUN_SCALE_TRIGGERS)

# ── Checks 19-22: Scale triggers ────────────────────────────────────────
# Run when: no flags (full run) OR --scale-triggers
if ! $RUN_ASSUMPTIONS_ONLY; then

# Check 19: Graph node count
echo "Check 19: Graph node count..."
if [ -f "$SPEC_GRAPH" ]; then
    NODE_COUNT=$(python3 -c "
import json
with open('$SPEC_GRAPH') as f:
    print(len(json.load(f).get('nodes', {})))
" 2>/dev/null || echo "0")

    if [ "$NODE_COUNT" -gt 500 ] 2>/dev/null; then
        warn "Check 19: SCALE TRIGGER — spec-graph.json has $NODE_COUNT nodes (threshold: 500). Consider AgentDB Cypher, see t-435"
    else
        pass "Check 19: PASS — Graph nodes: $NODE_COUNT/500"
    fi
else
    pass "Check 19: PASS — spec-graph.json not found, skipping"
fi
echo ""

# Check 20: Ruflo entry count
echo "Check 20: Ruflo entry count..."
RUFLO_DB="$HOME/.claude-flow/memory.db"
if [ -f "$RUFLO_DB" ] && command -v sqlite3 &>/dev/null; then
    ENTRY_COUNT=$(sqlite3 "$RUFLO_DB" "SELECT COUNT(*) FROM memory_entries;" 2>/dev/null || echo "0")
    if [ "$ENTRY_COUNT" -gt 10000 ] 2>/dev/null; then
        warn "Check 20: SCALE TRIGGER — ruflo has $ENTRY_COUNT entries (threshold: 10K). Consider temperature tiering"
    else
        pass "Check 20: PASS — Ruflo entries: $ENTRY_COUNT/10000"
    fi
else
    pass "Check 20: PASS — Ruflo DB not found or sqlite3 unavailable, skipping"
fi
echo ""

# Check 21: Typed edges per node
echo "Check 21: Typed edges per node..."
if [ -f "$SPEC_GRAPH" ]; then
    EDGE_HOTSPOT=$(python3 -c "
import json
from collections import Counter

with open('$SPEC_GRAPH') as f:
    graph = json.load(f)

edges = graph.get('typed_edges', [])
counts = Counter()
for edge in edges:
    counts[edge.get('from', '')] += 1
    counts[edge.get('to', '')] += 1

if counts:
    node, count = counts.most_common(1)[0]
    print(f'{count}|{node}')
else:
    print('0|none')
" 2>/dev/null || echo "0|none")

    EDGE_MAX="${EDGE_HOTSPOT%%|*}"
    EDGE_NODE="${EDGE_HOTSPOT##*|}"

    if [ "$EDGE_MAX" -gt 10 ] 2>/dev/null; then
        warn "Check 21: SCALE TRIGGER — node '$EDGE_NODE' has $EDGE_MAX typed edges (threshold: 10). Consider GraphRAG, see t-105"
    else
        pass "Check 21: PASS — Max typed edges per node: $EDGE_MAX/10"
    fi
else
    pass "Check 21: PASS — spec-graph.json not found, skipping"
fi
echo ""

# Check 22: Cross-client field note count
echo "Check 22: Cross-client field note count..."
FIELD_NOTE_COUNT=0

# Count field notes across all docs (## Field Notes sections)
count_field_notes() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local count
    count=$(perl -lne '
        $in = 1 if /^##\s+Field\s+Notes/;
        $in = 0 if $in && /^##\s/ && !/^##\s+Field\s+Notes/;
        print if $in && /^[-*]\s/;
    ' "$dir"/*.md "$dir"/**/*.md 2>/dev/null | wc -l)
    echo "${count:-0}"
}

# Count in thebrana docs
FN_THEBRANA=$(count_field_notes "$DOCS_DIR")
FIELD_NOTE_COUNT=$((FIELD_NOTE_COUNT + FN_THEBRANA))

# Count in brana-knowledge
if [ -d "$KNOWLEDGE_DIR" ]; then
    FN_KNOWLEDGE=$(count_field_notes "$KNOWLEDGE_DIR/dimensions")
    FIELD_NOTE_COUNT=$((FIELD_NOTE_COUNT + FN_KNOWLEDGE))
fi

# Count in client projects
CLIENTS_DIR="$HOME/enter_thebrana/clients"
if [ -d "$CLIENTS_DIR" ]; then
    for client_dir in "$CLIENTS_DIR"/*/; do
        [ -d "$client_dir" ] || continue
        for subdir in docs .claude; do
            if [ -d "$client_dir/$subdir" ]; then
                FN_CLIENT=$(count_field_notes "$client_dir/$subdir")
                FIELD_NOTE_COUNT=$((FIELD_NOTE_COUNT + FN_CLIENT))
            fi
        done
    done
fi

if [ "$FIELD_NOTE_COUNT" -gt 50 ]; then
    warn "Check 22: SCALE TRIGGER — $FIELD_NOTE_COUNT field notes across repos (threshold: 50). Consider witness chains, see t-436"
else
    pass "Check 22: PASS — Cross-repo field notes: $FIELD_NOTE_COUNT/50"
fi
echo ""

fi  # end of checks 19-22 conditional (! $RUN_ASSUMPTIONS_ONLY)

# Summary
echo "=== Validation Summary ==="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
if [ "$ERRORS" -gt 0 ]; then
    echo "VALIDATION FAILED"
    exit 1
else
    echo "VALIDATION PASSED"
    exit 0
fi
