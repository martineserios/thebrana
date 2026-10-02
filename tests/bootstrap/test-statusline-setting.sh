#!/usr/bin/env bash
# bootstrap.sh must WIRE the status line, not just copy the script (t-3388).
# The first real macOS run showed: ~/.claude/statusline.sh deployed, settings.json .statusLine still
# null, so the host never ran it. The fix is an idempotent settings.json edit in the same shape as
# the attribution / env / autoMode edits: ensure_statusline_setting. Contract under test:
#   - .statusLine null/absent      -> set {"type":"command","command":"~/.claude/statusline.sh"} (1 change)
#   - already points at statusline.sh -> untouched, 0 changes (extra keys such as padding survive)
#   - a custom command             -> untouched, 0 changes (never clobber the user's own status line)
#   - CHECK_ONLY                   -> reports the change, writes nothing
#   - settings.json missing        -> created with just the status line (a brand-new machine runs
#                                     bootstrap before the host ever wrote settings.json)
# Run: bash tests/bootstrap/test-statusline-setting.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BOOTSTRAP="$ROOT/bootstrap.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-statusline-setting.sh ==="

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- static: bootstrap defines and calls the function ---------------------------------------------
assert "T1: bootstrap.sh defines ensure_statusline_setting" yes "$(grep -q '^ensure_statusline_setting() {' "$BOOTSTRAP" && echo yes || echo no)"
assert "T1b: bootstrap.sh calls it (not just defines it)" yes "$(grep -qE '^[[:space:]]*ensure_statusline_setting( |$)' "$BOOTSTRAP" && echo yes || echo no)"
# The call must sit INSIDE the 'statusline.sh was deployed' guard: never wire a script that is not there.
assert "T1c: the call is inside the deploy guard (indented)" yes "$(grep -qE '^[[:space:]]+ensure_statusline_setting$' "$BOOTSTRAP" && echo yes || echo no)"

# --- behavioral: run the extracted function against a scratch settings.json ------------------------
FN=$(awk '/^ensure_statusline_setting\(\) \{/{flag=1} flag{print} flag&&/^\}/{exit}' "$BOOTSTRAP")
# run_fn <settings-file> <check_only true|false>  -> prints "<CHANGES>|<output>"
run_fn() {
    # Output goes to a file, not a $(...) — a command substitution would run the function in a
    # subshell and lose its CHANGES increment, which is half of what is under test.
    ( SETTINGS_FILE="$1"; CHECK_ONLY=$2; CHANGES=0
      eval "$FN"; ensure_statusline_setting >"$T/fn.out" 2>&1; printf '%s|%s' "$CHANGES" "$(cat "$T/fn.out")" )
}
if [ -z "$FN" ]; then
    echo "  FAIL: ensure_statusline_setting not extractable — behavioral tests cannot run"; FAIL=$((FAIL+1))
else
    # T2: null -> set
    S="$T/null.json"; printf '{"permissions":{"allow":[]},"statusLine":null}\n' >"$S"
    R="$(run_fn "$S" false)"
    assert "T2: null .statusLine -> counted as 1 change" 1 "${R%%|*}"
    assert "T2: command points at statusline.sh" yes "$(has statusline.sh "$(jq -r '.statusLine.command // ""' "$S")")"
    assert "T2: type is command" command "$(jq -r '.statusLine.type // ""' "$S")"
    assert "T2: other keys survive the edit" '[]' "$(jq -c '.permissions.allow' "$S")"
    # T3: second run converges
    R="$(run_fn "$S" false)"
    assert "T3: second run -> 0 changes (idempotent)" 0 "${R%%|*}"
    assert "T3: second run says '=' (unchanged)" yes "$(has '= settings.json statusLine' "${R#*|}")"
    # T4: custom command is never clobbered
    S="$T/custom.json"; printf '{"statusLine":{"type":"command","command":"/opt/me/my-status.sh"}}\n' >"$S"
    R="$(run_fn "$S" false)"
    assert "T4: custom command -> 0 changes" 0 "${R%%|*}"
    assert "T4: custom command kept verbatim" /opt/me/my-status.sh "$(jq -r '.statusLine.command' "$S")"
    assert "T4: output says the custom line was kept" yes "$(has custom "${R#*|}")"
    # T4b: a statusLine object WITHOUT a command field is still the user's — not ours to overwrite
    S="$T/nocmd.json"; printf '{"statusLine":{"type":"static","text":"hi"}}\n' >"$S"
    BEFORE="$(jq -cS . "$S")"; R="$(run_fn "$S" false)"
    assert "T4b: statusLine object without command -> 0 changes" 0 "${R%%|*}"
    assert "T4b: object kept byte-for-byte" "$BEFORE" "$(jq -cS . "$S")"
    # T4c: a NON-object value (schema-invalid, still the user's) -> kept, 0 changes, and no abort:
    # the function runs under bootstrap's set -e, so a failing jq read would kill the whole deploy.
    S="$T/string.json"; printf '{"statusLine":"~/.claude/statusline.sh"}\n' >"$S"
    BEFORE="$(jq -cS . "$S")"; R="$(bash -e -c 'SETTINGS_FILE="$1"; CHECK_ONLY=false; CHANGES=0; eval "$2"; ensure_statusline_setting >/dev/null 2>&1; printf "%s" "$CHANGES"' _ "$S" "$FN")"; RC=$?
    assert "T4c: non-object statusLine does not abort under set -e" 0 "$RC"
    assert "T4c: non-object statusLine -> 0 changes" 0 "$R"
    assert "T4c: value kept byte-for-byte" "$BEFORE" "$(jq -cS . "$S")"
    # T4d: a custom command whose basename merely CONTAINS statusline.sh is custom, not ours
    S="$T/lookalike.json"; printf '{"statusLine":{"type":"command","command":"/opt/me/my-statusline.sh"}}\n' >"$S"
    R="$(run_fn "$S" false)"
    assert "T4d: look-alike custom command reported as custom, not 'already wired'" yes "$(has custom "${R#*|}")"
    # T5: an already-wired brana line with extra keys (padding) is left alone
    S="$T/wired.json"; printf '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":1}}\n' >"$S"
    BEFORE="$(jq -cS . "$S")"; R="$(run_fn "$S" false)"
    assert "T5: already wired -> 0 changes" 0 "${R%%|*}"
    assert "T5: padding and friends preserved byte-for-byte" "$BEFORE" "$(jq -cS . "$S")"
    # T6: CHECK_ONLY reports but does not write
    S="$T/check.json"; printf '{"statusLine":null}\n' >"$S"
    R="$(run_fn "$S" true)"
    assert "T6: --check counts the pending change" 1 "${R%%|*}"
    assert "T6: --check says 'would set'" yes "$(has 'would set' "${R#*|}")"
    assert "T6: --check wrote nothing" null "$(jq -c '.statusLine' "$S")"
    # T7: missing settings.json is created (fresh machine)
    S="$T/fresh/settings.json"; mkdir -p "$T/fresh"
    R="$(run_fn "$S" false)"
    assert "T7: missing settings.json -> created, 1 change" 1 "${R%%|*}"
    assert "T7: created file has the status line" yes "$(has statusline.sh "$(jq -r '.statusLine.command // ""' "$S" 2>/dev/null)")"
    assert "T7: created file is valid JSON" yes "$(jq -e . "$S" >/dev/null 2>&1 && echo yes || echo no)"
    # T7b: --check on a missing file does not create it
    S="$T/fresh2/settings.json"; mkdir -p "$T/fresh2"
    R="$(run_fn "$S" true)"
    assert "T7b: --check on a missing file creates nothing" no "$([ -e "$S" ] && echo yes || echo no)"
fi

# --- end to end: --check on an empty HOME mentions the status line as pending -----------------------
H="$(mktemp -d)"; trap 'rm -rf "$T" "$H"' EXIT
OUT="$(cd "$ROOT" && HOME="$H" BRANA_SCHEDULER_BACKEND=none ./bootstrap.sh --check 2>&1)"; RC=$?
assert "T8: --check on an empty HOME still exits 0" 0 "$RC"
assert "T8: --check on an empty HOME reports settings.json would be created with the status line" yes "$(has 'would create with statusLine' "$OUT")"
assert "T8: --check names the knock-on (later settings.json steps apply on the real run)" yes "$(has 'then apply on the real run' "$OUT")"

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
