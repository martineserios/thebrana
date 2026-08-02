#!/usr/bin/env bash
# Tests for system/scripts/check-oracle-brana-drift.sh (t-2501)
#
# Stubs ssh via SSH_BIN and runs against a throwaway git fixture, so tests
# never touch oracle-hub or the real repo. The drift check has exactly four
# verdicts: SKIP (hub unreachable, exit 0), UNMANAGED (no manifest, exit 1),
# SWAPPED (binary sha != manifest sha, exit 1), DRIFT (main moved under
# system/cli/rust since the manifest commit, exit 1) — plus OK (exit 0).
#
# Usage: bash tests/scripts/test-check-oracle-brana-drift.sh

set -uo pipefail

# The red-verification pre-commit hook runs this test INSIDE a git hook,
# where git exports GIT_DIR/GIT_INDEX_FILE — without this unset, every
# fixture `git commit` below lands on the REAL branch instead of the mktemp
# repo (happened live 2026-08-01: three fixture commits hijacked the t-2501
# branch and trashed the worktree). Any test that runs git must do this.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../../system/scripts/check-oracle-brana-drift.sh"

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
fail() { echo "  FAIL: $1 -- $2"; ((FAIL++)) || true; }

# --- fixture: git repo with origin, workspace-shaped rust tree ---
# crates/brana-cli + crates/brana-core are in the shipped binary's dependency
# closure; crates/brana-mcp is NOT (challenger iteration 1: counting it
# produces false DRIFT for a crate the shipped binary doesn't contain).
make_repo() {
  local root="$1"
  git init -q --bare "$root/origin.git"
  git clone -q "$root/origin.git" "$root/repo" 2>/dev/null
  (cd "$root/repo" \
    && git config user.email t@t && git config user.name t \
    && mkdir -p system/cli/rust/crates/brana-cli/src system/cli/rust/crates/brana-mcp/src docs \
    && echo 'fn main(){}' > system/cli/rust/crates/brana-cli/src/main.rs \
    && echo 'fn mcp(){}'  > system/cli/rust/crates/brana-mcp/src/lib.rs \
    && echo '[workspace]' > system/cli/rust/Cargo.toml \
    && git add -A && git commit -q -m "rust: base" \
    && git push -q origin HEAD 2>/dev/null)
}

# ssh stub: dispatches on the remote command it receives.
# Controlled via env: STUB_UNREACHABLE, STUB_MANIFEST (path or empty=missing),
# STUB_BIN_SHA. Records invocations to SSH_LOG.
make_ssh_stub() {
  local dir="$1"
  cat > "$dir/ssh" <<'STUB'
#!/usr/bin/env bash
echo "ssh $*" >> "${SSH_LOG:-/dev/null}"
[[ "${STUB_UNREACHABLE:-0}" == "1" ]] && exit 255
# last argument is the remote command
cmd="${@: -1}"
case "$cmd" in
  true) exit 0 ;;
  *cat*manifest*)
    [[ -n "${STUB_MANIFEST:-}" && -f "${STUB_MANIFEST:-}" ]] || exit 1
    cat "$STUB_MANIFEST"; exit 0 ;;
  *sha256sum*)
    echo "${STUB_BIN_SHA:-0000}  /home/ubuntu/.local/bin/brana"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$dir/ssh"
}

# 64-char hex sha from a single repeated char (manifest sha256 validation
# rejects anything that is not exactly 64 hex chars)
hex64() { printf "%0.s$1" $(seq 1 64); }

write_manifest() {
  local path="$1" commit="$2" sha="$3"
  printf '{"commit":"%s","sha256":"%s","built_at":"2026-08-01T00:00:00Z","target":"x86_64-unknown-linux-musl","dirty":false}\n' \
    "$commit" "$sha" > "$path"
}

run_check() {
  local root="$1"
  SSH_BIN="$root/ssh" REPO="$root/repo" bash "$SCRIPT" 2>&1
}

echo "=== check-oracle-brana-drift.sh ==="
echo ""

# Test 1: hub unreachable -> SKIP, exit 0 (laptop-off / hub-down must not alarm)
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
OUT="$(STUB_UNREACHABLE=1 run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 0 ]] && grep -qi "skip" <<<"$OUT"; then
  pass "unreachable hub: clean skip, exit 0"
else
  fail "unreachable hub: clean skip, exit 0" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 2: no manifest on hub -> UNMANAGED, exit 1
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
OUT="$(STUB_MANIFEST= run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 1 ]] && grep -qi "unmanaged" <<<"$OUT"; then
  pass "missing manifest: unmanaged warning, exit 1"
else
  fail "missing manifest: unmanaged warning, exit 1" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 3: binary sha != manifest sha -> SWAPPED, exit 1
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
COMMIT="$(git -C "$ROOT/repo" rev-parse HEAD)"
write_manifest "$ROOT/manifest.json" "$COMMIT" "$(hex64 a)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 b)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 1 ]] && grep -qiE "match|swap" <<<"$OUT"; then
  pass "sha mismatch: swapped-binary warning, exit 1"
else
  fail "sha mismatch: swapped-binary warning, exit 1" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 4: main moved under crates/brana-cli since manifest commit -> DRIFT, exit 1
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
OLD="$(git -C "$ROOT/repo" rev-parse HEAD)"
(cd "$ROOT/repo" && echo 'fn fix(){}' >> system/cli/rust/crates/brana-cli/src/main.rs \
  && git add -A && git commit -q -m "fix(cli): newer" && git push -q origin HEAD 2>/dev/null)
write_manifest "$ROOT/manifest.json" "$OLD" "$(hex64 c)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 c)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 1 ]] && grep -qiE "drift|behind" <<<"$OUT"; then
  pass "cli commits after manifest: drift warning, exit 1"
else
  fail "cli commits after manifest: drift warning, exit 1" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 5: current binary -> OK, exit 0
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
COMMIT="$(git -C "$ROOT/repo" rev-parse HEAD)"
write_manifest "$ROOT/manifest.json" "$COMMIT" "$(hex64 d)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 d)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 0 ]] && grep -qi "ok" <<<"$OUT"; then
  pass "current binary: OK, exit 0"
else
  fail "current binary: OK, exit 0" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 6 (boundary): commits after manifest that do NOT touch system/cli/rust
# -> no false drift (docs/spec churn must not nag about the binary)
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
OLD="$(git -C "$ROOT/repo" rev-parse HEAD)"
(cd "$ROOT/repo" && echo x >> docs/notes.md \
  && git add -A && git commit -q -m "docs: unrelated" && git push -q origin HEAD 2>/dev/null)
write_manifest "$ROOT/manifest.json" "$OLD" "$(hex64 e)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 e)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 0 ]] && grep -qi "ok" <<<"$OUT"; then
  pass "non-cli commits only: no false drift, exit 0"
else
  fail "non-cli commits only: no false drift, exit 0" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# --- challenger iteration 1 findings (2026-08-02) ---

# Test 7: commit touching ONLY crates/brana-mcp (not in the shipped binary's
# dependency closure) -> no false drift, exit 0
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
OLD="$(git -C "$ROOT/repo" rev-parse HEAD)"
(cd "$ROOT/repo" && echo 'fn more(){}' >> system/cli/rust/crates/brana-mcp/src/lib.rs \
  && git add -A && git commit -q -m "feat(mcp): unrelated to cli binary" && git push -q origin HEAD 2>/dev/null)
write_manifest "$ROOT/manifest.json" "$OLD" "$(hex64 f)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 f)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 0 ]] && grep -qi "ok" <<<"$OUT"; then
  pass "brana-mcp-only commit: no false drift, exit 0"
else
  fail "brana-mcp-only commit: no false drift, exit 0" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 8: git fetch failure must be LOUD (exit 1, distinct verdict), never a
# silent comparison against a stale cached origin/main — that is the exact
# silent-staleness shape this task was filed to eliminate
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
COMMIT="$(git -C "$ROOT/repo" rev-parse HEAD)"
git -C "$ROOT/repo" remote set-url origin "$ROOT/gone.git"
write_manifest "$ROOT/manifest.json" "$COMMIT" "$(hex64 1)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 1)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 1 ]] && grep -qi "fetch" <<<"$OUT"; then
  pass "fetch failure: loud FETCH-FAILED verdict, exit 1"
else
  fail "fetch failure: loud FETCH-FAILED verdict, exit 1" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

# Test 9 (boundary): manifest commit that is not a hex object id must be
# rejected as malformed BEFORE reaching git argv (defense-in-depth)
ROOT="$(mktemp -d)"; make_repo "$ROOT"; make_ssh_stub "$ROOT"
write_manifest "$ROOT/manifest.json" '--upload-pack=/tmp/evil' "$(hex64 2)"
OUT="$(STUB_MANIFEST="$ROOT/manifest.json" STUB_BIN_SHA="$(hex64 2)" run_check "$ROOT")"; RC=$?
if [[ "$RC" -eq 1 ]] && grep -qiE "unmanaged|malformed" <<<"$OUT"; then
  pass "non-hex manifest commit: rejected as malformed, exit 1"
else
  fail "non-hex manifest commit: rejected as malformed, exit 1" "rc=$RC out=$OUT"
fi
rm -rf "$ROOT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
