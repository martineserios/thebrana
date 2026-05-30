#!/usr/bin/env bash
# Tests for validate.sh Check 30 — brana CLI cd GIT_ROOT wrapper (t-1439).
#
# Directly tests the grep logic used by Check 30 rather than running the full
# validate.sh (which requires a complete fixture due to set -euo pipefail).
#
# Rule: every "$BRANA*" subcommand call in system/hooks/*.sh must be inside
# (cd "${GIT_ROOT:-...}" && ...) or on a line with `cd` before the call.

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Reproduce the exact grep logic from Check 30
check30() {
    local hook_dir="$1"
    {
        /usr/bin/grep -rn '"$BRANA[^"]*" [a-z]' "$hook_dir"/*.sh 2>/dev/null
        /usr/bin/grep -rn '^\s*brana [a-z]' "$hook_dir"/*.sh 2>/dev/null
    } | /usr/bin/grep -v '/lib/\|/tests/' \
      | /usr/bin/grep -v ':[[:space:]]*#' \
      | /usr/bin/grep -v 'cd ["\$]' \
    || true
}

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no violations, got:"
        echo "$result" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

assert_nonempty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -n "$result" ]; then
        echo "  PASS: $desc (detected: $(echo "$result" | wc -l | tr -d ' ') violation(s))"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected violations but found none"
        FAIL=$((FAIL + 1))
    fi
}

setup() {
    rm -rf "$TMPROOT/hooks"
    mkdir -p "$TMPROOT/hooks"
}

echo "=== Check 30: brana CLI cd GIT_ROOT wrapper ==="
echo ""

# ── Test 1: Empty hooks dir → no violations ────────────────────────────────
echo "Test 1: empty hooks directory"
setup
result=$(check30 "$TMPROOT/hooks")
assert_empty "empty dir — no violations" "$result"

# ── Test 2: Bare variable call → violation ─────────────────────────────────
echo "Test 2: bare \$BRANA subcommand (no cd wrapper)"
setup
cat > "$TMPROOT/hooks/bad.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
BRANA=""
TASKS=$("$BRANA" backlog query --status in_progress 2>/dev/null) || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_nonempty "bare \$BRANA call detected" "$result"

# ── Test 3: BRANA_BIN variant → violation ──────────────────────────────────
echo "Test 3: bare \$BRANA_BIN subcommand"
setup
cat > "$TMPROOT/hooks/bad2.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
BRANA_BIN=""
TOP=$("$BRANA_BIN" skills usage --json 2>/dev/null) || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_nonempty "bare \$BRANA_BIN call detected" "$result"

# ── Test 4: BRANA_CLI variant → violation ──────────────────────────────────
echo "Test 4: bare \$BRANA_CLI subcommand"
setup
cat > "$TMPROOT/hooks/bad3.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
BRANA_CLI=""
"$BRANA_CLI" decisions log "x" "action" "msg" 2>/dev/null || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_nonempty "bare \$BRANA_CLI call detected" "$result"

# ── Test 5: Bare brana at line start → violation ───────────────────────────
echo "Test 5: bare \`brana\` command at line start"
setup
cat > "$TMPROOT/hooks/bare.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
GIT_ROOT="/some/root"
    brana graph build --output /tmp/out.json 2>/dev/null || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_nonempty "bare brana at line start detected" "$result"

# ── Test 6: Inline cd wrapper → no violation ──────────────────────────────
echo "Test 6: call wrapped with inline (cd GIT_ROOT && ...)"
setup
cat > "$TMPROOT/hooks/good.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
BRANA=""
GIT_ROOT="/some/root"
TASKS=$(cd "$GIT_ROOT" && "$BRANA" backlog query --status in_progress 2>/dev/null) || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_empty "wrapped call passes" "$result"

# ── Test 7: Subshell cd wrapper → no violation ────────────────────────────
echo "Test 7: call wrapped with (cd ... && \$BRANA_CLI ...)"
setup
cat > "$TMPROOT/hooks/good2.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
BRANA_CLI=""
GIT_ROOT="/some/root"
(cd "${GIT_ROOT:-/tmp}" && "$BRANA_CLI" decisions log "x" "action" "msg" 2>/dev/null || true)
EOF
result=$(check30 "$TMPROOT/hooks")
assert_empty "subshell cd wrapper passes" "$result"

# ── Test 8: Comment line → not flagged ────────────────────────────────────
echo "Test 8: brana call in comment not flagged"
setup
cat > "$TMPROOT/hooks/comment.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
# TASKS=$("$BRANA" backlog query 2>/dev/null) || true
echo '{"continue": true}'
EOF
result=$(check30 "$TMPROOT/hooks")
assert_empty "comment line not flagged" "$result"

# ── Test 9: lib/ excluded ─────────────────────────────────────────────────
echo "Test 9: brana call in lib/ not flagged"
setup
mkdir -p "$TMPROOT/hooks/lib"
cat > "$TMPROOT/hooks/lib/resolve.sh" << 'EOF'
#!/usr/bin/env bash
BRANA=$("$BRANA" --version 2>/dev/null) || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_empty "lib/ directory excluded" "$result"

# ── Test 10: Mixed — one good, one bad → violation found ──────────────────
echo "Test 10: mixed hook — one wrapped + one bare call"
setup
cat > "$TMPROOT/hooks/mixed.sh" << 'EOF'
#!/usr/bin/env bash
cd /tmp 2>/dev/null || true
BRANA=""
GIT_ROOT="/some/root"
GOOD=$(cd "$GIT_ROOT" && "$BRANA" backlog get t-1 2>/dev/null) || true
BAD=$("$BRANA" backlog rollup 2>/dev/null) || true
EOF
result=$(check30 "$TMPROOT/hooks")
assert_nonempty "bare call in mixed hook detected" "$result"

# ── Test 11: String literal with bare `brana` (no $ prefix) → violation ──────
echo "Test 11: WARNING string with bare \`brana <cmd>\` (no \$ prefix) → flagged"
setup
cat > "$TMPROOT/hooks/warning-bare.sh" << 'EOF'
#!/usr/bin/env bash
# Reproduces memory-write-gate.sh false-positive incident (t-1439).
# A WARNING heredoc with bare `brana memory write` inside a multi-line string.
WARNING="Route through the CLI:

  brana memory write \\
    --type feedback \\
    --slug my-slug"
echo "$WARNING" >&2
echo '{"continue": false}'
EOF
result=$(check30 "$TMPROOT/hooks")
assert_nonempty "bare brana in string literal detected (no \$ prefix)" "$result"

# ── Test 12: String literal with `$ brana` prefix → no violation ─────────────
echo "Test 12: WARNING string with \`\$ brana <cmd>\` (\$ prefix) → not flagged"
setup
cat > "$TMPROOT/hooks/warning-dollar.sh" << 'EOF'
#!/usr/bin/env bash
# Fix convention: prefix with $ so Check 30 grep does not match.
WARNING="Route through the CLI:

  $ brana memory write \\
    --type feedback \\
    --slug my-slug"
echo "$WARNING" >&2
echo '{"continue": false}'
EOF
result=$(check30 "$TMPROOT/hooks")
assert_empty "\$ brana prefix passes — no false positive" "$result"

echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
