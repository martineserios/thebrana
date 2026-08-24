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

// ── Backlog: epic model (Wave 4B) ──────────────────────────────────

const FOCUS_FIXTURE: &str = r#"{
  "version": "1",
  "project": "test",
  "tasks": [
    {"id":"t-001","subject":"epic task","type":"task","status":"in_progress","started":"2026-08-20","priority":"P2","effort":"S","epic":"cc-alignment","work_type":"implement","tags":[],"created":"2026-01-01"},
    {"id":"t-002","subject":"overflow task","type":"task","status":"pending","priority":"P1","effort":"S","tags":[],"created":"2026-01-01"},
    {"id":"t-003","subject":"research task","type":"task","status":"pending","priority":"P2","effort":"M","work_type":"research","tags":[],"created":"2026-01-01"}
  ]
}"#;

#[test]
fn backlog_focus_shows_epic_header() {
    // ADR-088: epic focus is task-derived — the most-recently-started
    // in_progress task's flat .epic field (v2 schema) — not read from
    // tasks-config.json. No config file involved at all.
    let tmp = tempfile::tempdir().unwrap();
    let claude_dir = tmp.path().join(".claude");
    std::fs::create_dir_all(&claude_dir).unwrap();
    std::fs::write(claude_dir.join("tasks.json"), FOCUS_FIXTURE).unwrap();
    brana()
        .args(["backlog", "focus"])
        .current_dir(tmp.path())
        .env("HOME", tmp.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("cc-alignment"));
}

#[test]
fn set_active_subcommand_no_longer_exists() {
    // ADR-088: set-active is removed entirely (clean removal, not a
    // deprecated no-op) — writing it is actively misleading once nothing
    // reads active_epic. Assert the actual clap error content, not just a
    // non-zero exit — a bare exit-code check can't distinguish this from
    // any other failure mode (challenger finding, 2026-08-24).
    brana()
        .args(["backlog", "set-active", "test-epic"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("unrecognized subcommand").or(
            predicate::str::contains("set-active"),
        ));
}

#[test]
fn focus_ignores_stale_active_epic_in_config_json() {
    // A leftover active_epic key (from before this ADR shipped) in either
    // local or global tasks-config.json is now a harmless, inert orphan —
    // focus must never surface it, because nothing reads that key anymore.
    // With no in_progress task in the fixture, focus must show no epic at
    // all, proving the config value isn't a fallback source.
    let home = tempfile::tempdir().unwrap();
    let proj = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(proj.path().join(".claude")).unwrap();
    std::fs::create_dir_all(home.path().join(".claude")).unwrap();
    std::fs::write(
        home.path().join(".claude/tasks-config.json"),
        r#"{"active_epic":"foreign-epic","theme":"emoji"}"#,
    )
    .unwrap();
    std::fs::write(
        proj.path().join(".claude/tasks-config.json"),
        r#"{"active_epic":"stale-local-epic"}"#,
    )
    .unwrap();
    std::fs::write(
        proj.path().join(".claude/tasks.json"),
        r#"{"version":"1","project":"proj","tasks":[{"id":"t-1","subject":"x","type":"task","status":"pending","tags":[],"blocked_by":[]}]}"#,
    )
    .unwrap();
    brana()
        .args(["backlog", "focus", "--json"])
        .env("HOME", home.path())
        .env_remove("CLAUDE_PROJECT_DIR")
        .current_dir(proj.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("foreign-epic").not())
        .stdout(predicate::str::contains("stale-local-epic").not());
}

#[test]
fn focus_fails_loud_when_explicit_epic_flag_resolves_to_nothing() {
    // t-2314 (ADR-065) behavior preserved for the EXPLICIT --epic path only:
    // resolve_focus_epic()'s task-derived tier is non-fatal (falls through to
    // no-boost), but assert_active_epic_resolves() stays fail-loud when the
    // caller explicitly asked for an epic that doesn't exist.
    let home = tempfile::tempdir().unwrap();
    let proj = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(proj.path().join(".claude")).unwrap();
    std::fs::write(
        proj.path().join(".claude/tasks.json"),
        r#"{"version":"1","project":"proj","tasks":[{"id":"t-1","subject":"x","type":"task","status":"pending","tags":[],"blocked_by":[],"epic":"a-different-epic"}]}"#,
    ).unwrap();
    brana()
        .args(["backlog", "focus", "--epic", "nonexistent-epic"])
        .env("HOME", home.path())
        .env_remove("CLAUDE_PROJECT_DIR")
        .current_dir(proj.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("nonexistent-epic"));
}

#[test]
fn backlog_add_project_writes_to_resolved_target() {
    // Cross-project create (t-2159): --project <slug> resolves the target repo's
    // tasks.json via the portfolio and writes there, leaving the current project untouched.
    let home = tempfile::tempdir().unwrap();
    let target = tempfile::tempdir().unwrap();
    let cwd = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(target.path().join(".claude")).unwrap();
    std::fs::write(
        target.path().join(".claude/tasks.json"),
        r#"{"version":"1","project":"target","tasks":[]}"#,
    )
    .unwrap();
    std::fs::create_dir_all(cwd.path().join(".claude")).unwrap();
    std::fs::write(
        cwd.path().join(".claude/tasks.json"),
        r#"{"version":"1","project":"cur","tasks":[]}"#,
    )
    .unwrap();
    std::fs::create_dir_all(home.path().join(".claude")).unwrap();
    let portfolio = format!(
        r#"{{"projects":[{{"slug":"otherproj","path":"{}"}}]}}"#,
        target.path().display()
    );
    std::fs::write(home.path().join(".claude/tasks-portfolio.json"), portfolio).unwrap();

    brana()
        .args(["backlog", "add", "--subject", "cross task", "--project", "otherproj"])
        .env("HOME", home.path())
        .env_remove("CLAUDE_PROJECT_DIR")
        .current_dir(cwd.path())
        .assert()
        .success();

    let target_tasks: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(target.path().join(".claude/tasks.json")).unwrap(),
    )
    .unwrap();
    let cur_tasks: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(cwd.path().join(".claude/tasks.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        target_tasks["tasks"].as_array().unwrap().len(),
        1,
        "task should be written to the target project"
    );
    assert_eq!(
        cur_tasks["tasks"].as_array().unwrap().len(),
        0,
        "current project must be untouched"
    );
}

#[test]
fn backlog_add_unknown_project_errors() {
    let home = tempfile::tempdir().unwrap();
    let cwd = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(cwd.path().join(".claude")).unwrap();
    std::fs::write(
        cwd.path().join(".claude/tasks.json"),
        r#"{"version":"1","project":"cur","tasks":[]}"#,
    )
    .unwrap();
    std::fs::create_dir_all(home.path().join(".claude")).unwrap();
    std::fs::write(
        home.path().join(".claude/tasks-portfolio.json"),
        r#"{"projects":[]}"#,
    )
    .unwrap();
    brana()
        .args(["backlog", "add", "--subject", "x", "--project", "nope"])
        .env("HOME", home.path())
        .env_remove("CLAUDE_PROJECT_DIR")
        .current_dir(cwd.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("not found in tasks-portfolio"));
}

#[test]
fn backlog_add_project_and_file_conflict() {
    // --project and --file are mutually exclusive (clap-enforced).
    brana()
        .args([
            "backlog", "add", "--subject", "x", "--project", "p", "--file", "/tmp/x.json",
        ])
        .assert()
        .failure();
}

#[test]
fn backlog_add_without_project_writes_to_current_project() {
    // Regression guard (challenger finding 5): plain `backlog add` with no --project
    // must write to the CURRENT project's tasks.json, unchanged from pre-t-2159 behavior.
    // The riskiest regression surface — if find_tasks_file() in the add path breaks,
    // unflagged adds silently land in the wrong file.
    let home = tempfile::tempdir().unwrap();
    let proj = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(proj.path().join(".claude")).unwrap();
    std::fs::write(
        proj.path().join(".claude/tasks.json"),
        r#"{"version":"1","project":"cur","tasks":[]}"#,
    )
    .unwrap();
    std::fs::create_dir_all(home.path().join(".claude")).unwrap();

    brana()
        .args(["backlog", "add", "--subject", "local task"])
        .env("HOME", home.path())
        .env_remove("CLAUDE_PROJECT_DIR")
        .current_dir(proj.path())
        .assert()
        .success();

    let tasks: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(proj.path().join(".claude/tasks.json")).unwrap(),
    )
    .unwrap();
    assert_eq!(
        tasks["tasks"].as_array().unwrap().len(),
        1,
        "no --project flag → task lands in the current project's tasks.json"
    );
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
}

#[test]
fn backlog_add_epic_flag_is_deprecated_noop() {
    // t-2310 (ADR-065): --epic is retired from cmd_add's shorthand path —
    // epic becomes a hierarchy node, not a flat field a new task can carry.
    // The flag stays parseable (no hard CLI error) but is a no-op with a
    // stderr deprecation warning.
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "shorthand with epic",
            "--epic", "cc-alignment",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .success()
        .stderr(predicate::str::contains("--epic is deprecated"));
    let written = std::fs::read_to_string(tasks.path()).unwrap();
    let val: serde_json::Value = serde_json::from_str(&written).unwrap();
    let added = &val["tasks"][0];
    assert!(added.get("epic").is_none() || added["epic"].is_null(),
        "--epic must be a no-op, got: {}", added["epic"]);
}

// ── t-2739: cmd_add validated kind/priority/status but not work_type or type,
// so the CLI add path leaked non-enum values (fix, docs) the MCP path rejects. ──

#[test]
fn backlog_add_rejects_invalid_work_type_shorthand() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "bad work type",
            "--work-type", "fix",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid work_type"));
    let written = std::fs::read_to_string(tasks.path()).unwrap();
    let val: serde_json::Value = serde_json::from_str(&written).unwrap();
    assert_eq!(
        val["tasks"].as_array().unwrap().len(), 0,
        "no task must be written on invalid work_type"
    );
}

#[test]
fn backlog_add_rejects_invalid_work_type_json() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--json", r#"{"subject":"bad wt via json","work_type":"docs"}"#,
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid work_type"));
}

#[test]
fn backlog_add_rejects_invalid_kind_shorthand() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "bad kind",
            "--kind", "banana",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid kind"));
}

#[test]
fn backlog_add_rejects_invalid_task_type() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "bad node type",
            "--type", "feature",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("invalid type"));
}

#[test]
fn backlog_add_accepts_initiative_task_type() {
    // Positive guard: the least-common canonical type must stay accepted
    // once type validation lands (t-2739).
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks
        .write_str(r#"{"version":"1","project":"test","tasks":[]}"#)
        .unwrap();
    brana()
        .args([
            "backlog", "add",
            "--subject", "an initiative",
            "--type", "initiative",
            "--file",
        ])
        .arg(tasks.path())
        .assert()
        .success();
    let written = std::fs::read_to_string(tasks.path()).unwrap();
    let val: serde_json::Value = serde_json::from_str(&written).unwrap();
    assert_eq!(val["tasks"][0]["type"].as_str(), Some("initiative"));
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

// ── session epic (t-1758) ────────────────────────────────────────────────

#[test]
fn session_epic_subcommand_exists() {
    // `brana session epic --help` must succeed — verifies the subcommand was wired up.
    brana()
        .args(["session", "epic", "--help"])
        .assert()
        .success();
}

#[test]
fn session_initiative_subcommand_removed() {
    // The old `brana session initiative` subcommand must no longer exist.
    brana()
        .args(["session", "initiative", "--help"])
        .assert()
        .failure();
}

// ── Backlog: lint — definition-of-ready checker (t-1981) ─────────────────

const LINT_FIXTURE: &str = r#"{
  "version": "1",
  "project": "test",
  "tasks": [
    {"id":"t-010","subject":"ready task","type":"task","status":"pending","effort":"S","tags":[],"blocked_by":[],
     "description":"A well-curated task with enough detail to dispatch.",
     "context":"Rich background on scope and constraints.\nAC: `cargo test` passes with lint tests included"},
    {"id":"t-011","subject":"vague task","type":"task","status":"pending","effort":"XL","tags":[],"blocked_by":[],
     "description":"A vague task.",
     "context":"AC: works well"}
  ]
}"#;

#[test]
fn backlog_lint_ready_task_exits_zero() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks.write_str(LINT_FIXTURE).unwrap();
    brana()
        .args(["backlog", "lint", "t-010", "--file"])
        .arg(tasks.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("ready"));
}

#[test]
fn backlog_lint_not_ready_exits_one_naming_each_failed_check() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks.write_str(LINT_FIXTURE).unwrap();
    let assert = brana()
        .args(["backlog", "lint", "t-011", "--file"])
        .arg(tasks.path())
        .assert()
        .code(1);
    // AC: failing output names each failed check on its own line.
    let stdout = String::from_utf8(assert.get_output().stdout.clone()).unwrap();
    let failed = ["machine-verifiable-ac", "rich-context", "effort-s-or-m"];
    for name in failed {
        assert!(
            stdout.lines().any(|l| l.contains(name)),
            "expected a line naming {name}, got:\n{stdout}"
        );
    }
}

#[test]
fn backlog_lint_json_emits_ready_and_checks() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks.write_str(LINT_FIXTURE).unwrap();
    let assert = brana()
        .args(["backlog", "lint", "t-011", "--json", "--file"])
        .arg(tasks.path())
        .assert()
        .code(1);
    let stdout = String::from_utf8(assert.get_output().stdout.clone()).unwrap();
    let v: serde_json::Value = serde_json::from_str(&stdout).expect("valid JSON");
    assert_eq!(v["ready"].as_bool(), Some(false));
    let checks = v["checks"].as_array().expect("checks array");
    assert_eq!(checks.len(), 4);
    for c in checks {
        assert!(c["name"].is_string() && c["pass"].is_boolean() && c["reason"].is_string());
    }
}

#[test]
fn backlog_lint_unknown_task_fails() {
    use assert_fs::prelude::*;
    let tmp = assert_fs::TempDir::new().unwrap();
    let tasks = tmp.child("tasks.json");
    tasks.write_str(LINT_FIXTURE).unwrap();
    brana()
        .args(["backlog", "lint", "t-999", "--file"])
        .arg(tasks.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("not found"));
}
