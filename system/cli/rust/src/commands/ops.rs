//! Ops subcommand handlers

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::process::Command;

use crate::themes;
use crate::util::{find_project_root, home, load_scheduler, load_status};

// ── ops commands ────────────────────────────────────────────────────────

pub fn cmd_ops_status(theme: &themes::Theme) {
    let sched = load_scheduler();
    let status = load_status();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    println!("\n{}Scheduler{}", themes::ansi(theme.color("header")), themes::RESET);
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

pub fn cmd_ops_health(theme: &themes::Theme) {
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

    let collisions = find_collisions(&jobs);

    println!("\n{}Scheduler health{}", themes::ansi(theme.color("header")), themes::RESET);
    if failures.is_empty() {
        println!("{}  {} No failures{}", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("{}  {} Failures: {}{}", themes::ansi("red"), theme.icon("blocked"), failures.join(", "), themes::RESET);
    }
    if !skipped.is_empty() {
        println!("{}  {} Skipped: {}{}", themes::ansi("yellow"), theme.icon("pending"), skipped.join(", "), themes::RESET);
    }
    if collisions.is_empty() {
        println!("{}  {} No schedule collisions{}", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("{}  {} Schedule collisions:{}", themes::ansi("red"), theme.icon("blocked"), themes::RESET);
        for (sched, proj, names) in &collisions {
            println!("      {sched} on {proj}: {}", names.join(", "));
        }
    }
    let enabled = jobs.values().filter(|v| v["enabled"].as_bool().unwrap_or(true)).count();
    println!("\n  {enabled} enabled, {} disabled, {} total\n", jobs.len() - enabled, jobs.len());
}

pub fn cmd_ops_collisions(theme: &themes::Theme) {
    let sched = load_scheduler();
    let jobs = sched.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let collisions = find_collisions(&jobs);
    if collisions.is_empty() {
        println!("\n  {}{}  No schedule collisions.{}\n", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("\n{}Schedule collisions{}", themes::ansi(theme.color("header")), themes::RESET);
        for (sched, proj, names) in &collisions {
            println!("{}  {} {sched} on {proj}: {}{}", themes::ansi("red"), theme.icon("blocked"), names.join(", "), themes::RESET);
        }
        println!();
    }
}

pub fn cmd_ops_drift(theme: &themes::Theme) {
    let root = find_project_root().unwrap_or_else(|| { eprintln!("Not in git repo"); std::process::exit(1); });
    let template_path = root.join("system/scheduler/scheduler.template.json");
    let live = load_scheduler();
    let template: HashMap<String, serde_json::Value> = std::fs::read_to_string(&template_path)
        .ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default();

    let tmpl_jobs = template.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let live_jobs = live.get("jobs").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    let mut drifts = vec![];
    let all_names: std::collections::BTreeSet<_> = tmpl_jobs.keys().chain(live_jobs.keys()).collect();
    for name in all_names {
        if !tmpl_jobs.contains_key(name) {
            drifts.push(format!("{}+ {name}: in live but not in template{}", themes::ansi("yellow"), themes::RESET));
        } else if !live_jobs.contains_key(name) {
            drifts.push(format!("{}- {name}: in template but not in live{}", themes::ansi("red"), themes::RESET));
        } else {
            for field in &["schedule", "enabled", "command", "project", "type"] {
                let tv = &tmpl_jobs[name][field];
                let lv = &live_jobs[name][field];
                if tv != lv {
                    drifts.push(format!("{}~ {name}.{field}: template={tv} live={lv}{}", themes::ansi("yellow"), themes::RESET));
                }
            }
        }
    }

    if drifts.is_empty() {
        println!("\n  {}{}  No drift — live matches template.{}\n", themes::ansi("green"), theme.icon("done"), themes::RESET);
    } else {
        println!("\n{}Config drift (template vs live){}", themes::ansi(theme.color("header")), themes::RESET);
        for d in &drifts { println!("  {d}"); }
        println!();
    }
}

pub fn cmd_ops_logs(job_name: &str, tail: usize) {
    let log_dir = home().join(format!(".claude/scheduler/logs/{job_name}"));
    if !log_dir.exists() {
        eprintln!("No logs for '{job_name}'."); std::process::exit(1);
    }
    let mut logs: Vec<_> = std::fs::read_dir(&log_dir).unwrap()
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
}

pub fn cmd_ops_history(job_name: &str, last: usize, theme: &themes::Theme) {
    let log_dir = home().join(format!(".claude/scheduler/logs/{job_name}"));
    if !log_dir.exists() { eprintln!("No history for '{job_name}'."); std::process::exit(1); }
    let mut logs: Vec<_> = std::fs::read_dir(&log_dir).unwrap()
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
}

pub fn cmd_ops_run(job_name: &str) {
    validate_job_name(job_name);
    let unit = format!("brana-sched-{job_name}.service");
    println!("\n  Starting {unit}...");
    let status = Command::new("systemctl").args(["--user", "start", &unit]).status();
    match status {
        Ok(s) if s.success() => println!("  \x1b[32mTriggered. Check: brana ops logs {job_name}\x1b[0m\n"),
        _ => { eprintln!("  \x1b[31mFailed to start {unit}\x1b[0m"); std::process::exit(1); }
    }
}

pub fn cmd_ops_toggle(job_name: &str, enabled: bool) {
    validate_job_name(job_name);
    let config_path = home().join(".claude/scheduler/scheduler.json");
    let mut sched = load_scheduler();
    if let Some(jobs) = sched.get_mut("jobs").and_then(|v| v.as_object_mut()) {
        if let Some(job) = jobs.get_mut(job_name) {
            job["enabled"] = serde_json::Value::Bool(enabled);
        } else {
            eprintln!("Job '{job_name}' not found."); std::process::exit(1);
        }
    }
    std::fs::write(&config_path, serde_json::to_string_pretty(&sched).unwrap() + "\n").ok();
    let action = if enabled { "Enabled" } else { "Disabled" };
    let col = if enabled { "\x1b[32m" } else { "\x1b[33m" };
    println!("\n  {col}{action} '{job_name}'{}", themes::RESET);

    let timer = format!("brana-sched-{job_name}.timer");
    let cmd = if enabled { "start" } else { "stop" };
    if Command::new("systemctl").args(["--user", cmd, &timer]).status().is_ok() {
        println!("  {col}Timer {cmd}ed.{}\n", themes::RESET);
    }
}

pub fn cmd_ops_sync(direction: &str, auto_commit: bool) {
    let root = find_project_root().unwrap_or_else(|| { eprintln!("Not in git repo"); std::process::exit(1); });
    let script = root.join("system/scripts/sync-state.sh");
    if !script.exists() { eprintln!("sync-state.sh not found"); std::process::exit(1); }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).arg(direction).current_dir(&root);
    if auto_commit { cmd.arg("--auto-commit"); }

    println!("\n  Running sync-state.sh {direction}...");
    match cmd.status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        _ => { eprintln!("  \x1b[31mFailed.\x1b[0m"); std::process::exit(1); }
    }
}

pub fn cmd_ops_reindex() {
    let root = find_project_root().unwrap_or_else(|| { eprintln!("Not in git repo"); std::process::exit(1); });
    let script = root.join("system/scripts/index-knowledge.sh");
    if !script.exists() { eprintln!("index-knowledge.sh not found"); std::process::exit(1); }

    println!("\n  Running index-knowledge.sh...");
    match Command::new("bash").arg(&script).current_dir(&root).status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        _ => { eprintln!("  \x1b[31mFailed.\x1b[0m"); std::process::exit(1); }
    }
}

// ── ops metrics ──────────────────────────────────────────────────────────

pub fn cmd_ops_metrics(session_file: &PathBuf) {
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
}

// ── helpers ─────────────────────────────────────────────────────────────

fn find_collisions(jobs: &serde_json::Map<String, serde_json::Value>) -> Vec<(String, String, Vec<String>)> {
    let mut groups: HashMap<(String, String), Vec<String>> = HashMap::new();
    for (name, cfg) in jobs {
        if !cfg["enabled"].as_bool().unwrap_or(true) { continue; }
        let key = (
            cfg["schedule"].as_str().unwrap_or("").to_string(),
            std::path::Path::new(cfg["project"].as_str().unwrap_or(""))
                .file_name().unwrap_or_default().to_string_lossy().to_string(),
        );
        groups.entry(key).or_default().push(name.clone());
    }
    groups.into_iter()
        .filter(|(_, v)| v.len() > 1)
        .map(|((s, p), v)| (s, p, v))
        .collect()
}

fn validate_job_name(name: &str) {
    if !name.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        eprintln!("Invalid job name '{name}'. Use alphanumeric, hyphens, underscores.");
        std::process::exit(1);
    }
}
