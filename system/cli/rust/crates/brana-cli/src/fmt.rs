//! brana-fmt — themed task line renderer
//!
//! Takes JSON task(s) from stdin, renders styled terminal lines.
//! Reads themes.json for icon/color definitions.
//!
//! Usage:
//!   echo '{"id":"t-001","subject":"Test","status":"pending"}' | brana-fmt
//!   brana-query --file .claude/tasks.json --tag auth | brana-fmt --theme emoji
//!   brana-fmt --theme minimal --progress 5 8

use clap::Parser;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{self, Read};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "brana-fmt", about = "Themed task line renderer for brana CLI")]
struct Args {
    /// Theme name: classic, emoji, minimal
    #[arg(long, default_value = "classic")]
    theme: String,

    /// Path to themes.json (default: look in CLI dir)
    #[arg(long)]
    themes_file: Option<PathBuf>,

    /// Render a progress bar instead of tasks: --progress DONE TOTAL
    #[arg(long, num_args = 2)]
    progress: Option<Vec<usize>>,

    /// Show tags inline
    #[arg(long, default_value = "true")]
    tags: bool,
}

fn find_themes_file(arg: &Option<PathBuf>) -> PathBuf {
    if let Some(p) = arg {
        return p.clone();
    }
    // Look relative to binary location
    if let Ok(exe) = std::env::current_exe() {
        let dir = exe.parent().unwrap_or(std::path::Path::new("."));
        // Installed: binary in target/release, themes.json in system/cli/
        for candidate in [
            dir.join("themes.json"),
            dir.join("../../system/cli/themes.json"),
            dir.join("../system/cli/themes.json"),
        ] {
            if candidate.exists() {
                return candidate;
            }
        }
    }
    // Fallback: look in known location
    let home = std::env::var("HOME").unwrap_or_default();
    let plugin_path = PathBuf::from(&home)
        .join(".claude/plugins/cache/brana/brana/1.0.0/system/cli/themes.json");
    if plugin_path.exists() {
        return plugin_path;
    }
    PathBuf::from("system/cli/themes.json")
}

fn load_theme(themes_file: &PathBuf, name: &str) -> HashMap<String, Value> {
    let content = std::fs::read_to_string(themes_file).unwrap_or_else(|e| {
        eprintln!("Error loading themes: {}: {}", themes_file.display(), e);
        std::process::exit(1);
    });
    let themes: HashMap<String, Value> = serde_json::from_str(&content).unwrap_or_else(|e| {
        eprintln!("Error parsing themes.json: {}", e);
        std::process::exit(1);
    });
    themes
        .get(name)
        .cloned()
        .or_else(|| themes.get("classic").cloned())
        .map(|v| {
            if let Value::Object(m) = v {
                m.into_iter().map(|(k, v)| (k, v)).collect()
            } else {
                HashMap::new()
            }
        })
        .unwrap_or_default()
}

fn get_icon(theme: &HashMap<String, Value>, status: &str) -> String {
    theme
        .get("icons")
        .and_then(|v| v.get(status))
        .and_then(|v| v.as_str())
        .unwrap_or("?")
        .to_string()
}

fn get_color<'a>(theme: &'a HashMap<String, Value>, status: &str) -> &'a str {
    theme
        .get("colors")
        .and_then(|v| v.get(status))
        .and_then(|v| v.as_str())
        .unwrap_or("white")
}

fn ansi_color(name: &str) -> &str {
    match name {
        "green" => "\x1b[32m",
        "red" | "bold red" => "\x1b[31m",
        "yellow" => "\x1b[33m",
        "cyan" => "\x1b[36m",
        "dim" => "\x1b[2m",
        "bold" => "\x1b[1m",
        "white" => "\x1b[37m",
        _ => "\x1b[0m",
    }
}

const RESET: &str = "\x1b[0m";

fn classify_simple(task: &Value) -> &'static str {
    match task["status"].as_str().unwrap_or("") {
        "completed" | "cancelled" => "done",
        "in_progress" => "active",
        _ => {
            if let Some(deps) = task["blocked_by"].as_array() {
                if !deps.is_empty() {
                    return "blocked";
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

fn render_task(task: &Value, theme: &HashMap<String, Value>, show_tags: bool) {
    let status = classify_simple(task);
    let ic = get_icon(theme, status);
    let col = ansi_color(get_color(theme, status));
    let id = task["id"].as_str().unwrap_or("?");
    let subject = task["subject"].as_str().unwrap_or("untitled");

    let mut line = format!("{col}{ic} {id}  {subject}");

    if show_tags {
        if let Some(tags) = task["tags"].as_array() {
            let tag_strs: Vec<&str> = tags.iter().filter_map(|v| v.as_str()).take(3).collect();
            if !tag_strs.is_empty() {
                let extra = if tags.len() > 3 {
                    format!(" +{}", tags.len() - 3)
                } else {
                    String::new()
                };
                line.push_str(&format!(" [{}{}]", tag_strs.join(", "), extra));
            }
        }
    }

    // Status detail
    if status == "blocked" {
        if let Some(deps) = task["blocked_by"].as_array() {
            let ref_icon = theme
                .get("blocked_ref")
                .and_then(|v| v.as_str())
                .unwrap_or("blocked by");
            let dep_ids: Vec<&str> = deps.iter().filter_map(|v| v.as_str()).collect();
            line.push_str(&format!("  {ref_icon} {}", dep_ids.join(", ")));
        }
    } else if status == "done" {
        if let Some(date) = task["completed"].as_str() {
            line.push_str(&format!("  completed {date}"));
        }
    } else if status == "active" {
        if let Some(step) = task["build_step"].as_str() {
            line.push_str(&format!("  [{}]", step.to_uppercase()));
        }
    }

    println!("{line}{RESET}");
}

fn render_progress(done: usize, total: usize, theme: &HashMap<String, Value>) {
    let width = 8;
    let fill = theme
        .get("bars")
        .and_then(|v| v["fill"].as_str())
        .unwrap_or("█");
    let empty = theme
        .get("bars")
        .and_then(|v| v["empty"].as_str())
        .unwrap_or("░");

    let filled = if total > 0 {
        (done as f64 / total as f64 * width as f64).round() as usize
    } else {
        0
    };

    let bar: String = fill.repeat(filled) + &empty.repeat(width - filled);
    println!("{bar} {done}/{total}");
}

fn main() {
    let args = Args::parse();
    let themes_file = find_themes_file(&args.themes_file);
    let theme = load_theme(&themes_file, &args.theme);

    if let Some(ref vals) = args.progress {
        render_progress(vals[0], vals[1], &theme);
        return;
    }

    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap_or_else(|e| {
        eprintln!("Error reading stdin: {}", e);
        std::process::exit(1);
    });

    let input = input.trim();
    if input.is_empty() {
        return;
    }

    // Support both array of tasks and single task object
    if input.starts_with('[') {
        let tasks: Vec<Value> = serde_json::from_str(input).unwrap_or_else(|e| {
            eprintln!("Error parsing JSON array: {}", e);
            std::process::exit(1);
        });
        for task in &tasks {
            render_task(task, &theme, args.tags);
        }
    } else {
        let task: Value = serde_json::from_str(input).unwrap_or_else(|e| {
            eprintln!("Error parsing JSON: {}", e);
            std::process::exit(1);
        });
        render_task(&task, &theme, args.tags);
    }
}
