//! `brana log` — append a URL or free-text note to the project's event-log.md.
//!
//! event-log.md is the capture surface for the knowledge pipeline.
//! Format per line: `- HH:MM — <entry> [#tag1 #tag2]`
//! Sections are grouped under `## YYYY-MM-DD` date headers.

use anyhow::{Context, Result};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

use brana_core::knowledge_pipeline::append_event_log_entry;
use brana_core::session::resolve_memory_dir;

pub fn cmd_log(entries: &[String], tags: Option<&str>) -> Result<()> {
    let root = require_project_root()?;
    let tag_list = parse_tags(tags);
    let tag_refs: Vec<&str> = tag_list.iter().map(String::as_str).collect();

    let existing = read_existing_urls(&root)?;

    let mut logged = 0usize;
    let mut skipped = 0usize;
    let mut log_path_out: Option<PathBuf> = None;

    for entry in entries {
        if entry.starts_with("https://") && existing.contains(entry.as_str()) {
            eprintln!("skipped (duplicate): {entry}");
            skipped += 1;
            continue;
        }
        let path = append_event_log_entry(&root, entry, &tag_refs)?;
        log_path_out = Some(path);
        logged += 1;
    }

    if entries.len() == 1 {
        if let Some(path) = log_path_out {
            println!("logged to {}", path.display());
        }
    } else {
        println!("logged {logged}, skipped {skipped} duplicate(s)");
    }

    Ok(())
}

/// Collect all https:// URLs already present in the project event-log.md.
/// Used for deduplication. Returns empty set if the file does not exist.
fn read_existing_urls(root: &Path) -> Result<HashSet<String>> {
    let log_path = resolve_memory_dir(root).join("event-log.md");
    if !log_path.exists() {
        return Ok(HashSet::new());
    }
    let content = std::fs::read_to_string(&log_path)
        .with_context(|| format!("reading {}", log_path.display()))?;
    let urls = content
        .lines()
        .filter_map(|line| {
            line.split_whitespace()
                .find(|t| t.starts_with("https://"))
                .map(|u| u.trim_end_matches(')').trim_end_matches(',').to_string())
        })
        .collect();
    Ok(urls)
}

fn parse_tags(tags: Option<&str>) -> Vec<String> {
    match tags {
        None | Some("") => Vec::new(),
        Some(s) => s
            .split(',')
            .map(|t| t.trim().to_lowercase())
            .filter(|t| !t.is_empty())
            .collect(),
    }
}

fn require_project_root() -> Result<PathBuf> {
    crate::util::find_project_root()
        .context("could not resolve project root (not in git repo and CLAUDE_PROJECT_DIR not set)")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_tags_none_returns_empty() {
        assert!(parse_tags(None).is_empty());
    }

    #[test]
    fn test_parse_tags_empty_string_returns_empty() {
        assert!(parse_tags(Some("")).is_empty());
    }

    #[test]
    fn test_parse_tags_single_tag() {
        assert_eq!(parse_tags(Some("ai")), vec!["ai"]);
    }

    #[test]
    fn test_parse_tags_multiple_tags() {
        assert_eq!(parse_tags(Some("ai,rust")), vec!["ai", "rust"]);
    }

    #[test]
    fn test_parse_tags_trims_whitespace() {
        assert_eq!(parse_tags(Some(" ai , rust ")), vec!["ai", "rust"]);
    }

    #[test]
    fn test_parse_tags_lowercased() {
        assert_eq!(parse_tags(Some("AI,Rust")), vec!["ai", "rust"]);
    }

    #[test]
    fn test_parse_tags_skips_empty_segments() {
        assert_eq!(parse_tags(Some("ai,,rust")), vec!["ai", "rust"]);
    }

    #[test]
    fn test_read_existing_urls_empty_when_no_file() {
        let dir = tempfile::tempdir().unwrap();
        let result = read_existing_urls(dir.path()).unwrap();
        assert!(result.is_empty());
    }
}
