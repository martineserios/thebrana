#!/usr/bin/env bash
# Semantic check functions for skill validation
# Sourced by validate.sh and test-semantic-checks.sh
#
# Each function takes a SKILL.md path and prints FAIL/WARN/PASS lines.
# Functions do NOT increment global counters — the caller does that.

# Known CC tool names (word-boundary matched in skill bodies)
KNOWN_TOOLS="Read Write Edit Glob Grep Bash Agent AskUserQuestion WebSearch WebFetch EnterPlanMode ExitPlanMode TaskCreate TaskUpdate TaskList TaskGet TaskOutput TaskStop NotebookEdit Skill SendMessage LSP"

# Valid enum values
VALID_STATUS="stable experimental seed deprecated"
VALID_GROWTH_STAGE="evergreen prototype seed"
VALID_GROUPS="execution session learning business integration content brana utility thinking venture core domain capture tools"

# Required frontmatter fields
REQUIRED_FIELDS="name description group allowed-tools status"

# ── Helper: extract frontmatter from SKILL.md ──
_extract_frontmatter() {
    awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$1"
}

# ── Helper: extract body (everything after frontmatter) from SKILL.md ──
_extract_body() {
    awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm{print}' "$1"
}

# ── Helper: get skill name from path ──
_skill_label() {
    local dir
    dir=$(dirname "$1")
    basename "$dir"
}

# ── Check A: allowed-tools body↔frontmatter consistency ──
# Scans body for tool name references, compares against allowed-tools frontmatter.
# FAIL: tool referenced in body but missing from allowed-tools
# WARN: tool in allowed-tools but never referenced in body (dead permission)
check_allowed_tools_consistency() {
    local skill_file="$1"
    local skill_name
    skill_name=$(_skill_label "$skill_file")

    local frontmatter body
    frontmatter=$(_extract_frontmatter "$skill_file")
    body=$(_extract_body "$skill_file")

    # Extract allowed-tools list from frontmatter
    local allowed_tools
    allowed_tools=$(echo "$frontmatter" | python3 -c "
import sys, yaml
d = yaml.safe_load(sys.stdin)
tools = d.get('allowed-tools', [])
if tools:
    for t in tools:
        # Only keep known CC tool names (skip MCP tools, skill refs)
        print(t)
" 2>/dev/null) || return 0

    [ -z "$allowed_tools" ] && return 0

    # Scan body for tool references using strict matching
    # Match tool names in instruction contexts only:
    #   `ToolName`  — backtick-wrapped (most common in skill markdown)
    #   ToolName:   — label pattern (e.g., "AskUserQuestion:")
    #   ToolName(   — function-call pattern
    #   "ToolName"  — quoted
    # Does NOT match bare prose usage (e.g., "Read the docs", "Write a report")
    local body_tools=""
    for tool in $KNOWN_TOOLS; do
        if echo "$body" | grep -qP "\`${tool}\`|(?<![a-zA-Z])${tool}\s*:|(?<![a-zA-Z])${tool}\s*\(|\"${tool}\""; then
            body_tools="$body_tools $tool"
        fi
    done

    # Check: tools in body but NOT in allowed-tools → FAIL
    for tool in $body_tools; do
        if ! echo "$allowed_tools" | grep -qx "$tool"; then
            echo "  FAIL: skills/$skill_name — tool '$tool' used in body but missing from allowed-tools"
        fi
    done

    # Check: tools in allowed-tools but NOT in body → WARN (dead permission)
    # Only check known CC tools (skip MCP tools, skill refs like "backlog", "challenge")
    while IFS= read -r tool; do
        [ -z "$tool" ] && continue
        # Skip non-CC tools (MCP tools, skill names)
        local is_known=false
        for kt in $KNOWN_TOOLS; do
            if [ "$tool" = "$kt" ]; then
                is_known=true
                break
            fi
        done
        $is_known || continue

        # Check if tool appears in body_tools
        if ! echo "$body_tools" | grep -qw "$tool"; then
            echo "  WARN: skills/$skill_name — '$tool' in allowed-tools but never referenced in body"
        fi
    done <<< "$allowed_tools"
}

# ── Helper: strip fenced code blocks from markdown ──
_strip_code_blocks() {
    awk '/^[[:space:]]*```/{skip=!skip; next} !skip{print}'  # indented fences count (list items)
}

# ── Check B: file path reference validation ──
# Extracts markdown link paths and resolves them relative to skill directory.
# FAIL: referenced file does not exist
check_file_path_references() {
    local skill_file="$1"
    local skill_name
    skill_name=$(_skill_label "$skill_file")
    local skill_dir
    skill_dir=$(dirname "$skill_file")

    local body
    body=$(_extract_body "$skill_file")

    # Strip code blocks to avoid matching placeholder paths in examples
    local prose
    prose=$(echo "$body" | _strip_code_blocks)

    # Extract markdown link paths: [text](path)
    # Only match relative paths (not http/https/mailto/anchors)
    local paths
    paths=$(echo "$prose" | grep -oP '\]\(\K[^)]+' | grep -v '^https\?://' | grep -v '^mailto:' | grep -v '^#') || true

    [ -z "$paths" ] && return 0

    # Resolve repo root (handle worktrees via git common dir)
    local repo_root
    repo_root=$(cd "$skill_dir" && git rev-parse --show-toplevel 2>/dev/null) || repo_root=""

    while IFS= read -r ref_path; do
        [ -z "$ref_path" ] && continue
        # Skip obvious placeholder paths
        case "$ref_path" in
            path|path.md|url|file|link|src|dest|target|relative-path.md) continue ;;
        esac
        # Skip template-style doc references like "NN-slug.md" without directory
        # that appear in [doc NN](NN-slug.md) patterns (no directory = template)
        if echo "$ref_path" | grep -qP '^[0-9]+-[a-z].*\.md$' && [[ "$ref_path" != */* ]]; then
            continue
        fi
        # Resolve relative to skill directory
        local resolved
        resolved=$(cd "$skill_dir" && realpath -m "$ref_path" 2>/dev/null) || resolved=""
        if [ -n "$resolved" ] && [ -e "$resolved" ]; then
            continue  # file exists, no problem
        fi
        # For cross-repo references (../../), try resolving from repo root's parent
        if [[ "$ref_path" == ../../* ]] && [ -n "$repo_root" ]; then
            local workspace_resolved
            workspace_resolved=$(cd "$skill_dir" && realpath -m "$ref_path" 2>/dev/null | sed "s|$(realpath -m "$skill_dir")/../../|$(dirname "$repo_root")/|") || workspace_resolved=""
            if [ -n "$workspace_resolved" ] && [ -e "$workspace_resolved" ]; then
                continue  # cross-repo file exists
            fi
        fi
        echo "  FAIL: skills/$skill_name — broken link: '$ref_path'"
    done <<< "$paths"
}

# ── Check C: frontmatter schema enum validation ──
# Validates required fields exist and enum values are valid.
# FAIL: missing required field or invalid enum value
check_frontmatter_schema() {
    local skill_file="$1"
    local skill_name
    skill_name=$(_skill_label "$skill_file")

    local frontmatter
    frontmatter=$(_extract_frontmatter "$skill_file")
    [ -z "$frontmatter" ] && return 0

    # Do all validation in a single Python call to avoid repeated parsing
    echo "$frontmatter" | python3 -c "
import sys, yaml

d = yaml.safe_load(sys.stdin)
if not d:
    sys.exit(0)

skill = '$skill_name'
errors = []

# Required fields
for field in ['name', 'description', 'group', 'allowed-tools', 'status']:
    if d.get(field) is None:
        errors.append(f\"  FAIL: skills/{skill} — missing required field '{field}'\")

# Enum: status
status = d.get('status')
valid_status = {'stable', 'experimental', 'seed', 'deprecated'}
if status and status not in valid_status:
    errors.append(f\"  FAIL: skills/{skill} — invalid status '{status}' (valid: {', '.join(sorted(valid_status))})\")

# Enum: growth_stage (optional)
gs = d.get('growth_stage')
valid_gs = {'evergreen', 'prototype', 'seed'}
if gs and gs not in valid_gs:
    errors.append(f\"  FAIL: skills/{skill} — invalid growth_stage '{gs}' (valid: {', '.join(sorted(valid_gs))})\")

# Enum: group
group = d.get('group')
valid_groups = {'execution', 'session', 'learning', 'business', 'integration',
                'content', 'brana', 'utility', 'thinking', 'venture', 'core', 'domain',
                'capture', 'tools'}
if group and group not in valid_groups:
    errors.append(f\"  FAIL: skills/{skill} — invalid group '{group}' (valid: {', '.join(sorted(valid_groups))})\")

for e in errors:
    print(e)
" 2>/dev/null || true
}

# ── Check D: step registry consistency ──
# For skills referencing guided-execution.md: cross-check registered steps vs section headers.
# WARN: registered step with no matching section
# WARN: section that doesn't match any registered step
check_step_registry() {
    local skill_file="$1"
    local skill_name
    skill_name=$(_skill_label "$skill_file")

    local body
    body=$(_extract_body "$skill_file")

    # Only check skills that reference guided-execution
    if ! echo "$body" | grep -q "guided-execution"; then
        return 0
    fi

    # Extract registered steps from "Register these steps: A, B, C" line
    local steps_line
    steps_line=$(echo "$body" | grep -i "Register these steps:" | head -1) || true
    [ -z "$steps_line" ] && return 0

    # Parse step names (comma or space separated, after the colon)
    local registered_steps
    registered_steps=$(echo "$steps_line" | sed 's/.*Register these steps:\s*//' | tr -d '.' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -v '^$')

    [ -z "$registered_steps" ] && return 0

    # Extract all ## and ### headers (the sections in the skill body)
    local all_headers
    all_headers=$(echo "$body" | grep -P '^#{2,3}\s+' || true)

    # Check: each registered step should appear (case-insensitive substring) in at least one header
    # This handles patterns like:
    #   Step "GATE" matched by "### Step 1: Gate check"
    #   Step "SEED" matched by "### Phase 1 — SEED"
    #   Step "SCAN-SPECS" matched by "## Step 3: Scan specs"
    while IFS= read -r step; do
        [ -z "$step" ] && continue
        # Convert hyphenated step names: SCAN-SPECS → "scan.specs" for flexible matching
        local pattern
        pattern=$(echo "$step" | tr '[:upper:]' '[:lower:]' | sed 's/-/[ -]/g')
        if ! echo "$all_headers" | grep -qiP "$pattern"; then
            echo "  WARN: skills/$skill_name — registered step '$step' has no matching section header"
        fi
    done <<< "$registered_steps"
}
