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
