#!/usr/bin/env bash
# Test: /brana:plugin add writes the engine's v2 registry and scans before activation (t-3502)
# The skill used to hand-write ~/.claude/plugins/installed_plugins.json with its own schema
# (`plugins.<name>: {...}`), so a plugin it installed was invisible to the engine's loader
# AND to mods-check.sh --installed (which follows the engine's `name@marketplace -> [entries]`
# shape). The contract: the add step documents the engine's shape and points at the scan.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$REPO_ROOT/system/skills/plugin/SKILL.md"
PASS=0; FAIL=0
assert() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  PASS: $desc"; ((PASS++)); else echo "  FAIL: $desc"; ((FAIL++)); fi; }

echo "=== test_plugin_skill_registry.sh ==="
assert "registry key is <name>@<marketplace> (engine v2)" grep -q '"<name>@<marketplace>"' "$SKILL"
assert "registry value is a list of entries" grep -qE '"<name>@<marketplace>": \[' "$SKILL"
assert "entries carry scope/installPath/version/installedAt (engine fields)" grep -q '"scope"' "$SKILL"
assert "the old hand-rolled shape is gone" bash -c "! grep -q '\"<name>\": {' '$SKILL'"
assert "add step points at mods-check.sh --installed before activation" grep -q 'mods-check.sh --installed' "$SKILL"
assert "add step names the session-start re-check" grep -q 'mods-installed-check.sh' "$SKILL"
assert "add step names ADR-096 Law 3 as the reason" grep -q 'Law 3' "$SKILL"
assert "remove step deletes the <name>@<marketplace> key" grep -qE 'Remove .*<name>@<marketplace>' "$SKILL"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
