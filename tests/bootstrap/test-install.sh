#!/usr/bin/env bash
# Tests for install.sh — fresh clone, update, and self-install paths.
#
# Run: bash tests/bootstrap/test-install.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"
PASS=0; FAIL=0; TOTAL=0

# ── Helpers ───────────────────────────────────────────────────────────────

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL+1))
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  PASS: $desc"; PASS=$((PASS+1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $expected"
        printf '    got:\n%s\n' "$actual" | head -10
        FAIL=$((FAIL+1))
    fi
}

assert_not_contains() {
    local desc="$1" absent="$2" actual="$3"
    TOTAL=$((TOTAL+1))
    if ! [[ "$actual" == *"$absent"* ]]; then
        echo "  PASS: $desc"; PASS=$((PASS+1))
    else
        echo "  FAIL: $desc — unexpected string found: $absent"
        FAIL=$((FAIL+1))
    fi
}

assert_exit() {
    local desc="$1" expected_rc="$2" actual_rc="$3"
    TOTAL=$((TOTAL+1))
    if [ "$actual_rc" -eq "$expected_rc" ]; then
        echo "  PASS: $desc"; PASS=$((PASS+1))
    else
        echo "  FAIL: $desc (expected exit $expected_rc, got $actual_rc)"
        FAIL=$((FAIL+1))
    fi
}

WORKDIR=$(mktemp -d)
BASH_BIN="$(command -v bash)"
DIRNAME_BIN="$(command -v dirname)"
PWD_BIN="$(command -v pwd)"
trap 'rm -rf "$WORKDIR"' EXIT

# Symlink the minimal set of tools install.sh needs into a bin dir, excluding
# any tools we want to appear "missing" in that test.
populate_bin() {
    local bindir="$1"; shift
    local exclude=("$@")
    mkdir -p "$bindir"
    for tool in bash dirname pwd; do
        local skip=0
        for ex in "${exclude[@]:-}"; do [[ "$tool" == "$ex" ]] && skip=1; done
        [[ "$skip" -eq 1 ]] && continue
        local src
        src="$(command -v "$tool" 2>/dev/null)" && ln -sf "$src" "$bindir/$tool"
    done
}

# Write a mock git binary that logs calls and simulates clone/pull.
write_mock_git() {
    local bindir="$1"
    mkdir -p "$bindir"
    populate_bin "$bindir"
    cat > "$bindir/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >> "$GIT_CALL_LOG"
case "$1" in
  clone)
    target="${@: -1}"
    mkdir -p "$target/.git"
    printf '#!/usr/bin/env bash\necho "bootstrap called"\n' > "$target/bootstrap.sh"
    ;;
  -C)
    # git -C <dir> pull [...]
    shift; shift
    case "$1" in
      pull) exit 0 ;;
    esac
    ;;
esac
exit 0
EOF
    chmod +x "$bindir/git"
}

# Write a no-op bootstrap.sh into a directory.
write_mock_bootstrap() {
    printf '#!/usr/bin/env bash\necho "bootstrap called"\n' > "$1/bootstrap.sh"
}

# ── Self-install path (running from inside an existing clone) ─────────────

echo ""
echo "── Self-install path ─────────────────────────────"

t="$WORKDIR/self"
bindir="$t/bin"
write_mock_git "$bindir"
# install.sh lives in a dir that also has bootstrap.sh → triggers self-install branch
repo="$t/repo"; mkdir -p "$repo"
cp "$INSTALL_SH" "$repo/install.sh"
write_mock_bootstrap "$repo"

GIT_CALL_LOG="$t/git.log"; export GIT_CALL_LOG
touch "$GIT_CALL_LOG"
out=$(PATH="$bindir:$PATH" BRANA_DIR="$t/should_not_be_used" bash "$repo/install.sh" 2>&1); rc=$?

assert_exit         "self-install exits 0"                    0   $rc
assert_contains     "self-install: reports existing repo"     "Using existing repo" "$out"
assert_contains     "self-install: runs bootstrap"            "bootstrap called"    "$out"
assert_not_contains "self-install: no clone"                  "Cloning brana"       "$out"
assert_not_contains "self-install: no pull"                   "git pull"            "$(cat "$GIT_CALL_LOG")"

# ── Fresh clone path (BRANA_DIR does not exist yet) ───────────────────────

echo ""
echo "── Fresh clone path ──────────────────────────────"

t="$WORKDIR/fresh"
bindir="$t/bin"
write_mock_git "$bindir"
# install.sh in a dir WITHOUT bootstrap.sh → external invocation path
cp "$INSTALL_SH" "$t/install.sh"
target="$t/brana_fresh"   # must not exist before the test

GIT_CALL_LOG="$t/git.log"; export GIT_CALL_LOG
touch "$GIT_CALL_LOG"
out=$(PATH="$bindir:$PATH" BRANA_DIR="$target" bash "$t/install.sh" 2>&1); rc=$?

assert_exit     "fresh clone exits 0"                     0   $rc
assert_contains "fresh clone: reports cloning"            "Cloning brana"  "$out"
assert_contains "fresh clone: git clone called"           "git clone"      "$(cat "$GIT_CALL_LOG")"
assert_contains "fresh clone: clones to BRANA_DIR"        "$target"        "$(cat "$GIT_CALL_LOG")"
assert_contains "fresh clone: runs bootstrap"             "bootstrap called" "$out"

# ── Update path (BRANA_DIR already has .git) ──────────────────────────────

echo ""
echo "── Update path ───────────────────────────────────"

t="$WORKDIR/update"
bindir="$t/bin"
write_mock_git "$bindir"
cp "$INSTALL_SH" "$t/install.sh"
target="$t/brana_update"
mkdir -p "$target/.git"
write_mock_bootstrap "$target"

GIT_CALL_LOG="$t/git.log"; export GIT_CALL_LOG
touch "$GIT_CALL_LOG"
out=$(PATH="$bindir:$PATH" BRANA_DIR="$target" bash "$t/install.sh" 2>&1); rc=$?

assert_exit         "update exits 0"                   0   $rc
assert_contains     "update: reports updating"         "Updating existing"  "$out"
assert_contains     "update: git pull called"          "pull"               "$(cat "$GIT_CALL_LOG")"
assert_not_contains "update: no clone"                 "git clone"          "$(cat "$GIT_CALL_LOG")"
assert_contains     "update: runs bootstrap"           "bootstrap called"   "$out"

# ── Prerequisites ──────────────────────────────────────────────────────────

echo ""
echo "── Prerequisites ─────────────────────────────────"

t="$WORKDIR/prereqs"
mkdir -p "$t"
cp "$INSTALL_SH" "$t/install.sh"

# git missing → fatal: populate with minimal tools but not git
no_git_dir="$t/no_git_bin"
populate_bin "$no_git_dir"
out=$(PATH="$no_git_dir" bash "$t/install.sh" 2>&1); rc=$?
assert_exit     "missing git: exits non-zero"          1   $rc
assert_contains "missing git: error message"           "git not found" "$out"

# git present, jq absent → warn but continue
write_mock_git "$t/bin"
target_nojq="$t/brana_nojq"
mkdir -p "$target_nojq/.git"
write_mock_bootstrap "$target_nojq"
GIT_CALL_LOG="$t/git2.log"; export GIT_CALL_LOG
touch "$GIT_CALL_LOG"
out=$(PATH="$t/bin" BRANA_DIR="$target_nojq" bash "$t/install.sh" 2>&1); rc=$?
assert_exit     "missing jq: exits 0 (non-fatal)"     0   $rc
assert_contains "missing jq: warns about jq"          "jq not found"       "$out"
assert_contains "missing jq: still runs bootstrap"    "bootstrap called"   "$out"

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
