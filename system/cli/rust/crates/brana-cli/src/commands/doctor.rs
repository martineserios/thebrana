//! Doctor command handler

use std::process::Command;

use crate::tasks;
use crate::themes;
use crate::util::{find_project_root, home, load_scheduler};

pub fn cmd_doctor(theme: &themes::Theme) {
    let ok = theme.icon("done");
    let fail = theme.icon("blocked");
    let mut passed = 0;
    let mut total = 0;

    let mut check = |name: &str, result: bool, detail: &str| {
        total += 1;
        let (ic, col) = if result { passed += 1; (ok, "\x1b[32m") } else { (fail, "\x1b[31m") };
        let d = if detail.is_empty() { String::new() } else { format!("  ({detail})") };
        println!("{col}  {ic} {name}{d}{}", themes::RESET);
    };

    println!("\n\x1b[1mbrana doctor\x1b[0m (Rust)\n");

    let root = find_project_root();
    check("Git project detected", root.is_some(),
        &root.as_ref().map(|r| r.file_name().unwrap_or_default().to_string_lossy().to_string()).unwrap_or_default());

    if let Some(ref root) = root {
        let tf = root.join(".claude/tasks.json");
        let tasks_ok = tf.exists();
        if tasks_ok {
            let data = tasks::load_tasks(&tf);
            let count = data.as_ref().map(|d| d.tasks.len()).unwrap_or(0);
            check("tasks.json exists", true, &format!("{count} tasks"));
            if let Ok(ref data) = data {
                let dupes = tasks::find_duplicate_ids(&data.tasks);
                check("No duplicate task IDs", dupes.is_empty(),
                    &if dupes.is_empty() { "all unique".into() } else { format!("duplicates: {}", dupes.join(", ")) });
            }
        } else {
            check("tasks.json exists", false, "not found");
        }
    }

    let sched_path = home().join(".claude/scheduler/scheduler.json");
    check("scheduler.json exists", sched_path.exists(), "");
    if sched_path.exists() {
        let sched = load_scheduler();
        let enabled = sched.get("jobs").and_then(|v| v.as_object())
            .map(|j| j.values().filter(|v| v["enabled"].as_bool().unwrap_or(true)).count())
            .unwrap_or(0);
        check("Scheduler jobs configured", enabled > 0, &format!("{enabled} enabled"));
    }

    // Systemd timers
    let timer_count = Command::new("systemctl")
        .args(["--user", "list-units", "brana-sched-*.timer", "--no-legend", "--plain"])
        .output().ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).lines()
            .filter(|l| l.contains("active")).count())
        .unwrap_or(0);
    check("Systemd timers active", timer_count > 0, &format!("{timer_count} active"));

    // Ruflo
    let ruflo = ["ruflo", "claude-flow"].iter().any(|cmd| {
        Command::new("which").arg(cmd).output().ok().map_or(false, |o| o.status.success())
    });
    check("Ruflo/claude-flow installed", ruflo, "");

    check("Bootstrap deployed", home().join(".claude/CLAUDE.md").exists(), "");

    println!("\n  {passed}/{total} checks passed\n");
}
