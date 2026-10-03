#!/usr/bin/env bash
# tests/lib/path-without.sh: hides exactly one executable and keeps every other tool on PATH,
# even when they share a directory (a developer Mac with claude beside Homebrew bash/jq —
# second-variant panel finding, t-3427).
# Run: bash tests/scripts/test-path-without.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/tests/lib/path-without.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
echo "=== test-path-without.sh ==="
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/shared" "$T/other"
for b in claude mytool; do printf '#!/bin/sh\necho %s\n' "$b" > "$T/shared/$b"; chmod +x "$T/shared/$b"; done
printf '#!/bin/sh\necho other\n' > "$T/other/othertool"; chmod +x "$T/other/othertool"
P="$(PATH="$T/shared:$T/other:/usr/bin:/bin" path_without claude)"
assert "claude is hidden" "" "$(PATH="$P" command -v claude 2>/dev/null)"
assert "a tool sharing claude's directory is still found" mytool "$(PATH="$P" mytool 2>/dev/null)"
assert "a tool in another directory is still found" other "$(PATH="$P" othertool 2>/dev/null)"
assert "system tools are still found" yes "$(PATH="$P" command -v sh >/dev/null 2>&1 && echo yes)"
echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
