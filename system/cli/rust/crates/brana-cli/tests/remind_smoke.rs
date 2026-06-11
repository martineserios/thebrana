//! End-to-end smoke tests for `brana remind` (t-1966, ADR-051).
//!
//! Isolation: `env("HOME", tmp.path())` so the store lands in
//! `<tmp>/.claude/reminders.json`.

use assert_cmd::Command;
use predicates::prelude::*;

fn brana(home: &std::path::Path) -> Command {
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.env("HOME", home);
    cmd
}

fn store_path(home: &std::path::Path) -> std::path::PathBuf {
    home.join(".claude/reminders.json")
}

#[test]
fn write_creates_store_and_prints_json() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path())
        .args(["remind", "write", "--text", "run validate.sh", "--action", "./validate.sh"])
        .assert()
        .success()
        .stdout(predicate::str::contains("\"id\""))
        .stdout(predicate::str::contains("pending"));
    assert!(store_path(tmp.path()).exists());
}

#[test]
fn write_requires_text() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path()).args(["remind", "write"]).assert().failure();
}

#[test]
fn list_resolve_snooze_roundtrip() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path())
        .args(["remind", "write", "--text", "a", "--priority", "high"])
        .assert()
        .success();
    brana(tmp.path())
        .args(["remind", "write", "--text", "b"])
        .assert()
        .success();

    let out = brana(tmp.path()).args(["remind", "list"]).output().unwrap();
    let val: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    let arr = val.as_array().unwrap();
    assert_eq!(arr.len(), 2);
    let id_a = arr[0]["id"].as_str().unwrap().to_string();
    let id_b = arr[1]["id"].as_str().unwrap().to_string();
    assert_eq!(arr[0]["priority"], "high");

    brana(tmp.path())
        .args(["remind", "resolve", &id_a])
        .assert()
        .success()
        .stdout(predicate::str::contains("resolved"));
    brana(tmp.path())
        .args(["remind", "snooze", &id_b, "1d"])
        .assert()
        .success()
        .stdout(predicate::str::contains("snoozed"));

    // Bad id / bad duration fail with non-zero exit.
    brana(tmp.path()).args(["remind", "resolve", "r-nope"]).assert().failure();
    brana(tmp.path()).args(["remind", "snooze", &id_b, "5x"]).assert().failure();
}

#[test]
fn dedup_key_increments_occurrences() {
    let tmp = tempfile::TempDir::new().unwrap();
    for _ in 0..2 {
        brana(tmp.path())
            .args(["remind", "write", "--text", "hooks edited", "--dedup-key", "hooks-validate"])
            .assert()
            .success();
    }
    let out = brana(tmp.path()).args(["remind", "list"]).output().unwrap();
    let val: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    let arr = val.as_array().unwrap();
    assert_eq!(arr.len(), 1);
    assert_eq!(arr[0]["occurrences"], 2);
}

#[test]
fn list_pending_filter_excludes_resolved() {
    let tmp = tempfile::TempDir::new().unwrap();
    brana(tmp.path()).args(["remind", "write", "--text", "a"]).assert().success();
    brana(tmp.path()).args(["remind", "write", "--text", "b"]).assert().success();
    let out = brana(tmp.path()).args(["remind", "list"]).output().unwrap();
    let val: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    let id = val[0]["id"].as_str().unwrap().to_string();
    brana(tmp.path()).args(["remind", "resolve", &id]).assert().success();

    let out = brana(tmp.path()).args(["remind", "list", "--status", "pending"]).output().unwrap();
    let val: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(val.as_array().unwrap().len(), 1);
    assert_eq!(val[0]["status"], "pending");
}

#[test]
fn corrupt_store_fails_without_clobbering() {
    let tmp = tempfile::TempDir::new().unwrap();
    let store = store_path(tmp.path());
    std::fs::create_dir_all(store.parent().unwrap()).unwrap();
    std::fs::write(&store, "{not json").unwrap();
    brana(tmp.path())
        .args(["remind", "write", "--text", "x"])
        .assert()
        .failure();
    assert_eq!(std::fs::read_to_string(&store).unwrap(), "{not json");
}
