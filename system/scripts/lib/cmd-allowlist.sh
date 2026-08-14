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
#
# t-2876 (Gate 3 ship-blocking finding): the original implementation validated
# via `grep <<<"$cmd"` — grep's input model is LINE-ORIENTED, so a $cmd
# containing an embedded literal newline was checked one line at a time. Line 1
# alone ("pytest") satisfied the allowlist-prefix match, and no single line
# contained a blocked metacharacter, so a payload like $'pytest\ntouch PWNED'
# passed both checks — then reached `eval`, where bash treats an embedded
# newline as a command separator exactly like `;`, executing the injected
# second line. `[[ =~ ]]` alone does NOT fix this: a whole-string `^(cargo
# test|...)` still matches at position 0 regardless of what characters (incl.
# newlines) follow. The newline must be rejected explicitly, before any other
# check — this closes the class for every current and future consumer, not
# just the call site (H10's demoable:, ac-grade.sh) where it was first found
# reachable.

CMD_ALLOWLIST_RE='^(cargo test|pytest|python -m pytest|bun test|npm test|yarn test|bash tests/|\./tests/)'

allowlisted_command() {
    local cmd="$1"
    [[ "$cmd" == *$'\n'* ]] && return 1
    [[ "$cmd" =~ [\;\&\|\`\$\(\)\{\}\<\>] ]] && return 1
    [[ "$cmd" =~ $CMD_ALLOWLIST_RE ]]
}
