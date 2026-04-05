//! Theme loading and ANSI rendering — reads themes.json, outputs styled terminal text.

use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub struct Theme {
    data: HashMap<String, Value>,
}

impl Theme {
    pub fn load(name: &str) -> Self {
        let path = find_themes_file();
        let content = std::fs::read_to_string(&path).unwrap_or_else(|_| "{}".into());
        let themes: HashMap<String, Value> =
            serde_json::from_str(&content).unwrap_or_default();
        let data = themes
            .get(name)
            .or_else(|| themes.get("classic"))
            .cloned()
            .map(|v| match v {
                Value::Object(m) => m.into_iter().collect(),
                _ => HashMap::new(),
            })
            .unwrap_or_default();
        Theme { data }
    }

    pub fn icon(&self, status: &str) -> &str {
        self.data
            .get("icons")
            .and_then(|v| v.get(status))
            .and_then(|v| v.as_str())
            .unwrap_or("?")
    }

    pub fn color(&self, status: &str) -> &str {
        self.data
            .get("colors")
            .and_then(|v| v.get(status))
            .and_then(|v| v.as_str())
            .unwrap_or("white")
    }

    pub fn bar(&self, done: usize, total: usize, width: usize) -> String {
        if total == 0 {
            return String::new();
        }
        let fill = self.data.get("bars")
            .and_then(|v| v["fill"].as_str())
            .unwrap_or("█");
        let empty = self.data.get("bars")
            .and_then(|v| v["empty"].as_str())
            .unwrap_or("░");
        let filled = (done as f64 / total as f64 * width as f64).round() as usize;
        format!(
            "{}{} {}/{}",
            fill.repeat(filled),
            empty.repeat(width - filled),
            done,
            total
        )
    }

    pub fn blocked_ref(&self) -> &str {
        self.data
            .get("blocked_ref")
            .and_then(|v| v.as_str())
            .unwrap_or("blocked by")
    }
}

pub fn ansi(color_name: &str) -> &'static str {
    match color_name {
        "green" => "\x1b[32m",
        "red" | "bold red" => "\x1b[1;31m",
        "yellow" => "\x1b[33m",
        "cyan" => "\x1b[36m",
        "dim" => "\x1b[2m",
        "bold" => "\x1b[1m",
        "white" => "\x1b[37m",
        _ => "",
    }
}

pub const RESET: &str = "\x1b[0m";

/// Render a single task line with theme styling.
pub fn render_task_line(task: &serde_json::Value, status: &str, theme: &Theme, show_tags: bool) -> String {
    let ic = theme.icon(status);
    let col = ansi(theme.color(status));
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

    if status == "blocked" {
        if let Some(deps) = task["blocked_by"].as_array() {
            let dep_ids: Vec<&str> = deps.iter().filter_map(|v| v.as_str()).collect();
            line.push_str(&format!("  {} {}", theme.blocked_ref(), dep_ids.join(", ")));
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

    format!("{line}{RESET}")
}

/// Load theme name from ~/.claude/tasks-config.json.
pub fn load_theme_name() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let config = PathBuf::from(&home).join(".claude/tasks-config.json");
    if let Ok(content) = std::fs::read_to_string(&config) {
        if let Ok(cfg) = serde_json::from_str::<HashMap<String, Value>>(&content) {
            if let Some(name) = cfg.get("theme").and_then(|v| v.as_str()) {
                return name.to_string();
            }
        }
    }
    "classic".to_string()
}

fn find_themes_file() -> PathBuf {
    // Look relative to binary
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            for candidate in [
                dir.join("../../../cli/themes.json"),  // target/release/../../../cli/
                dir.join("../../themes.json"),
                dir.join("themes.json"),
            ] {
                if candidate.exists() {
                    return candidate;
                }
            }
        }
    }
    // Fallback: known locations
    let home = std::env::var("HOME").unwrap_or_default();
    for p in [
        "system/cli/themes.json",
        &format!("{home}/.claude/plugins/cache/brana/brana/1.0.0/system/cli/themes.json"),
    ] {
        let path = Path::new(p);
        if path.exists() {
            return path.to_path_buf();
        }
    }
    PathBuf::from("system/cli/themes.json")
}
