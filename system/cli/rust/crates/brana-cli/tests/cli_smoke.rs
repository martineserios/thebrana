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

// ── Backlog: --json flag standardization (t-1335) ───────────────────────

#[test]
fn backlog_query_json_flag_accepted() {
    // --json is a bool alias for --output json; must not fail with "unexpected argument"
    brana()
        .args(["backlog", "query", "--status", "pending", "--json"])
        .assert()
        .success()
        .stdout(predicate::str::starts_with("[").or(predicate::str::starts_with("[")));
}

#[test]
fn backlog_query_json_flag_outputs_json_array() {
    let out = brana()
        .args(["backlog", "query", "--json"])
        .output()
        .expect("brana should run");
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(stdout.trim()).expect("output should be valid JSON");
    assert!(parsed.is_array(), "expected JSON array, got: {stdout}");
}

#[test]
fn backlog_next_json_flag_accepted() {
    brana()
        .args(["backlog", "next", "--json"])
        .assert()
        .success();
}

#[test]
fn backlog_next_json_flag_outputs_json_array() {
    let out = brana()
        .args(["backlog", "next", "--json"])
        .output()
        .expect("brana should run");
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(stdout.trim()).expect("output should be valid JSON");
    assert!(parsed.is_array(), "expected JSON array, got: {stdout}");
}

#[test]
fn backlog_focus_json_flag_accepted() {
    brana()
        .args(["backlog", "focus", "--json"])
        .assert()
        .success();
}

#[test]
fn backlog_focus_json_flag_outputs_json_array() {
    let out = brana()
        .args(["backlog", "focus", "--json"])
        .output()
        .expect("brana should run");
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(stdout.trim()).expect("output should be valid JSON");
    assert!(parsed.is_array(), "expected JSON array, got: {stdout}");
}

#[test]
fn backlog_search_json_flag_accepted() {
    brana()
        .args(["backlog", "search", "--json", "nonexistent-query-xyzzy"])
        .assert()
        .success();
}

#[test]
fn backlog_search_json_flag_outputs_json_array() {
    let out = brana()
        .args(["backlog", "search", "--json", "nonexistent-query-xyzzy"])
        .output()
        .expect("brana should run");
    assert!(out.status.success());
    let stdout = String::from_utf8(out.stdout).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(stdout.trim()).expect("output should be valid JSON");
    assert!(parsed.is_array(), "expected JSON array, got: {stdout}");
}

// ── Backlog: add with shorthand flags ────────────────────────────────────

#[test]
fn backlog_add_priority_and_context_flags_persist() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"smoke-test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "test priority+context flags",
            "--kind", "feature",
            "--effort", "S",
            "--priority", "P1",
            "--context", "verifying t-1336 shorthand merge",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .success();
    let written = std::fs::read_to_string(tasks.path()).unwrap();
    let val: serde_json::Value = serde_json::from_str(&written).unwrap();
    let added = &val["tasks"][0];
    assert_eq!(added["priority"].as_str(), Some("P1"));
    assert_eq!(added["context"].as_str(), Some("verifying t-1336 shorthand merge"));
    assert_eq!(added["effort"].as_str(), Some("S"));
}

// ── Backlog: initiative model (Wave 4B) ──────────────────────────────────

const FOCUS_FIXTURE: &str = r#"{
  "version": "1",
  "project": "test",
  "tasks": [
    {"id":"t-001","subject":"initiative task","type":"task","status":"pending","priority":"P2","effort":"S","initiative":"cc-alignment","work_type":"implement","tags":[],"created":"2026-01-01"},
    {"id":"t-002","subject":"overflow task","type":"task","status":"pending","priority":"P1","effort":"S","tags":[],"created":"2026-01-01"},
    {"id":"t-003","subject":"research task","type":"task","status":"pending","priority":"P2","effort":"M","work_type":"research","tags":[],"created":"2026-01-01"}
  ]
}"#;

#[test]
fn backlog_focus_shows_initiative_header() {
    let tmp = tempfile::tempdir().unwrap();
    let claude_dir = tmp.path().join(".claude");
    std::fs::create_dir_all(&claude_dir).unwrap();
    std::fs::write(claude_dir.join("tasks.json"), FOCUS_FIXTURE).unwrap();
    std::fs::write(
        claude_dir.join("tasks-config.json"),
        r#"{"active_initiative":"cc-alignment"}"#,
    ).unwrap();
    brana()
        .args(["backlog", "focus"])
        .current_dir(tmp.path())
        .env("HOME", tmp.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("cc-alignment"));
}

#[test]
fn backlog_set_active_updates_config() {
    let tmp = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(tmp.path().join(".claude")).unwrap();
    brana()
        .args(["backlog", "set-active", "test-initiative"])
        .env("HOME", tmp.path())
        .assert()
        .success();
    let cfg_path = tmp.path().join(".claude/tasks-config.json");
    assert!(cfg_path.exists(), "tasks-config.json should be created");
    let cfg: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(&cfg_path).unwrap()).unwrap();
    assert_eq!(cfg["active_initiative"].as_str(), Some("test-initiative"));
}

#[test]
fn backlog_add_with_work_type_persists() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "wire new filter",
            "--work-type", "implement",
            "--initiative", "cc-alignment",
            "--effort", "S",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .success();
    let written = std::fs::read_to_string(tasks.path()).unwrap();
    let val: serde_json::Value = serde_json::from_str(&written).unwrap();
    let added = &val["tasks"][0];
    assert_eq!(added["work_type"].as_str(), Some("implement"));
    assert_eq!(added["initiative"].as_str(), Some("cc-alignment"));
}

#[test]
fn backlog_query_by_work_type_filters_correctly() {
    let tmp = tempfile::tempdir().unwrap();
    let claude_dir = tmp.path().join(".claude");
    std::fs::create_dir_all(&claude_dir).unwrap();
    std::fs::write(claude_dir.join("tasks.json"), FOCUS_FIXTURE).unwrap();
    let out = brana()
        .args(["backlog", "query", "--work-type", "research"])
        .current_dir(tmp.path())
        .output()
        .expect("brana should run");
    assert!(out.status.success());
    let parsed: serde_json::Value =
        serde_json::from_str(std::str::from_utf8(&out.stdout).unwrap().trim()).unwrap();
    let tasks = parsed.as_array().unwrap();
    assert_eq!(tasks.len(), 1, "only t-003 has work_type=research");
    assert_eq!(tasks[0]["id"].as_str(), Some("t-003"));
}

// ── Ratings ──────────────────────────────────────────────────────────────

#[test]
fn ratings_help_exits_zero() {
    brana().args(["ratings", "--help"]).assert().success();
}

#[test]
fn ratings_json_missing_file_exits_zero() {
    let tmp = tempfile::tempdir().unwrap();
    brana()
        .args(["ratings", "--json"])
        .env("HOME", tmp.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("\"total\""));
}

#[test]
fn ratings_json_fixture_shows_breakdown() {
    let tmp = tempfile::tempdir().unwrap();
    let ratings_dir = tmp.path().join(".claude/ratings");
    std::fs::create_dir_all(&ratings_dir).unwrap();
    std::fs::write(
        ratings_dir.join("ratings.jsonl"),
        "{\"ts\":\"2026-05-01T10:00:00Z\",\"session_id\":\"s1\",\"signal\":\"positive\",\"category\":\"positive\",\"prompt\":\"test\"}\n\
         {\"ts\":\"2026-05-01T11:00:00Z\",\"session_id\":\"s1\",\"signal\":\"negative\",\"category\":\"negative\",\"prompt\":\"test2\"}\n",
    )
    .unwrap();
    let out = brana()
        .args(["ratings", "--json"])
        .env("HOME", tmp.path())
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let parsed: serde_json::Value =
        serde_json::from_str(std::str::from_utf8(&out).unwrap().trim()).unwrap();
    assert_eq!(parsed["total"].as_u64(), Some(2));
    assert_eq!(parsed["positive"].as_u64(), Some(1));
    assert_eq!(parsed["negative"].as_u64(), Some(1));
}
