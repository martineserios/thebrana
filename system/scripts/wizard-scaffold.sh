#!/usr/bin/env bash
# t-2836 (ADR-084 §7a DEPEND expansion of the vendor+wrap band): scaffolds a
# new wizard script from the vendored .agents/skills/wizard/template.sh
# library. This is the build-composable step -- /brana:build or another skill
# calls this to get a fresh, executable wizard script to author stages into,
# instead of hand-copying the vendored template.
#
# Ephemeral by default, per system/rules/cwd-discipline.md's "/tmp/ is the
# only handoff zone" convention: with no --out, this writes to a fresh
# /tmp/wizard-<rand>.sh. The author (human, or the calling skill) commits it
# into the repo (e.g. scripts/) explicitly only when the human wants a
# repeatable setup path -- never as this script's default.
#
# Usage:
#   wizard-scaffold.sh [--title "Setup title"] [--out /path/to/script.sh]
#
# Prints the path to the scaffolded, executable script on stdout.
#
# WIZARD_SCRATCH_DIR overrides the default scratch directory (default /tmp).
# WIZARD_TEMPLATE_OVERRIDE overrides the vendored template path (test-only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="${WIZARD_TEMPLATE_OVERRIDE:-$REPO_ROOT/.agents/skills/wizard/template.sh}"

TITLE=""
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:?--title requires a value}"
      shift 2
      ;;
    --out)
      OUT="${2:?--out requires a value}"
      shift 2
      ;;
    *)
      echo "wizard-scaffold.sh: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

[[ -f "$TEMPLATE" ]] || {
  echo "wizard-scaffold.sh: vendored template missing: $TEMPLATE" >&2
  exit 1
}

if [[ -z "$OUT" ]]; then
  SCRATCH_DIR="${WIZARD_SCRATCH_DIR:-/tmp}"
  OUT=$(mktemp "$SCRATCH_DIR/wizard-XXXXXX.sh")
fi

cp "$TEMPLATE" "$OUT"

if [[ -n "$TITLE" ]]; then
  # Replace only the example banner call the template ships with -- the rest
  # of the STAGES example section is left for the author (human, or the
  # calling skill acting on the vendored SKILL.md's Process §3) to replace
  # with real stages.
  ESCAPED_TITLE=${TITLE//\\/\\\\}
  ESCAPED_TITLE=${ESCAPED_TITLE//\"/\\\"}
  TMP_EDIT=$(mktemp)
  sed "s|banner \"Stripe setup\"|banner \"${ESCAPED_TITLE}\"|" "$OUT" > "$TMP_EDIT"
  mv "$TMP_EDIT" "$OUT"
fi

chmod +x "$OUT"
printf '%s\n' "$OUT"
