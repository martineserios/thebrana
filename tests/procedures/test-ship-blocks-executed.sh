#!/usr/bin/env bash
# /brana:ship's three glue blocks — Part A's tail (push → PR → checks → rerun → gate), the pre-flight
# 2b sweep and the Step 4 install/restore — used to be grep-pinned only; test-ship-hardening.sh ran
# just the SHIP-CHECKS helpers. This suite EXTRACTS each block from SKILL.md by its markers and
# EXECUTES it with stubbed gh/git/cargo/cp/brana/brana-mcp, under bash AND zsh (the harness shell;
# tests/procedures/test-close-gate-zsh-argv.sh pattern), and mutates each block once to prove the
# assertion that guards it can fire (t-3500).
# Run: bash tests/procedures/test-ship-blocks-executed.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$ROOT/system/skills/ship/SKILL.md"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
assert() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }
has() { case "$2" in *"$1"*) echo yes;; *) echo no;; esac; }
echo "=== test-ship-blocks-executed.sh ==="
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# extract <name> → $T/<name>.sh : marker-delimited, fences and list indentation stripped
extract() {
  awk -v b="<!-- $1 -->" -v e="<!-- /$1 -->" 'index($0,b){g=1;next} index($0,e){g=0} g' "$SKILL" \
    | sed -E '/^[[:space:]]*```/d; s/^   //' > "$T/$1.sh"
  [ -s "$T/$1.sh" ]
}
for blk in SHIP-CHECKS-BLOCK SHIP-TAIL-BLOCK SHIP-SWEEP-BLOCK MCP-ALIVE-BLOCK SHIP-INSTALL-BLOCK; do
  if extract "$blk"; then ok "$blk extracted"; else bad "$blk missing from SKILL.md"; fi
done
[ "$FAIL" -eq 0 ] || { echo; echo "=== Results: $PASS passed, $FAIL failed ==="; exit 1; }

# ── stubs ─────────────────────────────────────────────────────────────────────────────
mkdir -p "$T/bin" "$T/sc"
# gh: PR list/create/view, checks (shape from test-ship-hardening.sh), api annotations, rerun.
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
S="$GH_STUB_DIR"
case "$1 $2" in
  "pr list") cat "$S/pr_number" 2>/dev/null; exit 0 ;;
  "pr create") echo "https://github.com/o/r/pull/$(cat "$S/pr_number_after_create")"; cp "$S/pr_number_after_create" "$S/pr_number"; echo created >> "$S/events"; exit 0 ;;
  "pr view")
    if printf '%s ' "$@" | grep -q 'headRefOid'; then cat "$S/head_sha"; exit 0; fi
    cat "$S/pr_view"; exit 0 ;;
  "pr checks")
    shift 2; shift; REQ=0; [ "${1:-}" = "--required" ] && { shift; REQ=1; }
    if [ "${1:-}" = "--watch" ]; then
      if [ -f "$S/reruns" ] && [ -f "$S/green_after_rerun" ]; then exit 0; fi
      exit "$(cat "$S/watch_rc")"
    fi
    n=$(cat "$S/calls" 2>/dev/null || echo 0); echo $((n+1)) > "$S/calls"
    if [ -f "$S/reruns" ] && [ -f "$S/green_after_rerun" ]; then printf 'validate\tpass\t1m\thttps://github.com/o/r/actions/runs/2/job/9\n'; exit 0; fi
    if [ -s "$S/links" ]; then awk '{ printf "job%d\tfail\t1m\t%s\n", NR, $0 }' "$S/links"; exit 1; fi
    printf 'validate\tpass\t1m\thttps://github.com/o/r/actions/runs/1/job/9\n'; exit 0 ;;
  "api "*) jid=$(printf '%s' "$2" | sed -E 's#.*/check-runs/([0-9]+)/annotations.*#\1#')
    if grep -qx "$jid" "$S/infra_ids" 2>/dev/null; then echo "The job was not acquired by Runner of type hosted even after multiple attempts"; fi; exit 0 ;;
  "run rerun") echo "$3:$5" >> "$S/reruns"; exit 0 ;;
esac
exit 0
STUB
# git: push is stubbed (never touches a remote); everything else goes to the real git.
cat > "$T/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = push ]; then echo "push $*" >> "$GH_STUB_DIR/events"; exit "${GIT_PUSH_RC:-0}"; fi
exec /usr/bin/git "$@"
STUB
# cargo: "builds" scripts into target/release; brana-cli always, brana-mcp only when asked.
cat > "$T/bin/cargo" <<'STUB'
#!/usr/bin/env bash
[ -f "$GH_STUB_DIR/cargo_fail" ] && { echo "error: build failed" >&2; exit 101; }
mkdir -p target/release
cat > target/release/brana <<'B'
#!/usr/bin/env bash
case "$1" in
  --version) echo "brana 9.9.9-new" ;;
  --help) [ -f "$GH_STUB_DIR/new_help_broken" ] && exit 1; echo "usage" ;;
  backlog) echo "tasks: 42" ;;
esac
B
chmod +x target/release/brana
if printf '%s ' "$@" | grep -q 'brana-mcp'; then
  cat > target/release/brana-mcp <<'M'
#!/usr/bin/env bash
cat >/dev/null; [ -f "$GH_STUB_DIR/new_mcp_silent" ] && exit 0
printf '%s' '{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"brana-mcp","version":"9.9.9-new"}}}'
M
  chmod +x target/release/brana-mcp
fi
echo "cargo $*" >> "$GH_STUB_DIR/events"
STUB
# cp: fails on request for *.new destinations (the swap's staging copy), else real cp.
cat > "$T/bin/cp" <<'STUB'
#!/usr/bin/env bash
last="${@: -1}"
if [ -f "$GH_STUB_DIR/cp_new_fails" ]; then case "$last" in *.new) echo "cp: disk full" >&2; exit 1;; esac; fi
exec /bin/cp "$@"
STUB
chmod +x "$T/bin/"*
# installed binaries under a fake HOME: brana (old) and brana-mcp (old, answers initialize)
mk_home() {  # $1 = with_mcp (1|0)
  rm -rf "$T/home"; mkdir -p "$T/home/.local/bin"
  printf '#!/usr/bin/env bash\ncase "$1" in --version) echo "brana 1.0.0-old";; --help) echo usage;; backlog) cat "$GH_STUB_DIR/stats" 2>/dev/null || echo "tasks: 42";; esac\n' > "$T/home/.local/bin/brana"
  chmod +x "$T/home/.local/bin/brana"
  if [ "$1" = 1 ]; then
    printf '#!/usr/bin/env bash\ncat >/dev/null; printf %%s '"'"'{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"brana-mcp","version":"1.0.0-old"}}}'"'"'\n' > "$T/home/.local/bin/brana-mcp"
    chmod +x "$T/home/.local/bin/brana-mcp"
  fi
}
# a tiny real repo: main == dev, system/cli committed, a suite runner that honours a red-file
mk_repo() {
  rm -rf "$T/repo"; mkdir -p "$T/repo/system/cli/rust/src" "$T/repo/system/scripts" "$T/repo/tests/x"
  ( cd "$T/repo" && /usr/bin/git init -q -b main . && /usr/bin/git config user.email t@t && /usr/bin/git config user.name t
    echo 'fn main(){}' > system/cli/rust/src/main.rs
    printf '#!/usr/bin/env bash\nif [ -f "$GH_STUB_DIR/sweep_red" ]; then echo "Failed tests:"; echo "  - tests/x/red.sh"; exit 1; fi\necho "all green"\n' > system/scripts/run-test-suites.sh
    chmod +x system/scripts/run-test-suites.sh; echo 'exit 0' > tests/x/ok.sh
    /usr/bin/git add -A && /usr/bin/git commit -qm init && /usr/bin/git branch dev )
}
reset_sc() { rm -rf "$T/sc"; mkdir -p "$T/sc"; echo 7 > "$T/sc/pr_number"; echo 8 > "$T/sc/pr_number_after_create"; echo 0 > "$T/sc/watch_rc"; : > "$T/sc/links"; : > "$T/sc/infra_ids"; echo "deadbeef" > "$T/sc/head_sha"; }

# run_block <sh> <blockfile> [<prelude blocks...>] → stdout+stderr, rc in $RC; runs inside $T/repo
run_block() {
  local sh="$1" blk="$2"; shift 2; local pre=""
  for p in "$@"; do pre="$pre source '$T/$p.sh';"; done
  OUT="$( cd "$T/repo" && HOME="$T/home" GH_STUB_DIR="$T/sc" PATH="$T/bin:$PATH" "$sh" -c "$pre source '$T/$blk.sh'" 2>&1 )"; RC=$?
}

for sh in bash zsh; do
  if ! command -v "$sh" >/dev/null 2>&1; then echo "  SKIP: $sh not installed"; continue; fi
  echo "--- Shell: $sh"

  # ── Part A tail: push → PR → checks (rerun path) → gate ─────────────────────────────
  mk_repo; mk_home 1; reset_sc
  # ship_pr_matches_dev reads `gh pr view` for head sha + isCrossRepository; feed dev's sha
  DEVSHA=$(cd "$T/repo" && /usr/bin/git rev-parse dev); printf '%s false\n' "$DEVSHA" > "$T/sc/pr_view"; echo "$DEVSHA" > "$T/sc/head_sha"
  run_block "$sh" SHIP-TAIL-BLOCK SHIP-CHECKS-BLOCK
  assert "$sh tail: green CI → prints PR and SHA, rc 0" "0|yes" "$RC|$(has "PR=7 SHA=$DEVSHA" "$OUT")"
  assert "$sh tail: pushed dev before looking for the PR" yes "$(has 'push origin dev' "$(cat "$T/sc/events")")"
  reset_sc; printf '%s false\n' "$DEVSHA" > "$T/sc/pr_view"; echo "$DEVSHA" > "$T/sc/head_sha"; : > "$T/sc/pr_number"   # no open PR → create
  run_block "$sh" SHIP-TAIL-BLOCK SHIP-CHECKS-BLOCK
  assert "$sh tail: no open PR → gh pr create, then re-listed number 8" "0|yes|yes" "$RC|$(has created "$(cat "$T/sc/events")")|$(has 'PR=8' "$OUT")"
  reset_sc; printf '%s false\n' "$DEVSHA" > "$T/sc/pr_view"; echo "$DEVSHA" > "$T/sc/head_sha"
  echo 1 > "$T/sc/watch_rc"; printf 'https://github.com/o/r/actions/runs/900/job/111\n' > "$T/sc/links"; echo 111 > "$T/sc/infra_ids"; touch "$T/sc/green_after_rerun"
  run_block "$sh" SHIP-TAIL-BLOCK SHIP-CHECKS-BLOCK
  assert "$sh tail: runner-never-acquired → rerun that job, then a SECOND wait that goes green → rc 0" "0|900:111|yes" "$RC|$(cat "$T/sc/reruns" 2>/dev/null | tr -d '\n')|$(has 'PR=7' "$OUT")"
  reset_sc; printf '%s false\n' "$DEVSHA" > "$T/sc/pr_view"; echo "$DEVSHA" > "$T/sc/head_sha"
  echo 1 > "$T/sc/watch_rc"; printf 'https://github.com/o/r/actions/runs/900/job/111\n' > "$T/sc/links"   # real red, no infra ids
  run_block "$sh" SHIP-TAIL-BLOCK SHIP-CHECKS-BLOCK
  assert "$sh tail: real red → stop, do NOT merge, no rerun" "1|yes|no" "$RC|$(has 'do NOT merge' "$OUT")|$([ -f "$T/sc/reruns" ] && echo yes || echo no)"
  reset_sc; printf '%s false\n' "$DEVSHA" > "$T/sc/pr_view"; echo "$DEVSHA" > "$T/sc/head_sha"
  run_block "$sh" SHIP-TAIL-BLOCK SHIP-CHECKS-BLOCK; : # baseline for the mutation below
  # mutation: drop the gate line → a red CI must no longer stop the tail
  sed '/\[ "\$rc" -eq 0 \] ||/d' "$T/SHIP-TAIL-BLOCK.sh" > "$T/MUT-TAIL.sh"
  reset_sc; printf '%s false\n' "$DEVSHA" > "$T/sc/pr_view"; echo "$DEVSHA" > "$T/sc/head_sha"; echo 1 > "$T/sc/watch_rc"; printf 'https://github.com/o/r/actions/runs/900/job/111\n' > "$T/sc/links"
  run_block "$sh" MUT-TAIL SHIP-CHECKS-BLOCK
  assert "$sh tail mutation: without the gate line, red CI no longer stops (so the test above is live)" "0" "$RC"

  # ── 2b sweep: clone at dev, suites, ledger guard ────────────────────────────────────
  mk_repo; mk_home 1; reset_sc; echo "tasks: 42" > "$T/sc/stats"
  run_block "$sh" SHIP-SWEEP-BLOCK
  assert "$sh sweep: green suites → 'sweep rc=0', no ledger WARN" "0|yes|no" "$RC|$(has 'sweep rc=0' "$OUT")|$(has 'ledger stats changed' "$OUT")"
  assert "$sh sweep: took a runnable brana.bak before the build" yes "$([ -x "$T/home/.local/bin/brana.bak" ] && echo yes || echo no)"
  touch "$T/sc/sweep_red"; run_block "$sh" SHIP-SWEEP-BLOCK; rm -f "$T/sc/sweep_red"
  assert "$sh sweep: red suite → 'sweep rc=1' and the failed suite is listed" "yes|yes" "$(has 'sweep rc=1' "$OUT")|$(has 'tests/x/red.sh' "$OUT")"
  # ledger-count warn: brana's stats change between the before/after hashes
  printf '#!/usr/bin/env bash\nn=$(cat "$GH_STUB_DIR/n" 2>/dev/null || echo 0); echo $((n+1)) > "$GH_STUB_DIR/n"; case "$1" in --version) echo old;; backlog) echo "tasks: $((42+n))";; esac\n' > "$T/home/.local/bin/brana"; chmod +x "$T/home/.local/bin/brana"
  run_block "$sh" SHIP-SWEEP-BLOCK
  assert "$sh sweep: ledger stats differ after the sweep → WARN" yes "$(has 'ledger stats changed' "$OUT")"
  sed '/LEDGER_BEFORE" = /d' "$T/SHIP-SWEEP-BLOCK.sh" > "$T/MUT-SWEEP.sh"; rm -f "$T/sc/n"
  run_block "$sh" MUT-SWEEP
  assert "$sh sweep mutation: without the compare line the WARN disappears (so the test above is live)" no "$(has 'ledger stats changed' "$OUT")"

  # ── Step 4 install: both binaries, verify-before-swap, restore both, cp failure, no mcp ──
  mk_repo; mk_home 1; reset_sc
  run_block "$sh" SHIP-INSTALL-BLOCK MCP-ALIVE-BLOCK
  assert "$sh install: happy path installs both and says to restart sessions" "0|yes" "$RC|$(has 'installed: brana + brana-mcp' "$OUT")"
  assert "$sh install: installed brana is the new build" yes "$(has '9.9.9-new' "$("$T/home/.local/bin/brana" --version)")"
  assert "$sh install: backups of both previous binaries exist" "yes|yes" "$([ -f "$T/home/.local/bin/brana.bak" ] && echo yes || echo no)|$([ -f "$T/home/.local/bin/brana-mcp.bak" ] && echo yes || echo no)"
  mk_home 1; reset_sc; touch "$T/sc/new_help_broken"
  run_block "$sh" SHIP-INSTALL-BLOCK MCP-ALIVE-BLOCK
  assert "$sh install: failed verify → restored BOTH previous binaries, rc 1" "1|yes|yes|yes" "$RC|$(has 'restored: brana brana-mcp' "$OUT")|$(has '1.0.0-old' "$("$T/home/.local/bin/brana" --version)")|$(has '1.0.0-old' "$(printf '' | "$T/home/.local/bin/brana-mcp")")"
  rm -f "$T/sc/new_help_broken"; mk_home 1; reset_sc; touch "$T/sc/new_mcp_silent"
  run_block "$sh" SHIP-INSTALL-BLOCK MCP-ALIVE-BLOCK
  assert "$sh install: new brana-mcp silent → nothing replaced (verify-before-swap)" "1|yes|yes" "$RC|$(has 'nothing replaced' "$OUT")|$(has '1.0.0-old' "$("$T/home/.local/bin/brana" --version)")"
  rm -f "$T/sc/new_mcp_silent"; mk_home 1; reset_sc; touch "$T/sc/cp_new_fails"
  run_block "$sh" SHIP-INSTALL-BLOCK MCP-ALIVE-BLOCK
  assert "$sh install: cp of the staging copy fails → previous binaries kept, rc 1" "1|yes|yes" "$RC|$(has 'previous binaries kept' "$OUT")|$(has '1.0.0-old' "$("$T/home/.local/bin/brana" --version)")"
  rm -f "$T/sc/cp_new_fails"; mk_home 0; reset_sc
  run_block "$sh" SHIP-INSTALL-BLOCK MCP-ALIVE-BLOCK
  assert "$sh install: no brana-mcp on the machine → brana-cli alone, nothing stops" "0|yes|no" "$RC|$(has 'no brana-mcp on this machine' "$OUT")|$(has 'brana-mcp' "$(grep cargo "$T/sc/events" | tail -1)")"
  mk_home 1; reset_sc
  run_block "$sh" SHIP-INSTALL-BLOCK   # probe fence NOT sourced
  assert "$sh install: without mcp_alive in the same call it stops before building" "1|yes|no" "$RC|$(has 'same Bash call' "$OUT")|$(has cargo "$(cat "$T/sc/events" 2>/dev/null)")"
  sed '/mv -f "\$BIN.bak" "\$BIN" && R="brana"/d' "$T/SHIP-INSTALL-BLOCK.sh" > "$T/MUT-INSTALL.sh"
  mk_home 1; reset_sc; touch "$T/sc/new_help_broken"
  run_block "$sh" MUT-INSTALL MCP-ALIVE-BLOCK; rm -f "$T/sc/new_help_broken"
  assert "$sh install mutation: without the brana restore line the old brana is NOT back (so the test above is live)" no "$(has '1.0.0-old' "$("$T/home/.local/bin/brana" --version)")"
done

echo; echo "=== Results: $PASS passed, $FAIL failed ==="; [ "$FAIL" -eq 0 ]
