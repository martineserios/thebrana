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

echo "=== Scenario 6: auto-commit is a robust allowlist, not a blanket 'git add system/state/' ==="
# Root cause of the leak was the capability (publish whatever lands in system/state/),
# not the two file names. Two properties, both asserted on COMMIT COUNT (asserting on HEAD
# proved nothing: HEAD was the fixture's own init commit, which already held the file):
#   (a) a NEW unrelated file in system/state/ is never auto-committed;
#   (b) the allowlist still commits when some allowlisted files do not exist yet
#       (git add aborts the whole command on a missing pathspec — a fresh clone or a
#        partial state dir must not silently turn auto-commit into a no-op).
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
FIX="$TMP/fixrepo"
mkdir -p "$FIX/system/scripts" "$FIX/system/state"
cp "$SCRIPT" "$FIX/system/scripts/sync-state.sh"
git init -q "$FIX"
echo "readme" > "$FIX/README.md"                                  # init commit deliberately holds NO state file
git -C "$FIX" add -A && git -C "$FIX" commit -q -m init
echo '{"theme":"new"}' > "$H/.claude/tasks-config.json"          # only tasks-config.json + event-log exist in the cache
echo "SOMETHING-PRIVATE" > "$FIX/system/state/some-new-private-file.md"
# A concurrent session may have STAGED something unrelated: the path-limited commit must not sweep it in.
echo "staged-by-someone-else" > "$FIX/staged-elsewhere.txt"
git -C "$FIX" add staged-elsewhere.txt
BEFORE_N=$(git -C "$FIX" rev-list --count HEAD)
HOME="$H" BRANA_PRIVATE_REPO="$PRIV" bash "$FIX/system/scripts/sync-state.sh" push --auto-commit >"$TMP/out6" 2>&1
AFTER_N=$(git -C "$FIX" rev-list --count HEAD)
[ "$AFTER_N" -eq $((BEFORE_N + 1)) ] && ok "auto-commit created exactly one commit ($BEFORE_N -> $AFTER_N)" || bad "expected one new commit, got $BEFORE_N -> $AFTER_N (log: $(tail -2 "$TMP/out6" | tr '\n' ' '))"
git -C "$FIX" log -1 --format=%s 2>/dev/null | grep -q "sync: push operational state" && ok "the new commit is the auto-commit" || bad "HEAD is not the auto-commit (subject: $(git -C "$FIX" log -1 --format=%s))"
NEWFILES=$(git -C "$FIX" show --name-only --format= HEAD 2>/dev/null)
echo "$NEWFILES" | grep -q "^system/state/tasks-config.json$" && ok "allowlisted file is in the auto-commit" || bad "tasks-config.json missing from the auto-commit (got: $NEWFILES)"
echo "$NEWFILES" | grep -q "some-new-private-file" && bad "unrelated new file was auto-committed" || ok "unrelated new file was NOT auto-committed"
echo "$NEWFILES" | grep -q "staged-elsewhere" && bad "a file staged by another session was swept into the auto-commit" || ok "a file staged by another session was NOT swept in (path-limited commit)"
git -C "$FIX" diff --cached --name-only | grep -q "staged-elsewhere.txt" && ok "the other session's staged file is still staged" || bad "the other session's staged file was lost from the index"
git -C "$FIX" status --porcelain | grep -q "?? system/state/some-new-private-file.md" \
    && ok "unrelated file left untracked for a human to decide" \
    || bad "unrelated file state unexpected: $(git -C "$FIX" status --porcelain)"
grep -q "auto-committed" "$TMP/out6" && ok "log says auto-committed only because a commit happened" || bad "no auto-commit log line"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
