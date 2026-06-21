//! Orbit subcommand handlers — the operator front-door for the UNATTENDED tier
//! of the autonomous runner (t-2197).
//!
//! This is a *thin control surface* over `system/scripts/autonomous-runner.sh`:
//! the script stays the engine, the `brana ops` scheduler stays the host. Flags
//! map to the runner's `RUNNER_*` env contract and are set ONLY when the operator
//! passes them — the script's own defaults are never duplicated here.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::process::Command;

use anyhow::{bail, Context};

use crate::themes;
use crate::util::{find_project_root, home, load_scheduler};

const JOB: &str = "autonomous-runner";
const SCRIPT_REL: &str = "system/scripts/autonomous-runner.sh";

// ── observe / run: shell out to the engine ─────────────────────────────────

/// Run the runner script with `mode_arg`, setting only the env vars the operator
/// explicitly passed. Unset flags are left to the script's defaults — the
/// `RUNNER_*` contract is preserved without duplicating a single default here.
/// The ambient environment is inherited, so any `RUNNER_*` var set in the
/// operator's shell still passes through unchanged.
fn run_script(mode_arg: &str, env: &[(&str, String)]) -> anyhow::Result<()> {
    let root = find_project_root()
        .context("Not in a brana project (no git root or CLAUDE_PROJECT_DIR)")?;
    let script = root.join(SCRIPT_REL);
    if !script.exists() {
        bail!("runner not found at {}", script.display());
    }
    let mut cmd = Command::new("bash");
    cmd.arg(&script).arg(mode_arg).current_dir(&root);
    for (k, v) in env {
        cmd.env(*k, v.as_str());
    }
    match cmd.status() {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => bail!("runner exited with code {}", s.code().unwrap_or(-1)),
        Err(e) => bail!("failed to launch runner: {e}"),
    }
}

pub fn cmd_orbit_observe(max_tasks: Option<usize>) -> anyhow::Result<()> {
    let mut env = vec![];
    if let Some(n) = max_tasks {
        env.push(("RUNNER_MAX_TASKS", n.to_string()));
    }
    run_script("--observe", &env)
}

pub fn cmd_orbit_run(
    one: bool,
    push: bool,
    max_tasks: Option<usize>,
    max_fails: Option<usize>,
) -> anyhow::Result<()> {
    let mut env = vec![];
    if push {
        env.push(("RUNNER_PUSH", "1".to_string()));
    }
    if let Some(n) = max_tasks {
        env.push(("RUNNER_MAX_TASKS", n.to_string()));
    }
    if let Some(n) = max_fails {
        env.push(("RUNNER_MAX_FAILS", n.to_string()));
    }
    let mode = if one { "--run-one" } else { "--run-batch" };
    run_script(mode, &env)
}

// ── enable / disable: flip the scheduler job ───────────────────────────────

/// Arm/disarm the `autonomous-runner` scheduler job: flip `enabled` and swap the
/// run mode in its `command` (`--observe` ↔ `--run-batch`) — the two edits the
/// operator otherwise makes by hand in scheduler.json.
pub fn cmd_orbit_toggle(enabled: bool) -> anyhow::Result<()> {
    let config_path = home().join(".claude/scheduler/scheduler.json");
    let mut sched = load_scheduler();
    {
        let job = sched
            .get_mut("jobs")
            .and_then(|v| v.as_object_mut())
            .and_then(|jobs| jobs.get_mut(JOB))
            .with_context(|| {
                format!("scheduler job '{JOB}' not found — deploy the scheduler first (bootstrap.sh / brana ops sync)")
            })?;
        job["enabled"] = serde_json::Value::Bool(enabled);
        if let Some(cmd) = job.get("command").and_then(|c| c.as_str()) {
            let swapped = if enabled {
                cmd.replace("--observe", "--run-batch")
            } else {
                cmd.replace("--run-batch", "--observe")
            };
            job["command"] = serde_json::Value::String(swapped);
        }
    }
    std::fs::write(&config_path, serde_json::to_string_pretty(&sched).unwrap() + "\n")
        .with_context(|| format!("writing {}", config_path.display()))?;

    let (action, mode, col) = if enabled {
        ("Armed", "--run-batch", "\x1b[32m")
    } else {
        ("Disarmed", "--observe", "\x1b[33m")
    };
    println!("\n  {col}{action} '{JOB}' ({mode}){}", themes::RESET);

    // Mirror `brana ops`: start/stop the systemd timer if present (best-effort).
    let timer = format!("brana-sched-{JOB}.timer");
    let sub = if enabled { "start" } else { "stop" };
    if Command::new("systemctl").args(["--user", sub, &timer]).status().is_ok() {
        println!("  {col}Timer {sub}ed.{}\n", themes::RESET);
    } else {
        println!();
    }
    Ok(())
}

// ── stop: the kill-switch ──────────────────────────────────────────────────

/// Where the runner looks for its kill-switch: `RUNNER_KILL_SWITCH` if set,
/// else `~/.claude/scheduler/runner.stop` (the script's default).
fn kill_switch_path() -> PathBuf {
    match std::env::var("RUNNER_KILL_SWITCH") {
        Ok(p) if !p.is_empty() => PathBuf::from(p),
        _ => home().join(".claude/scheduler/runner.stop"),
    }
}

pub fn cmd_orbit_stop(clear: bool) -> anyhow::Result<()> {
    let ks = kill_switch_path();
    if clear {
        if ks.exists() {
            std::fs::remove_file(&ks).with_context(|| format!("removing {}", ks.display()))?;
            println!("\n  \x1b[32mKill-switch cleared — runner re-armed.\x1b[0m\n");
        } else {
            println!("\n  \x1b[2mNo kill-switch present ({}).\x1b[0m\n", ks.display());
        }
    } else {
        if let Some(parent) = ks.parent() {
            std::fs::create_dir_all(parent).ok();
        }
        std::fs::write(&ks, "stopped via brana orbit stop\n")
            .with_context(|| format!("creating {}", ks.display()))?;
        println!("\n  \x1b[33mKill-switch set — a running batch halts cleanly and new batches are blocked.\x1b[0m");
        println!("  \x1b[2mClear with: brana orbit stop --clear\x1b[0m\n");
    }
    Ok(())
}

// ── status: job + kill-switch + latest ledger ──────────────────────────────

pub fn cmd_orbit_status(theme: &themes::Theme) -> anyhow::Result<()> {
    let sched = load_scheduler();
    let job = sched
        .get("jobs")
        .and_then(|v| v.as_object())
        .and_then(|jobs| jobs.get(JOB));

    println!(
        "\n{}Orbit — autonomous runner{}",
        themes::ansi(theme.color("header")),
        themes::RESET
    );

    match job {
        Some(j) => {
            let enabled = j["enabled"].as_bool().unwrap_or(false);
            let command = j["command"].as_str().unwrap_or("");
            let mode = if command.contains("--run-batch") {
                "run-batch"
            } else if command.contains("--run-one") {
                "run-one"
            } else {
                "observe"
            };
            let schedule = j["schedule"].as_str().unwrap_or("—");
            let (ic, col, state) = if enabled {
                (theme.icon("done"), themes::ansi("green"), "ARMED")
            } else {
                (theme.icon("parked"), themes::ansi("dim"), "disarmed")
            };
            println!(
                "{col}  {ic} job {JOB}: {state} · mode={mode} · schedule={schedule}{}",
                themes::RESET
            );
        }
        None => {
            println!(
                "{}  {} job '{JOB}' not in scheduler (not deployed){}",
                themes::ansi("yellow"),
                theme.icon("pending"),
                themes::RESET
            );
        }
    }

    let ks = kill_switch_path();
    if ks.exists() {
        println!(
            "{}  {} kill-switch: PRESENT — batches blocked ({}){}",
            themes::ansi("red"),
            theme.icon("blocked"),
            ks.display(),
            themes::RESET
        );
    } else {
        println!(
            "{}  {} kill-switch: clear{}",
            themes::ansi("green"),
            theme.icon("done"),
            themes::RESET
        );
    }

    match latest_ledger() {
        Some(path) => {
            let counts = ledger_counts(&path);
            println!("\n  {}ledger: {}{}", themes::ansi("dim"), path.display(), themes::RESET);
            if counts.is_empty() {
                println!("    (empty)");
            } else {
                let summary: Vec<String> = counts.iter().map(|(k, v)| format!("{k}={v}")).collect();
                println!("    {}", summary.join("  "));
            }
        }
        None => println!("\n  {}ledger: none yet{}", themes::ansi("dim"), themes::RESET),
    }
    println!();
    Ok(())
}

/// The most recent date-stamped runner ledger, or `RUNNER_LEDGER` if set.
fn latest_ledger() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("RUNNER_LEDGER") {
        if !p.is_empty() {
            let pb = PathBuf::from(p);
            return pb.exists().then_some(pb);
        }
    }
    let dir = home().join(".claude/scheduler");
    let mut ledgers: Vec<PathBuf> = std::fs::read_dir(&dir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with("runner-ledger-") && n.ends_with(".jsonl"))
                .unwrap_or(false)
        })
        .collect();
    ledgers.sort();
    ledgers.pop()
}

/// Tally a ledger's entries by `decision` (would-run / would-park / ran /
/// parked / excluded / failed).
fn ledger_counts(path: &PathBuf) -> BTreeMap<String, usize> {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    if let Ok(content) = std::fs::read_to_string(path) {
        for line in content.lines() {
            if line.trim().is_empty() {
                continue;
            }
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
                let d = v["decision"].as_str().unwrap_or("?").to_string();
                *counts.entry(d).or_insert(0) += 1;
            }
        }
    }
    counts
}
