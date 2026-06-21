//! Integration tests for `brana orbit` — the thin operator front-door for the
//! unattended autonomous runner (t-2197).
//!
//! Hermetic: every test isolates HOME + project dir via tempfile and drives a
//! STUB `autonomous-runner.sh` that echoes its args + selected env. No real
//! `claude -p`, no real scheduler, no global ~/.claude touched.
//!
//! Conventions mirror cli_smoke.rs: one assertion per test, assert_fs/tempfile
//! for isolation, predicates for stdout/stderr.

use assert_cmd::Command;
use predicates::prelude::*;

fn brana() -> Command {
    Command::cargo_bin("brana").expect("binary should build")
}

/// A project tempdir holding a stub runner that echoes args + env, so a verb
/// that shells out can be observed without running the real engine.
fn stub_project() -> tempfile::TempDir {
    let proj = tempfile::tempdir().unwrap();
    let scripts = proj.path().join("system/scripts");
    std::fs::create_dir_all(&scripts).unwrap();
    std::fs::write(
        scripts.join("autonomous-runner.sh"),
        "#!/usr/bin/env bash\n\
         echo \"ARGS:$*\"\n\
         echo \"RUNNER_MAX_TASKS=${RUNNER_MAX_TASKS:-UNSET}\"\n\
         echo \"RUNNER_MAX_FAILS=${RUNNER_MAX_FAILS:-UNSET}\"\n\
         echo \"RUNNER_PUSH=${RUNNER_PUSH:-UNSET}\"\n",
    )
    .unwrap();
    proj
}

/// A HOME tempdir seeded with a scheduler.json containing the disabled,
/// default-deny `autonomous-runner` job (as it ships in the template).
fn home_with_job() -> tempfile::TempDir {
    let home = tempfile::tempdir().unwrap();
    let sched_dir = home.path().join(".claude/scheduler");
    std::fs::create_dir_all(&sched_dir).unwrap();
    std::fs::write(
        sched_dir.join("scheduler.json"),
        r#"{"jobs":{"autonomous-runner":{"type":"command","command":"./system/scripts/autonomous-runner.sh --observe","enabled":false,"schedule":"*-*-* 03:00:00"}}}"#,
    )
    .unwrap();
    home
}

fn read_job(home: &tempfile::TempDir) -> serde_json::Value {
    let p = home.path().join(".claude/scheduler/scheduler.json");
    let v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(p).unwrap()).unwrap();
    v["jobs"]["autonomous-runner"].clone()
}

// ── Surface ───────────────────────────────────────────────────────────────

#[test]
fn orbit_help_lists_all_verbs() {
    brana()
        .args(["orbit", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("observe"))
        .stdout(predicate::str::contains("run"))
        .stdout(predicate::str::contains("enable"))
        .stdout(predicate::str::contains("disable"))
        .stdout(predicate::str::contains("stop"))
        .stdout(predicate::str::contains("status"));
}

// ── observe / run: mode dispatch to the script ──────────────────────────────

#[test]
fn observe_invokes_script_with_observe_flag() {
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "observe"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("ARGS:--observe"));
}

#[test]
fn run_invokes_script_with_run_batch_flag() {
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "run"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("ARGS:--run-batch"));
}

#[test]
fn run_one_invokes_script_with_run_one_flag() {
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "run", "--one"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("ARGS:--run-one"));
}

// ── env contract: flags map to env vars, defaults NOT duplicated ────────────

#[test]
fn max_tasks_flag_sets_env_var() {
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "observe", "--max-tasks", "9"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("RUNNER_MAX_TASKS=9"));
}

#[test]
fn push_flag_sets_runner_push() {
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "run", "--push"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .assert()
        .success()
        .stdout(predicate::str::contains("RUNNER_PUSH=1"));
}

#[test]
fn no_flag_leaves_env_to_script_default() {
    // Wrapper must NOT inject a default — when the flag is absent and the var is
    // not in the environment, the script sees it unset and uses its own default.
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "observe"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .env_remove("RUNNER_MAX_TASKS")
        .assert()
        .success()
        .stdout(predicate::str::contains("RUNNER_MAX_TASKS=UNSET"));
}

#[test]
fn ambient_env_var_passes_through() {
    // Pass-through: a RUNNER_* var set in the operator's environment reaches the
    // script unchanged (the contract is preserved without duplicating defaults).
    let proj = stub_project();
    let home = tempfile::tempdir().unwrap();
    brana()
        .args(["orbit", "observe"])
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", proj.path())
        .env("RUNNER_MAX_TASKS", "42")
        .assert()
        .success()
        .stdout(predicate::str::contains("RUNNER_MAX_TASKS=42"));
}

// ── enable / disable: flip the scheduler job (no hand-editing JSON) ─────────

#[test]
fn enable_sets_enabled_true_and_run_batch_arg() {
    let home = home_with_job();
    brana()
        .args(["orbit", "enable"])
        .env("HOME", home.path())
        .assert()
        .success();
    let job = read_job(&home);
    assert_eq!(job["enabled"].as_bool(), Some(true));
    assert!(
        job["command"].as_str().unwrap().contains("--run-batch"),
        "command should be armed to --run-batch, got {:?}",
        job["command"]
    );
    assert!(!job["command"].as_str().unwrap().contains("--observe"));
}

#[test]
fn disable_sets_enabled_false_and_observe_arg() {
    let home = home_with_job();
    // First arm it, then disarm.
    brana().args(["orbit", "enable"]).env("HOME", home.path()).assert().success();
    brana()
        .args(["orbit", "disable"])
        .env("HOME", home.path())
        .assert()
        .success();
    let job = read_job(&home);
    assert_eq!(job["enabled"].as_bool(), Some(false));
    assert!(job["command"].as_str().unwrap().contains("--observe"));
    assert!(!job["command"].as_str().unwrap().contains("--run-batch"));
}

#[test]
fn enable_without_job_fails_cleanly() {
    // No scheduler.json / no job (e.g. scheduler not deployed yet).
    let home = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(home.path().join(".claude/scheduler")).unwrap();
    std::fs::write(
        home.path().join(".claude/scheduler/scheduler.json"),
        r#"{"jobs":{}}"#,
    )
    .unwrap();
    brana()
        .args(["orbit", "enable"])
        .env("HOME", home.path())
        .assert()
        .failure()
        .stderr(predicate::str::contains("autonomous-runner").and(predicate::str::contains("not found")));
}

// ── stop: kill-switch create / clear ────────────────────────────────────────

#[test]
fn stop_creates_kill_switch() {
    let home = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(home.path().join(".claude/scheduler")).unwrap();
    brana()
        .args(["orbit", "stop"])
        .env("HOME", home.path())
        .env_remove("RUNNER_KILL_SWITCH")
        .assert()
        .success();
    assert!(home.path().join(".claude/scheduler/runner.stop").exists());
}

#[test]
fn stop_clear_removes_kill_switch() {
    let home = tempfile::tempdir().unwrap();
    let ks = home.path().join(".claude/scheduler/runner.stop");
    std::fs::create_dir_all(ks.parent().unwrap()).unwrap();
    std::fs::write(&ks, "").unwrap();
    brana()
        .args(["orbit", "stop", "--clear"])
        .env("HOME", home.path())
        .env_remove("RUNNER_KILL_SWITCH")
        .assert()
        .success();
    assert!(!ks.exists());
}

#[test]
fn stop_honors_kill_switch_env_override() {
    let home = tempfile::tempdir().unwrap();
    let custom = tempfile::tempdir().unwrap();
    let ks = custom.path().join("custom.stop");
    brana()
        .args(["orbit", "stop"])
        .env("HOME", home.path())
        .env("RUNNER_KILL_SWITCH", &ks)
        .assert()
        .success();
    assert!(ks.exists(), "kill-switch should honor RUNNER_KILL_SWITCH override");
}

// ── status: reads job + ledger state ────────────────────────────────────────

#[test]
fn status_reports_job_and_kill_switch_state() {
    let home = home_with_job();
    // Seed a ledger so status has something to summarize.
    let led = home.path().join(".claude/scheduler/runner-ledger-20260621.jsonl");
    std::fs::write(
        &led,
        "{\"id\":\"t-1\",\"decision\":\"would-run\",\"reason\":\"x\"}\n\
         {\"id\":\"t-2\",\"decision\":\"excluded\",\"reason\":\"y\"}\n",
    )
    .unwrap();
    brana()
        .args(["orbit", "status"])
        .env("HOME", home.path())
        .env_remove("RUNNER_KILL_SWITCH")
        .assert()
        .success()
        .stdout(predicate::str::contains("autonomous-runner"));
}
