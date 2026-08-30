#!/usr/bin/env bash
# t-2836 (ADR-084 §7a DEPEND expansion): wizard-scaffold.sh's only real logic
# is (a) defaulting the output path to a scratch/tmp location when the caller
# doesn't name one, and (b) copying the vendored template verbatim rather than
# hand-authoring it -- both are easy to get subtly wrong (default path landing
# in the repo instead of scratch, template drifting from the vendored copy),
# so this test pins both before any adapter wiring is trusted.
#
# Written before system/scripts/wizard-scaffold.sh exists (TDD) -- must fail
# with "no such file" on first run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCAFFOLD="$REPO_ROOT/system/scripts/wizard-scaffold.sh"
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1)); echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
  fi
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "== wizard-scaffold.sh: exists and is executable =="
if [ -x "$SCAFFOLD" ]; then
  PASS=$((PASS + 1)); echo "  PASS: scaffold script exists and is executable"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: $SCAFFOLD missing or not executable"
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  exit 1
fi

echo ""
echo "== wizard-scaffold.sh: default path lands in scratch (/tmp), not the repo =="
OUT1=$("$SCAFFOLD")
RC1=$?
check "default invocation exits 0" "0" "$RC1"
case "$OUT1" in
  /tmp/*) check "default output path is under /tmp" "under-tmp" "under-tmp" ;;
  *) check "default output path is under /tmp" "under-tmp" "NOT-under-tmp:$OUT1" ;;
esac
[ -f "$OUT1" ] && rm -f "$OUT1"

echo ""
echo "== wizard-scaffold.sh: explicit --out is honored exactly =="
EXPLICIT_OUT="$WORKDIR/my-onboarding-wizard.sh"
OUT2=$("$SCAFFOLD" --out "$EXPLICIT_OUT")
check "explicit --out path is returned verbatim" "$EXPLICIT_OUT" "$OUT2"
check "explicit --out path was actually written" "yes" "$([ -f "$EXPLICIT_OUT" ] && echo yes || echo no)"

echo ""
echo "== wizard-scaffold.sh: scaffolded file is the vendored template, executable =="
check "scaffolded file is executable" "yes" "$([ -x "$EXPLICIT_OUT" ] && echo yes || echo no)"
check "scaffolded file carries the vendored STAGES marker" "yes" "$(grep -q 'STAGES — author this section' "$EXPLICIT_OUT" && echo yes || echo no)"
check "scaffolded file carries the vendored write_env helper" "yes" "$(grep -q '^write_env()' "$EXPLICIT_OUT" && echo yes || echo no)"

echo ""
echo "== wizard-scaffold.sh: --title replaces only the example banner =="
TITLED_OUT="$WORKDIR/titled-wizard.sh"
"$SCAFFOLD" --out "$TITLED_OUT" --title "Client Onboarding — Stripe + GitHub" >/dev/null
check "custom title appears in banner call" "yes" "$(grep -q 'banner "Client Onboarding — Stripe + GitHub"' "$TITLED_OUT" && echo yes || echo no)"
check "generic banner() helper definition untouched" "yes" "$(grep -q '^banner()' "$TITLED_OUT" && echo yes || echo no)"

echo ""
echo "== wizard-scaffold.sh: missing vendored template is a hard error =="
MISSING_TEMPLATE="$WORKDIR/does-not-exist.sh"
WIZARD_TEMPLATE_OVERRIDE="$MISSING_TEMPLATE" "$SCAFFOLD" --out "$WORKDIR/never-written.sh" >/dev/null 2>&1
RC3=$?
if [ "$RC3" -ne 0 ]; then
  PASS=$((PASS + 1)); echo "  PASS: missing template -> non-zero exit"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: missing template -> exit 0 (expected failure)"
fi
check "nothing written when template missing" "no" "$([ -f "$WORKDIR/never-written.sh" ] && echo yes || echo no)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
