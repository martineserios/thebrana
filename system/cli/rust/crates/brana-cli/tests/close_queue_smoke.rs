//! End-to-end smoke tests for `brana close-queue` (t-1972, ADR-052).
//! Isolation: `env("HOME", tmp.path())` → store at `<tmp>/.claude/close-queue.json`.

use assert_cmd::Command;
use predicates::prelude::*;

fn brana(home: &std::path::Path) -> Command {
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.env("HOME", home);
    cmd
}

fn append_args<'a>(branch: &'a str, range: &'a str) -> Vec<&'a str> {
    vec![
        "close-queue", "append",
        "--project", "thebrana",
        "--branch", branch,
        "--git-root", "/repo",
        "--git-range", range,
        "--snapshot-path", "~/.claude/sessions/snap.diff",
        "--commit-count", "2",
    ]
}

#[test]
fn append_creates_store_and_prints_entry() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path())
        .args(append_args("feat/x", "a..b"))
        .assert()
        .success()
        .stdout(predicate::str::contains("\"id\""))
        .stdout(predicate::str::contains("thebrana:feat/x:a..b"));
    assert!(tmp.path().join(".claude/close-queue.json").exists());
}

#[test]
fn append_requires_args() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path())
        .args(["close-queue", "append", "--project", "x"])
        .assert()
        .failure();
}

#[test]
fn full_lifecycle_roundtrip() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path()).args(append_args("feat/x", "a..b")).assert().success();
    brana(tmp.path()).args(append_args("feat/y", "c..d")).assert().success();

    // dedup: same range again → still 2 entries
    brana(tmp.path()).args(append_args("feat/x", "a..b")).assert().success();

    let out = brana(tmp.path()).args(["close-queue", "list", "--unprocessed"]).output().unwrap();
    let val: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    let arr = val.as_array().unwrap();
    assert_eq!(arr.len(), 2);
    let id0 = arr[0]["id"].as_str().unwrap().to_string();
    // snapshot path was tilde-expanded
    assert!(arr[0]["snapshot_path"].as_str().unwrap().starts_with('/'));

    brana(tmp.path())
        .args(["close-queue", "mark-processed", &id0, "--summary-path", "/tmp/sum.md"])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"processed\": true"));

    let out = brana(tmp.path()).args(["close-queue", "list", "--unprocessed"]).output().unwrap();
    let val: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(val.as_array().unwrap().len(), 1);
    let id1 = val[0]["id"].as_str().unwrap().to_string();

    brana(tmp.path())
        .args(["close-queue", "mark-failed", &id1, "--error", "agy output unparseable"])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"retry_count\": 1"));

    // prune: nothing old enough → 0 removed
    brana(tmp.path())
        .args(["close-queue", "prune"])
        .assert()
        .success()
        .stdout(predicate::str::contains("0"));

    // bad ids fail non-zero
    brana(tmp.path())
        .args(["close-queue", "mark-processed", "q-nope", "--summary-path", "/s.md"])
        .assert()
        .failure();
}

#[test]
fn reset_retries_by_id_succeeds() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path()).args(append_args("feat/x", "a..b")).assert().success();
    let out = brana(tmp.path()).args(["close-queue", "list"]).output().unwrap();
    let arr: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    let id = arr[0]["id"].as_str().unwrap().to_string();

    // fail it 3 times
    for _ in 0..3 {
        brana(tmp.path())
            .args(["close-queue", "mark-failed", &id, "--error", "agy-empty-output"])
            .assert().success();
    }

    // reset by id
    brana(tmp.path())
        .args(["close-queue", "reset-retries", &id])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"retry_count\": 0"))
        .stdout(predicate::str::contains("\"failed\": false"));
}

#[test]
fn reset_retries_all_requeues_all_failed() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path()).args(append_args("feat/a", "a..b")).assert().success();
    brana(tmp.path()).args(append_args("feat/b", "c..d")).assert().success();
    let out = brana(tmp.path()).args(["close-queue", "list"]).output().unwrap();
    let arr: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    for entry in arr.as_array().unwrap() {
        let id = entry["id"].as_str().unwrap();
        brana(tmp.path())
            .args(["close-queue", "mark-failed", id, "--error", "agy regression"])
            .assert().success();
    }
    // reset all (no id argument)
    brana(tmp.path())
        .args(["close-queue", "reset-retries"])
        .assert()
        .success();
    // both entries now have retry_count 0
    let out2 = brana(tmp.path()).args(["close-queue", "list"]).output().unwrap();
    let arr2: serde_json::Value = serde_json::from_slice(&out2.stdout).unwrap();
    for entry in arr2.as_array().unwrap() {
        assert_eq!(entry["retry_count"], 0);
        assert_eq!(entry["failed"], false);
    }
}

#[test]
fn existing_brana_queue_command_is_untouched() {
    // `brana queue` (task spawn) must still parse — regression guard for the
    // ADR-052 naming amendment.
    let tmp = tempfile::TempDir::new().unwrap();
    let out = brana(tmp.path()).args(["queue", "--help"]).output().unwrap();
    assert!(out.status.success());
    let help = String::from_utf8_lossy(&out.stdout);
    assert!(help.contains("unblocked tasks") || help.contains("model recommendations"));
}

#[test]
fn corrupt_store_fails_without_clobbering() {
    let tmp = tempfile::TempDir::new().unwrap();
    let store = tmp.path().join(".claude/close-queue.json");
    std::fs::create_dir_all(store.parent().unwrap()).unwrap();
    std::fs::write(&store, "{not json").unwrap();
    brana(tmp.path()).args(append_args("feat/x", "a..b")).assert().failure();
    assert_eq!(std::fs::read_to_string(&store).unwrap(), "{not json");
}
