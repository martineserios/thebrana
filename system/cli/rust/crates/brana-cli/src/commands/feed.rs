//! brana feed — RSS/Atom feed polling and monitoring.
//!
//! Config: ~/.claude/scheduler/feeds.json
//! State:  ~/.claude/scheduler/state/{name}.json
//! Log:    ~/.claude/scheduler/feed-log.jsonl

use crate::cli::FeedCmd;
use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{BufWriter, Write};
use std::path::PathBuf;

// ── Data types ──────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FeedEntry {
    pub name: String,
    pub url: String,
    pub action: String, // "log" | "task"
    pub enabled: bool,
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct FeedState {
    pub etag: Option<String>,
    pub last_modified: Option<String>,
    pub last_entry_ids: Vec<String>,
    pub last_poll: Option<String>,
    pub new_count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FeedLogEntry {
    pub feed: String,
    pub title: String,
    pub link: String,
    pub published: Option<String>,
    pub polled_at: String,
}

// ── Paths ───────────────────────────────────────────────────────────────

fn feeds_config_path() -> PathBuf {
    dirs_home().join(".claude/scheduler/feeds.json")
}

fn feed_state_path(name: &str) -> PathBuf {
    dirs_home().join(format!(".claude/scheduler/state/{name}.json"))
}

fn feed_log_path() -> PathBuf {
    dirs_home().join(".claude/scheduler/feed-log.jsonl")
}

fn dirs_home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
}

fn ensure_state_dir() {
    let dir = dirs_home().join(".claude/scheduler/state");
    let _ = fs::create_dir_all(&dir);
}

// ── Config CRUD ─────────────────────────────────────────────────────────

fn load_feeds() -> Vec<FeedEntry> {
    let path = feeds_config_path();
    match fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
        Err(_) => Vec::new(),
    }
}

fn save_feeds(feeds: &[FeedEntry]) -> Result<()> {
    let path = feeds_config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(feeds)?;
    fs::write(&path, json).context("writing feeds.json")?;
    Ok(())
}

fn load_state(name: &str) -> FeedState {
    let path = feed_state_path(name);
    match fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
        Err(_) => FeedState::default(),
    }
}

fn save_state(name: &str, state: &FeedState) -> Result<()> {
    ensure_state_dir();
    let path = feed_state_path(name);
    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(state)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

fn derive_name(url: &str) -> String {
    // Extract domain without TLD, lowercase
    url.trim_start_matches("https://")
        .trim_start_matches("http://")
        .split('/')
        .next()
        .unwrap_or("unknown")
        .split('.')
        .next()
        .unwrap_or("unknown")
        .to_lowercase()
}

// ── Commands ────────────────────────────────────────────────────────────

pub fn cmd_feed(cmd: FeedCmd) {
    let result = match cmd {
        FeedCmd::Add { url, name, action } => cmd_add(&url, name, &action),
        FeedCmd::List => cmd_list(),
        FeedCmd::Poll { name, all } => cmd_poll(name, all),
        FeedCmd::Remove { name } => cmd_remove(&name),
        FeedCmd::Status => cmd_status(),
    };
    if let Err(e) = result {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn cmd_add(url: &str, name: Option<String>, action: &str) -> Result<()> {
    let name = name.unwrap_or_else(|| derive_name(url));
    let mut feeds = load_feeds();

    if feeds.iter().any(|f| f.name == name) {
        anyhow::bail!("feed '{name}' already exists. Remove it first or use a different --name.");
    }

    if action != "log" && action != "task" {
        anyhow::bail!("action must be 'log' or 'task', got '{action}'");
    }

    feeds.push(FeedEntry {
        name: name.clone(),
        url: url.to_string(),
        action: action.to_string(),
        enabled: true,
    });
    save_feeds(&feeds)?;

    println!("{{\"ok\":true,\"name\":\"{name}\",\"url\":\"{url}\",\"action\":\"{action}\"}}");
    Ok(())
}

fn cmd_list() -> Result<()> {
    let feeds = load_feeds();
    let json = serde_json::to_string_pretty(&feeds)?;
    println!("{json}");
    Ok(())
}

fn cmd_remove(name: &str) -> Result<()> {
    let mut feeds = load_feeds();
    let before = feeds.len();
    feeds.retain(|f| f.name != name);
    if feeds.len() == before {
        anyhow::bail!("feed '{name}' not found");
    }
    save_feeds(&feeds)?;

    // Remove state file too
    let state_path = feed_state_path(name);
    let _ = fs::remove_file(state_path);

    println!("{{\"ok\":true,\"removed\":\"{name}\"}}");
    Ok(())
}

fn cmd_status() -> Result<()> {
    let feeds = load_feeds();
    let mut results = Vec::new();
    for feed in &feeds {
        let state = load_state(&feed.name);
        results.push(serde_json::json!({
            "name": feed.name,
            "url": feed.url,
            "action": feed.action,
            "enabled": feed.enabled,
            "last_poll": state.last_poll,
            "new_count": state.new_count,
            "cached_entries": state.last_entry_ids.len(),
        }));
    }
    println!("{}", serde_json::to_string_pretty(&results)?);
    Ok(())
}

fn cmd_poll(name: Option<String>, all: bool) -> Result<()> {
    let feeds = load_feeds();
    let targets: Vec<&FeedEntry> = if let Some(ref n) = name {
        let f = feeds.iter().find(|f| f.name == *n)
            .with_context(|| format!("feed '{n}' not found"))?;
        vec![f]
    } else if all || feeds.len() == 1 {
        feeds.iter().filter(|f| f.enabled).collect()
    } else {
        anyhow::bail!("specify a feed name or use --all");
    };

    let mut results = Vec::new();
    for feed in targets {
        match poll_one(feed) {
            Ok(new_count) => {
                results.push(serde_json::json!({
                    "name": feed.name,
                    "new_entries": new_count,
                    "status": "ok",
                }));
            }
            Err(e) => {
                results.push(serde_json::json!({
                    "name": feed.name,
                    "new_entries": 0,
                    "status": "error",
                    "error": format!("{e:#}"),
                }));
            }
        }
    }

    println!("{}", serde_json::to_string_pretty(&results)?);
    Ok(())
}

fn poll_one(feed: &FeedEntry) -> Result<usize> {
    let mut state = load_state(&feed.name);

    // Build request with conditional headers
    let mut req = ureq::get(&feed.url);
    if let Some(ref etag) = state.etag {
        req = req.header("If-None-Match", etag);
    }
    if let Some(ref lm) = state.last_modified {
        req = req.header("If-Modified-Since", lm);
    }

    let resp = req.call();

    match resp {
        Ok(resp) => {
            if resp.status() == 304 {
                state.last_poll = Some(Utc::now().to_rfc3339());
                state.new_count = 0;
                save_state(&feed.name, &state)?;
                return Ok(0);
            }

            // Capture headers before consuming body
            let new_etag = resp.headers().get("ETag")
                .and_then(|v| v.to_str().ok()).map(String::from);
            let new_lm = resp.headers().get("Last-Modified")
                .and_then(|v| v.to_str().ok()).map(String::from);

            let body = resp.into_body().read_to_string()
                .context("reading feed body")?;
            let parsed = feed_rs::parser::parse(body.as_bytes())
                .context("parsing feed XML/Atom")?;

            // Detect new entries by ID
            let current_ids: Vec<String> = parsed.entries.iter()
                .map(|e| e.id.clone())
                .collect();
            let new_entries: Vec<_> = parsed.entries.iter()
                .filter(|e| !state.last_entry_ids.contains(&e.id))
                .collect();

            let new_count = new_entries.len();

            // Execute action for new entries
            for entry in &new_entries {
                let title = entry.title.as_ref()
                    .map(|t| t.content.clone())
                    .unwrap_or_default();
                let link = entry.links.first()
                    .map(|l| l.href.clone())
                    .unwrap_or_default();
                let published = entry.published
                    .map(|d| d.to_rfc3339());

                match feed.action.as_str() {
                    "task" => {
                        let subj = format!("[{}] {}", feed.name, title);
                        let ctx = format!("URL: {link}");
                        let json = serde_json::json!({
                            "subject": subj,
                            "stream": "research",
                            "type": "task",
                            "tags": ["feed", &feed.name],
                            "context": ctx,
                        });
                        // Shell out to brana backlog add
                        let _ = std::process::Command::new("brana")
                            .args(["backlog", "add", "--json", &json.to_string()])
                            .status();
                    }
                    _ => {
                        // "log" — append to JSONL
                        let log_entry = FeedLogEntry {
                            feed: feed.name.clone(),
                            title,
                            link,
                            published,
                            polled_at: Utc::now().to_rfc3339(),
                        };
                        if let Ok(line) = serde_json::to_string(&log_entry) {
                            let log_path = feed_log_path();
                            if let Ok(file) = fs::OpenOptions::new()
                                .create(true).append(true).open(&log_path)
                            {
                                let mut w = BufWriter::new(file);
                                let _ = writeln!(w, "{line}");
                            }
                        }
                    }
                }
            }

            // Update state
            state.etag = new_etag;
            state.last_modified = new_lm;
            state.last_entry_ids = current_ids;
            state.last_poll = Some(Utc::now().to_rfc3339());
            state.new_count = new_count;
            save_state(&feed.name, &state)?;

            Ok(new_count)
        }
        Err(ureq::Error::StatusCode(304)) => {
            state.last_poll = Some(Utc::now().to_rfc3339());
            state.new_count = 0;
            save_state(&feed.name, &state)?;
            Ok(0)
        }
        Err(e) => Err(anyhow::anyhow!("HTTP error: {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::env;

    /// Helper: set HOME to a temp dir for test isolation, returns the temp dir.
    /// Must be used with #[serial] — env::set_var is process-global.
    fn with_temp_home() -> tempfile::TempDir {
        let tmp = tempfile::tempdir().unwrap();
        // SAFETY: all callers are #[serial], so no concurrent env mutation
        unsafe { env::set_var("HOME", tmp.path()) };
        tmp
    }

    #[test]
    fn test_derive_name_https() {
        assert_eq!(derive_name("https://simonwillison.net/atom/everything/"), "simonwillison");
    }

    #[test]
    fn test_derive_name_http() {
        assert_eq!(derive_name("http://example.com/feed"), "example");
    }

    #[test]
    fn test_derive_name_substack() {
        assert_eq!(derive_name("https://newsletter.substack.com/feed"), "newsletter");
    }

    #[test]
    #[serial]
    fn test_feed_crud_add_list_remove() {
        let _tmp = with_temp_home();

        // Starts empty
        let feeds = load_feeds();
        assert!(feeds.is_empty());

        // Add a feed
        let feed = FeedEntry {
            name: "test-feed".into(),
            url: "https://example.com/rss".into(),
            action: "log".into(),
            enabled: true,
        };
        save_feeds(&[feed.clone()]).unwrap();

        // List
        let feeds = load_feeds();
        assert_eq!(feeds.len(), 1);
        assert_eq!(feeds[0].name, "test-feed");
        assert_eq!(feeds[0].url, "https://example.com/rss");

        // Remove
        let mut feeds = load_feeds();
        feeds.retain(|f| f.name != "test-feed");
        save_feeds(&feeds).unwrap();
        assert!(load_feeds().is_empty());
    }

    #[test]
    #[serial]
    fn test_feed_state_roundtrip() {
        let _tmp = with_temp_home();

        let state = FeedState {
            etag: Some("\"abc123\"".into()),
            last_modified: Some("Wed, 19 Mar 2026 10:00:00 GMT".into()),
            last_entry_ids: vec!["id-1".into(), "id-2".into()],
            last_poll: Some("2026-03-19T16:00:00Z".into()),
            new_count: 2,
        };
        save_state("mytest", &state).unwrap();

        let loaded = load_state("mytest");
        assert_eq!(loaded.etag, Some("\"abc123\"".into()));
        assert_eq!(loaded.last_entry_ids.len(), 2);
        assert_eq!(loaded.new_count, 2);
    }

    #[test]
    #[serial]
    fn test_feed_state_missing_returns_default() {
        let _tmp = with_temp_home();
        let state = load_state("nonexistent");
        assert!(state.etag.is_none());
        assert!(state.last_entry_ids.is_empty());
        assert_eq!(state.new_count, 0);
    }

    #[test]
    fn test_feed_log_entry_serialization() {
        let entry = FeedLogEntry {
            feed: "test".into(),
            title: "A Post".into(),
            link: "https://example.com/post".into(),
            published: Some("2026-03-19T10:00:00Z".into()),
            polled_at: "2026-03-19T16:00:00Z".into(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("\"feed\":\"test\""));
        assert!(json.contains("\"title\":\"A Post\""));

        // Roundtrip
        let parsed: FeedLogEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.feed, "test");
    }

    #[test]
    #[serial]
    fn test_duplicate_feed_detection() {
        let _tmp = with_temp_home();

        let feed = FeedEntry {
            name: "dup".into(),
            url: "https://example.com/rss".into(),
            action: "log".into(),
            enabled: true,
        };
        save_feeds(&[feed]).unwrap();

        let feeds = load_feeds();
        assert!(feeds.iter().any(|f| f.name == "dup"));
    }

    #[test]
    #[serial]
    fn test_feed_config_path_uses_home() {
        let _tmp = with_temp_home();
        let path = feeds_config_path();
        assert!(path.to_str().unwrap().contains(".claude/scheduler/feeds.json"));
    }

    #[test]
    #[serial]
    fn test_atomic_state_write() {
        let _tmp = with_temp_home();

        // Write state
        let state = FeedState {
            etag: Some("\"v1\"".into()),
            ..Default::default()
        };
        save_state("atomic-test", &state).unwrap();

        // Verify no .tmp file left behind
        let tmp_path = feed_state_path("atomic-test").with_extension("tmp");
        assert!(!tmp_path.exists());

        // Verify real file exists
        assert!(feed_state_path("atomic-test").exists());
    }
}
