//! brana-query — fast JSON task filter
//!
//! Reads tasks.json from stdin or file, filters by tag/status/stream/priority/effort/text,
//! outputs filtered results as JSON. Called by Python CLI for hot-path filtering.
//!
//! Usage:
//!   brana-query --file .claude/tasks.json --tag scheduler --status pending
//!   cat .claude/tasks.json | brana-query --tag auth --stream roadmap
//!   brana-query --file .claude/tasks.json --search "JWT middleware"
//!   brana-query --file .claude/tasks.json --count --tag scheduler

use clap::Parser;
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;
use std::io::{self, Read};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "brana-query", about = "Fast JSON task filter for brana CLI")]
struct Args {
    /// Path to tasks.json (reads stdin if omitted)
    #[arg(short, long)]
    file: Option<PathBuf>,

    /// Filter by tag
    #[arg(short, long)]
    tag: Option<String>,

    /// Filter by classified status: done|active|pending|blocked|parked
    #[arg(short, long)]
    status: Option<String>,

    /// Filter by stream
    #[arg(long)]
    stream: Option<String>,

    /// Filter by priority: P0|P1|P2|P3
    #[arg(short, long)]
    priority: Option<String>,

    /// Filter by effort: S|M|L|XL
    #[arg(short, long)]
    effort: Option<String>,

    /// Free-text search across subject, description, context, notes
    #[arg(long)]
    search: Option<String>,

    /// Task types to include (comma-separated, default: task,subtask)
    #[arg(long, default_value = "task,subtask")]
    types: String,

    /// Output: json (default) or ids (one per line)
    #[arg(long, default_value = "json")]
    output: String,

    /// Output count only
    #[arg(long)]
    count: bool,
}

#[derive(Deserialize)]
struct TasksFile {
    #[serde(default)]
    tasks: Vec<Value>,
}

fn classify(task: &Value, all: &[Value]) -> &'static str {
    match task["status"].as_str().unwrap_or("") {
        "completed" | "cancelled" => "done",
        "in_progress" => "active",
        _ => {
            if let Some(deps) = task["blocked_by"].as_array() {
                if !deps.is_empty() {
                    let done_ids: HashSet<&str> = all
                        .iter()
                        .filter(|t| matches!(t["status"].as_str(), Some("completed" | "cancelled")))
                        .filter_map(|t| t["id"].as_str())
                        .collect();
                    if !deps.iter().all(|d| done_ids.contains(d.as_str().unwrap_or(""))) {
                        return "blocked";
                    }
                }
            }
            if task["tags"]
                .as_array()
                .map_or(false, |t| t.iter().any(|v| v.as_str() == Some("parked")))
            {
                return "parked";
            }
            "pending"
        }
    }
}

fn text_match(task: &Value, needle: &str) -> bool {
    let n = needle.to_lowercase();
    ["subject", "description", "context", "notes"]
        .iter()
        .any(|f| {
            task[f]
                .as_str()
                .map_or(false, |v| v.to_lowercase().contains(&n))
        })
}

fn main() {
    let args = Args::parse();
    let types: Vec<&str> = args.types.split(',').collect();

    let input = match &args.file {
        Some(p) => std::fs::read_to_string(p).unwrap_or_else(|e| {
            eprintln!("Error: {}: {}", p.display(), e);
            std::process::exit(1);
        }),
        None => {
            let mut buf = String::new();
            io::stdin().read_to_string(&mut buf).unwrap_or_else(|e| {
                eprintln!("Error reading stdin: {}", e);
                std::process::exit(1);
            });
            buf
        }
    };

    let tasks: Vec<Value> = serde_json::from_str::<TasksFile>(&input)
        .map(|tf| tf.tasks)
        .or_else(|_| serde_json::from_str::<Vec<Value>>(&input))
        .unwrap_or_else(|_| {
            eprintln!("Error: invalid JSON");
            std::process::exit(1);
        });

    let results: Vec<&Value> = tasks
        .iter()
        .filter(|t| {
            let tt = t["type"].as_str().unwrap_or("task");
            if !types.contains(&tt) {
                return false;
            }
            if let Some(ref s) = args.status {
                if classify(t, &tasks) != s.as_str() {
                    return false;
                }
            }
            if let Some(ref tag) = args.tag {
                let tags: Vec<&str> = t["tags"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                if !tags.contains(&tag.as_str()) {
                    return false;
                }
            }
            if let Some(ref s) = args.stream {
                if t["stream"].as_str().unwrap_or("") != s.as_str() {
                    return false;
                }
            }
            if let Some(ref p) = args.priority {
                if t["priority"].as_str().unwrap_or("") != p.as_str() {
                    return false;
                }
            }
            if let Some(ref e) = args.effort {
                if t["effort"].as_str().unwrap_or("") != e.as_str() {
                    return false;
                }
            }
            if let Some(ref q) = args.search {
                if !text_match(t, q) {
                    return false;
                }
            }
            true
        })
        .collect();

    if args.count {
        println!("{}", results.len());
    } else if args.output == "ids" {
        for t in &results {
            if let Some(id) = t["id"].as_str() {
                println!("{}", id);
            }
        }
    } else {
        println!("{}", serde_json::to_string(&results).unwrap());
    }
}
