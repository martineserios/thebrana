//! Knowledge subcommand handlers

use anyhow::{Result, bail};
use serde::{Deserialize, Serialize};
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

pub fn cmd_reindex_patterns(files: Vec<PathBuf>) {
    let root = find_project_root().unwrap_or_else(|| {
        eprintln!("Not in git repo");
        std::process::exit(1);
    });
    let script = root.join("system/scripts/index-patterns.sh");
    if !script.exists() {
        eprintln!("index-patterns.sh not found at {}", script.display());
        std::process::exit(1);
    }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).current_dir(&root);

    for f in &files {
        cmd.arg(f);
    }

    println!("\n  Running index-patterns.sh...");
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

// ── knowledge search ─────────────────────────────────────────────────

/// A single result entry returned by ruflo memory search.
#[derive(Debug, Deserialize, Serialize)]
pub struct SearchResult {
    pub key: String,
    pub value: String,
    #[serde(default)]
    pub score: f64,
}

/// Parse a ruflo memory search JSON response into `SearchResult` entries.
/// The ruflo CLI returns a JSON array of `{key, value, score}` objects.
pub fn parse_search_results(text: &str) -> Result<Vec<SearchResult>> {
    let results: Vec<SearchResult> = serde_json::from_str(text.trim())?;
    Ok(results)
}

/// Truncate `text` to at most `max_chars` characters, appending "..." when clipped.
pub fn truncate(text: &str, max_chars: usize) -> String {
    let text = text.trim();
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    let clipped: String = text.chars().take(max_chars).collect();
    format!("{clipped}...")
}

/// Format search results for human-readable display.
///
/// Example output:
/// ```text
/// 1. [0.82] pattern:thebrana:hooks-cant-enforce-ordering
///    Hooks are stateless — can't enforce workflow ordering...
/// ```
pub fn format_results(results: &[SearchResult]) -> String {
    if results.is_empty() {
        return "  No results found.".to_string();
    }
    let mut lines = Vec::new();
    for (i, r) in results.iter().enumerate() {
        lines.push(format!(
            "{}. [{:.2}] {}",
            i + 1,
            r.score,
            r.key
        ));
        lines.push(format!("   {}", truncate(&r.value, 100)));
    }
    lines.join("\n")
}

/// Resolve the ruflo/claude-flow binary path (same logic as skills.rs).
fn which_ruflo() -> Option<String> {
    let home_str = std::env::var("HOME").unwrap_or_default();
    let cf_env = format!("{home_str}/.claude/scripts/cf-env.sh");
    if std::path::Path::new(&cf_env).exists() {
        if let Ok(output) = std::process::Command::new("bash")
            .args(["-c", &format!("source '{cf_env}' 2>/dev/null && echo \"$CF\"")])
            .output()
        {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() && std::path::Path::new(&path).exists() {
                    return Some(path);
                }
            }
        }
    }

    // Try nvm global bin locations
    let nvm_dir = std::env::var("NVM_DIR").unwrap_or_else(|_| format!("{home_str}/.nvm"));
    if let Ok(entries) = std::fs::read_dir(format!("{nvm_dir}/versions/node")) {
        for entry in entries.flatten() {
            for name in ["ruflo", "claude-flow"] {
                let bin = entry.path().join("bin").join(name);
                if bin.exists() {
                    return Some(bin.to_string_lossy().to_string());
                }
            }
        }
    }

    // Try PATH
    for name in ["ruflo", "claude-flow"] {
        if let Ok(output) = std::process::Command::new("which").arg(name).output() {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() {
                    return Some(path);
                }
            }
        }
    }
    None
}

/// Call ruflo memory search and return raw JSON output.
/// Uses a 15-second timeout (ruflo CLI can hang after completion — known issue).
fn call_ruflo_search(query: &str, namespace: &str, limit: usize) -> Result<String> {
    let cf = std::env::var("CF")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(which_ruflo)
        .ok_or_else(|| anyhow::anyhow!("ruflo not found — run `brana knowledge reindex` first"))?;

    let home_str = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let limit_str = limit.to_string();

    let mut child = std::process::Command::new(&cf)
        .args([
            "memory", "search",
            "-q", query,
            "--namespace", namespace,
            "--limit", &limit_str,
        ])
        .env("HOME", &home_str)
        .current_dir(&home_str)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| anyhow::anyhow!("failed to spawn ruflo: {e}"))?;

    let timeout = std::time::Duration::from_secs(15);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() {
                    let _ = child.wait();
                    bail!("ruflo search exited with non-zero status");
                }
                break;
            }
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("ruflo search timed out after 15s");
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => bail!("ruflo wait error: {e}"),
        }
    }

    let output = child.wait_with_output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// `brana knowledge search <query> [--limit N] [--namespace NS] [--json]`
pub fn cmd_search(query: &str, limit: usize, namespace: &str, json_output: bool) -> Result<()> {
    let raw = call_ruflo_search(query, namespace, limit)?;
    let results = parse_search_results(&raw)?;

    if json_output {
        let out = serde_json::to_string_pretty(&results)?;
        println!("{out}");
    } else {
        println!("\n  \x1b[1mKnowledge Search\x1b[0m — \"{query}\" (namespace: {namespace})\n");
        println!("{}", format_results(&results));
        println!();
    }
    Ok(())
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

#[cfg(test)]
mod tests {
    use super::*;

    // ── parse_search_results ─────────────────────────────────────────

    #[test]
    fn test_parse_valid_results() {
        let json = r#"[
            {"key": "knowledge:docs/reflections/31-assurance.md:testing", "value": "Testing and assurance framework overview", "score": 0.82},
            {"key": "pattern:thebrana:hooks-cant-enforce-ordering", "value": "Hooks are stateless — can't enforce workflow ordering", "score": 0.75}
        ]"#;
        let results = parse_search_results(json).expect("should parse");
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].key, "knowledge:docs/reflections/31-assurance.md:testing");
        assert!((results[0].score - 0.82).abs() < 1e-9);
        assert_eq!(results[1].key, "pattern:thebrana:hooks-cant-enforce-ordering");
    }

    #[test]
    fn test_parse_empty_array() {
        let results = parse_search_results("[]").expect("should parse");
        assert!(results.is_empty());
    }

    #[test]
    fn test_parse_missing_score_defaults_to_zero() {
        let json = r#"[{"key": "knowledge:some:key", "value": "content here"}]"#;
        let results = parse_search_results(json).expect("should parse");
        assert_eq!(results.len(), 1);
        assert!((results[0].score - 0.0).abs() < 1e-9);
    }

    #[test]
    fn test_parse_invalid_json_returns_error() {
        assert!(parse_search_results("not json").is_err());
        assert!(parse_search_results("{\"key\":\"v\"}").is_err()); // object, not array
    }

    // ── truncate ─────────────────────────────────────────────────────

    #[test]
    fn test_truncate_short_string_unchanged() {
        assert_eq!(truncate("hello world", 50), "hello world");
    }

    #[test]
    fn test_truncate_exact_length_unchanged() {
        let s = "abcde";
        assert_eq!(truncate(s, 5), "abcde");
    }

    #[test]
    fn test_truncate_long_string_clipped() {
        let s = "abcdefghij";
        let result = truncate(s, 5);
        assert_eq!(result, "abcde...");
    }

    #[test]
    fn test_truncate_trims_whitespace() {
        assert_eq!(truncate("  hi  ", 50), "hi");
    }

    // ── format_results ───────────────────────────────────────────────

    #[test]
    fn test_format_empty_results() {
        let out = format_results(&[]);
        assert!(out.contains("No results found"));
    }

    #[test]
    fn test_format_single_result() {
        let results = vec![SearchResult {
            key: "knowledge:docs/reflections/31-assurance.md:testing".into(),
            value: "Testing and assurance framework overview".into(),
            score: 0.82,
        }];
        let out = format_results(&results);
        assert!(out.contains("1."), "should contain rank number");
        assert!(out.contains("[0.82]"), "should contain formatted score");
        assert!(out.contains("knowledge:docs/reflections/31-assurance.md:testing"), "should contain key");
        assert!(out.contains("Testing and assurance framework"), "should contain value preview");
    }

    #[test]
    fn test_format_multiple_results_numbered_sequentially() {
        let results = vec![
            SearchResult { key: "k:a".into(), value: "first".into(), score: 0.9 },
            SearchResult { key: "k:b".into(), value: "second".into(), score: 0.7 },
            SearchResult { key: "k:c".into(), value: "third".into(), score: 0.5 },
        ];
        let out = format_results(&results);
        assert!(out.contains("1."));
        assert!(out.contains("2."));
        assert!(out.contains("3."));
        // Verify ordering: first result should appear before second
        let pos_first = out.find("k:a").unwrap();
        let pos_second = out.find("k:b").unwrap();
        assert!(pos_first < pos_second);
    }

    #[test]
    fn test_format_long_value_is_truncated() {
        let long_value = "x".repeat(200);
        let results = vec![SearchResult {
            key: "k:long".into(),
            value: long_value,
            score: 0.5,
        }];
        let out = format_results(&results);
        // Value preview line should end with "..." due to truncation
        assert!(out.contains("..."), "long value should be truncated with ...");
    }

    #[test]
    fn test_format_score_precision() {
        let results = vec![SearchResult {
            key: "k:precise".into(),
            value: "some content".into(),
            score: 0.123456,
        }];
        let out = format_results(&results);
        // Score should be formatted with 2 decimal places
        assert!(out.contains("[0.12]"), "score should be 2 decimal places, got: {out}");
    }
}
