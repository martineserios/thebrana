//! End-to-end smoke tests for `brana time` (t-2921/t-2922, ADR-083).
//!
//! Same fixture shape as `receipt_smoke.rs`: throwaway git repos in tempdirs, every git
//! and `brana` invocation runs with the git-env denylist scrubbed
//! (`pattern_git-hook-env-leaks-into-executed-tests`).
//!
//! t-2921 (this file): tests only, against a `todo!()`-stubbed `brana time` — every test
//! here is expected to fail red until t-2922 implements the real logic.

use assert_cmd::Command;
use predicates::prelude::*;
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
    // N real `brana` subprocesses, each starting+closing a DISTINCT task_id, all racing
    // to write into the same brana/time/ directory (shared, git-common-dir-scoped).
    // Each writer uses its own worktree so the per-worktree lock doesn't itself
    // serialize them — the thing under test is the shared *data store*'s atomicity.
    let handles: Vec<_> = (0..n)
        .map(|i| {
            let base = root.clone();
            std::thread::spawn(move || {
                let wt = add_worktree(&base, &format!("wt-b{i}"), &format!("feat/b{i}"));
                let task_id = format!("t-b{i}");
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

#[test]
fn d1_corrupt_data_store_is_not_silently_overwritten() {
    let tmp = repo();
    let path = data_store_path(tmp.path(), "t-1");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, "{not valid jsonl at all").unwrap();

    // Starting a bracket for a task_id whose store file is already corrupt must error
    // with a message that names the real cause, not just fail for any reason (a stub
    // panic also exits non-zero — that must NOT count as passing this test) — parse-
    // before-write, queue.rs-shaped: `parse_before_write_never_clobbers_corrupt_store`.
    brana(tmp.path())
        .args(["time", "start", "t-1"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("corrupt").or(predicate::str::contains("parse")));
    let content = std::fs::read_to_string(&path).unwrap();
    assert_eq!(content, "{not valid jsonl at all", "corrupt store was overwritten");
}
