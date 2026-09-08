#!/usr/bin/env bash
# CI shim (t-3323): CI's `tests` job globs tests/*/*.sh one level deep, so the ADR-094
# suites under system/scripts/tests/ would never gate a merge (the t-3331 gap). This shim
# runs them under the TDD_RED_UNTIL convention (BRANA_TDD_SWEEP=1): a RED-by-design suite
# exits 0 with "RED as expected (pending t-NNNN)"; any other failure propagates.
# Retire when t-3331 aligns CI discovery with validate.sh's sweeps.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAIL=0
for s in test-adr094-ledger-in-git-dir.sh test-adr094-ledger-migration.sh test-post-checkout-ledger-backstop.sh; do
    echo "=== $s ==="
    if BRANA_TDD_SWEEP=1 bash "$ROOT/system/scripts/tests/$s" </dev/null; then
        echo "--- ok ---"
    else
        echo "--- FAILED outside the RED convention ---"; FAIL=1
    fi
done
exit "$FAIL"
