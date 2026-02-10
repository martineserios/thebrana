#!/usr/bin/env bash
set -euo pipefail

# Brana Test Runner
# Runs all test layers in order. Stops on first failure unless --all is passed.
#
# Layers:
#   0. validate.sh    — static checks (YAML, JSON, syntax, secrets, sizes)
#   1. test-hooks.sh  — hook smoke test (pipe fake JSON, check exit 0)
#   2. test-memory.sh — memory round-trip (store → search → verify)
#
# Usage:
#   ./test.sh          — run all, stop on first failure
#   ./test.sh --all    — run all, report everything
#   ./test.sh hooks    — run only hook smoke test
#   ./test.sh memory   — run only memory round-trip
#   ./test.sh validate — run only static validation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP_ON_FAIL=true
RUN_LAYER=""

for arg in "$@"; do
    case "$arg" in
        --all)     STOP_ON_FAIL=false ;;
        validate)  RUN_LAYER="validate" ;;
        hooks)     RUN_LAYER="hooks" ;;
        memory)    RUN_LAYER="memory" ;;
        *)         echo "Usage: $0 [--all] [validate|hooks|memory]"; exit 1 ;;
    esac
done

TOTAL_ERRORS=0

run_layer() {
    local name="$1"
    local script="$2"
    echo ""
    echo "━━━ Layer: $name ━━━"
    echo ""
    if bash "$script"; then
        echo ""
        return 0
    else
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        echo ""
        if [ "$STOP_ON_FAIL" = true ]; then
            echo "Stopping — $name failed. Use --all to run everything."
            exit 1
        fi
        return 1
    fi
}

echo "=== Brana Test Suite ==="

if [ -z "$RUN_LAYER" ] || [ "$RUN_LAYER" = "validate" ]; then
    run_layer "Static Validation" "$SCRIPT_DIR/validate.sh" || true
    [ -n "$RUN_LAYER" ] && exit $TOTAL_ERRORS
fi

if [ -z "$RUN_LAYER" ] || [ "$RUN_LAYER" = "hooks" ]; then
    run_layer "Hook Smoke Test" "$SCRIPT_DIR/test-hooks.sh" || true
    [ -n "$RUN_LAYER" ] && exit $TOTAL_ERRORS
fi

if [ -z "$RUN_LAYER" ] || [ "$RUN_LAYER" = "memory" ]; then
    run_layer "Memory Round-Trip" "$SCRIPT_DIR/test-memory.sh" || true
    [ -n "$RUN_LAYER" ] && exit $TOTAL_ERRORS
fi

echo ""
echo "=== Test Suite Complete ==="
if [ "$TOTAL_ERRORS" -gt 0 ]; then
    echo "FAILED — $TOTAL_ERRORS layer(s) with errors"
    exit 1
else
    echo "ALL LAYERS PASSED"
    exit 0
fi
