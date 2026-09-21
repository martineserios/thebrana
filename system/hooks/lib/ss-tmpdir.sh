#!/usr/bin/env bash
# session-start.sh temp-dir setup and checked writer (t-3195, hardened t-3357).
# Extracted from the hook to keep it under the 50KB file-size gate (validate Check 8, t-3360).
#
# Usage: source it with TMPDIR_SS already set. It creates the directory (mode 700), sets
# SS_TMP_FAIL / SS_TMP_SHOW, and defines _ss_put, the one writer every job result goes through.
#
# Temp-dir trouble (full/read-only /tmp) must be VISIBLE, never fatal.
# Every job result goes through _ss_put; a failed write leaves a marker that
# Phase 3 turns into a [Hook warning]. The probe catches a dir we cannot use.
SS_TMP_FAIL=""
SS_TMP_SHOW="$TMPDIR_SS"
mkdir -p -m 700 "$TMPDIR_SS" 2>/dev/null || true
# Gate 3 (t-3357): the path is predictable and may sit in a shared /tmp. Results are READ BACK
# from this dir into additionalContext, so a dir another user pre-created (or a symlink) would
# let them inject context. Anything not owned by us is unusable: point at a path that cannot
# exist (nothing is read or written; the final rm -rf is a no-op) and surface the warning.
if [ -L "$TMPDIR_SS" ] || { [ -e "$TMPDIR_SS" ] && [ ! -O "$TMPDIR_SS" ]; }; then
    TMPDIR_SS="/nonexistent/brana-ss-unowned"
    SS_TMP_FAIL=1
fi
{ : > "$TMPDIR_SS/.probe"; } 2>/dev/null || SS_TMP_FAIL=1
_ss_put() {  # usage: <producer> | _ss_put <name>
    { cat > "$TMPDIR_SS/$1"; } 2>/dev/null || { : > "$TMPDIR_SS/.write-failed"; } 2>/dev/null || true
}
