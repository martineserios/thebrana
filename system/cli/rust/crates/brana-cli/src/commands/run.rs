//! Run, queue, and agents handlers

use std::process::Command;

use crate::tasks;
use crate::util::{find_project_root, find_tasks_file, home};

pub fn cmd_run(task_id: &str, spawn: bool) {
    let tf = find_tasks_file().unwrap_or_else(|| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": "tasks.json not found"}));
        std::process::exit(1);
    });
    let mut val = tasks::load_raw(&tf).unwrap_or_else(|e| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
        std::process::exit(1);
    });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
        std::process::exit(1);
    });

    let task = data.tasks.iter().find(|t| t["id"].as_str() == Some(task_id));
    let task = match task {
        Some(t) => t,
        None => {
            eprintln!("{}", serde_json::json!({"ok": false, "error": format!("task {task_id} not found")}));
            std::process::exit(1);
        }
    };

    match tasks::validate_task_runnable(task, &data.tasks) {
        Ok(()) => {}
        Err(e) => {
            if e.contains("already in_progress") {
                let branch = task["branch"].as_str().unwrap_or("unknown");
                println!("{}", serde_json::json!({
                    "ok": true, "id": task_id, "status": "already_running", "branch": branch
                }));
                return;
            }
            eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
            std::process::exit(1);
        }
    }

    let branch = tasks::branch_for_task(task);
    let repo_root = find_project_root().unwrap_or_else(|| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": "not in a git repo"}));
        std::process::exit(1);
    });
    let repo_name = repo_root.file_name().unwrap().to_str().unwrap();
    let worktree_rel = tasks::worktree_path_for_task(task, repo_name);
    let worktree_abs = repo_root.parent().unwrap().join(&worktree_rel[3..]);

    // Create git worktree
    let wt_out = Command::new("git")
        .args(["worktree", "add", &worktree_rel, "-b", &branch])
        .current_dir(&repo_root)
        .output();
    match wt_out {
        Ok(o) if o.status.success() => {}
        Ok(o) => {
            let err = String::from_utf8_lossy(&o.stderr);
            if err.contains("already exists") {
                let wt2 = Command::new("git")
                    .args(["worktree", "add", &worktree_rel, &branch])
                    .current_dir(&repo_root)
                    .output();
                match wt2 {
                    Ok(o2) if o2.status.success() => {}
                    _ => {
                        eprintln!("{}", serde_json::json!({"ok": false, "error": format!("worktree failed: {err}")}));
                        std::process::exit(1);
                    }
                }
            } else {
                eprintln!("{}", serde_json::json!({"ok": false, "error": format!("worktree failed: {err}")}));
                std::process::exit(1);
            }
        }
        Err(e) => {
            eprintln!("{}", serde_json::json!({"ok": false, "error": format!("git error: {e}")}));
            std::process::exit(1);
        }
    }

    // Update task fields
    let idx = val["tasks"]
        .as_array()
        .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)));
    if let Some(idx) = idx {
        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        val["tasks"][idx]["status"] = serde_json::json!("in_progress");
        val["tasks"][idx]["started"] = serde_json::json!(today);
        val["tasks"][idx]["branch"] = serde_json::json!(branch);
        tasks::save_tasks(&tf, &val).unwrap_or_else(|e| {
            eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
            std::process::exit(1);
        });
    }

    // Spawn in tmux if requested
    if spawn {
        if !tasks::is_in_tmux() {
            eprintln!("{}", serde_json::json!({
                "ok": false,
                "error": "tmux required for --spawn. Run without --spawn to get the command."
            }));
            std::process::exit(1);
        }

        let tmux_target = format!("t-{}", task_id.strip_prefix("t-").unwrap_or(task_id));
        let tmux_cmd = format!("cd {} && claude", worktree_abs.display());

        let spawn_result = Command::new("tmux")
            .args(["new-window", "-n", &tmux_target, &tmux_cmd])
            .output();

        match spawn_result {
            Ok(o) if o.status.success() => {
                let pid_out = Command::new("tmux")
                    .args(["list-panes", "-t", &tmux_target, "-F", "#{pane_pid}"])
                    .output();
                let pid: u32 = pid_out.ok()
                    .and_then(|o| String::from_utf8(o.stdout).ok())
                    .and_then(|s| s.trim().parse().ok())
                    .unwrap_or(0);

                let agents_path = home().join(".claude/agents.json");
                let mut agents = tasks::load_agents(&agents_path);
                let entry = tasks::new_agent_entry(
                    task_id, pid, &tmux_target, &worktree_rel, &branch,
                );
                agents.push(entry);
                tasks::save_agents(&agents_path, &agents).ok();

                println!("{}", serde_json::json!({
                    "ok": true,
                    "id": task_id,
                    "branch": branch,
                    "worktree": worktree_rel,
                    "tmux_target": tmux_target,
                    "pid": pid,
                    "spawned": true
                }));
            }
            Ok(o) => {
                let err = String::from_utf8_lossy(&o.stderr);
                eprintln!("{}", serde_json::json!({"ok": false, "error": format!("tmux spawn failed: {err}")}));
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("{}", serde_json::json!({"ok": false, "error": format!("tmux error: {e}")}));
                std::process::exit(1);
            }
        }
    } else {
        let cmd = format!("cd {} && claude", worktree_abs.display());
        println!("{}", serde_json::json!({
            "ok": true,
            "id": task_id,
            "branch": branch,
            "worktree": worktree_rel,
            "command": cmd
        }));
    }
}

pub fn cmd_agents() {
    let agents_path = home().join(".claude/agents.json");
    let agents = tasks::load_agents(&agents_path);
    let (alive, removed) = tasks::prune_dead_agents(agents);

    if removed > 0 {
        tasks::save_agents(&agents_path, &alive).ok();
    }

    if alive.is_empty() {
        println!("No active agents.");
        return;
    }

    println!("{}", tasks::format_agents_table(&alive));
    if removed > 0 {
        eprintln!("({removed} dead agent(s) pruned)");
    }
}

pub fn cmd_agents_kill(agent_id: &str) {
    let agents_path = home().join(".claude/agents.json");
    let agents = tasks::load_agents(&agents_path);

    let agent = agents.iter().find(|a| a["id"].as_str() == Some(agent_id));
    let agent = match agent {
        Some(a) => a.clone(),
        None => {
            eprintln!("{}", serde_json::json!({"ok": false, "error": format!("agent {agent_id} not found")}));
            std::process::exit(1);
        }
    };

    let pid = agent["pid"].as_u64().unwrap_or(0) as u32;
    let tmux_target = agent["tmux_target"].as_str().unwrap_or("");
    let task_id = agent["task_id"].as_str().unwrap_or("");

    if !tmux_target.is_empty() {
        Command::new("tmux")
            .args(["send-keys", "-t", tmux_target, "C-c"])
            .output()
            .ok();
        std::thread::sleep(std::time::Duration::from_secs(3));
    }

    if pid > 0 && tasks::is_pid_alive(pid) {
        Command::new("kill").args(["-15", &pid.to_string()]).output().ok();
        std::thread::sleep(std::time::Duration::from_secs(2));

        if tasks::is_pid_alive(pid) {
            Command::new("kill").args(["-9", &pid.to_string()]).output().ok();
        }
    }

    let remaining: Vec<_> = agents
        .into_iter()
        .filter(|a| a["id"].as_str() != Some(agent_id))
        .collect();
    tasks::save_agents(&agents_path, &remaining).ok();

    if !task_id.is_empty() {
        let tf = find_tasks_file();
        if let Some(tf) = tf {
            let mut val = tasks::load_raw(&tf).unwrap_or_default();
            let idx = val["tasks"]
                .as_array()
                .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(task_id)));
            if let Some(idx) = idx {
                val["tasks"][idx]["status"] = serde_json::json!("pending");
                val["tasks"][idx]["started"] = serde_json::Value::Null;
                tasks::save_tasks(&tf, &val).ok();
            }
        }
    }

    println!("{}", serde_json::json!({
        "ok": true,
        "killed": agent_id,
        "task_reset": task_id
    }));
}

pub fn cmd_queue(max: usize, auto: bool) {
    let tf = find_tasks_file().unwrap_or_else(|| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": "tasks.json not found"}));
        std::process::exit(1);
    });
    let data = tasks::load_tasks(&tf).unwrap_or_else(|e| {
        eprintln!("{}", serde_json::json!({"ok": false, "error": e}));
        std::process::exit(1);
    });

    let candidates = tasks::queue_candidates(&data.tasks, max);

    if candidates.is_empty() {
        println!("No unblocked tasks in queue.");
        return;
    }

    if auto {
        if !tasks::is_in_tmux() {
            eprintln!("{}", serde_json::json!({
                "ok": false, "error": "tmux required for --auto. Run without --auto to see candidates."
            }));
            std::process::exit(1);
        }
        for c in &candidates {
            let id = c["id"].as_str().unwrap_or("");
            eprintln!("Spawning {id}...");
            let result = Command::new(std::env::current_exe().unwrap())
                .args(["run", id, "--spawn"])
                .output();
            match result {
                Ok(o) => {
                    let out = String::from_utf8_lossy(&o.stdout);
                    let err = String::from_utf8_lossy(&o.stderr);
                    if o.status.success() {
                        println!("{out}");
                    } else {
                        eprintln!("  Failed: {err}");
                    }
                }
                Err(e) => eprintln!("  Error: {e}"),
            }
        }
    } else {
        println!("{:<10} {:<35} {:<5} {:<5} {:<10} {:<6} {:<7}",
            "ID", "SUBJECT", "PRI", "EFF", "STREAM", "SCORE", "MODEL");
        for c in &candidates {
            let id = c["id"].as_str().unwrap_or("?");
            let subject = c["subject"].as_str().unwrap_or("?");
            let subject_short = if subject.len() > 33 { &subject[..33] } else { subject };
            let pri = c["priority"].as_str().unwrap_or("—");
            let eff = c["effort"].as_str().unwrap_or("—");
            let stream = c["stream"].as_str().unwrap_or("—");
            let score = c["score"].as_f64().unwrap_or(0.0);
            let model = c["model"].as_str().unwrap_or("?");
            println!("{:<10} {:<35} {:<5} {:<5} {:<10} {:<6.2} {:<7}",
                id, subject_short, pri, eff, stream, score, model);
        }
        println!("\nRun with --auto to spawn agents on all, or: brana run <ID> --spawn");
    }
}
