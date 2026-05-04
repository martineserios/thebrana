//! Integration smoke tests for the `brana` CLI.
//!
//! These tests exercise the binary end-to-end via `assert_cmd`. They
//! complement the unit tests in `src/commands/*.rs` — the unit tests
//! cover individual functions; these cover the dispatch layer + clap
//! argument parsing + actual binary output.
//!
//! Conventions:
//! - One test per assertion. Failure output is more useful that way.
//! - Use `assert_fs` + `tempfile` for filesystem isolation. Never touch
//!   the real ~/.claude or repo state.
//! - Use `predicates` for stdout/stderr matching.
//! - For complex expected output, use `insta::assert_snapshot!`.

use assert_cmd::Command;
use predicates::prelude::*;

fn brana() -> Command {
    Command::cargo_bin("brana").expect("binary should build")
}

// ── Top-level surface ────────────────────────────────────────────────────

#[test]
fn version_prints_version() {
    brana()
        .arg("version")
        .assert()
        .success()
        .stdout(predicate::str::contains("brana"));
}

#[test]
fn help_lists_subcommands() {
    brana()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("backlog"))
        .stdout(predicate::str::contains("doctor"))
        .stdout(predicate::str::contains("session"))
        .stdout(predicate::str::contains("graph"))
        .stdout(predicate::str::contains("knowledge"));
}

#[test]
fn unknown_subcommand_fails_cleanly() {
    brana()
        .arg("nonexistent")
        .assert()
        .failure()
        .stderr(predicate::str::contains("unrecognized"));
}

// ── Backlog: read-only commands ──────────────────────────────────────────
//
// These are read-only so we run them against the live tasks.json — they
// should not modify state. They smoke-test the dispatch path + JSON output.

#[test]
fn backlog_help_lists_subcommands() {
    brana()
        .args(["backlog", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("query"))
        .stdout(predicate::str::contains("get"))
        .stdout(predicate::str::contains("set"))
        .stdout(predicate::str::contains("add"));
}

#[test]
fn backlog_query_with_invalid_status_fails() {
    brana()
        .args(["backlog", "query", "--status", "bogus"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid value"));
}

#[test]
fn backlog_get_unknown_id_fails() {
    brana()
        .args(["backlog", "get", "t-00000000"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("not found").or(predicate::str::contains("t-00000000")));
}

// ── Validate ─────────────────────────────────────────────────────────────

#[test]
fn validate_missing_file_fails() {
    brana()
        .args(["validate", "/tmp/nonexistent-tasks-file.json"])
        .assert()
        .failure();
}

#[test]
fn validate_minimal_tasks_json_passes() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"smoke-test","tasks":[]}"#)
        .unwrap();
    brana()
        .args(["validate"])
        .arg(tasks.path())
        .assert()
        .success();
}

#[test]
fn validate_rejects_missing_project_field() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","tasks":[]}"#)
        .unwrap();
    brana()
        .args(["validate"])
        .arg(tasks.path())
        .assert()
        .failure()
        .stdout(predicate::str::contains("missing project"));
}

// ── Doctor ───────────────────────────────────────────────────────────────

#[test]
fn doctor_runs_without_panic() {
    // Doctor returns 0 even with check failures — its job is to report,
    // not gate. We only assert exit success and that some checks ran.
    brana()
        .arg("doctor")
        .assert()
        .success()
        .stdout(predicate::str::contains("brana doctor"));
}
