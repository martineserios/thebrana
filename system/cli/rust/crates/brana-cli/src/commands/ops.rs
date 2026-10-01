//! Ops subcommand handlers

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::process::Command;

use anyhow::{bail, Context};
use crate::themes;
use crate::util::{find_project_root, home, load_scheduler, load_status};

// ── ops commands ────────────────────────────────────────────────────────

pub fn cmd_ops_status(theme: &themes::Theme, all: bool) -> anyhow::Result<()> {
    print_cc_agents_status(theme);
    print_env_status(theme, "local", &load_scheduler(), &load_status());

    if all {
        match fetch_remote_status("oracle-hub") {
            Ok((remote_sched, remote_status)) => {
                print_env_status(theme, "oracle", &remote_sched, &remote_status);
            }
            Err(e) => {
                println!("{}  {} oracle: {}{}\n",
                    themes::ansi("red"), theme.icon("blocked"), e, themes::RESET);
            }
        }
    }
    Ok(())
}

fn print_cc_agents_status(theme: &themes::Theme) {
    let output = Command::new("claude")
        .args(["agents", "--json"])
        .output();

    let json_bytes = match output {
        Ok(ref o) if o.status.success() && !o.stdout.is_empty() => &o.stdout,
        _ => return,
    };

    let agents: Vec<serde_json::Value> = match serde_json::from_slice(json_bytes) {
        Ok(v) => v,
        Err(_) => return,
    };

    if agents.is_empty() {
        return;
    }

    println!("\n{}CC Agents{}", themes::ansi(theme.color("header")), themes::RESET);

    for agent in &agents {
        let status = agent["status"].as_str().unwrap_or("unknown");
        let waiting_for = agent["waitingFor"].as_str().unwrap_or("");
        let cwd = agent["cwd"].as_str().unwrap_or("?");
        let project = std::path::Path::new(cwd)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(cwd);
        let pid = agent["pid"].as_u64().unwrap_or(0);

        let (ic, col) = if !waiting_for.is_empty() {
            (theme.icon("blocked"), themes::ansi("red"))
        } else {
            match status {
                "busy" => (theme.icon("pending"), themes::ansi("yellow")),
                "idle" => (theme.icon("done"), themes::ansi("dim")),
                _ => (theme.icon("pending"), themes::ansi("dim")),
            }
        };

        if !waiting_for.is_empty() {
            println!("{col}  {ic} {status:<8} {project:<20} BLOCKED: {waiting_for}  (pid {pid}){}", themes::RESET);
        } else {
            println!("{col}  {ic} {status:<8} {project:<20} (pid {pid}){}", themes::RESET);
        }
    }
    println!();
}

fn print_env_status(
    theme: &themes::Theme,
    env_name: &str,
    sched: &HashMap<String, serde_json::Value>,
    status: &HashMap<String, serde_json::Value>,
) {
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    println!("\n{}Scheduler [{}]{}", themes::ansi(theme.color("header")), env_name, themes::RESET);
    for (name, cfg) in jobs.iter() {
        let enabled = cfg["enabled"].as_bool().unwrap_or(true);
        let job_st = status.get(name).and_then(|v| v["status"].as_str()).unwrap_or("—");
        let ts = status.get(name).and_then(|v| v["timestamp"].as_str()).unwrap_or("");
        let short_ts = if ts.len() > 16 { &ts[5..16] } else { ts };
        let schedule = cfg["schedule"].as_str().unwrap_or("—");
        let ic = if !enabled { theme.icon("parked") }
            else { match job_st { "SUCCESS" => theme.icon("done"), "FAILED"|"TIMEOUT" => theme.icon("blocked"), _ => theme.icon("pending") } };
        let col = if !enabled { themes::ansi("dim") }
            else { match job_st { "SUCCESS" => themes::ansi("green"), "FAILED"|"TIMEOUT" => themes::ansi("red"), _ => themes::ansi("yellow") } };
        let disabled = if !enabled { "  [disabled]" } else { "" };
        println!("{col}  {ic} {name:<24} {schedule:<24} {job_st:<10} {short_ts}{disabled}{}", themes::RESET);
    }
    println!();
}

fn fetch_remote_status(host: &str) -> Result<(HashMap<String, serde_json::Value>, HashMap<String, serde_json::Value>), String> {
    let output = Command::new("ssh")
        .args(["-o", "ConnectTimeout=5", "-o", "BatchMode=yes", host,
            "cat ~/.claude/scheduler/scheduler.json 2>/dev/null; echo '---SEPARATOR---'; cat ~/.claude/scheduler/last-status.json 2>/dev/null"])
        .output()
        .map_err(|e| format!("SSH failed: {e}"))?;

    if !output.status.success() {
        return Err(format!("unreachable (SSH exit {})", output.status.code().unwrap_or(-1)));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let parts: Vec<&str> = stdout.splitn(2, "---SEPARATOR---").collect();
    if parts.len() < 2 {
        return Err("unexpected output format".into());
    }

    let sched: HashMap<String, serde_json::Value> = serde_json::from_str(parts[0].trim())
        .map_err(|e| format!("parse scheduler.json: {e}"))?;
    let status: HashMap<String, serde_json::Value> = serde_json::from_str(parts[1].trim())
        .unwrap_or_default();

    Ok((sched, status))
}

pub fn cmd_ops_health(theme: &themes::Theme) -> anyhow::Result<()> {
    let sched = load_scheduler();
    let status = load_status();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    let mut failures = vec![];
    let mut skipped = vec![];
    for (name, info) in &status {
        if let Some(st) = info["status"].as_str() {
            match st {
                "FAILED" => failures.push(name.as_str()),
                "SKIPPED" => skipped.push(name.as_str()),
                _ => {}
            }
        }
    }

    let report = brana_core::scheduler::check_health(&jobs, &status);

    println!("\n{}Scheduler health{}", themes::ansi(theme.color("header")), themes::RESET);
    if report.failures.is_empty() {
        println!("{}  {} No failures{}", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("{}  {} Failures: {}{}", themes::ansi("red"), theme.icon("blocked"), report.failures.join(", "), themes::RESET);
    }
    if !report.skipped.is_empty() {
        println!("{}  {} Skipped: {}{}", themes::ansi("yellow"), theme.icon("pending"), report.skipped.join(", "), themes::RESET);
    }
    if !report.never_run.is_empty() {
        println!("{}  {} Never run: {}{}", themes::ansi("yellow"), theme.icon("pending"), report.never_run.join(", "), themes::RESET);
    }
    if report.collisions.is_empty() {
        println!("{}  {} No schedule collisions{}", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("{}  {} Schedule collisions:{}", themes::ansi("red"), theme.icon("blocked"), themes::RESET);
        for c in &report.collisions {
            println!("      {} on {}: {}", c.schedule, c.project, c.jobs.join(", "));
        }
    }
    println!("\n  {} enabled, {} disabled, {} total\n", report.enabled_count, report.disabled_count, report.total_count);
    Ok(())
}

pub fn cmd_ops_collisions(theme: &themes::Theme) -> anyhow::Result<()> {
    let sched = load_scheduler();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let collisions = brana_core::scheduler::find_collisions(&jobs);
    if collisions.is_empty() {
        println!("\n  {}{}  No schedule collisions.{}\n", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("\n{}Schedule collisions{}", themes::ansi(theme.color("header")), themes::RESET);
        for c in &collisions {
            println!("{}  {} {} on {}: {}{}", themes::ansi("red"), theme.icon("blocked"), c.schedule, c.project, c.jobs.join(", "), themes::RESET);
        }
        println!();
    }
    Ok(())
}

pub fn cmd_ops_drift(theme: &themes::Theme) -> anyhow::Result<()> {
    let root = find_project_root().context("Not in git repo")?;
    let template_path = root.join("system/scheduler/scheduler.template.json");
    let live = load_scheduler();
    let template: HashMap<String, serde_json::Value> = std::fs::read_to_string(&template_path)
        .ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default();

    let tmpl_jobs = template.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let live_jobs = live.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    let drifts = brana_core::scheduler::detect_drift(&tmpl_jobs, &live_jobs);

    if drifts.is_empty() {
        println!("\n  {}{}  No drift — live matches template.{}\n", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("\n{}Config drift (template vs live){}", themes::ansi(theme.color("header")), themes::RESET);
        for d in &drifts {
            let line = match d.kind {
                brana_core::scheduler::DriftKind::Added => format!("{}+ {}: in live but not in template{}", themes::ansi("yellow"), d.job_name, themes::RESET),
                brana_core::scheduler::DriftKind::Removed => format!("{}- {}: in template but not in live{}", themes::ansi("red"), d.job_name, themes::RESET),
                brana_core::scheduler::DriftKind::Changed => format!("{}~ {}.{}: template={} live={}{}", themes::ansi("yellow"), d.job_name, d.field.as_deref().unwrap_or("?"), d.template_value.as_deref().unwrap_or("?"), d.live_value.as_deref().unwrap_or("?"), themes::RESET),
            };
            println!("  {line}");
        }
        println!();
    }
    Ok(())
}

pub fn cmd_ops_logs(job_name: &str, tail: usize) -> anyhow::Result<()> {
    let log_dir = home().join(format!(".claude/scheduler/logs/{job_name}"));
    if !log_dir.exists() {
        bail!("No logs for '{job_name}'.");
    }
    let mut logs: Vec<_> = std::fs::read_dir(&log_dir).context("reading log directory")?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |x| x == "log"))
        .collect();
    logs.sort_by_key(|e| std::cmp::Reverse(e.file_name()));
    if let Some(latest) = logs.first() {
        let content = std::fs::read_to_string(latest.path()).unwrap_or_default();
        let lines: Vec<_> = content.lines().collect();
        let start = if lines.len() > tail { lines.len() - tail } else { 0 };
        println!("\n  \x1b[2m{}\x1b[0m\n", latest.file_name().to_string_lossy());
        for line in &lines[start..] {
            if line.contains("SUCCESS") { println!("  \x1b[32m{line}\x1b[0m"); }
            else if line.contains("FAILED") || line.contains("ERROR") { println!("  \x1b[31m{line}\x1b[0m"); }
            else { println!("  {line}"); }
        }
        println!();
    }
    Ok(())
}

pub fn cmd_ops_history(job_name: &str, last: usize, theme: &themes::Theme) -> anyhow::Result<()> {
    let log_dir = home().join(format!(".claude/scheduler/logs/{job_name}"));
    if !log_dir.exists() { bail!("No history for '{job_name}'."); }
    let mut logs: Vec<_> = std::fs::read_dir(&log_dir).context("reading log directory")?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().map_or(false, |x| x == "log"))
        .collect();
    logs.sort_by_key(|e| std::cmp::Reverse(e.file_name()));

    println!("\n{}History: {job_name} (last {}){}", themes::ansi(theme.color("header")), logs.len().min(last), themes::RESET);
    for entry in logs.iter().take(last) {
        let content = std::fs::read_to_string(entry.path()).unwrap_or_default();
        let (st, col) = if content.contains("SUCCESS") { ("SUCCESS", "green") }
            else if content.contains("FAILED") { ("FAILED", "red") }
            else if content.contains("TIMEOUT") { ("TIMEOUT", "red") }
            else if content.contains("SKIPPED") { ("SKIPPED", "dim") }
            else { ("UNKNOWN", "yellow") };
        let ic = match st { "SUCCESS" => theme.icon("done"), "FAILED"|"TIMEOUT" => theme.icon("blocked"), _ => theme.icon("pending") };
        let date = entry.path().file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        println!("{}{ic} {date}  {st}{}", themes::ansi(col), themes::RESET);
    }
    println!();
    Ok(())
}

// ── scheduler backend (t-3375, ADR-071 amendment) ───────────────────────────
// A host has a scheduler backend iff `systemctl` is an executable on PATH (capability, not OS
// name). `BRANA_SCHEDULER_BACKEND=none|systemd|auto` overrides. Mirrors
// system/hooks/lib/scheduler-backend.sh — keep the wording in step (a test pins it).

/// True iff an executable regular file `name` exists in one of the `path` dirs (empty entries
/// are ignored). Pure over its arguments so tests never touch the process environment.
fn on_path(name: &str, path: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.split(':').filter(|d| !d.is_empty()).any(|d| {
        std::fs::metadata(PathBuf::from(d).join(name))
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    })
}

fn backend_available_with(override_: Option<&str>, path: &str) -> bool {
    match override_ {
        Some("none") => false,
        Some("systemd") => true,
        _ => on_path("systemctl", path),
    }
}

/// PATH to probe: the environment's, or a standard default when it is unset/empty/non-UTF-8 — spawning
/// `systemctl` would still resolve via the default search path, so the probe must not say "absent".
fn path_or_default(path: Option<String>) -> String {
    match path {
        Some(p) if !p.is_empty() => p,
        _ => "/usr/bin:/bin".to_string(),
    }
}

/// Did `systemctl --user start|stop <timer>` achieve what the user asked? A zero exit does; so does
/// exit 5 on STOP ("unit not loaded": disabling a never-deployed timer leaves it disabled).
pub(crate) fn systemctl_succeeded(starting: bool, code: Option<i32>) -> bool {
    matches!((starting, code), (_, Some(0)) | (false, Some(5)))
}

pub(crate) fn scheduler_backend_available() -> bool {
    let ov = std::env::var("BRANA_SCHEDULER_BACKEND").ok();
    backend_available_with(ov.as_deref(), &path_or_default(std::env::var("PATH").ok()))
}

fn backend_note(override_: Option<&str>) -> String {
    let why = if override_ == Some("none") {
        "opted out via BRANA_SCHEDULER_BACKEND=none"
    } else {
        "systemctl not found"
    };
    format!("no scheduler backend on this host ({why}): unattended jobs run on the always-on host, not here — see ADR-071 amendment.")
}

fn current_note() -> String {
    backend_note(std::env::var("BRANA_SCHEDULER_BACKEND").ok().as_deref())
}

fn run_unit_checked(available: bool, job_name: &str) -> anyhow::Result<()> {
    if !available {
        bail!("{}", current_note());
    }
    let unit = format!("brana-sched-{job_name}.service");
    println!("\n  Starting {unit}...");
    match Command::new("systemctl").args(["--user", "start", &unit]).status() {
        Ok(s) if s.success() => println!("  \x1b[32mTriggered. Check: brana ops logs {job_name}\x1b[0m\n"),
        _ => bail!("Failed to start {unit}"),
    }
    Ok(())
}

pub fn cmd_ops_run(job_name: &str) -> anyhow::Result<()> {
    validate_job_name(job_name)?;
    run_unit_checked(scheduler_backend_available(), job_name)
}

/// What `enable`/`disable` tells the user after `scheduler.json` was edited. Pure so the three
/// outcomes are testable: no backend (nothing scheduled), timer changed (exit 0), timer change
/// failed (the old code counted a merely-spawned `systemctl` as success).
pub(crate) fn toggle_outcome(available: bool, enabled: bool, job_name: &str, systemctl_ok: bool) -> String {
    let (verb, done) = if enabled { ("start", "started") } else { ("stop", "stopped") };
    if !available {
        let state = if enabled { "enabled" } else { "disabled" };
        format!("'{job_name}' {state} in scheduler.json — nothing was scheduled here: {}", current_note())
    } else if systemctl_ok {
        format!("Timer {done}.")
    } else {
        format!("Timer {verb} FAILED — scheduler.json was updated but the systemd timer state was not changed. Check: systemctl --user status brana-sched-{job_name}.timer")
    }
}

pub fn cmd_ops_toggle(job_name: &str, enabled: bool) -> anyhow::Result<()> {
    validate_job_name(job_name)?;
    let config_path = home().join(".claude/scheduler/scheduler.json");
    let mut sched = load_scheduler();
    if let Some(jobs) = sched.get_mut("jobs").and_then(|v| v.as_object_mut()) {
        if let Some(job) = jobs.get_mut(job_name) {
            job["enabled"] = serde_json::Value::Bool(enabled);
        } else {
            bail!("Job '{job_name}' not found.");
        }
    }
    std::fs::write(&config_path, serde_json::to_string_pretty(&sched).unwrap() + "\n").ok();
    let action = if enabled { "Enabled" } else { "Disabled" };
    let col = if enabled { "\x1b[32m" } else { "\x1b[33m" };
    println!("\n  {col}{action} '{job_name}'{}", themes::RESET);

    let available = scheduler_backend_available();
    let ok = available && {
        let timer = format!("brana-sched-{job_name}.timer");
        let cmd = if enabled { "start" } else { "stop" };
        Command::new("systemctl").args(["--user", cmd, &timer]).status().map(|s| systemctl_succeeded(enabled, s.code())).unwrap_or(false)
    };
    let msg = toggle_outcome(available, enabled, job_name, ok);
    let msg_col = if available && !ok { "\x1b[31m" } else { col };
    println!("  {msg_col}{msg}{}\n", themes::RESET);
    Ok(())
}

pub fn cmd_ops_sync(direction: &str, auto_commit: bool) -> anyhow::Result<()> {
    let root = find_project_root().context("Not in git repo")?;
    let script = root.join("system/scripts/sync-state.sh");
    if !script.exists() { bail!("sync-state.sh not found"); }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).arg(direction).current_dir(&root);
    if auto_commit { cmd.arg("--auto-commit"); }

    println!("\n  Running sync-state.sh {direction}...");
    match cmd.status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        _ => bail!("sync-state.sh {direction} failed"),
    }
    Ok(())
}

pub fn cmd_ops_reindex() -> anyhow::Result<()> {
    let root = find_project_root().context("Not in git repo")?;
    let script = root.join("system/scripts/index-knowledge.sh");
    if !script.exists() { bail!("index-knowledge.sh not found"); }

    println!("\n  Running index-knowledge.sh...");
    match Command::new("bash").arg(&script).current_dir(&root).status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        _ => bail!("index-knowledge.sh failed"),
    }
    Ok(())
}

// ── ops metrics ──────────────────────────────────────────────────────────

pub fn cmd_ops_metrics(session_file: &PathBuf) -> anyhow::Result<()> {
    let content = std::fs::read_to_string(session_file).unwrap_or_default();
    let events: Vec<serde_json::Value> = content
        .lines()
        .filter_map(|l| serde_json::from_str(l).ok())
        .collect();

    let total = events.len();
    let successes = events.iter().filter(|e| e["outcome"].as_str() == Some("success")).count();
    let failures = events.iter().filter(|e| matches!(e["outcome"].as_str(), Some("failure" | "test-fail" | "lint-fail"))).count();
    let corrections = events.iter().filter(|e| e["outcome"].as_str() == Some("correction")).count();
    let test_writes = events.iter().filter(|e| e["outcome"].as_str() == Some("test-write")).count();
    let cascades = events.iter().filter(|e| e["cascade"].as_bool() == Some(true)).count();
    let pr_creates = events.iter().filter(|e| e["outcome"].as_str() == Some("pr-create")).count();
    let test_passes = events.iter().filter(|e| e["outcome"].as_str() == Some("test-pass")).count();
    let test_fails = events.iter().filter(|e| e["outcome"].as_str() == Some("test-fail")).count();
    let lint_passes = events.iter().filter(|e| e["outcome"].as_str() == Some("lint-pass")).count();
    let lint_fails = events.iter().filter(|e| e["outcome"].as_str() == Some("lint-fail")).count();
    let edits = events.iter().filter(|e| matches!(e["tool"].as_str(), Some("Edit" | "Write"))).count();
    let delegations = events.iter().filter(|e| e["tool"].as_str() == Some("Task")).count();

    let tools: std::collections::BTreeSet<&str> = events.iter().filter_map(|e| e["tool"].as_str()).collect();
    let files: std::collections::BTreeSet<&str> = events.iter()
        .filter_map(|e| e["detail"].as_str())
        .filter(|d| !d.is_empty())
        .collect();
    let files_vec: Vec<&str> = files.into_iter().take(10).collect();

    let correction_rate = if edits > 0 { corrections as f64 / edits as f64 } else { 0.0 };
    let test_write_rate = if edits > 0 { test_writes as f64 / edits as f64 } else { 0.0 };
    let cascade_rate = if failures > 0 { cascades as f64 / failures as f64 } else { 0.0 };

    let mut fail_files: HashSet<String> = HashSet::new();
    let mut auto_fixes = 0usize;
    for e in &events {
        let detail = e["detail"].as_str().unwrap_or("").to_string();
        match e["outcome"].as_str() {
            Some("failure" | "test-fail" | "lint-fail") => { fail_files.insert(detail); }
            Some("success" | "correction" | "test-pass" | "lint-pass") => {
                if fail_files.remove(&detail) { auto_fixes += 1; }
            }
            _ => {}
        }
    }
    let auto_fix_rate = if failures > 0 { auto_fixes as f64 / failures as f64 } else { 0.0 };

    let test_total = test_passes + test_fails;
    let test_pass_rate = if test_total > 0 { format!("{:.2}", test_passes as f64 / test_total as f64) } else { "N/A".into() };
    let lint_total = lint_passes + lint_fails;
    let lint_pass_rate = if lint_total > 0 { format!("{:.2}", lint_passes as f64 / lint_total as f64) } else { "N/A".into() };

    let output = serde_json::json!({
        "events": total,
        "successes": successes,
        "failures": failures,
        "corrections": corrections,
        "test_writes": test_writes,
        "cascades": cascades,
        "pr_creates": pr_creates,
        "edits": edits,
        "test_passes": test_passes,
        "test_fails": test_fails,
        "lint_passes": lint_passes,
        "lint_fails": lint_fails,
        "delegations": delegations,
        "flywheel": {
            "correction_rate": format!("{:.2}", correction_rate),
            "auto_fix_rate": format!("{:.2}", auto_fix_rate),
            "test_write_rate": format!("{:.2}", test_write_rate),
            "cascade_rate": format!("{:.2}", cascade_rate),
            "test_pass_rate": test_pass_rate,
            "lint_pass_rate": lint_pass_rate,
            "delegations": delegations,
            "pr_creates": pr_creates,
        },
        "tools": tools.into_iter().collect::<Vec<_>>().join(","),
        "files": files_vec.join(","),
    });

    println!("{}", serde_json::to_string(&output).unwrap());
    Ok(())
}

// ── helpers ─────────────────────────────────────────────────────────────

fn validate_job_name(name: &str) -> anyhow::Result<()> {
    brana_core::scheduler::validate_job_name(name)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

#[cfg(test)]
mod scheduler_backend_tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn dir_with(name: &str, mode: u32) -> tempfile::TempDir {
        let d = tempfile::tempdir().unwrap();
        let f = d.path().join(name);
        std::fs::write(&f, "#!/bin/sh\nexit 0\n").unwrap();
        std::fs::set_permissions(&f, std::fs::Permissions::from_mode(mode)).unwrap();
        d
    }

    #[test]
    fn on_path_finds_an_executable() {
        let d = dir_with("systemctl", 0o755);
        assert!(on_path("systemctl", d.path().to_str().unwrap()));
    }

    #[test]
    fn on_path_ignores_a_non_executable_file() {
        let d = dir_with("systemctl", 0o644);
        assert!(!on_path("systemctl", d.path().to_str().unwrap()));
    }

    #[test]
    fn on_path_misses_when_absent_or_path_empty() {
        let d = dir_with("other", 0o755);
        assert!(!on_path("systemctl", d.path().to_str().unwrap()));
        assert!(!on_path("systemctl", ""));
    }

    #[test]
    fn on_path_searches_every_dir_in_order() {
        let empty = tempfile::tempdir().unwrap();
        let has = dir_with("systemctl", 0o755);
        let path = format!("{}:{}", empty.path().display(), has.path().display());
        assert!(on_path("systemctl", &path));
    }

    #[test]
    fn override_none_beats_a_present_systemctl() {
        let d = dir_with("systemctl", 0o755);
        assert!(!backend_available_with(Some("none"), d.path().to_str().unwrap()));
    }

    #[test]
    fn override_systemd_beats_an_absent_systemctl() {
        assert!(backend_available_with(Some("systemd"), ""));
    }

    #[test]
    fn auto_bogus_and_unset_probe_the_path() {
        let d = dir_with("systemctl", 0o755);
        let p = d.path().to_str().unwrap();
        for o in [Some("auto"), Some("bogus"), None] {
            assert!(backend_available_with(o, p), "{o:?} with systemctl");
            assert!(!backend_available_with(o, ""), "{o:?} without systemctl");
        }
    }

    #[test]
    fn note_matches_the_shell_wording_and_names_an_opt_out() {
        let plain = backend_note(None);
        assert!(plain.contains("no scheduler backend on this host (systemctl not found)"));
        assert!(plain.contains("always-on host") && plain.contains("ADR-071"));
        assert!(backend_note(Some("none")).contains("BRANA_SCHEDULER_BACKEND=none"));
    }

    #[test]
    fn systemctl_start_needs_a_zero_exit() {
        assert!(systemctl_succeeded(true, Some(0)));
        assert!(!systemctl_succeeded(true, Some(1)));
        assert!(!systemctl_succeeded(true, Some(5)), "start of an unloaded unit is a real failure");
        assert!(!systemctl_succeeded(true, None), "killed by signal / never ran");
    }

    #[test]
    fn systemctl_stop_of_a_never_deployed_timer_is_not_a_failure() {
        // `systemctl --user stop X.timer` exits 5 when the unit is not loaded: disabling a job whose
        // timer was never deployed leaves it disabled — the user's goal is met.
        assert!(systemctl_succeeded(false, Some(0)));
        assert!(systemctl_succeeded(false, Some(5)));
        assert!(!systemctl_succeeded(false, Some(1)));
        assert!(!systemctl_succeeded(false, None));
    }

    #[test]
    fn unset_path_falls_back_to_a_standard_one_instead_of_reading_as_no_backend() {
        // With PATH unset, exec would still find systemctl via the default search path; the probe
        // must agree (it used to see "" and report no backend, then enable/disable stopped touching timers).
        assert_eq!(path_or_default(None), "/usr/bin:/bin");
        assert_eq!(path_or_default(Some("/opt/x:/y".to_string())), "/opt/x:/y");
        assert_eq!(path_or_default(Some(String::new())), "/usr/bin:/bin");
    }

    #[test]
    fn run_bails_with_the_note_when_there_is_no_backend() {
        let err = run_unit_checked(false, "job1").unwrap_err().to_string();
        assert!(err.contains("no scheduler backend"), "{err}");
    }

    #[test]
    fn toggle_reports_nothing_scheduled_when_there_is_no_backend() {
        let msg = toggle_outcome(false, true, "job1", true);
        assert!(msg.contains("nothing was scheduled") && msg.contains("no scheduler backend"), "{msg}");
    }

    #[test]
    fn toggle_requires_a_zero_exit_when_a_backend_exists() {
        // The old code treated Command::status().is_ok() (process spawned) as success.
        let ok = toggle_outcome(true, true, "job1", true);
        assert!(ok.contains("Timer started"), "{ok}");
        let failed = toggle_outcome(true, true, "job1", false);
        assert!(failed.contains("FAILED") && !failed.contains("Timer started"), "{failed}");
    }
}

