//! End-to-end smoke tests for `brana time` (t-2921/t-2922, ADR-083).
//!
//! Same fixture shape as `receipt_smoke.rs`: throwaway git repos in tempdirs, every git
//! and `brana` invocation runs with the git-env denylist scrubbed
//! (`pattern_git-hook-env-leaks-into-executed-tests`).
//!
//! t-2921 (this file): tests only, against a `todo!()`-stubbed `brana time` — every test
//! here is expected to fail red until t-2922 implements the real logic.

use assert_cmd::Command;
use std::path::{Path, PathBuf};

const GIT_ENV: [&str; 6] = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_COMMON_DIR",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
];

fn git(dir: &Path, args: &[&str]) -> std::process::Output {
    let mut c = std::process::Command::new("git");
    c.current_dir(dir).args(args);
    for k in GIT_ENV {
        c.env_remove(k);
    }
    c.output().expect("git runs")
}

fn git_ok(dir: &Path, args: &[&str]) -> String {
    let out = git(dir, args);
    assert!(
        out.status.success(),
        "git {args:?} failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn brana(dir: &Path) -> Command {
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(dir);
    for k in GIT_ENV {
        cmd.env_remove(k);
    }
    cmd
}

/// A bare-bones repo on `dev` with one commit — no tasks.json/AC needed for these tests.
fn repo() -> tempfile::TempDir {
    let tmp = tempfile::TempDir::new().unwrap();
    let p = tmp.path();
    git_ok(p, &["init", "-q", "-b", "dev"]);
    git_ok(p, &["config", "user.email", "t@t"]);
    git_ok(p, &["config", "user.name", "t"]);
    git_ok(p, &["config", "commit.gpgsign", "false"]);
    std::fs::write(p.join("seed.txt"), "seed\n").unwrap();
    git_ok(p, &["add", "-A"]);
    git_ok(p, &["commit", "-q", "-m", "base"]);
    tmp
}

/// Add a second worktree off `base`'s `dev` branch — a genuinely separate `--git-dir`
/// from `base`'s own, sharing the same `--git-common-dir`. Returns the worktree path.
fn add_worktree(base: &Path, name: &str, branch: &str) -> PathBuf {
    let wt_path = base.parent().unwrap().join(name);
    git_ok(base, &[
        "worktree", "add", wt_path.to_str().unwrap(), "-b", branch,
    ]);
    wt_path
}

fn data_store_path(repo_root: &Path, task_id: &str) -> PathBuf {
    repo_root.join(".git/brana/time").join(format!("{task_id}.jsonl"))
}

// ---- Group A: serialized-bracket rejection, scoped per-worktree -----------------

#[test]
fn a1_second_start_in_same_worktree_is_rejected() {
    let tmp = repo();
    // First start should succeed (once implemented) and open the bracket.
    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();
    // A second start for a DIFFERENT task_id in the SAME worktree, while the first
    // bracket is still open, must be rejected — one open bracket per worktree.
    brana(tmp.path())
        .args(["time", "start", "t-2"])
        .assert()
        .failure();
}

/// Rung-2 concurrency-lock finder catch (2026-08-17): `a1` above is sequential — the
/// first call fully completes before the second is even constructed, so it cannot
/// distinguish a real TOCTOU-safe lock from a naive unlocked check-then-write. This
/// test fires two `time start` calls at the SAME worktree with no serialization
/// between them (a `Barrier` holds both threads until both are ready to launch their
/// subprocess), asserting exactly one succeeds — the actual invariant the per-worktree
/// lock exists to protect.
#[test]
fn a4_concurrent_starts_in_same_worktree_exactly_one_succeeds() {
    let tmp = repo();
    let root = tmp.path().to_path_buf();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));

    let handles: Vec<_> = ["t-race-a", "t-race-b"]
        .iter()
        .map(|task_id| {
            let root = root.clone();
            let barrier = barrier.clone();
            let task_id = task_id.to_string();
            std::thread::spawn(move || {
                barrier.wait();
                brana(&root).args(["time", "start", &task_id]).ok().is_ok()
            })
        })
        .collect();
    let successes: usize = handles.into_iter().map(|h| h.join().unwrap()).filter(|ok| *ok).count();
    assert_eq!(
        successes, 1,
        "expected exactly one concurrent `time start` to win the same-worktree lock"
    );
}

#[test]
fn a2_start_after_close_succeeds() {
    let tmp = repo();
    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();
    brana(tmp.path()).args(["time", "close", "t-1"]).assert().success();
    // Bracket closed -> a new start (even for a different task_id) must succeed.
    brana(tmp.path()).args(["time", "start", "t-2"]).assert().success();
}

#[test]
fn a3_different_worktrees_different_task_ids_both_succeed_independently() {
    let tmp = repo();
    let wt = add_worktree(tmp.path(), "wt2", "feat/other");
    // Two different worktrees, two different task_ids, concurrently — must not block
    // each other. This is the redesign's whole point: --git-dir is worktree-unique.
    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();
    brana(&wt).args(["time", "start", "t-2"]).assert().success();
}

// ---- Group B: atomic concurrent-write stress test (queue.rs-shaped) -------------

#[test]
fn b1_concurrent_writers_distinct_task_ids_no_corruption() {
    let tmp = repo();
    let root = tmp.path().to_path_buf();
    let n = 6;
    // Pre-create all N worktrees SEQUENTIALLY first, outside the timed region — `git
    // worktree add`'s own internal repo-state locking (rung-2 concurrency-lock finder,
    // 2026-08-17) otherwise staggers thread start times enough to reduce genuine
    // overlap at the shared brana/time/ writes, weakening this test's evidentiary
    // value. A Barrier then holds all N threads until every worktree exists and every
    // thread is ready, so the actual start+close calls fire as close to simultaneously
    // as possible — that's the thing under test, not worktree setup.
    let worktrees: Vec<PathBuf> = (0..n)
        .map(|i| add_worktree(&root, &format!("wt-b{i}"), &format!("feat/b{i}")))
        .collect();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(n));
    let handles: Vec<_> = worktrees
        .into_iter()
        .enumerate()
        .map(|(i, wt)| {
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                let task_id = format!("t-b{i}");
                barrier.wait();
                brana(&wt).args(["time", "start", &task_id]).assert().success();
                brana(&wt).args(["time", "close", &task_id]).assert().success();
                task_id
            })
        })
        .collect();
    let task_ids: Vec<String> = handles.into_iter().map(|h| h.join().unwrap()).collect();

    // Every task_id's data file must exist, contain exactly one well-formed Start and
    // one well-formed Close line, with no interleaved/corrupted bytes from another
    // writer's concurrent append.
    for task_id in &task_ids {
        let path = data_store_path(&root, task_id);
        let content = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("missing data file for {task_id}: {e}"));
        let lines: Vec<&str> = content.lines().filter(|l| !l.trim().is_empty()).collect();
        assert_eq!(lines.len(), 2, "{task_id}: expected exactly 2 lines, got {lines:?}");
        for line in &lines {
            let _: serde_json::Value = serde_json::from_str(line)
                .unwrap_or_else(|e| panic!("{task_id}: corrupt JSONL line {line:?}: {e}"));
        }
    }
}

// ---- Group C: H2 git-env-leak test ------------------------------------------------

#[test]
fn c1_leaked_git_dir_does_not_relocate_the_data_store() {
    let tmp = repo();
    let foreign = tempfile::TempDir::new().unwrap();
    git_ok(foreign.path(), &["init", "-q", "-b", "main"]);

    // Simulate being invoked from a git hook, which exports GIT_DIR.
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(tmp.path())
        .env("GIT_DIR", foreign.path().join(".git"))
        .args(["time", "start", "t-1"]);
    cmd.assert().success();

    // The bracket must land in tmp's own store, never the foreign repo's.
    assert!(
        data_store_path(tmp.path(), "t-1").exists(),
        "GIT_DIR leaked — data store not written to the correct (real) repo"
    );
    assert!(
        !foreign.path().join(".git/brana").exists(),
        "GIT_DIR leaked — the foreign repo was touched"
    );
}

#[test]
fn c2_leaked_git_dir_does_not_relocate_the_open_bracket_lock() {
    // Same hazard, but for the --git-dir-resolved lock file rather than the
    // --git-common-dir-resolved data store — the two resolve differently and both
    // need independent H2 coverage per the spec's Testing Strategy.
    let tmp = repo();
    let foreign = tempfile::TempDir::new().unwrap();
    git_ok(foreign.path(), &["init", "-q", "-b", "main"]);

    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(tmp.path())
        .env("GIT_DIR", foreign.path().join(".git"))
        .args(["time", "start", "t-1"]);
    cmd.assert().success();

    let real_lock = tmp.path().join(".git/brana-time-open-bracket.json");
    assert!(real_lock.exists(), "open-bracket lock not written to the correct repo");
}

// ---- Group D: corrupt-store-not-clobbered ----------------------------------------

/// Rung-2 design fix (2026-08-17): the data store is a blind `O_APPEND` log (see
/// spec Decision #2), not a read-modify-write document — appending a new line never
/// needs to parse or validate what's already in the file, so a pre-existing corrupt
/// line does NOT block a new bracket from opening (unlike `queue.rs`'s
/// `parse_before_write_never_clobbers_corrupt_store`, which applies to the
/// LOCK file's read-modify-write, not this file). What must hold: the append succeeds,
/// the corrupt prefix is never truncated/rewritten, and the new line is well-formed —
/// data-quality issues in old lines are an aggregation-time concern (a later,
/// unbuilt task), not a write-time one.
#[test]
fn d1_corrupt_data_store_does_not_block_append_and_is_never_truncated() {
    let tmp = repo();
    let path = data_store_path(tmp.path(), "t-1");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, "{not valid jsonl at all\n").unwrap();

    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();

    let content = std::fs::read_to_string(&path).unwrap();
    assert!(
        content.starts_with("{not valid jsonl at all\n"),
        "the pre-existing corrupt line was truncated or rewritten: {content:?}"
    );
    let appended: Vec<&str> = content
        .lines()
        .skip(1)
        .filter(|l| !l.trim().is_empty())
        .collect();
    assert_eq!(appended.len(), 1, "expected exactly one new line appended: {content:?}");
    let _: serde_json::Value = serde_json::from_str(appended[0])
        .unwrap_or_else(|e| panic!("appended line is not valid JSON: {e}"));
}

/// A lock file left behind by a crash (a `Start` that never got `Close`d — no OS
/// mechanism reclaims ordinary file content, unlike the transient `lock_sidecar`
/// flock which the kernel releases on process death). The next `time start`/`close`
/// in that worktree must produce a clean, named-cause outcome, not a silent hang or
/// an unrelated crash.
#[test]
fn d2_stale_open_bracket_lock_after_crash_is_handled_cleanly() {
    let tmp = repo();
    let lock_path = tmp.path().join(".git/brana-time-open-bracket.json");
    std::fs::write(&lock_path, r#"{"task_id":"t-crashed","opened_at":"2020-01-01T00:00:00Z"}"#)
        .unwrap();

    // A start for a DIFFERENT task_id must be refused — the stale lock still says a
    // bracket is open, exactly as if the crashed session were still running.
    brana(tmp.path()).args(["time", "start", "t-1"]).assert().failure();

    // Closing the crashed task_id's own bracket must succeed and clear the lock,
    // regardless of how long ago `opened_at` claims it was opened.
    brana(tmp.path()).args(["time", "close", "t-crashed"]).assert().success();
    assert!(!lock_path.exists(), "stale lock not cleared after closing its own task_id");
}
