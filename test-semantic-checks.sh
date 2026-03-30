#!/usr/bin/env bash
set -euo pipefail

# Test suite for semantic skill validation checks (checks A-D)
# Tests use temporary fixture skills to verify detection of real issues.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ERRORS=0
PASS=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

# Create temp fixture directory
FIXTURES=$(mktemp -d)
trap 'rm -rf "$FIXTURES"' EXIT

mkdir -p "$FIXTURES/skills/good-skill"
mkdir -p "$FIXTURES/skills/bad-tools"
mkdir -p "$FIXTURES/skills/dead-perm"
mkdir -p "$FIXTURES/skills/bad-paths"
mkdir -p "$FIXTURES/skills/bad-enums"
mkdir -p "$FIXTURES/skills/guided-ok"
mkdir -p "$FIXTURES/skills/guided-bad"
mkdir -p "$FIXTURES/skills/_shared"

# Shared file referenced by guided skills
cat > "$FIXTURES/skills/_shared/guided-execution.md" << 'FIXTURE'
# Guided Execution Protocol
This file exists for path reference tests.
FIXTURE

# ── Fixture: good-skill (all checks should pass) ──
cat > "$FIXTURES/skills/good-skill/SKILL.md" << 'FIXTURE'
---
name: good-skill
description: "A well-formed skill for testing"
group: execution
allowed-tools:
  - Read
  - Bash
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

# Good Skill

## Step 1

Use `Read` to read the file.
Then run `Bash` to execute a command.

```
AskUserQuestion:
  question: "Ready?"
```

See the [shared protocol](../_shared/guided-execution.md) for reference.
FIXTURE

# ── Fixture: bad-tools (tool in body not in allowed-tools) ──
cat > "$FIXTURES/skills/bad-tools/SKILL.md" << 'FIXTURE'
---
name: bad-tools
description: "Skill with tool mismatch"
group: execution
allowed-tools:
  - Read
  - Bash
status: stable
growth_stage: evergreen
---

# Bad Tools Skill

## Step 1

Use `Read` to read, then `Bash` to run.

## Step 2

Spawn an `Agent` to handle research.

Use `WebSearch` to find docs.

```
AskUserQuestion:
  question: "Continue?"
```
FIXTURE

# ── Fixture: dead-perm (allowed-tool never referenced in body) ──
cat > "$FIXTURES/skills/dead-perm/SKILL.md" << 'FIXTURE'
---
name: dead-perm
description: "Skill with unused allowed-tools"
group: execution
allowed-tools:
  - Read
  - Bash
  - WebFetch
  - Agent
  - Write
status: stable
growth_stage: evergreen
---

# Dead Perm Skill

## Step 1

Use `Read` to read files.
Run `Bash` commands.

That's all this skill does.
FIXTURE

# ── Fixture: bad-paths (broken file references) ──
cat > "$FIXTURES/skills/bad-paths/SKILL.md" << 'FIXTURE'
---
name: bad-paths
description: "Skill with broken paths"
group: execution
allowed-tools:
  - Read
status: stable
growth_stage: evergreen
---

# Bad Paths Skill

See the [shared protocol](../_shared/guided-execution.md) for reference.
See the [broken link](../_shared/nonexistent-file.md) for more info.
Also check [another broken](../missing-skill/README.md).
FIXTURE

# ── Fixture: bad-enums (invalid frontmatter enum values) ──
cat > "$FIXTURES/skills/bad-enums/SKILL.md" << 'FIXTURE'
---
name: bad-enums
description: "Skill with invalid enum values"
group: invalid-group
allowed-tools:
  - Read
status: active
growth_stage: mature
---

# Bad Enums Skill

Use `Read` here.
FIXTURE

# ── Fixture: guided-ok (step registry matches sections) ──
cat > "$FIXTURES/skills/guided-ok/SKILL.md" << 'FIXTURE'
---
name: guided-ok
description: "Guided skill with matching steps"
group: execution
allowed-tools:
  - Read
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

# Guided Skill

Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: SEED, EXPAND, OUTPUT.

### Phase 1 — SEED

Do the seed thing with `Read`.

### Phase 2 — EXPAND

Expand with `AskUserQuestion`.

### Phase 3 — OUTPUT

Write the output.
FIXTURE

# ── Fixture: guided-bad (step registry doesn't match sections) ──
cat > "$FIXTURES/skills/guided-bad/SKILL.md" << 'FIXTURE'
---
name: guided-bad
description: "Guided skill with mismatched steps"
group: execution
allowed-tools:
  - Read
status: stable
growth_stage: evergreen
---

# Guided Bad Skill

Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: SEED, EXPAND, SHAPE, OUTPUT.

### Phase 1 — SEED

Do the seed thing with `Read`.

### Phase 2 — EXPAND

Expand.

### Phase 3 — CLEANUP

This section doesn't match any registered step.
FIXTURE

# ═══════════════════════════════════════════════════════════════════
# Test runner: source the check functions and run against fixtures
# ═══════════════════════════════════════════════════════════════════

echo "=== Semantic Check Tests ==="
echo ""

# Source the semantic check functions
source "$SCRIPT_DIR/semantic-checks.sh"

# ── Check A Tests: allowed-tools consistency ──
echo "Check A: allowed-tools consistency..."

output=$(check_allowed_tools_consistency "$FIXTURES/skills/good-skill/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL"; then
    fail "good-skill should have no FAIL (got: $output)"
else
    pass "good-skill: no FAILs"
fi

output=$(check_allowed_tools_consistency "$FIXTURES/skills/bad-tools/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL.*Agent"; then
    pass "bad-tools: detected Agent missing from allowed-tools"
else
    fail "bad-tools: should FAIL on Agent (got: $output)"
fi
if echo "$output" | grep -q "FAIL.*WebSearch"; then
    pass "bad-tools: detected WebSearch missing from allowed-tools"
else
    fail "bad-tools: should FAIL on WebSearch (got: $output)"
fi
if echo "$output" | grep -q "FAIL.*AskUserQuestion"; then
    pass "bad-tools: detected AskUserQuestion missing from allowed-tools"
else
    fail "bad-tools: should FAIL on AskUserQuestion (got: $output)"
fi

output=$(check_allowed_tools_consistency "$FIXTURES/skills/dead-perm/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "WARN.*WebFetch"; then
    pass "dead-perm: detected WebFetch as unused"
else
    fail "dead-perm: should WARN on unused WebFetch (got: $output)"
fi
if echo "$output" | grep -q "WARN.*Agent"; then
    pass "dead-perm: detected Agent as unused"
else
    fail "dead-perm: should WARN on unused Agent (got: $output)"
fi
if echo "$output" | grep -q "WARN.*Write"; then
    pass "dead-perm: detected Write as unused"
else
    fail "dead-perm: should WARN on unused Write (got: $output)"
fi
echo ""

# ── Check B Tests: file path references ──
echo "Check B: file path references..."

output=$(check_file_path_references "$FIXTURES/skills/good-skill/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL"; then
    fail "good-skill should have no broken paths (got: $output)"
else
    pass "good-skill: all paths resolve"
fi

output=$(check_file_path_references "$FIXTURES/skills/bad-paths/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL.*nonexistent-file.md"; then
    pass "bad-paths: detected broken link to nonexistent-file.md"
else
    fail "bad-paths: should FAIL on nonexistent-file.md (got: $output)"
fi
if echo "$output" | grep -q "FAIL.*missing-skill/README.md"; then
    pass "bad-paths: detected broken link to missing-skill/README.md"
else
    fail "bad-paths: should FAIL on missing-skill/README.md (got: $output)"
fi
# Valid path should not trigger a FAIL
if echo "$output" | grep -q "FAIL.*guided-execution.md"; then
    fail "bad-paths: should NOT fail on existing guided-execution.md"
else
    pass "bad-paths: valid path guided-execution.md not flagged"
fi
echo ""

# ── Check C Tests: frontmatter schema enums ──
echo "Check C: frontmatter schema enums..."

output=$(check_frontmatter_schema "$FIXTURES/skills/good-skill/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL"; then
    fail "good-skill should have valid enums (got: $output)"
else
    pass "good-skill: all enums valid"
fi

output=$(check_frontmatter_schema "$FIXTURES/skills/bad-enums/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL.*status.*active"; then
    pass "bad-enums: detected invalid status 'active'"
else
    fail "bad-enums: should FAIL on status=active (got: $output)"
fi
if echo "$output" | grep -q "FAIL.*growth_stage.*mature"; then
    pass "bad-enums: detected invalid growth_stage 'mature'"
else
    fail "bad-enums: should FAIL on growth_stage=mature (got: $output)"
fi
if echo "$output" | grep -q "FAIL.*group.*invalid-group"; then
    pass "bad-enums: detected invalid group 'invalid-group'"
else
    fail "bad-enums: should FAIL on group=invalid-group (got: $output)"
fi
echo ""

# ── Check D Tests: step registry consistency ──
echo "Check D: step registry consistency..."

output=$(check_step_registry "$FIXTURES/skills/guided-ok/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL\|WARN"; then
    fail "guided-ok should have no issues (got: $output)"
else
    pass "guided-ok: steps match sections"
fi

output=$(check_step_registry "$FIXTURES/skills/guided-bad/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "WARN.*SHAPE"; then
    pass "guided-bad: detected registered step SHAPE with no section"
else
    fail "guided-bad: should WARN on SHAPE with no section (got: $output)"
fi
if echo "$output" | grep -q "WARN.*OUTPUT"; then
    pass "guided-bad: detected registered step OUTPUT with no section"
else
    fail "guided-bad: should WARN on OUTPUT with no section (got: $output)"
fi
# Note: section→step reverse check removed (too noisy on real skills).
# Only registered→section direction is checked.
if ! echo "$output" | grep -q "WARN.*CLEANUP"; then
    pass "guided-bad: unregistered section CLEANUP not flagged (by design)"
else
    fail "guided-bad: should NOT flag unregistered sections (got: $output)"
fi

# Non-guided skill should skip silently
output=$(check_step_registry "$FIXTURES/skills/good-skill/SKILL.md" 2>&1) || true
if echo "$output" | grep -q "FAIL\|WARN"; then
    fail "good-skill (non-guided) should be skipped silently (got: $output)"
else
    pass "good-skill: non-guided skill skipped"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════
echo "=== Semantic Check Test Summary ==="
echo "Passed: $PASS"
echo "Failed: $ERRORS"
if [ "$ERRORS" -gt 0 ]; then
    echo "TEST SUITE FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
