#!/usr/bin/env bash
# t-3488 gate-parity fixtures — six inputs brana's PreToolUse gates BLOCK today (measurement b).
# Usage: fixtures.sh list | fixtures.sh gates   (gates = run the command/content cases through `ruflo guidance gates`)
# Each case: name | brana hook | kind (command|content|write) | input. Expected brana result: BLOCK for all six.
set -euo pipefail
T="${RUFLO_TRIAL_DIR:-$HOME/enter_thebrana/ruflo-trial}"
R="$T/node_modules/.bin/ruflo"

cases() {
cat <<'EOF'
worktree-gate|worktree-gate.sh|command|git checkout -b feature/x
main-guard|main-guard.sh|command|git commit -m "feat: change system/hooks/foo.sh" # on branch main, system/ file staged
secret-scan|secret-scan.sh|content|SLACK_TOKEN=xoxb-EXAMPLE-0000000000-REDACTEDREDACTED  # shape-only EXAMPLE; brana's secret-scan blocked the unmarked form on commit (live baseline, 2026-10-07)
spec-gate|spec-gate.sh|write|Write system/hooks/new-gate.sh # M+ task, no docs/architecture/features/*.md spec (advisory in brana)
tdd-gate|tdd-gate.sh|write|Write src/feature.rs # implementation file, no test file in project root
no-attribution|no-attribution-commit.sh|command|git commit -m "fix: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
EOF
}

case "${1:-list}" in
  list) cases | column -t -s'|' ;;
  gates)
    cases | while IFS='|' read -r name hook kind input; do
      printf '\n== %s (%s) ==\n' "$name" "$kind"
      case "$kind" in
        command) HOME="$T/home" "$R" guidance gates -c "${input%% #*}" --json 2>/dev/null | tr -d '\n' | head -c 300 ;;
        content) HOME="$T/home" "$R" guidance gates --content "$input" --json 2>/dev/null | tr -d '\n' | head -c 300 ;;
        write)   echo "(write case — only testable in a live session via tool.check / policy)" ;;
      esac; echo
    done ;;
  *) echo "usage: $0 list|gates"; exit 2 ;;
esac
