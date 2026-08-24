#!/usr/bin/env bash
# Tests for system/scripts/readme-coverage.sh (t-3031).
# 1. Fixture: detects a missing ADR row and a dead link, exits 1.
# 2. Fixture: clean README exits 0.
# 3. Fixture: same-basename files in different feature dirs are NOT conflated
#    (t-3031 challenger finding — basename-only matching hid 12 real gaps).
# 4. Fixture: an anchored dead link (foo.md#section) is still caught.
# 5. Fixture: an absolute-path link is never flagged as dead.
# 6. Live repo: docs/README.md must be complete (the AC itself).
set -u
ROOT=$(git rev-parse --show-toplevel); S=$ROOT/system/scripts/readme-coverage.sh
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  PASS: $1"; }; bad(){ fail=$((fail+1)); echo "  FAIL: $1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/docs/architecture/decisions" "$T/docs/architecture/features"; (cd "$T" && git init -q)
echo '# ADR-001: x' > "$T/docs/architecture/decisions/ADR-001-x.md"
echo '# ADR-002: y' > "$T/docs/architecture/decisions/ADR-002-y.md"
echo '# f' > "$T/docs/architecture/features/f.md"
cat > "$T/docs/README.md" <<'R'
| [ADR-001](architecture/decisions/ADR-001-x.md) | x |
| [f.md](architecture/features/f.md) | f |
| [gone.md](architecture/gone.md) | dead |
R
out=$(cd "$T" && bash "$S"); rc=$?
echo "$out" | grep -q 'MISSING architecture/decisions/ADR-002-y.md' && echo "$out" | grep -q 'DEAD architecture/gone.md' && [ $rc -eq 1 ] && ok "fixture: reports missing ADR + dead link, exit 1" || bad "fixture gap detection (rc=$rc): $out"
echo '| [ADR-002](architecture/decisions/ADR-002-y.md) | y |' >> "$T/docs/README.md"; sed -i '/gone.md/d' "$T/docs/README.md"
(cd "$T" && bash "$S" --quiet) && ok "fixture: clean README exits 0" || bad "fixture clean README should exit 0"

# Basename collision: two files named same-thing.md in different feature dirs.
T2=$(mktemp -d); trap 'rm -rf "$T" "$T2"' EXIT
mkdir -p "$T2/docs/architecture/decisions" "$T2/docs/architecture/features" "$T2/docs/guide/features"; (cd "$T2" && git init -q)
echo '# real' > "$T2/docs/architecture/features/same-thing.md"
echo '# howto' > "$T2/docs/guide/features/same-thing.md"
cat > "$T2/docs/README.md" <<'R'
| [same-thing.md](guide/features/same-thing.md) | how-to |
R
out=$(cd "$T2" && bash "$S"); rc=$?
echo "$out" | grep -q 'MISSING architecture/features/same-thing.md' && [ $rc -eq 1 ] && ok "fixture: same-basename-different-dir is NOT conflated (regression for the basename-only bug)" || bad "collision fixture: expected MISSING architecture/features/same-thing.md, got: $out"
echo '| [same-thing.md](architecture/features/same-thing.md) | real |' >> "$T2/docs/README.md"
(cd "$T2" && bash "$S" --quiet) && ok "fixture: both same-basename files covered → exit 0" || bad "collision fixture should be clean once both rows exist"

# Anchored dead link and absolute-path link.
T3=$(mktemp -d); trap 'rm -rf "$T" "$T2" "$T3"' EXIT
mkdir -p "$T3/docs/architecture/decisions" "$T3/docs/architecture/features"; (cd "$T3" && git init -q)
cat > "$T3/docs/README.md" <<'R'
| [gone.md](architecture/gone.md#section) | dead with anchor |
| [abs.md](/docs/architecture/abs.md) | absolute path |
R
out=$(cd "$T3" && bash "$S")
echo "$out" | grep -q 'DEAD architecture/gone.md' && ok "fixture: anchored dead link still caught" || bad "anchored dead link not caught: $out"
echo "$out" | grep -q 'DEAD.*abs.md' && bad "absolute-path link false-flagged as dead: $out" || ok "fixture: absolute-path link never flagged as dead"

out=$(cd "$ROOT" && bash "$S"); rc=$?
[ $rc -eq 0 ] && ok "live docs/README.md is complete" || bad "live README has gaps:\n$out"
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
