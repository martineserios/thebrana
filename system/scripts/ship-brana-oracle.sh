#!/usr/bin/env bash
# ship-brana-oracle.sh — cross-compile brana and ship it to oracle-hub (t-2501)
#
# The one documented command for the procedure previously scattered across
# docs/architecture/features/scheduler.md §Oracle-hub deployment. oracle-hub
# (2-core/956MB, glibc 2.35) cannot build Rust and cannot run binaries linked
# against a newer glibc, so we build a static musl artifact here and ship it.
#
#   build (musl, static) -> verify static -> scp -> atomic rename install
#   -> write manifest (commit, sha256, built_at, dirty) -> verify remote sha
#
# The manifest is what system/scripts/check-oracle-brana-drift.sh audits —
# shipping through this script is what makes the binary "managed".
#
# Install is a SAME-DIRECTORY rename (.brana.new -> brana): atomic on one
# filesystem and safe while the old binary is executing (running-binary-
# replace-via-rename). Never copy over the live file.
#
# Env overrides (tests): REPO, RUSTUP_BIN, CARGO_BIN, FILE_BIN, SSH_BIN,
#                        SCP_BIN, OH_TARGET, REMOTE_BIN.

set -uo pipefail

REPO="${REPO:-$HOME/enter_thebrana/thebrana}"
RUSTUP_BIN="${RUSTUP_BIN:-rustup}"
CARGO_BIN="${CARGO_BIN:-cargo}"
FILE_BIN="${FILE_BIN:-file}"
SSH_BIN="${SSH_BIN:-ssh}"
SCP_BIN="${SCP_BIN:-scp}"
OH_TARGET="${OH_TARGET:-oracle-hub}"
REMOTE_BIN="${REMOTE_BIN:-/home/ubuntu/.local/bin/brana}"
TARGET="x86_64-unknown-linux-musl"
CLI_DIR="$REPO/system/cli/rust"
BIN="$CLI_DIR/target/$TARGET/release/brana"
REMOTE_DIR="$(dirname "$REMOTE_BIN")"
REMOTE_TMP="$REMOTE_DIR/.brana.new"
REMOTE_MANIFEST="$REMOTE_BIN.manifest.json"

log()  { echo "[ship-brana-oracle] $*"; }
die()  { echo "[ship-brana-oracle] FAIL: $*" >&2; exit 1; }

remote() { "$SSH_BIN" -o ConnectTimeout=10 -o BatchMode=yes "$OH_TARGET" "$1"; }

# --- provenance -------------------------------------------------------------
commit="$(git -C "$REPO" rev-parse HEAD)" || die "cannot resolve HEAD in $REPO"
dirty=false
if [[ -n "$(git -C "$REPO" status --porcelain -- system/cli/rust 2>/dev/null)" ]]; then
  dirty=true
  log "WARNING: system/cli/rust has uncommitted changes — shipping a dirty build (manifest will say so)"
fi

# --- preflight (fail before the 5-minute build, not after) -------------------
"$RUSTUP_BIN" target list --installed 2>/dev/null | grep -q "^$TARGET$" \
  || die "rust target $TARGET not installed — run: rustup target add $TARGET"
command -v musl-gcc >/dev/null 2>&1 \
  || die "musl-gcc not found — run: sudo apt-get install musl-tools"
remote "true" >/dev/null 2>&1 \
  || die "$OH_TARGET unreachable over ssh"

# --- build -------------------------------------------------------------------
log "building brana ($TARGET, release) from ${commit:0:12}..."
(cd "$CLI_DIR" && "$CARGO_BIN" build --release --target "$TARGET" -p brana-cli) \
  || die "cargo build failed"
[[ -f "$BIN" ]] || die "expected artifact missing: $BIN"

"$FILE_BIN" "$BIN" | grep -qi "static" \
  || die "artifact is not statically linked ($("$FILE_BIN" "$BIN")) — glibc mismatch would break oracle-hub"

sha="$(sha256sum "$BIN" | awk '{print $1}')"

# --- ship: stage next to target, atomic rename, then manifest ----------------
log "shipping to $OH_TARGET:$REMOTE_BIN (sha ${sha:0:12}...)"
"$SCP_BIN" -q "$BIN" "$OH_TARGET:$REMOTE_TMP" || die "scp failed"
remote "chmod +x $REMOTE_TMP && mv -f $REMOTE_TMP $REMOTE_BIN" || die "remote install (rename) failed"

# --- verify BEFORE writing the manifest ---------------------------------------
# Never leave a manifest describing an install that failed verification: the
# manifest is the drift check's ground truth, so it is written only for a
# verified binary (challenger iteration 1, 2026-08-02). A verified-but-
# manifest-less state self-reports as UNMANAGED on the next drift run.
remote_sha="$(remote "sha256sum $REMOTE_BIN" | awk '{print $1}')"
[[ "$remote_sha" == "$sha" ]] \
  || die "post-install verification failed: remote sha ${remote_sha:0:12}... != shipped ${sha:0:12}... (mismatch) — manifest NOT written"

manifest="$(printf '{"commit":"%s","sha256":"%s","built_at":"%s","target":"%s","dirty":%s}' \
  "$commit" "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TARGET" "$dirty")"
echo "$manifest" | remote "cat > $REMOTE_MANIFEST" || die "manifest write failed"

version="$(remote "$REMOTE_BIN --version 2>/dev/null" || true)"

log "OK: shipped ${commit:0:12} (dirty=$dirty) -> $OH_TARGET:$REMOTE_BIN"
log "    remote reports: ${version:-<no --version output>}"
log "    manifest: $REMOTE_MANIFEST"
exit 0
