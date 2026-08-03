#!/usr/bin/env bash
# Tests for system/scripts/ship-brana-oracle.sh (t-2501)
#
# Stubs cargo/rustup/file/ssh/scp so no real build or network happens.
# Verifies: preflight failure is loud, the install is a same-directory
# atomic rename, the manifest records commit+sha+dirty, and a post-install
# sha mismatch fails the ship.
#
# Usage: bash tests/scripts/test-ship-brana-oracle.sh

set -uo pipefail

# See test-check-oracle-brana-drift.sh — mandatory for any test running git:
# the red-verification hook executes tests inside a git hook where GIT_DIR is
# exported, which would point fixture git calls at the real repo. Same 5-var
# denylist also lives in system/hooks/red-verification.sh (the root fix,
# t-2602) and docs/architecture/features/build-receipts.md — no shared
# source yet; update all four if the list ever changes.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../system/scripts/ship-brana-oracle.sh"

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1 -- $2"; ((FAIL++)) || true; }

make_fixture() {
  local root="$1"
  # repo with a rust cli dir
  git init -q "$root/repo"
  (cd "$root/repo" && git config user.email t@t && git config user.name t \
    && mkdir -p system/cli/rust/src \
    && echo 'fn main(){}' > system/cli/rust/src/main.rs \
    && git add -A && git commit -q -m base)

  # tool stubs
  cat > "$root/rustup" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_NO_MUSL:-0}" == "1" ]] && { echo "x86_64-unknown-linux-gnu"; exit 0; }
echo "x86_64-unknown-linux-musl"
STUB
  cat > "$root/cargo" <<'STUB'
#!/usr/bin/env bash
mkdir -p "target/x86_64-unknown-linux-musl/release"
echo "dummy-binary-$STUB_BUILD_TAG" > "target/x86_64-unknown-linux-musl/release/brana"
STUB
  cat > "$root/file" <<'STUB'
#!/usr/bin/env bash
echo "$1: ELF 64-bit LSB pie executable, x86-64, static-pie linked"
STUB
  cat > "$root/musl-gcc" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat > "$root/scp" <<'STUB'
#!/usr/bin/env bash
echo "scp $*" >> "${TOOL_LOG:-/dev/null}"
exit 0
STUB
  cat > "$root/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "${TOOL_LOG:-/dev/null}"
cmd="${@: -1}"
case "$cmd" in
  true) exit 0 ;;
  *"cat >"*) cat >> "${TOOL_LOG:-/dev/null}"; exit 0 ;;   # manifest write via stdin
  *sha256sum*)
    if [[ -n "${STUB_REMOTE_SHA:-}" ]]; then
      echo "$STUB_REMOTE_SHA  /home/ubuntu/.local/bin/brana"
    else
      sha256sum "$STUB_BIN_FILE" | awk '{print $1 "  /home/ubuntu/.local/bin/brana"}'
    fi
    exit 0 ;;
  *--version*) echo "brana 9.9.9"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$root/rustup" "$root/cargo" "$root/file" "$root/musl-gcc" "$root/scp" "$root/ssh"
}

run_ship() {
  local root="$1"; shift
  PATH="$root:$PATH" \
  REPO="$root/repo" RUSTUP_BIN="$root/rustup" CARGO_BIN="$root/cargo" \
  FILE_BIN="$root/file" SSH_BIN="$root/ssh" SCP_BIN="$root/scp" \
  TOOL_LOG="$root/tool.log" \
  STUB_BIN_FILE="$root/repo/system/cli/rust/target/x86_64-unknown-linux-musl/release/brana" \
  "$@" bash "$SCRIPT" 2>&1
}

echo "=== ship-brana-oracle.sh ==="
echo ""

# Test 1: musl target not installed -> loud preflight failure, no build attempted
ROOT="$(mktemp -d)"; make_fixture "$ROOT"
OUT="$(run_ship "$ROOT" env STUB_NO_MUSL=1 STUB_BUILD_TAG=t1)"; RC=$?
if [[ "$RC" -ne 0 ]] && grep -qi "musl" <<<"$OUT" && [[ ! -f "$ROOT/repo/system/cli/rust/target/x86_64-unknown-linux-musl/release/brana" ]]; then
  pass "preflight: missing musl target fails loudly before building"
else
  fail "preflight: missing musl target fails loudly before building" "rc=$RC out=$(head -3 <<<"$OUT")"
fi
rm -rf "$ROOT"

# Test 2: happy path -> atomic same-dir rename install + manifest with commit/sha/dirty=false
ROOT="$(mktemp -d)"; make_fixture "$ROOT"
OUT="$(run_ship "$ROOT" env STUB_BUILD_TAG=t2)"; RC=$?
COMMIT="$(git -C "$ROOT/repo" rev-parse HEAD)"
SHA="$(sha256sum "$ROOT/repo/system/cli/rust/target/x86_64-unknown-linux-musl/release/brana" | awk '{print $1}')"
LOG="$(cat "$ROOT/tool.log" 2>/dev/null)"
ok=1
[[ "$RC" -eq 0 ]] || ok=0
grep -q "mv -f" <<<"$LOG" || ok=0                       # rename install
grep -q ".brana.new" <<<"$LOG" || ok=0                  # staged next to target (same fs)
grep -q "\"commit\":\"$COMMIT\"" <<<"$LOG" || ok=0      # manifest content
grep -q "\"sha256\":\"$SHA\"" <<<"$LOG" || ok=0
grep -q "\"dirty\":false" <<<"$LOG" || ok=0
if [[ "$ok" -eq 1 ]]; then
  pass "happy path: atomic rename install + correct manifest shipped"
else
  fail "happy path: atomic rename install + correct manifest shipped" "rc=$RC log=$(tail -4 <<<"$LOG")"
fi
rm -rf "$ROOT"

# Test 3: dirty working tree -> ship proceeds but manifest records dirty:true and warns
ROOT="$(mktemp -d)"; make_fixture "$ROOT"
echo change >> "$ROOT/repo/system/cli/rust/src/main.rs"
OUT="$(run_ship "$ROOT" env STUB_BUILD_TAG=t3)"; RC=$?
LOG="$(cat "$ROOT/tool.log" 2>/dev/null)"
if [[ "$RC" -eq 0 ]] && grep -q "\"dirty\":true" <<<"$LOG" && grep -qi "dirty" <<<"$OUT"; then
  pass "dirty tree: warns and records dirty:true in manifest"
else
  fail "dirty tree: warns and records dirty:true in manifest" "rc=$RC"
fi
rm -rf "$ROOT"

# Test 4 (boundary): post-install remote sha mismatch -> ship FAILS (never
# report success on an unverified install), and NO manifest is written for
# the unverified install (challenger iteration 1: manifest-before-verify left
# a manifest describing a binary that failed verification)
ROOT="$(mktemp -d)"; make_fixture "$ROOT"
OUT="$(run_ship "$ROOT" env STUB_BUILD_TAG=t4 STUB_REMOTE_SHA=deadbeef)"; RC=$?
LOG="$(cat "$ROOT/tool.log" 2>/dev/null)"
if [[ "$RC" -ne 0 ]] && grep -qiE "verif|mismatch" <<<"$OUT" && ! grep -q "manifest.json" <<<"$LOG"; then
  pass "verify: remote sha mismatch fails the ship, manifest not written"
else
  fail "verify: remote sha mismatch fails the ship, manifest not written" "rc=$RC out=$(tail -2 <<<"$OUT")"
fi
rm -rf "$ROOT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
