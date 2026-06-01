#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

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
RUN_SEMANTIC_ONLY=false
RUN_GOLDEN=false
GRACE_DAYS=7
CHECK_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --assumptions-only) RUN_ASSUMPTIONS_ONLY=true; shift ;;
        --scale-triggers) RUN_SCALE_TRIGGERS=true; shift ;;
        --semantic) RUN_SEMANTIC_ONLY=true; shift ;;
        --golden) RUN_GOLDEN=true; shift ;;
        --grace-days) GRACE_DAYS="$2"; shift 2 ;;
        --check)
            if [ -z "${2:-}" ]; then echo "--check requires a check number argument"; exit 1; fi
            CHECK_FILTER="$2"; shift 2 ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

echo "=== Brana Validate ==="
echo ""

fail() { echo "  FAIL: $1"; (( ERRORS++ )) || true; }
warn() { echo "  WARN: $1"; (( WARNINGS++ )) || true; }
pass() { echo "  PASS: $1"; }

# should_run N: returns 0 (true) if CHECK_FILTER is unset or matches this check.
# --check 5  matches "5" and "5b" (base-number prefix match).
# --check 31 matches "31", "31a", "31b" but not "3".
should_run() {
    [ -z "$CHECK_FILTER" ] && return 0
    local base="${1%%[a-z]*}"
    [ "$base" = "$CHECK_FILTER" ]
}

# ── Checks 1-14: Core validation ─────────────────────────────────────────
# Skip when running subset flags or when --check targets a check >= 15.
# Note: individual checks 1-14 are not separately filterable; --check N for
# N in 1-14 runs the whole 1-14 block. The primary win is skipping checks 15+.
_run_core=true; _run_15_18=true; _run_19_22=true; _run_semantic=true
if [ -n "$CHECK_FILTER" ]; then
    _cf_base="${CHECK_FILTER%%[a-z]*}"
    if [[ "$_cf_base" =~ ^[0-9]+$ ]]; then
        if [ "$_cf_base" -gt 14 ]; then _run_core=false; fi
        if ! { [ "$_cf_base" -ge 15 ] && [ "$_cf_base" -le 18 ]; }; then _run_15_18=false; fi
        if ! { [ "$_cf_base" -ge 19 ] && [ "$_cf_base" -le 22 ]; }; then _run_19_22=false; fi
        _run_semantic=false
    fi
fi
if ! $RUN_ASSUMPTIONS_ONLY && ! $RUN_SCALE_TRIGGERS && ! $RUN_SEMANTIC_ONLY && $_run_core; then

# Check 1: Skill YAML frontmatter
echo "Checking skill frontmatter..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    # Skip non-skill directories
    [ "$skill_name" = "acquired" ] && continue
    [ "$skill_name" = "_shared" ] && continue
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

# Check 2: Rule files — every rule must declare paths: (scoped) or
# always-load: true (universal). Contract: system/rules/README.md (t-1285).
echo "Checking rules..."
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    # Guard against empty-glob expansion (literal "*.md" when no rules exist).
    [ -f "$rule_file" ] || continue
    rule_name=$(basename "$rule_file")
    # README.md is the authoring contract, not a rule itself — skip.
    [ "$rule_name" = "README.md" ] && continue

    if head -1 "$rule_file" | grep -q '^---$'; then
        frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$rule_file")
        if ! echo "$frontmatter" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin)" 2>/dev/null; then
            fail "Invalid YAML frontmatter in rules/$rule_name"
            continue
        fi
        has_paths=$(echo "$frontmatter" | grep -cE '^paths:' || true)
        has_always=$(echo "$frontmatter" | grep -cE '^always-load:[[:space:]]+true' || true)
        if [ "$has_paths" -gt 0 ] || [ "$has_always" -gt 0 ]; then
            pass "rules/$rule_name — valid frontmatter"
        else
            fail "rules/$rule_name — unscoped (no paths: or always-load: true). See system/rules/README.md."
        fi
    else
        fail "rules/$rule_name — unscoped (no paths: or always-load: true). Add frontmatter per system/rules/README.md."
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

# Rules with always-load: true (counted against the always-loaded budget).
# Scoped rules (paths:) only load when a matching file is in the working
# set, so they don't contribute to the baseline budget.
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    [ "$(basename "$rule_file")" = "README.md" ] && continue
    if grep -qE '^always-load:[[:space:]]+true' "$rule_file" 2>/dev/null; then
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

# Rule directives (always-loaded only — scoped rules don't contribute
# to the unconditional directive count)
for rule_file in "$SYSTEM_DIR"/rules/*.md; do
    [ -f "$rule_file" ] || continue
    [ "$(basename "$rule_file")" = "README.md" ] && continue
    # Only count always-load: true rules — scoped rules load on demand.
    grep -qE '^always-load:[[:space:]]+true' "$rule_file" 2>/dev/null || continue
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
SECRETS_FOUND=$(grep -rn -E '(API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY)\s*=' "$SYSTEM_DIR" 2>/dev/null | grep -v -E '(\.sh:|#|example|placeholder|never commit|/state/)' || true)
if [ -n "$SECRETS_FOUND" ]; then
    fail "Potential secrets found:"
    echo "$SECRETS_FOUND"
else
    pass "No secrets detected"
fi

# Check 6b: Key-shaped values in state/ (catches real secrets by value pattern, not name)
# Excludes patterns-export.json (large pattern store with legitimate long strings).
echo "Checking state/ for key-shaped values (32+ alnum chars)..."
STATE_DIR="$SYSTEM_DIR/state"
if [ -d "$STATE_DIR" ]; then
    STATE_SECRETS=$(grep -rn --exclude="patterns-export.json" -E '[A-Za-z0-9]{40,}' "$STATE_DIR" 2>/dev/null \
        | grep -v -E '(#|example|placeholder|\.gitkeep)' || true)
    if [ -n "$STATE_SECRETS" ]; then
        fail "Key-shaped values found in state/ (review for accidental secrets):"
        echo "$STATE_SECRETS"
    else
        pass "No key-shaped values in state/"
    fi
else
    pass "state/ directory absent — skipping"
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
OVERSIZED=$(find "$SYSTEM_DIR" -type f -size +50k \
    -not -path "*/cli/rust/*" \
    -not -path "*/state/*" \
    -not -path "*/procedures/*" \
    2>/dev/null)
if [ -n "$OVERSIZED" ]; then
    fail "Files over 50KB found:"
    echo "$OVERSIZED"
else
    pass "All files under 50KB"
fi
echo ""

# Check 8b: Propose-first — AskUserQuestion options should have (Recommended) on first option
echo "Checking propose-first convention..."
PROCEDURES_DIR="$SYSTEM_DIR/procedures"
if [ -d "$PROCEDURES_DIR" ]; then
    TOTAL_ASK=0
    MISSING_REC=0
    MISSING_FILES=""
    for proc_file in "$PROCEDURES_DIR"/*.md; do
        [ -f "$proc_file" ] || continue
        proc_name=$(basename "$proc_file")
        # Count AskUserQuestion occurrences
        count=$(grep -c "AskUserQuestion" "$proc_file" 2>/dev/null || true)
        if [ "$count" -gt 0 ]; then
            TOTAL_ASK=$((TOTAL_ASK + count))
            # Check if at least one (Recommended) exists in the file
            rec_count=$(grep -c "(Recommended)" "$proc_file" 2>/dev/null || true)
            if [ "$rec_count" -eq 0 ]; then
                MISSING_REC=$((MISSING_REC + count))
                MISSING_FILES="$MISSING_FILES $proc_name"
            fi
        fi
    done
    if [ "$TOTAL_ASK" -eq 0 ]; then
        pass "No AskUserQuestion calls in procedures"
    elif [ -z "$MISSING_FILES" ]; then
        pass "All procedures with AskUserQuestion have (Recommended) ($TOTAL_ASK total)"
    else
        warn "Procedures with AskUserQuestion but no (Recommended):$MISSING_FILES"
    fi
else
    pass "No procedures directory"
fi
echo ""

# Check 9: Hook scripts
echo "Checking hook scripts..."
KNOWN_EVENTS="PreToolUse PostToolUse PreToolUseFailure PostToolUseFailure Stop Notification SubagentStop SubagentNotification SessionStart SessionPause SessionEnd StopFailure SubagentStart TaskCompleted UserPromptSubmit ConfigChange"

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
# Check 9b: Hook shared libs (system/hooks/lib/)
echo "Checking hook shared libs..."
HOOK_LIB_DIR="$SYSTEM_DIR/hooks/lib"
if [ -d "$HOOK_LIB_DIR" ]; then
    for lib_script in "$HOOK_LIB_DIR"/*.sh; do
        [ -f "$lib_script" ] || continue
        lib_name=$(basename "$lib_script")
        if ! bash -n "$lib_script" 2>/dev/null; then
            fail "hooks/lib/$lib_name — syntax error"
        else
            pass "hooks/lib/$lib_name — valid script"
        fi
    done
    # Verify hooks that use resolve_lookup_dir source git-helpers.sh
    GIT_HELPERS="$HOOK_LIB_DIR/git-helpers.sh"
    if [ -f "$GIT_HELPERS" ]; then
        for hook_script in "$SYSTEM_DIR"/hooks/*.sh; do
            [ -f "$hook_script" ] || continue
            hook_name=$(basename "$hook_script")
            if grep -q 'resolve_lookup_dir\|extract_git_c_dir' "$hook_script"; then
                if grep -q 'git-helpers.sh' "$hook_script"; then
                    pass "hooks/$hook_name — sources git-helpers.sh"
                else
                    fail "hooks/$hook_name — uses resolve_lookup_dir but does not source git-helpers.sh"
                fi
            fi
        done
    fi
    # Verify hooks that use is_layer1_file source layer1-paths.sh
    LAYER1_LIB="$HOOK_LIB_DIR/layer1-paths.sh"
    if [ -f "$LAYER1_LIB" ]; then
        for hook_script in "$SYSTEM_DIR"/hooks/*.sh; do
            [ -f "$hook_script" ] || continue
            hook_name=$(basename "$hook_script")
            if grep -q 'is_layer1_file' "$hook_script"; then
                if grep -q 'layer1-paths.sh' "$hook_script"; then
                    pass "hooks/$hook_name — sources layer1-paths.sh"
                else
                    fail "hooks/$hook_name — uses is_layer1_file but does not source layer1-paths.sh"
                fi
            fi
        done
    fi
else
    pass "No hooks/lib/ directory (optional)"
fi
echo ""

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

# Check 13: Count drift in reflection docs and architecture living docs
echo "Checking for count drift in docs..."

# Count actual system components
ACTUAL_SKILLS=$(for d in "$SYSTEM_DIR"/skills/*/; do [ "$(basename "$d")" != "acquired" ] && echo 1; done | wc -l | tr -d ' ')
ACTUAL_RULES=$(ls "$SYSTEM_DIR"/rules/*.md 2>/dev/null | grep -v '/README\.md$' | wc -l | tr -d ' ')
ACTUAL_AGENTS=$(grep -rl '^model:' "$SYSTEM_DIR/agents" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
ACTUAL_CHECKS=$(grep -c "^# Check [0-9]" "$SCRIPT_DIR/validate.sh" 2>/dev/null || echo "0")
ACTUAL_HOOKS=$(ls "$SYSTEM_DIR"/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ')

# Scan reflection docs AND architecture living docs (excluding decisions/) for hardcoded counts
# Match enumeration patterns: "(N skills:", "N rules —", "N checks," etc.
# Avoid contextual mentions like "76 agents with inconsistent metadata" or "3-5 agents"
COUNT_DRIFT=0
while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    docname=$(realpath --relative-to="$DOCS_DIR" "$doc" 2>/dev/null || basename "$doc")

    while IFS=: read -r linenum num component; do
        [ -z "$component" ] && continue

        case "$component" in
            skills) actual=$ACTUAL_SKILLS ;;
            rules)  actual=$ACTUAL_RULES ;;
            agents) actual=$ACTUAL_AGENTS ;;
            checks) actual=$ACTUAL_CHECKS ;;
            hooks)  actual=$ACTUAL_HOOKS ;;
            *) continue ;;
        esac

        # Skip subset counts — only flag if close enough to actual to be a stale total.
        # hooks use 80% (grew from 10→35; old docs can be far off but still be stale totals).
        # All other components use 30%.
        diff=$((num - actual))
        [ "$diff" -lt 0 ] && diff=$((-diff))
        case "$component" in
            hooks) threshold=$((actual * 80 / 100)) ;;
            *)     threshold=$((actual * 30 / 100)) ;;
        esac
        [ "$threshold" -lt 2 ] && threshold=2
        [ "$diff" -ge "$threshold" ] && continue

        if [ "$num" != "$actual" ]; then
            warn "Count drift in $docname:$linenum — says '$num $component' but actual is $actual"
            COUNT_DRIFT=$((COUNT_DRIFT + 1))
        fi
    done < <(perl -ne '
        # Dedup: multiple patterns may match the same line:num:component tuple.
        my $k;
        # Pattern 1: parenthesized enumeration — "(N skills:", "(N hooks,"
        while (/\((\d+)\s+(skills|rules|agents|checks|hooks)[:\s,)]/g) { $k="$.:$1:$2"; print "$k\n" unless $seen{$k}++ }
        # Pattern 2: verb-prefixed enumeration — "has N hooks", "deploys N skills"
        while (/(?:has|have|deploys?|includes?|contains?|runs?)\s+(\d+)\s+(skills|rules|agents|checks|hooks)\b/g) { $k="$.:$1:$2"; print "$k\n" unless $seen{$k}++ }
        # Pattern 3: plain list — "33 skills, 11 agents, 10 hooks." (no bracket or verb needed)
        while (/\b(\d+)\s+(skills|rules|agents|checks|hooks)(?=[,\.\)])/g) { $k="$.:$1:$2"; print "$k\n" unless $seen{$k}++ }
    ' "$doc" 2>/dev/null || true)
done < <(
    find "$DOCS_DIR/reflections" -maxdepth 1 -name "*.md"
    find "$DOCS_DIR/architecture" -name "*.md" -not -path "*/decisions/*"
)

if [ "$COUNT_DRIFT" -eq 0 ]; then
    pass "No count drift detected (skills=$ACTUAL_SKILLS, rules=$ACTUAL_RULES, agents=$ACTUAL_AGENTS, checks=$ACTUAL_CHECKS, hooks=$ACTUAL_HOOKS)"
else
    echo "  Actual counts: skills=$ACTUAL_SKILLS, rules=$ACTUAL_RULES, agents=$ACTUAL_AGENTS, checks=$ACTUAL_CHECKS, hooks=$ACTUAL_HOOKS"
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

# ── Checks A-D: Semantic skill validation ──────────────────────────────────
# Run when: no flags (full run) OR --semantic. Skipped when --check N is numeric.
if { ! $RUN_ASSUMPTIONS_ONLY && ! $RUN_SCALE_TRIGGERS && $_run_semantic; } || $RUN_SEMANTIC_ONLY; then

# Source semantic check functions
source "$SCRIPT_DIR/semantic-checks.sh"

echo "Check A: Skill allowed-tools consistency..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    [ "$skill_name" = "acquired" ] && continue
    [ "$skill_name" = "_shared" ] && continue
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    output=$(check_allowed_tools_consistency "$skill_file" 2>&1) || true
    if [ -n "$output" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "FAIL:"; then
                fail "$(echo "$line" | sed 's/^  FAIL: //')"
            elif echo "$line" | grep -q "WARN:"; then
                warn "$(echo "$line" | sed 's/^  WARN: //')"
            fi
        done <<< "$output"
    fi
done
pass "Skill allowed-tools consistency checked"
echo ""

echo "Check B: Skill file path references..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    [ "$skill_name" = "acquired" ] && continue
    [ "$skill_name" = "_shared" ] && continue
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    output=$(check_file_path_references "$skill_file" 2>&1) || true
    if [ -n "$output" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "FAIL:"; then
                fail "$(echo "$line" | sed 's/^  FAIL: //')"
            fi
        done <<< "$output"
    fi
done
pass "Skill file path references checked"
echo ""

echo "Check C: Skill frontmatter schema validation..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    [ "$skill_name" = "acquired" ] && continue
    [ "$skill_name" = "_shared" ] && continue
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    output=$(check_frontmatter_schema "$skill_file" 2>&1) || true
    if [ -n "$output" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "FAIL:"; then
                fail "$(echo "$line" | sed 's/^  FAIL: //')"
            fi
        done <<< "$output"
    fi
done
pass "Skill frontmatter schema checked"
echo ""

echo "Check D: Skill step registry consistency..."
for skill_dir in "$SYSTEM_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    [ "$skill_name" = "acquired" ] && continue
    [ "$skill_name" = "_shared" ] && continue
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue

    output=$(check_step_registry "$skill_file" 2>&1) || true
    if [ -n "$output" ]; then
        while IFS= read -r line; do
            if echo "$line" | grep -q "WARN:"; then
                warn "$(echo "$line" | sed 's/^  WARN: //')"
            fi
        done <<< "$output"
    fi
done
pass "Skill step registry consistency checked"
echo ""

fi  # end of semantic checks conditional

# ── Checks 15-18: Knowledge architecture fitness functions ───────────────
# Run when: no flags (full run) OR --assumptions-only
if ! $RUN_SCALE_TRIGGERS && $_run_15_18; then

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

    # Look for ## Assumptions section with Last Verified or last_verified dates.
    # Extract per-row "tier|date" pairs (tier empty if Tier column absent or empty).
    # See docs/architecture/features/doc-frontmatter-spec.md (t-434).
    local rows
    rows=$(perl -ne '
        $in_section = 1 if /^##\s+Assumptions/;
        $in_section = 0 if $in_section && /^##\s/ && !/^##\s+Assumptions/;
        next unless $in_section;

        # Detect Tier column index from the header row
        if (/^\|\s*\#\s*\|/ && /Tier/i) {
            @cols = split(/\|/);
            for my $i (0..$#cols) {
                $tier_col = $i if $cols[$i] =~ /\bTier\b/i;
            }
            next;
        }

        # Skip separator rows
        next if /^\|[\s\-:]*\|/;

        # Data row: extract per-row tier (if column present) and last_verified date
        if (/^\|.*\|$/) {
            my $date_match;
            if (/last.verified[:\s]*(\d{4}-\d{2}-\d{2})/i) {
                $date_match = $1;
            } else {
                # Fallback: grab any YYYY-MM-DD in the row (assumed to be last_verified)
                $date_match = $1 if /(\d{4}-\d{2}-\d{2})/;
            }
            next unless $date_match;

            my $row_tier = "";
            if (defined $tier_col) {
                my @cells = split(/\|/);
                $row_tier = $cells[$tier_col] // "";
                $row_tier =~ s/^\s+|\s+$//g;
                $row_tier = "" if $row_tier !~ /^(tech|architecture|methodology)$/;
            }
            print "$row_tier|$date_match\n";
        }

        # YAML-style assumption block (no per-row tier support — uses doc default)
        elsif (/last_verified:\s*(\d{4}-\d{2}-\d{2})/) {
            print "|$1\n";
        }
    ' "$doc" 2>/dev/null)

    [ -z "$rows" ] && return 0

    # Read doc-level confidence_tier from frontmatter (default: tech).
    # See docs/architecture/features/doc-frontmatter-spec.md (t-439, t-434).
    local doc_tier
    doc_tier=$(awk '
        /^---$/ { fm = !fm; next }
        fm && /^confidence_tier:/ { gsub(/^confidence_tier:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }
    ' "$doc" 2>/dev/null)
    [ -z "$doc_tier" ] && doc_tier="tech"

    # Threshold-by-tier helper
    tier_threshold_days() {
        case "$1" in
            architecture) echo 547 ;;
            methodology)  echo 1095 ;;
            tech|*)       echo 182 ;;
        esac
    }

    while IFS= read -r row; do
        [ -z "$row" ] && continue
        local row_tier="${row%%|*}"
        local verified_date="${row#*|}"
        [ -z "$verified_date" ] && continue
        ASSUMPTION_CHECKED=$((ASSUMPTION_CHECKED + 1))
        local verified_epoch
        verified_epoch=$(date -d "$verified_date" +%s 2>/dev/null || echo "0")
        [ "$verified_epoch" = "0" ] && continue

        # Per-row tier overrides doc-level tier when present
        local effective_tier="${row_tier:-$doc_tier}"
        local threshold_days
        threshold_days=$(tier_threshold_days "$effective_tier")
        local threshold=$((threshold_days * 86400))

        local staleness=$((NOW_EPOCH - verified_epoch))
        if [ "$staleness" -gt "$threshold" ]; then
            local tier_label
            if [ -n "$row_tier" ]; then
                tier_label="$row_tier (per-row)"
            elif [ -n "$doc_tier" ] && [ "$doc_tier" != "tech" ]; then
                tier_label="$doc_tier (doc)"
            else
                tier_label="tech (default)"
            fi
            warn "Stale assumption in $label — last verified $verified_date (>$threshold_days days, tier=$tier_label)"
            STALE_ASSUMPTIONS=$((STALE_ASSUMPTIONS + 1))
        fi
    done <<< "$rows"
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
if ! $RUN_ASSUMPTIONS_ONLY && $_run_19_22; then

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

if should_run 23; then
# Check 23: Skill routing contract — procedures must have acquire-skills trigger
echo "Checking skill routing contract..."
BACKLOG_PROC="$SYSTEM_DIR/procedures/backlog.md"
BUILD_PROC="$SYSTEM_DIR/procedures/build.md"

if [ -f "$BACKLOG_PROC" ]; then
    # backlog.md step 5d must have MANDATORY acquisition offer
    if grep -q "MANDATORY acquisition offer" "$BACKLOG_PROC"; then
        pass "Check 23a: backlog.md has MANDATORY acquisition offer in step 5d"
    else
        fail "Check 23a: backlog.md missing MANDATORY acquisition offer — acquire-skills won't trigger on low scores"
    fi

    # backlog.md must write skill_gap_checked breadcrumb
    if grep -q "skill_gap_checked" "$BACKLOG_PROC"; then
        pass "Check 23b: backlog.md writes skill_gap_checked breadcrumb"
    else
        fail "Check 23b: backlog.md missing skill_gap_checked breadcrumb — build.md safety net won't work"
    fi
else
    fail "Check 23a: backlog.md procedure not found"
    fail "Check 23b: backlog.md procedure not found"
fi

if [ -f "$BUILD_PROC" ]; then
    # build.md step 4a must check for skill_gap_checked (not unconditional skip)
    if grep -q "skill_gap_checked" "$BUILD_PROC"; then
        pass "Check 23c: build.md step 4a checks skill_gap_checked breadcrumb"
    else
        fail "Check 23c: build.md step 4a missing skill_gap_checked guard — no safety net if backlog step 5 skipped"
    fi
else
    fail "Check 23c: build.md procedure not found"
fi
echo ""
fi  # should_run 23

if should_run 24; then
# Check 24 — .mcp.json entries (ADR-033: no npx/uvx, use pinned wrappers)
echo "Checking .mcp.json entries..."
MCP_FILE="$SCRIPT_DIR/.mcp.json"
if [ -f "$MCP_FILE" ]; then
  MCP_OK=true
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if echo "$entry" | grep -qE '"command"[[:space:]]*:[[:space:]]*"(npx|uvx)'; then
      NAME=$(echo "$entry" | jq -r '.name // "unknown"' 2>/dev/null || echo "unknown")
      fail "Check 24: .mcp.json entry uses npx/uvx (server: $NAME) — use pinned wrapper per ADR-033"
      MCP_OK=false
    fi
  done < <(jq -c '.mcpServers | to_entries[] | .value + {name: .key}' "$MCP_FILE" 2>/dev/null)
  $MCP_OK && pass "Check 24: .mcp.json — no npx/uvx entries (ADR-033 OK)"
else
  warn "Check 24: .mcp.json not found at $SCRIPT_DIR/.mcp.json (skipped)"
fi
echo ""
fi  # should_run 24

if should_run 25; then
# Check 25 — tasks.json priority enum hygiene (t-1344)
echo "Checking tasks.json priority enum..."
TASKS_FILE="$SCRIPT_DIR/.claude/tasks.json"
if [ -f "$TASKS_FILE" ]; then
  BAD_PRIORITIES=$(jq -r '[.tasks[] | select(.priority != null and (.priority | test("^P[0-3]$") | not)) | .priority] | unique | join(",")' "$TASKS_FILE" 2>/dev/null)
  if [ -n "$BAD_PRIORITIES" ]; then
    BAD_IDS=$(jq -r '[.tasks[] | select(.priority != null and (.priority | test("^P[0-3]$") | not)) | .id] | join(",")' "$TASKS_FILE" 2>/dev/null)
    fail "Check 25: tasks.json has non-canonical priority values: $BAD_PRIORITIES (tasks: $BAD_IDS) — must be P0/P1/P2/P3 or null"
  else
    pass "Check 25: tasks.json — all priorities canonical (P[0-3] or null)"
  fi
else
  warn "Check 25: $TASKS_FILE not found (skipped)"
fi
echo ""
fi  # should_run 25

if should_run 26; then
# Check 26 — tasks.json status enum hygiene (t-1345)
echo "Checking tasks.json status enum..."
if [ -f "$TASKS_FILE" ]; then
  BAD_STATUSES=$(jq -r '[.tasks[] | select(.status != null and (.status | test("^(pending|in_progress|completed|cancelled)$") | not)) | .status] | unique | join(",")' "$TASKS_FILE" 2>/dev/null)
  if [ -n "$BAD_STATUSES" ]; then
    BAD_IDS=$(jq -r '[.tasks[] | select(.status != null and (.status | test("^(pending|in_progress|completed|cancelled)$") | not)) | .id] | join(",")' "$TASKS_FILE" 2>/dev/null)
    fail "Check 26: tasks.json has non-canonical status values: $BAD_STATUSES (tasks: $BAD_IDS) — must be pending/in_progress/completed/cancelled or null"
  else
    pass "Check 26: tasks.json — all statuses canonical (pending/in_progress/completed/cancelled or null)"
  fi
else
  warn "Check 26: $TASKS_FILE not found (skipped)"
fi
echo ""
fi  # should_run 26

if should_run 27; then
# Check 27 — MCP wrapper scripts must use exec, not background+wait (t-1086)
# Background pattern (`binary & wait`) breaks JSON-RPC stdin delivery;
# exec is required to keep the pipe alive for MCP stdio.
echo "Checking MCP wrapper scripts for exec pattern..."
MCP_WRAPPERS=$(grep -rl "exec " "$SCRIPT_DIR/system/scripts/" --include="*.sh" 2>/dev/null | xargs grep -l "mcp\|ruflo\|claude-flow" 2>/dev/null || true)
WRAPPER_OK=true
WRAPPER_ANTI=()
for wrapper in $MCP_WRAPPERS; do
  # Detect background+wait anti-pattern: ampersand followed by wait on same or next line
  if grep -qE '^\s*(ruflo|node|npx|python|uvx)[^|&]*&\s*$' "$wrapper" 2>/dev/null; then
    WRAPPER_ANTI+=("$(basename "$wrapper")")
    WRAPPER_OK=false
  fi
done
if ! $WRAPPER_OK; then
  fail "Check 27: MCP wrapper script(s) use background+wait anti-pattern: ${WRAPPER_ANTI[*]} — use exec instead (breaks stdin for MCP stdio)"
else
  pass "Check 27: MCP wrapper scripts use exec, no background+wait anti-pattern"
fi
echo ""
fi  # should_run 27

if should_run 28; then
# Check 28 — no bare python3 in system/hooks/ (t-1407)
# Use jq instead of python3 in hook scripts — python3 is fragile in hook subprocesses.
# Bare `python3` means any occurrence not preceded by `uv run`.
echo "Checking system/hooks/ for bare python3 invocations..."
BARE_PY3=$(grep -rn "python3" "$SCRIPT_DIR/system/hooks/" --include="*.sh" 2>/dev/null \
    | grep -v "uv run python3" \
    | grep -v ":[[:space:]]*#" \
    || true)
if [ -n "$BARE_PY3" ]; then
    echo "$BARE_PY3" | sed 's/^/  /'
    fail "Check 28: bare python3 found in system/hooks/ — use jq or uv run python3 instead (jq-over-python3 convention)"
else
    pass "Check 28: system/hooks/ — no bare python3 invocations"
fi
echo ""
fi  # should_run 28

if should_run 29; then
# Check 29 — reference docs up to date (t-1429)
# Catches silent drift when hooks.json schema or frontmatter sources change
# without a corresponding regeneration of docs/reference/*.md.
echo "Checking reference docs up to date..."
if command -v brana >/dev/null 2>&1; then
    REF_ERR=0
    REF_OUT=$(brana reference generate --check 2>&1) || REF_ERR=$?
    [ -n "$REF_OUT" ] && echo "$REF_OUT" | sed 's/^/  /'
    if [ "$REF_ERR" -ne 0 ]; then
        fail "Check 29: reference docs out of date — run 'brana reference generate' to update"
    else
        pass "Check 29: reference docs up to date"
    fi
else
    warn "Check 29: brana CLI not found — skipping reference doc check"
fi
echo ""
fi  # should_run 29

if should_run 30; then
# Check 30 — brana CLI calls in hooks must use cd GIT_ROOT subshell wrapper (t-1439)
# All hooks do `cd /tmp` at startup. brana subcommands resolve the project from CWD,
# so bare calls return empty results. Every "$BRANA*" call must be inside
# (cd "${GIT_ROOT:-...}" && ...) or on a line with `cd` before the call.
echo "Checking system/hooks/ for brana CLI calls without cd GIT_ROOT wrapper..."
HOOK_DIR="$SCRIPT_DIR/system/hooks"
UNWRAPPED_BRANA=$(
    {
        grep -rn '"$BRANA[^"]*" [a-z]' "$HOOK_DIR"/*.sh 2>/dev/null
        grep -rn '^\s*brana [a-z]' "$HOOK_DIR"/*.sh 2>/dev/null
    } | grep -v '/lib/\|/tests/' \
      | grep -v ':[[:space:]]*#' \
      | grep -v 'cd ["\$]' \
    || true
)
if [ -n "$UNWRAPPED_BRANA" ]; then
    echo "$UNWRAPPED_BRANA" | sed 's/^/  /'
    fail "Check 30: brana CLI calls without cd GIT_ROOT wrapper found in system/hooks/ — wrap with (cd \"\${GIT_ROOT:-/tmp}\" && ...) (t-1439)"
else
    pass "Check 30: system/hooks/ — all brana CLI calls wrapped in cd GIT_ROOT"
fi
echo ""
fi  # should_run 30

if should_run 31; then
# Check 31 — knowledge file cap triggers (patterns.md + knowledge-staging.md)
echo "Checking knowledge file caps..."
MEMORY_DIR="$HOME/.claude/memory"
PATTERNS_FILE="$MEMORY_DIR/patterns.md"
KNOWLEDGE_STAGING_FILE="$MEMORY_DIR/knowledge-staging.md"

if [ -f "$PATTERNS_FILE" ]; then
    PATTERN_COUNT=$(grep -c '^## ' "$PATTERNS_FILE" 2>/dev/null) || PATTERN_COUNT=0
    _P_WARN=40
    _P_CAP=50
    if [ "$PATTERN_COUNT" -ge "$_P_CAP" ]; then
        # Auto-prune: remove oldest quarantine entries until count < cap
        _pruned=0
        _current="$PATTERN_COUNT"
        while [ "$_current" -ge "$_P_CAP" ]; do
            _oldest=$(awk '
/^## /                  { if (slug!="" && conf=="quarantine") printf "%s|%s\n", date, slug
                          slug=substr($0,4); date=""; conf="" }
/^\*\*Confidence:\*\* / { conf=$NF }
/^\*\*Added:\*\* /       { date=$NF }
END                     { if (slug!="" && conf=="quarantine") printf "%s|%s\n", date, slug }
' "$PATTERNS_FILE" | sort | head -1) || _oldest=""
            if [ -z "$_oldest" ]; then
                if [ "$_pruned" -gt 0 ]; then
                    warn "Check 31a: patterns.md at cap ($_current/$_P_CAP) — pruned $_pruned quarantine entries but cap still hit; manual review required"
                else
                    warn "Check 31a: patterns.md at cap ($_current/$_P_CAP) — no quarantine entries to prune; manual review required"
                fi
                break
            fi
            _slug="${_oldest#*|}"
            awk -v target="## $_slug" '
BEGIN { skip=0 }
/^## / { skip=($0==target) }
!skip  { print }
' "$PATTERNS_FILE" > "${PATTERNS_FILE}.tmp" && mv "${PATTERNS_FILE}.tmp" "$PATTERNS_FILE"
            _pruned=$(( _pruned + 1 ))
            _current=$(grep -c '^## ' "$PATTERNS_FILE" 2>/dev/null) || _current=0
        done
        if [ "$_current" -lt "$_P_CAP" ]; then
            pass "Check 31a: patterns.md auto-pruned $_pruned quarantine entries → $_current/$_P_CAP"
        fi
    elif [ "$PATTERN_COUNT" -ge "$_P_WARN" ]; then
        warn "Check 31a: patterns.md has $PATTERN_COUNT entries (warn at $_P_WARN, cap at $_P_CAP) — prune quarantine entries"
    else
        pass "Check 31a: patterns.md entries: $PATTERN_COUNT/$_P_WARN warn threshold"
    fi
else
    pass "Check 31a: patterns.md not found — skipping"
fi

if [ -f "$KNOWLEDGE_STAGING_FILE" ]; then
    KNOWLEDGE_COUNT=$(grep -c '^## ' "$KNOWLEDGE_STAGING_FILE" 2>/dev/null) || KNOWLEDGE_COUNT=0
    if [ "$KNOWLEDGE_COUNT" -ge 20 ]; then
        warn "Check 31b: knowledge-staging.md has $KNOWLEDGE_COUNT entries (warn at 20, cap at 30) — promote or discard stale findings"
    else
        pass "Check 31b: knowledge-staging.md entries: $KNOWLEDGE_COUNT/20 warn threshold"
    fi
else
    pass "Check 31b: knowledge-staging.md not found — skipping"
fi
echo ""
fi  # should_run 31

if should_run 32; then
# Check 32 — echo|grep-q pipefail anti-pattern in tests/ and system/scripts/ (t-1454)
# `echo "$x" | grep -q` under set -o pipefail: grep exits early on match, echo gets SIGPIPE 141,
# pipefail returns 141, if-condition evaluates false → false negative on successful match.
# Fix: use [[ "$x" == *"$needle"* ]] for simple contains checks, or append || true.
echo "Checking tests/ and system/scripts/ for echo|grep-q pipefail anti-pattern..."
PIPEFAIL_HITS=$(
    grep -rn '|[[:space:]]*grep -q' \
        "$SCRIPT_DIR/tests/" "$SCRIPT_DIR/system/scripts/" \
        --include="*.sh" 2>/dev/null \
    | grep -v ':[[:space:]]*#' \
    | grep -v '|| true' \
    || true
)
if [ -n "$PIPEFAIL_HITS" ]; then
    HIT_COUNT=$(printf '%s\n' "$PIPEFAIL_HITS" | wc -l | tr -d ' ')
    printf '%s\n' "$PIPEFAIL_HITS" | sed 's/^/  /'
    warn "Check 32: $HIT_COUNT echo|grep-q pipefail anti-pattern(s) — replace with [[ == *needle* ]] (t-1454)"
else
    pass "Check 32: no echo|grep-q pipefail anti-pattern found in tests/ or system/scripts/"
fi
echo ""
fi  # should_run 32

if should_run 33; then
# Check 33 — SKILL.md keywords field required for code-strategy skills (t-1482)
# Step 4a tech-detection gate uses the keywords field to match installed skills to
# detected tech context. Any SKILL.md whose task_strategies includes a code-work
# strategy (feature, refactor, bug-fix, tech-debt) must declare a non-empty keywords
# list, or the gate silently bypasses the skill match.
echo "Checking SKILL.md keywords field for code-strategy skills..."
MISSING_KW_COUNT=0
for skill_dir in "$SYSTEM_DIR"/skills/*/ "$SYSTEM_DIR"/skills/acquired/*/; do
    skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    strategies_line=$(grep -E '^task_strategies:' "$skill_file" 2>/dev/null || true)
    [ -z "$strategies_line" ] && continue
    if [[ "$strategies_line" != *feature* ]] && [[ "$strategies_line" != *refactor* ]] && \
       [[ "$strategies_line" != *bug-fix* ]] && [[ "$strategies_line" != *tech-debt* ]]; then
        continue
    fi
    kw_line=$(grep -E '^keywords:' "$skill_file" 2>/dev/null || true)
    if [ -z "$kw_line" ] || [[ "$kw_line" =~ ^keywords:[[:space:]]*\[[[:space:]]*\] ]]; then
        echo "  missing keywords: $(basename "$skill_dir")"
        (( MISSING_KW_COUNT++ )) || true
    fi
done
if [ "$MISSING_KW_COUNT" -gt 0 ]; then
    fail "Check 33: $MISSING_KW_COUNT code-strategy SKILL.md file(s) missing keywords field — breaks step 4a tech-detection gate (t-1482)"
else
    pass "Check 33: all code-strategy SKILL.md files have keywords field"
fi
echo ""
fi  # should_run 33

if should_run 34; then
# Check 34 — scheduler template vs live drift (t-1684)
# Jobs added to scheduler.template.json silently don't run until synced to live.
echo "Checking scheduler template vs live drift..."
SCHEDULER_TEMPLATE="$SCRIPT_DIR/system/scheduler/scheduler.template.json"
SCHEDULER_LIVE="$HOME/.claude/scheduler/scheduler.json"
if [ ! -f "$SCHEDULER_TEMPLATE" ]; then
    warn "Check 34: scheduler.template.json not found at $SCHEDULER_TEMPLATE — skipping"
elif ! command -v jq &>/dev/null; then
    warn "Check 34: jq not available — cannot compare scheduler template vs live"
elif [ ! -f "$SCHEDULER_LIVE" ]; then
    warn "Check 34: live scheduler not found at $SCHEDULER_LIVE — run bootstrap.sh to deploy"
else
    TEMPLATE_JOBS=$(jq -r '.jobs | keys | .[]' "$SCHEDULER_TEMPLATE" | sort)
    LIVE_JOBS=$(jq -r '.jobs | keys | .[]' "$SCHEDULER_LIVE" | sort)
    MISSING_JOBS=$(comm -23 <(echo "$TEMPLATE_JOBS") <(echo "$LIVE_JOBS"))
    if [ -n "$MISSING_JOBS" ]; then
        MISSING_COUNT=$(echo "$MISSING_JOBS" | wc -l | tr -d ' ')
        while IFS= read -r job; do echo "  missing from live: $job"; done <<< "$MISSING_JOBS"
        warn "Check 34: $MISSING_COUNT scheduler job(s) in template but missing from live — run brana scheduler sync or bootstrap.sh (t-1684)"
    else
        pass "Check 34: scheduler template and live file have matching job names"
    fi
fi
echo ""
fi  # should_run 34

# Check 35 — system/plugin.json must have skills and commands fields (t-1753)
# Without these, Skill() routing fails silently even though SKILL.md scanning
# still populates the available-skills system-reminder.
if should_run 35; then
echo "Check 35: system/plugin.json required fields..."
PLUGIN_JSON="$SCRIPT_DIR/system/plugin.json"
if [ ! -f "$PLUGIN_JSON" ]; then
    fail "Check 35: system/plugin.json not found — --plugin-dir mode requires this manifest"
elif ! command -v jq &>/dev/null; then
    warn "Check 35: jq not available — cannot validate system/plugin.json fields"
else
    MISSING_FIELDS=()
    jq -e '.skills' "$PLUGIN_JSON" > /dev/null 2>&1 || MISSING_FIELDS+=("skills")
    jq -e '.commands' "$PLUGIN_JSON" > /dev/null 2>&1 || MISSING_FIELDS+=("commands")
    if [ "${#MISSING_FIELDS[@]}" -gt 0 ]; then
        fail "Check 35: system/plugin.json missing required field(s): ${MISSING_FIELDS[*]} — Skill() routing fails without 'skills'; commands won't register without 'commands' (t-1753)"
    else
        pass "Check 35: system/plugin.json has required fields: skills + commands"
    fi
fi
echo ""
fi  # should_run 35

# Check 36 — procedure files with mcp__ruflo__ calls must have a <!-- ruflo preamble --> block
# Any procedure with ruflo calls but no preamble will silently throw InputValidationError at runtime
if should_run 36; then
echo "Check 36: ruflo preamble in procedures..."
PROCS_DIR="$SCRIPT_DIR/system/procedures"
MISSING_PREAMBLE=()
if [ -d "$PROCS_DIR" ]; then
    while IFS= read -r -d '' proc_file; do
        if grep -q "mcp__ruflo__" "$proc_file" 2>/dev/null; then
            if ! grep -q "ruflo preamble" "$proc_file" 2>/dev/null; then
                MISSING_PREAMBLE+=("$(basename "$proc_file")")
            fi
        fi
    done < <(find "$PROCS_DIR" -name "*.md" -print0 2>/dev/null)
fi
if [ "${#MISSING_PREAMBLE[@]}" -gt 0 ]; then
    fail "Check 36: procedures with mcp__ruflo__ calls missing <!-- ruflo preamble --> block: ${MISSING_PREAMBLE[*]}"
else
    pass "Check 36: all procedures with ruflo calls have preamble block"
fi
echo ""
fi  # should_run 36

# Check 37 — stale model version strings in system/hooks/*.sh (t-1769)
# Hook warning text often embeds model names (e.g. "Opus 4.6"). When a model
# family ships or retires, these drift silently. Flag known retired patterns.
if should_run 37; then
echo "Check 37: stale model version strings in hook scripts..."
HOOKS_DIR="$SCRIPT_DIR/system/hooks"
STALE_MODEL_HITS=()
# Patterns that are known-retired: Opus 4.5 and older, Sonnet 3.x and older
STALE_PATTERNS=("opus-4\.5" "opus-4\.4" "opus-4\.3" "opus 4\.5" "opus 4\.4" "opus 4\.3" "sonnet-3\." "sonnet 3\." "Opus 4\.5" "Opus 4\.4" "Opus 4\.3" "Sonnet 3\." "claude-3\." "Claude 3\.")
if [ -d "$HOOKS_DIR" ]; then
    while IFS= read -r -d '' hook_file; do
        for pattern in "${STALE_PATTERNS[@]}"; do
            if grep -qE "$pattern" "$hook_file" 2>/dev/null; then
                STALE_MODEL_HITS+=("$(basename "$hook_file"):$pattern")
                break
            fi
        done
    done < <(find "$HOOKS_DIR" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
fi
if [ "${#STALE_MODEL_HITS[@]}" -gt 0 ]; then
    warn "Check 37: stale model version string(s) in hook scripts: ${STALE_MODEL_HITS[*]}"
else
    pass "Check 37: no stale model version strings in hook scripts"
fi
echo ""
fi  # should_run 37

# Check 38 — agy installed version must match AGY_PINNED_VERSION in agy_delegate.rs
# Version drift causes every mcp__brana__agy_delegate call to hard-error. Catches upgrade
# without re-running adversarial spike (C2 from 2026-05-30 challenge report).
if should_run 38; then
echo "Check 38: agy installed version vs pinned constant..."
AGY_DELEGATE_SRC="$SCRIPT_DIR/system/cli/rust/crates/brana-mcp/src/tools/agy_delegate.rs"
if [ ! -f "$AGY_DELEGATE_SRC" ]; then
    warn "Check 38: agy_delegate.rs not found at expected path — skipping"
elif ! command -v agy &>/dev/null; then
    warn "Check 38: agy not installed — skipping version check"
else
    AGY_INSTALLED=$(agy --version 2>/dev/null || echo "")
    AGY_PINNED=$(grep 'AGY_PINNED_VERSION.*str' "$AGY_DELEGATE_SRC" | grep -o '"[^"]*"' | tr -d '"' || echo "")
    if [ -z "$AGY_INSTALLED" ]; then
        warn "Check 38: agy --version returned empty — cannot verify pin"
    elif [ -z "$AGY_PINNED" ]; then
        warn "Check 38: could not extract AGY_PINNED_VERSION from agy_delegate.rs"
    elif [ "$AGY_INSTALLED" != "$AGY_PINNED" ]; then
        fail "Check 38: agy version mismatch — installed=$AGY_INSTALLED pinned=$AGY_PINNED — re-run adversarial spike then bump AGY_PINNED_VERSION in agy_delegate.rs"
    else
        pass "Check 38: agy installed version matches pinned constant ($AGY_INSTALLED)"
    fi
fi
echo ""
fi  # should_run 38

# Check 39 — hooks.json must not use args[] array form (CC dropped it; command string required)
# Catching this prevents silent hook failure where all enforcement stops with no observable error.
if should_run 39; then
echo "Check 39: hooks.json hook command format..."
HOOKS_JSON="$SCRIPT_DIR/system/hooks/hooks.json"
if [ ! -f "$HOOKS_JSON" ]; then
    warn "Check 39: hooks.json not found — skipping"
elif ! command -v jq &>/dev/null; then
    warn "Check 39: jq not available — skipping hooks.json format check"
else
    ARGS_COUNT=$(jq '[.hooks | .[][] | .hooks[]? | select(.args != null)] | length' "$HOOKS_JSON" 2>/dev/null || echo 0)
    BADCMD_COUNT=$(jq '[.hooks | .[][] | .hooks[]? | select((.command | type) != "string" or .command == "")] | length' "$HOOKS_JSON" 2>/dev/null || echo 0)
    if [ "${ARGS_COUNT:-0}" -gt 0 ]; then
        fail "Check 39: hooks.json has $ARGS_COUNT hook(s) using args[] array form — CC requires command string. Run: jq '.hooks | .[][] | .hooks[]? | select(.args != null)' hooks.json to find offenders."
    elif [ "${BADCMD_COUNT:-0}" -gt 0 ]; then
        fail "Check 39: hooks.json has $BADCMD_COUNT hook(s) with missing or non-string command — expected string, received undefined (E2026-05-31-2). Run: jq '.hooks | .[][] | .hooks[]? | select((.command | type) != \"string\")' hooks.json"
    else
        pass "Check 39: hooks.json all hooks use command string form"
    fi
fi
echo ""
fi  # should_run 39

# Check 40 — AskUserQuestion option blocks must include description: for every label:
# Missing description silently degrades UI (less context shown); accumulates across sessions.
if should_run 40; then
echo "Check 40: AskUserQuestion option description fields..."
PROCS_DIR="$SCRIPT_DIR/system/procedures"
MISSING_DESC_FILES=()
if [ -d "$PROCS_DIR" ]; then
    while IFS= read -r -d '' proc_file; do
        if grep -q "AskUserQuestion" "$proc_file" 2>/dev/null; then
            # Find label: lines not followed by description: within 2 lines
            if python3 - "$proc_file" << 'PYEOF' 2>/dev/null
import sys, re
text = open(sys.argv[1]).read()
AQU = re.compile(r'AskUserQuestion[:\(].*?(?=\n(?:#{1,4} |\Z))', re.DOTALL)
OPT = re.compile(r'^(\s+- )(?:"[^"]*"|label: "[^"]*")$')
DESC = re.compile(r'^\s+description:', re.IGNORECASE)
found = False
for m in AQU.finditer(text):
    lines = m.group().split('\n')
    for i, line in enumerate(lines):
        if OPT.match(line):
            j = i + 1
            while j < len(lines) and not lines[j].strip(): j += 1
            nxt = lines[j] if j < len(lines) else ''
            if not DESC.match(nxt):
                found = True; break
    if found: break
sys.exit(0 if found else 1)
PYEOF
            then
                MISSING_DESC_FILES+=("$(basename "$proc_file")")
            fi
        fi
    done < <(find "$PROCS_DIR" -name "*.md" -print0 2>/dev/null)
fi
if [ "${#MISSING_DESC_FILES[@]}" -gt 0 ]; then
    warn "Check 40: AskUserQuestion options missing description: field in: ${MISSING_DESC_FILES[*]}"
else
    pass "Check 40: all AskUserQuestion options have description: field"
fi
echo ""
fi  # should_run 40

# Check 41 — feed-summarize.sh --dry-run smoke test (t-1796)
# Verifies dedup logic, watermark bypass (--force), and SUMMARIZE_FEEDS filter
# without invoking claude -p. Catches regressions in the feed-summarize pipeline.
if should_run 41; then
echo "Check 41: feed-summarize.sh --dry-run smoke test..."
FEED_SUMMARIZE_SH="$SYSTEM_DIR/scripts/feed-summarize.sh"
if [ ! -f "$FEED_SUMMARIZE_SH" ]; then
    warn "Check 41: feed-summarize.sh not found at $FEED_SUMMARIZE_SH — skipping"
else
    TMP_FIXTURE=$(mktemp /tmp/validate-feed-fixture-XXXXXX.jsonl)
    TMP_SUMMARIES=$(mktemp /tmp/validate-feed-summaries-XXXXXX.jsonl)
    TMP_WATERMARK=$(mktemp /tmp/validate-feed-watermark-XXXXXX)
    trap 'rm -f "$TMP_FIXTURE" "$TMP_SUMMARIES" "$TMP_WATERMARK"' EXIT
    printf '%s\n' \
        '{"feed":"anthropic-news","title":"Claude 4 Released","link":"https://www.anthropic.com/news/claude-4","published":"2026-01-01","polled_at":"2026-01-01T12:00:00Z"}' \
        '{"feed":"anthropic-news","title":"New API Features","link":"https://www.anthropic.com/news/api-features","published":"2026-01-02","polled_at":"2026-01-02T12:00:00Z"}' \
        '{"feed":"anthropic-news","title":"Pricing Update","link":"https://www.anthropic.com/news/pricing","published":"2026-01-03","polled_at":"2026-01-03T12:00:00Z"}' \
        > "$TMP_FIXTURE"

    DRY_OUT=$(FEED_LOG="$TMP_FIXTURE" SUMMARIES="$TMP_SUMMARIES" WATERMARK="$TMP_WATERMARK" \
        bash "$FEED_SUMMARIZE_SH" --dry-run --force 2>&1) || true

    MISSING=0
    for url in \
        "https://www.anthropic.com/news/claude-4" \
        "https://www.anthropic.com/news/api-features" \
        "https://www.anthropic.com/news/pricing"; do
        if [[ "$DRY_OUT" != *"$url"* ]]; then
            echo "  missing URL in dry-run output: $url"
            MISSING=$((MISSING + 1))
        fi
    done

    if [ "$MISSING" -gt 0 ]; then
        fail "Check 41: feed-summarize.sh --dry-run missing $MISSING expected URL(s) — fixture test failed"
    elif [[ "$DRY_OUT" != *"[dry-run]"* ]]; then
        fail "Check 41: feed-summarize.sh --dry-run output missing [dry-run] marker"
    else
        pass "Check 41: feed-summarize.sh --dry-run output contains all 3 expected URLs"
    fi
fi
echo ""
fi  # should_run 41

# Check 42 — debrief-analyst agent must use model: sonnet (ADR-040 §6, t-1801)
if should_run 42; then
echo "Check 42: debrief-analyst model: sonnet..."
DEBRIEF_AGENT="$SYSTEM_DIR/agents/debrief-analyst.md"
if [ ! -f "$DEBRIEF_AGENT" ]; then
    warn "Check 42: debrief-analyst.md not found — skipping"
else
    DEBRIEF_MODEL=$(grep -m1 '^model:' "$DEBRIEF_AGENT" | awk '{print $2}' | tr -d '"')
    if [ "$DEBRIEF_MODEL" = "sonnet" ]; then
        pass "Check 42: debrief-analyst model: sonnet ✓"
    else
        fail "Check 42: debrief-analyst model is '$DEBRIEF_MODEL' — must be 'sonnet' (ADR-040 §6)"
    fi
fi
echo ""
fi  # should_run 42

# Check 43 — close.md must contain weight classification block (NANO/LIGHT/FULL) (ADR-040 §7, t-1802)
if should_run 43; then
echo "Check 43: close.md weight classification block..."
CLOSE_PROC="$SYSTEM_DIR/procedures/close.md"
if [ ! -f "$CLOSE_PROC" ]; then
    warn "Check 43: close.md not found at $CLOSE_PROC — skipping"
else
    MISSING_MODES=()
    grep -q "CLOSE_MODE=\"FULL\""  "$CLOSE_PROC" || MISSING_MODES+=("FULL")
    grep -q "CLOSE_MODE=\"LIGHT\"" "$CLOSE_PROC" || MISSING_MODES+=("LIGHT")
    grep -q "CLOSE_MODE=\"NANO\""  "$CLOSE_PROC" || MISSING_MODES+=("NANO")
    if [ ${#MISSING_MODES[@]} -eq 0 ]; then
        pass "Check 43: close.md has NANO/LIGHT/FULL weight classification ✓"
    else
        fail "Check 43: close.md missing CLOSE_MODE assignment(s): ${MISSING_MODES[*]} (ADR-040 §7)"
    fi
fi
echo ""
fi  # should_run 43

# Check 44 — close.md tasks.json ambiguous case must route to NANO (not LIGHT) (ADR-040 §7, t-1803)
if should_run 44; then
echo "Check 44: close.md tasks.json → NANO routing..."
CLOSE_PROC="$SYSTEM_DIR/procedures/close.md"
if [ ! -f "$CLOSE_PROC" ]; then
    warn "Check 44: close.md not found at $CLOSE_PROC — skipping"
else
    # tasks.json-only case must be documented as NANO (not LIGHT) in the ambiguous cases block
    if grep -q "tasks\.json.*NANO" "$CLOSE_PROC"; then
        pass "Check 44: close.md tasks.json ambiguous case routes to NANO ✓"
    elif grep -q "tasks\.json.*LIGHT" "$CLOSE_PROC"; then
        fail "Check 44: close.md tasks.json ambiguous case still shows LIGHT — must be NANO (ADR-040 §7 updated 2026-05-31)"
    else
        warn "Check 44: close.md tasks.json ambiguous case not found — verify manually"
    fi
fi
echo ""
fi  # should_run 44

# ── Optional: Golden-path drift (--golden flag) ──────────────────────────
if $RUN_GOLDEN; then
    echo "Check 27: Golden-path drift..."
    if [ -x "$SCRIPT_DIR/system/scripts/golden-path-diff.sh" ]; then
        if "$SCRIPT_DIR/system/scripts/golden-path-diff.sh" 2>&1 | sed 's/^/  /'; then
            pass "Check 27: Golden-path drift — none"
        else
            # Drift in golden paths is a warning, not a hard error: snapshots may
            # legitimately lag procedure changes. The signal is "review the diff".
            warn "Check 27: Golden-path drift detected — see output above"
        fi
    else
        warn "Check 25: golden-path-diff.sh not found at $SCRIPT_DIR/system/scripts/ (skipped)"
    fi
    echo ""
fi

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
