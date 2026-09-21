#!/usr/bin/env bash
# t-3352: portfolio.md and tasks-portfolio.json hold private client/venture data
# (fees, sheet ids, a GCP project id, client names). thebrana is a PUBLIC repo, and
# sync-state.sh push --auto-commit used to publish both into system/state/ and commit
# them. They must never land in the public STATE_DIR. tasks-portfolio.json travels to
# the PRIVATE brana-knowledge repo instead (its daily job runs `git add -A`);
# portfolio.md is already backed up there by brana-knowledge/backup.sh.
#
# Fully sandboxed: temp HOME, BRANA_STATE_DIR and BRANA_PRIVATE_REPO. Never touches
# the real ~/.claude (the trap behind t-3351).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/system/scripts/sync-state.sh"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

H="$TMP/home"
STATE="$TMP/state"
PRIV="$TMP/private-repo"
mkdir -p "$H/.claude/memory" "$H/.claude/scheduler" "$STATE"
git init -q "$PRIV"

echo "PRIVATE-PORTFOLIO-MARKER" > "$H/.claude/memory/portfolio.md"
echo '{"clients":[],"marker":"PRIVATE-TASKS-PORTFOLIO-MARKER"}' > "$H/.claude/tasks-portfolio.json"
echo '{"theme":"emoji"}' > "$H/.claude/tasks-config.json"
echo "event-log-marker" > "$H/.claude/memory/event-log.md"

run() { # run <private-repo> <subcommand>
    HOME="$H" BRANA_STATE_DIR="$STATE" BRANA_PRIVATE_REPO="$1" bash "$SCRIPT" "$2" >"$TMP/out" 2>&1
}

echo "=== Scenario 1: push keeps private files out of the public STATE_DIR ==="
run "$PRIV" push
[ ! -e "$STATE/portfolio.md" ] && ok "portfolio.md not written to public STATE_DIR" || bad "portfolio.md leaked into public STATE_DIR"
[ ! -e "$STATE/tasks-portfolio.json" ] && ok "tasks-portfolio.json not written to public STATE_DIR" || bad "tasks-portfolio.json leaked into public STATE_DIR"
[ -e "$STATE/tasks-config.json" ] && ok "public files still sync (tasks-config.json)" || bad "regression: tasks-config.json no longer synced"

echo "=== Scenario 2: tasks-portfolio.json goes to the private repo ==="
if grep -q "PRIVATE-TASKS-PORTFOLIO-MARKER" "$PRIV/backup/state/tasks-portfolio.json" 2>/dev/null; then
    ok "tasks-portfolio.json pushed to private repo backup/state/"
else
    bad "tasks-portfolio.json not found in private repo backup/state/"
fi

echo "=== Scenario 3: no private repo -> skip, never fall back to public dir ==="
rm -rf "$STATE"; mkdir -p "$STATE"
run "$TMP/does-not-exist" push
rc=$?
[ "$rc" -eq 0 ] && ok "push exits 0 when the private repo is absent" || bad "push failed (rc=$rc) when private repo absent"
[ ! -e "$STATE/tasks-portfolio.json" ] && [ ! -e "$STATE/portfolio.md" ] && ok "no fallback into public STATE_DIR" || bad "fell back to public STATE_DIR"
grep -qi "private" "$TMP/out" && ok "skip is logged" || bad "skip not logged"

echo "=== Scenario 4: pull restores tasks-portfolio.json from the private repo ==="
rm -f "$H/.claude/tasks-portfolio.json"
# The public dir must be empty here, or a leaked public copy would satisfy the
# restore and this scenario would pass without the private repo ever being read.
rm -f "$STATE/tasks-portfolio.json" "$STATE/portfolio.md"
run "$PRIV" pull
if grep -q "PRIVATE-TASKS-PORTFOLIO-MARKER" "$H/.claude/tasks-portfolio.json" 2>/dev/null; then
    ok "cache restored from private repo"
else
    bad "cache not restored from private repo"
fi

echo "=== Scenario 5: the repo itself no longer tracks or fails to ignore them ==="
TRACKED=$(git -C "$ROOT" ls-files system/state/portfolio.md system/state/tasks-portfolio.json)
[ -z "$TRACKED" ] && ok "neither file is tracked" || bad "still tracked: $(echo $TRACKED)"
for f in system/state/portfolio.md system/state/tasks-portfolio.json; do
    git -C "$ROOT" check-ignore -q "$f" && ok "$f is gitignored" || bad "$f is not gitignored"
done

echo "=== Scenario 6: auto-commit is an allowlist, not a blanket 'git add system/state/' ==="
# Root cause of the leak was the capability (publish whatever lands in system/state/),
# not the two file names. A NEW, unrelated file there must never be auto-committed.
FIX="$TMP/fixrepo"
mkdir -p "$FIX/system/scripts" "$FIX/system/state"
cp "$SCRIPT" "$FIX/system/scripts/sync-state.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q "$FIX"
echo '{"theme":"old"}' > "$FIX/system/state/tasks-config.json"
git -C "$FIX" add -A && git -C "$FIX" commit -q -m init
echo '{"theme":"new"}' > "$H/.claude/tasks-config.json"
echo "SOMETHING-PRIVATE" > "$FIX/system/state/some-new-private-file.md"
HOME="$H" BRANA_PRIVATE_REPO="$PRIV" bash "$FIX/system/scripts/sync-state.sh" push --auto-commit >"$TMP/out6" 2>&1
COMMITTED=$(git -C "$FIX" show --name-only --format= HEAD 2>/dev/null)
echo "$COMMITTED" | grep -q "system/state/tasks-config.json" && ok "allowlisted public file is auto-committed" || bad "tasks-config.json not auto-committed (got: $COMMITTED)"
git -C "$FIX" ls-files --error-unmatch system/state/some-new-private-file.md >/dev/null 2>&1 \
    && bad "unrelated new file in system/state/ was auto-committed" \
    || ok "unrelated new file in system/state/ was NOT auto-committed"
git -C "$FIX" status --porcelain | grep -q "?? system/state/some-new-private-file.md" \
    && ok "unrelated file left untracked for a human to decide" \
    || bad "unrelated file state unexpected: $(git -C "$FIX" status --porcelain)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
