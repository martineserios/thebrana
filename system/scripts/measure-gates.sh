#!/usr/bin/env bash
# measure-gates.sh — Run all 3 ADR-027 ratchet gates and output combined report.
#
# Usage: ./measure-gates.sh [--days N]
#   --days N   Window for Gate A commit analysis (default: 30)
#
# Output: one JSON object per gate, then a summary line.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== ADR-027 Ratchet Gate Report ===" >&2
echo "" >&2

echo "--- Gate A: doc-update rate ---" >&2
A_OUT=$("$SCRIPT_DIR/measure-gate-a.sh" "$@")
echo "$A_OUT"

echo "" >&2
echo "--- Gate B: EXTRACT accuracy ---" >&2
B_OUT=$("$SCRIPT_DIR/measure-gate-b.sh" "$@")
echo "$B_OUT"

echo "" >&2
echo "--- Gate C: accept/skip rate ---" >&2
C_OUT=$("$SCRIPT_DIR/measure-gate-c.sh" "$@")
echo "$C_OUT"

echo "" >&2

# Summary: check each gate vs threshold using jq if available
if command -v jq &>/dev/null; then
  echo "--- Summary ---" >&2

  check_gate() {
    local label="$1"
    local json="$2"
    local metric="$3"

    STATUS=$(echo "$json" | jq -r '.status // "ok"' 2>/dev/null)
    if [ "$STATUS" = "no_data" ]; then
      NOTE=$(echo "$json" | jq -r '.note // ""' 2>/dev/null)
      echo "  $label: NO DATA — $NOTE" >&2
      return
    fi

    RATE=$(echo "$json" | jq -r ".$metric // \"null\"" 2>/dev/null)
    THRESHOLD=$(echo "$json" | jq -r '.threshold // "null"' 2>/dev/null)

    if [ "$RATE" = "null" ] || [ "$THRESHOLD" = "null" ]; then
      echo "  $label: UNKNOWN (rate or threshold not available)" >&2
      return
    fi

    PASS=$(echo "$RATE >= $THRESHOLD" | bc -l 2>/dev/null || echo "?")
    if [ "$PASS" = "1" ]; then
      echo "  $label: PASS ($RATE >= $THRESHOLD)" >&2
    else
      echo "  $label: FAIL ($RATE < $THRESHOLD)" >&2
    fi
  }

  check_gate "Gate A (doc-update rate)" "$A_OUT" "rate"
  check_gate "Gate B (EXTRACT precision)" "$B_OUT" "precision"
  check_gate "Gate C (accept rate)" "$C_OUT" "rate"

  echo "" >&2
fi
