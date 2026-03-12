#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/system"
ERRORS=0
WARNINGS=0

echo "=== Brana Validate ==="
echo ""

fail() { echo "  FAIL: $1"; ((ERRORS++)); }
warn() { echo "  WARN: $1"; ((WARNINGS++)); }
pass() { echo "  PASS: $1"; }

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
DOCS_DIR="$SCRIPT_DIR/docs"

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
