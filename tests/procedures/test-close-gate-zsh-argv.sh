#!/usr/bin/env bash
# Regression test: the close gate's Step 1b snippet must pass --git-range as TWO
# argv entries under zsh as well as bash (t-2478).
#
# Bug (live, thebrana 2026-07-27): the snippet used
#     ${SESSION_RANGE:+--git-range "$SESSION_RANGE"}
# zsh does NOT word-split unquoted parameter expansions, so close-snapshot.sh
# received the single argument '--git-range 4199f469..6d206522' and exited with
# "unknown argument". close-snapshot.sh itself is correct — the bug is purely the
# caller's shell assumption. Impact: on zsh every close silently lost the t-2242
# explicit-range fix and fell back to the known-wrong HEAD~N..HEAD derivation.
#
# Same class as pattern_zsh-for-loop-no-word-split. The phase file's own Step 11c
# already works around this; Step 1b did not.
#
# The snippet is EXTRACTED from system/skills/close/phases/gate-and-evidence.md so
# the test exercises the shipped procedure text, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-close-gate-zsh-argv.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_pass() { TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; PASS=$((PASS + 1)); }
assert_fail() { TOTAL=$((TOTAL + 1)); echo "  FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

echo "=== test-close-gate-zsh-argv.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE_MD="$REPO_ROOT/system/skills/close/phases/gate-and-evidence.md"

[ -f "$PHASE_MD" ] || { echo "ERROR: $PHASE_MD not found"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# ── Extract the ```bash block that invokes close-snapshot.sh ─────────────────
awk '
  /^```bash$/ { inb=1; n++; buf=""; next }
  /^```$/     { if (inb && buf ~ /close-snapshot\.sh/) { printf "%s", buf; exit } inb=0; next }
  inb         { buf = buf $0 "\n" }
' "$PHASE_MD" > "$TMPROOT/step1b.sh"

if ! grep -q 'close-snapshot.sh' "$TMPROOT/step1b.sh"; then
    echo "ERROR: could not extract the Step 1b snippet from $PHASE_MD"
    exit 1
fi
echo "Extracted Step 1b snippet ($(wc -l < "$TMPROOT/step1b.sh") lines)"
echo ""

# ── Stub $HOME/.claude/scripts/close-snapshot.sh — records argv one per line ──
FAKE_HOME="$TMPROOT/home"
mkdir -p "$FAKE_HOME/.claude/scripts"
cat > "$FAKE_HOME/.claude/scripts/close-snapshot.sh" <<'STUB'
#!/usr/bin/env bash
: > "$ARGV_LOG"
for a in "$@"; do printf '%s\n' "$a" >> "$ARGV_LOG"; done
exit 0
STUB
chmod +x "$FAKE_HOME/.claude/scripts/close-snapshot.sh"

# ── Fixture repo: one backdated commit + three recent ones ───────────────────
# The backdated commit falls OUTSIDE the "6 hours ago" window, so the oldest
# in-window commit has a parent and SESSION_RANGE is non-empty (the branch that
# actually exercises the bug).
FIX="$TMPROOT/repo"
mkdir -p "$FIX"
git -C "$FIX" init -q
git -C "$FIX" config user.email t@t.t
git -C "$FIX" config user.name t
OLD_DATE="$(date -d '3 days ago' --iso-8601=seconds 2>/dev/null || echo '2026-01-01T00:00:00')"
echo base > "$FIX/f.txt"; git -C "$FIX" add -A
GIT_AUTHOR_DATE="$OLD_DATE" GIT_COMMITTER_DATE="$OLD_DATE" git -C "$FIX" commit -qm base
for i in 1 2 3; do
    echo "c$i" >> "$FIX/f.txt"; git -C "$FIX" add -A; git -C "$FIX" commit -qm "c$i"
done

run_snippet() {
    local shell_bin="$1" log="$2"
    ( cd "$FIX" && HOME="$FAKE_HOME" ARGV_LOG="$log" COMMIT_COUNT=3 \
        "$shell_bin" "$TMPROOT/step1b.sh" >/dev/null 2>&1 )
}

check_argv() {
    local shell_name="$1" log="$2"
    if [ ! -s "$log" ]; then
        assert_fail "$shell_name: close-snapshot.sh invoked" "argv log empty — snippet never reached the script"
        return
    fi
    # --git-range and its value must be SEPARATE argv entries.
    if grep -qx -- '--git-range' "$log"; then
        assert_pass "$shell_name: --git-range is its own argv entry"
    else
        if grep -q -- '--git-range ' "$log"; then
            assert_fail "$shell_name: --git-range is its own argv entry" \
                "got the glued form [$(grep -- '--git-range ' "$log" | head -1)]"
        else
            assert_fail "$shell_name: --git-range is its own argv entry" "flag absent entirely"
        fi
        return
    fi
    local val
    val="$(grep -A1 -x -- '--git-range' "$log" | tail -1)"
    if printf '%s' "$val" | grep -qE '^[0-9a-f]+\.\.[0-9a-f]+$'; then
        assert_pass "$shell_name: range value [$val] passed as a separate entry"
    else
        assert_fail "$shell_name: range value passed as a separate entry" "got [$val]"
    fi
}

for sh in bash zsh; do
    echo "Shell: $sh"
    if ! command -v "$sh" >/dev/null 2>&1; then
        echo "  SKIP: $sh not installed"
        echo ""
        continue
    fi
    LOG="$TMPROOT/argv-$sh.txt"
    : > "$LOG"
    run_snippet "$(command -v "$sh")" "$LOG"
    check_argv "$sh" "$LOG"
    echo ""
done

echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
