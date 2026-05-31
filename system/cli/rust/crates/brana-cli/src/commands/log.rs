//! `brana log` — append a URL or free-text note to the project's event-log.md.
//!
//! event-log.md is the capture surface for the knowledge pipeline.
//! Format per line: `- HH:MM — <entry> [#tag1 #tag2]`
//! Sections are grouped under `## YYYY-MM-DD` date headers.

use anyhow::{Context, Result};
use std::path::PathBuf;

use brana_core::knowledge_pipeline::append_event_log_entry;

pub fn cmd_log(entry: &str, tags: Option<&str>) -> Result<()> {
    let root = require_project_root()?;
    let tag_list = parse_tags(tags);
    let tag_refs: Vec<&str> = tag_list.iter().map(String::as_str).collect();
    let log_path = append_event_log_entry(&root, entry, &tag_refs)?;
    println!("logged to {}", log_path.display());
    Ok(())
}

/// Parse `--tags "ai,rust"` into `["ai", "rust"]`, trimming whitespace.
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
}
