# cmd-allowlist.sh — shared command allowlist for AC-grammar heuristics 7/9/10.
#
# The single owner of CMD_ALLOWLIST_RE / allowlisted_command() (ADR-081 D1). Prior
# to t-2857, this guard existed as two independently-authored copies
# (goal-completion.sh, ac-lint.sh) — proven by divergent syntax despite one's
# comment claiming to mirror the other. That drift is exactly what let a
# prefix-anchored, substring-matched allowlist reach unattended `eval` with an
# injected suffix (t-2856 challenger finding). Every consumer of this guard
# (ac-grade.sh, ac-lint.sh) sources this file — never redefines it locally.
#
# Usage: source this file, then call `allowlisted_command "$cmd"` — returns 0
# (true) iff the command both matches an allowed test-runner prefix AND contains
# no shell metacharacters (rejecting "safe-prefix; payload" injection).

CMD_ALLOWLIST_RE='^(cargo test|pytest|python -m pytest|bun test|npm test|yarn test|bash tests/|\./tests/)'

allowlisted_command() {
    local cmd="$1"
    grep -qE '[;&|`$(){}<>]' <<<"$cmd" && return 1
    grep -qE "$CMD_ALLOWLIST_RE" <<<"$cmd"
}
