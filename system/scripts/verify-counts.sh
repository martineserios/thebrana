#!/usr/bin/env bash
# verify-counts.sh — Check filesystem counts against documented claims
# Compares actual skill/agent/rule/command counts with docs/reference/*.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

check_category() {
  local category="$1"
  local fs_count="$2"
  local doc_file="$3"
  local doc_count=""

  if [[ ! -f "$doc_file" ]]; then
    echo "  $category: MISMATCH — filesystem: $fs_count, documented: (file missing: $doc_file)"
    FAIL=$((FAIL + 1))
    return
  fi

  # Extract the bold count from the first line matching "**N ...**"
  doc_count=$(grep -oP '\*\*\K[0-9]+(?= [a-z].*\*\*)' "$doc_file" | head -1)

  if [[ -z "$doc_count" ]]; then
    echo "  $category: MISMATCH — filesystem: $fs_count, documented: (no count found in $doc_file)"
    FAIL=$((FAIL + 1))
    return
  fi

  if [[ "$fs_count" -eq "$doc_count" ]]; then
    echo "  $category: PASS — filesystem: $fs_count, documented: $doc_count"
    PASS=$((PASS + 1))
  else
    echo "  $category: MISMATCH — filesystem: $fs_count, documented: $doc_count"
    FAIL=$((FAIL + 1))
  fi
}

# Count skills: directories in system/skills/ that contain SKILL.md (exclude _shared)
skills_count=$(find "$REPO_ROOT/system/skills" -name "SKILL.md" -not -path "*/_shared/*" | wc -l)

# Count agents: .md files in system/agents/
agents_count=$(find "$REPO_ROOT/system/agents" -maxdepth 1 -name "*.md" | wc -l)

# Count rules: .md files in system/rules/
rules_count=$(find "$REPO_ROOT/system/rules" -maxdepth 1 -name "*.md" | wc -l)

# Count commands: files in system/commands/ (both .md and extensionless)
commands_count=$(find "$REPO_ROOT/system/commands" -maxdepth 1 -type f | wc -l)

echo "=== verify-counts: filesystem vs docs ==="

check_category "skills" "$skills_count" "$REPO_ROOT/docs/reference/skills.md"
check_category "agents" "$agents_count" "$REPO_ROOT/docs/reference/agents.md"
check_category "rules" "$rules_count" "$REPO_ROOT/docs/reference/rules.md"
check_category "commands" "$commands_count" "$REPO_ROOT/docs/reference/commands.md"

echo ""
echo "Results: $PASS passed, $FAIL mismatches"

if [[ $FAIL -gt 0 ]]; then
  echo "Action: run 'uv run python system/scripts/generate-reference.py' to update docs"
  exit 1
fi

exit 0
