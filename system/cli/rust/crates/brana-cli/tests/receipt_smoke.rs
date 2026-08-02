//! End-to-end smoke tests for `brana receipt` (t-2593, ADR-076).
//!
//! Each test builds a throwaway git repo in a tempdir. Every git invocation here — and the
//! `brana` invocation itself — runs with `GIT_DIR` and friends removed: git exports those
//! into hook environments, they override path-based discovery, and `cd` does not protect
//! you (`pattern_git-hook-env-leaks-into-executed-tests`, live failure 2026-08-01).
//! Without the scrub these fixtures would operate on the real repository.

use assert_cmd::Command;
use predicates::prelude::*;
use std::path::Path;

const GIT_ENV: [&str; 6] = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_COMMON_DIR",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
];

fn git(dir: &Path, args: &[&str]) -> String {
    let mut c = std::process::Command::new("git");
    c.current_dir(dir).args(args);
    for k in GIT_ENV {
        c.env_remove(k);
    }
    let out = c.output().expect("git runs");
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

/// A repo on `dev` with one task carrying two `AC:` lines, plus a feature commit on top.
fn repo(ac: &str) -> tempfile::TempDir {
    let tmp = tempfile::TempDir::new().unwrap();
    let p = tmp.path();
    git(p, &["init", "-q", "-b", "dev"]);
    git(p, &["config", "user.email", "t@t"]);
    git(p, &["config", "user.name", "t"]);
    git(p, &["config", "commit.gpgsign", "false"]);

    std::fs::create_dir_all(p.join(".claude")).unwrap();
    std::fs::write(
        p.join(".claude/tasks.json"),
        serde_json::json!({
            "project": "fixture",
            "tasks": [{"id": "t-1", "subject": "fixture", "context": ac}]
        })
        .to_string(),
    )
    .unwrap();
    std::fs::write(p.join("seed.txt"), "seed\n").unwrap();
    git(p, &["add", "-A"]);
    git(p, &["commit", "-q", "-m", "base"]);

    git(p, &["checkout", "-q", "-b", "feat"]);
    std::fs::write(p.join("feature.txt"), "work\n").unwrap();
    git(p, &["add", "-A"]);
    git(p, &["commit", "-q", "-m", "feature"]);
    tmp
}

fn receipt_json(dir: &Path) -> serde_json::Value {
    let path = dir.join(".git/brana/receipts/t-1.json");
    serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap()
}

// ---- T1: a failing command still mints, recorded as failed ----------------------

#[test]
fn t1_failing_command_mints_a_failed_receipt() {
    let tmp = repo("AC: one");
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "sh", "-c", "echo boom; exit 1"])
        .assert()
        .success()
        .stdout(predicate::str::contains("failed"));

    let r = receipt_json(tmp.path());
    assert_eq!(r["outcome"], "failed");
    assert_eq!(r["execution"]["exit_code"], 1);
}

#[test]
fn passing_command_mints_a_passed_receipt_that_validates() {
    let tmp = repo("AC: one");
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "true"])
        .assert()
        .success();
    assert_eq!(receipt_json(tmp.path())["outcome"], "passed");

    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .success()
        .stdout(predicate::str::contains("allow"));
}

#[test]
fn a_failed_receipt_never_allows() {
    let tmp = repo("AC: one");
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "false"])
        .assert()
        .success();
    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(4)
        .stdout(predicate::str::contains("invalidated"));
}

#[test]
fn missing_receipt_is_invalidated_not_a_crash() {
    let tmp = repo("AC: one");
    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(4)
        .stdout(predicate::str::contains("no receipt"));
}

// ---- T3/T4/T5: what mint refuses ------------------------------------------------

#[test]
fn t3_dirty_worktree_refuses() {
    let tmp = repo("AC: one");
    std::fs::write(tmp.path().join("seed.txt"), "edited\n").unwrap();
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "true"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("uncommitted tracked changes"));
    assert!(!tmp.path().join(".git/brana/receipts/t-1.json").exists());
}

#[test]
fn t4_command_that_writes_a_tracked_file_refuses() {
    let tmp = repo("AC: one");
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "sh", "-c", "echo mutated > seed.txt"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("modified tracked files"));
    assert!(!tmp.path().join(".git/brana/receipts/t-1.json").exists());
}

#[test]
fn t5_command_that_writes_only_gitignored_files_succeeds() {
    let tmp = repo("AC: one");
    std::fs::write(tmp.path().join(".gitignore"), "junk/\n").unwrap();
    git(tmp.path(), &["add", "-A"]);
    git(tmp.path(), &["commit", "-q", "-m", "ignore junk"]);

    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "sh", "-c", "mkdir -p junk && echo x > junk/a"])
        .assert()
        .success();
    assert_eq!(receipt_json(tmp.path())["outcome"], "passed");
}

// ---- T13/T14: content-bound idempotency ----------------------------------------

#[test]
fn t13_identical_remint_is_a_noop() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();
    let first = std::fs::read_to_string(tmp.path().join(".git/brana/receipts/t-1.json")).unwrap();

    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "true"])
        .assert()
        .success()
        .stdout(predicate::str::contains("no-op"));
    let second = std::fs::read_to_string(tmp.path().join(".git/brana/receipts/t-1.json")).unwrap();
    assert_eq!(first, second, "a no-op must not rewrite the receipt");
}

#[test]
fn t14_same_candidate_different_command_is_a_hard_error() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "echo", "different"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("different command"));
}

#[test]
fn re_mint_at_a_new_candidate_supersedes() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();
    let before = receipt_json(tmp.path());

    std::fs::write(tmp.path().join("more.txt"), "more\n").unwrap();
    git(tmp.path(), &["add", "-A"]);
    git(tmp.path(), &["commit", "-q", "-m", "more"]);

    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();
    let after = receipt_json(tmp.path());
    assert_ne!(
        before["repo"]["candidate_commit"], after["repo"]["candidate_commit"],
        "a new candidate must supersede"
    );
}

// ---- T6/T7/T9 through the real CLI ---------------------------------------------

#[test]
fn t6_a_later_commit_is_scope_changed() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();

    std::fs::write(tmp.path().join("extra.txt"), "extra\n").unwrap();
    git(tmp.path(), &["add", "-A"]);
    git(tmp.path(), &["commit", "-q", "-m", "extra"]);

    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(3)
        .stdout(predicate::str::contains("scope-changed"));
}

#[test]
fn t7_editing_the_ac_lines_invalidates() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();

    let p = tmp.path().join(".claude/tasks.json");
    let mut v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&p).unwrap()).unwrap();
    v["tasks"][0]["context"] = serde_json::json!("AC: one\nAC: two (added later)");
    std::fs::write(&p, v.to_string()).unwrap();

    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(4)
        .stdout(predicate::str::contains("invalidated"));
}

#[test]
fn t9_tampering_with_the_output_blob_invalidates() {
    let tmp = repo("AC: one");
    brana(tmp.path())
        .args(["receipt", "mint", "t-1", "--", "sh", "-c", "echo real-output"])
        .assert()
        .success();
    // Rewrite the captured evidence. The receipt's hash no longer describes the blob.
    std::fs::write(tmp.path().join(".git/brana/receipts/t-1.stdout"), "forged\n").unwrap();

    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(4)
        .stdout(predicate::str::contains("invalidated"));
}

#[test]
fn t9_deleting_the_output_blob_invalidates() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();
    std::fs::remove_file(tmp.path().join(".git/brana/receipts/t-1.stdout")).unwrap();

    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(4);
}

#[test]
fn forged_outcome_in_the_stored_receipt_is_rejected() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "false"]).assert().success();

    // Hand-edit `outcome` to "passed" while exit_code stays 1 — the forged-verdict case.
    let p = tmp.path().join(".git/brana/receipts/t-1.json");
    let mut v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&p).unwrap()).unwrap();
    v["outcome"] = serde_json::json!("passed");
    std::fs::write(&p, v.to_string()).unwrap();

    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .code(4)
        .stdout(predicate::str::contains("OutcomeIncoherent"));
}

// ---- T16/T17: the two live hazards ---------------------------------------------

#[test]
fn t16_leaked_git_dir_does_not_reach_the_executed_command() {
    let tmp = repo("AC: one");
    let foreign = tempfile::TempDir::new().unwrap();
    git(foreign.path(), &["init", "-q", "-b", "main"]);

    // Simulate being invoked from a git hook, which exports GIT_DIR.
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(tmp.path())
        .env("GIT_DIR", foreign.path().join(".git"))
        .args([
            "receipt", "mint", "t-1", "--",
            "sh", "-c", "test -z \"$GIT_DIR\" || { echo GIT_DIR=$GIT_DIR leaked; exit 9; }",
        ]);
    cmd.assert().success();

    let r = receipt_json(tmp.path());
    assert_eq!(r["execution"]["exit_code"], 0, "GIT_DIR leaked into the executed command");
    // And the foreign repo was never touched.
    assert!(!foreign.path().join(".git/brana").exists());
}

#[test]
fn t17_base_is_the_merge_base_and_does_not_move_when_dev_advances() {
    let tmp = repo("AC: one");
    brana(tmp.path()).args(["receipt", "mint", "t-1", "--", "true"]).assert().success();
    let pinned = receipt_json(tmp.path())["repo"]["base_commit"].clone();

    // Another session advances `dev` after the receipt was minted.
    git(tmp.path(), &["checkout", "-q", "dev"]);
    std::fs::write(tmp.path().join("theirs.txt"), "concurrent\n").unwrap();
    git(tmp.path(), &["add", "-A"]);
    git(tmp.path(), &["commit", "-q", "-m", "their work"]);
    git(tmp.path(), &["checkout", "-q", "feat"]);

    // The merge-base is unchanged, so their commit is not attributed to this task and the
    // receipt still binds.
    brana(tmp.path())
        .args(["receipt", "validate", "t-1"])
        .assert()
        .success()
        .stdout(predicate::str::contains("allow"));
    assert_eq!(receipt_json(tmp.path())["repo"]["base_commit"], pinned);
}
