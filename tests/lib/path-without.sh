#!/usr/bin/env bash
# path_without NAME — print a PATH under which NAME is not found but every other executable is.
#
# WHY. The mods-harness suites stage "claude is not installed". Replacing PATH with /usr/bin:/bin
# also hid Homebrew's bash >= 4 and jq on the macOS CI job (CI run 37140367665, t-3427), and simply
# dropping every directory that holds NAME hides whatever shares it (a developer Mac with claude in
# /opt/homebrew/bin beside bash and jq — panel finding). So: keep every directory without NAME;
# for each directory WITH it, link its other executables into one shadow directory.
# The shadow directory lives under ${TMPDIR:-/tmp} and is reused per process.
# Usage: source tests/lib/path-without.sh; PATH="$(path_without claude)" cmd ...
path_without() {
    local name="$1" out="" dir f shadow=""
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] || continue
        if [ -x "$dir/$name" ]; then
            if [ -z "$shadow" ]; then
                shadow="${TMPDIR:-/tmp}/path-without.$$.$name"
                rm -rf "$shadow"; mkdir -p "$shadow"
                out="${out:+$out:}$shadow"
            fi
            for f in "$dir"/*; do
                [ -f "$f" ] && [ -x "$f" ] || continue
                [ "${f##*/}" = "$name" ] && continue
                [ -e "$shadow/${f##*/}" ] || ln -s "$f" "$shadow/${f##*/}"
            done
            continue
        fi
        out="${out:+$out:}$dir"
    done
    printf '%s' "$out"
}
