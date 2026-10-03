#!/usr/bin/env bash
# path_without NAME — print $PATH with every directory that holds an executable NAME removed.
#
# WHY. The mods-harness suites stage "claude is not installed" by hiding the binary. The first
# version replaced PATH with /usr/bin:/bin, which on the macOS CI job also hid Homebrew's
# bash >= 4 and jq — bootstrap's bash preflight then exited 1 and every case failed for the
# wrong reason (CI run 37140367665, t-3427). Remove only what must be absent; keep the rest.
# Usage: source tests/lib/path-without.sh; PATH="$(path_without claude)" cmd ...
path_without() {
    local name="$1" out="" dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] || continue
        [ -x "$dir/$name" ] && continue
        out="${out:+$out:}$dir"
    done
    printf '%s' "$out"
}
