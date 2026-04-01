//! Knowledge subcommand handlers

use std::path::PathBuf;
use std::process::Command;

use crate::util::{find_project_root, home};

pub fn cmd_reindex(changed: bool, files: Vec<PathBuf>) {
    let root = find_project_root().unwrap_or_else(|| {
        eprintln!("Not in git repo");
        std::process::exit(1);
    });
    let script = root.join("system/scripts/index-knowledge.sh");
    if !script.exists() {
        eprintln!("index-knowledge.sh not found at {}", script.display());
        std::process::exit(1);
    }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).current_dir(&root);

    if changed {
        cmd.arg("--changed");
    } else {
        for f in &files {
            cmd.arg(f);
        }
    }

    println!("\n  Running index-knowledge.sh...");
    match cmd.status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        Ok(s) => {
            eprintln!("  \x1b[31mFailed (exit {}).\x1b[0m", s.code().unwrap_or(-1));
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("  \x1b[31mFailed: {e}\x1b[0m");
            std::process::exit(1);
        }
    }
}

pub fn cmd_status() {
    let db_path = home().join(".swarm/memory.db");

    if !db_path.exists() {
        println!("  Knowledge DB not found at {}", db_path.display());
        println!("  Run `brana knowledge reindex` to create it.");
        return;
    }

    // Query entry count and last modified via sqlite3
    let output = Command::new("sqlite3")
        .arg(&db_path)
        .arg("SELECT COUNT(*), datetime(MAX(COALESCE(updated_at, created_at)) / 1000, 'unixepoch', 'localtime') FROM memory_entries WHERE namespace = 'knowledge' AND status = 'active';")
        .output();

    match output {
        Ok(out) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            let parts: Vec<&str> = text.trim().split('|').collect();
            let count = parts.first().unwrap_or(&"?");
            let last = parts.get(1).unwrap_or(&"?");
            println!("\n  \x1b[1mKnowledge Index Status\x1b[0m");
            println!("  Entries:      {count}");
            println!("  Last indexed: {last}");
            println!("  DB path:      {}\n", db_path.display());
        }
        Ok(out) => {
            let err = String::from_utf8_lossy(&out.stderr);
            eprintln!("  sqlite3 error: {err}");
            // Fallback: just show file stats
            if let Ok(meta) = std::fs::metadata(&db_path) {
                println!("  DB size: {} bytes", meta.len());
            }
        }
        Err(_) => {
            // sqlite3 not available — show file info
            println!("\n  \x1b[1mKnowledge Index Status\x1b[0m");
            println!("  DB path: {}", db_path.display());
            if let Ok(meta) = std::fs::metadata(&db_path) {
                println!("  DB size: {} bytes", meta.len());
                if let Ok(modified) = meta.modified() {
                    let elapsed = modified.elapsed().unwrap_or_default();
                    let hours = elapsed.as_secs() / 3600;
                    println!("  Last modified: ~{hours}h ago");
                }
            }
            println!("  (install sqlite3 for detailed stats)\n");
        }
    }
}
