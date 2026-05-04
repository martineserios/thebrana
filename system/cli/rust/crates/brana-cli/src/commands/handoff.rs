//! Session handoff commands: read/show handoff notes for the current project.
//!
//! Resolves the Claude Code memory directory automatically from the git root,
//! parses session-handoff.md, and returns entries.

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};

use crate::util;

/// Encode a project root path into the CC project directory name.
///
/// CC convention: replace `/` and `_` with `-`.
/// e.g. `/home/user/my_proj` → `-home-user-my-proj`
///
/// Older CC versions preserved underscores, so `resolve_handoff_path`
/// tries both encodings as a fallback.
fn encode_path(project_root: &std::path::Path) -> String {
    project_root
        .to_string_lossy()
        .replace('/', "-")
        .replace('_', "-")
}

/// Encode with only `/` → `-` (legacy CC encoding that preserves underscores).
fn encode_path_legacy(project_root: &std::path::Path) -> String {
    project_root
        .to_string_lossy()
        .replace('/', "-")
}

/// Resolve the CC project memory dir for a given project root.
///
/// Convention: `~/.claude/projects/-{encoded-path}/memory/`
pub fn resolve_memory_dir(project_root: &std::path::Path) -> PathBuf {
    util::home()
        .join(".claude/projects")
        .join(encode_path(project_root))
        .join("memory")
}

/// Resolve the handoff file path for the current project.
/// Tries current encoding first, falls back to legacy (underscore-preserving).
pub fn resolve_handoff_path(project_root: &std::path::Path) -> PathBuf {
    let base = util::home().join(".claude/projects");

    // Current encoding: / and _ → -
    let current = base.join(encode_path(project_root))
        .join("memory/session-handoff.md");
    if current.exists() {
        return current;
    }

    // Legacy encoding: only / → -
    let legacy = base.join(encode_path_legacy(project_root))
        .join("memory/session-handoff.md");
    if legacy.exists() {
        return legacy;
    }

    // Return current encoding path (caller handles missing file)
    current
}

/// A parsed handoff entry.
#[derive(Debug, Clone)]
pub struct HandoffEntry {
    pub heading: String,
    pub body: String,
}

/// Parse all `## ` sections from handoff markdown content.
/// Returns entries in file order (newest first, if the file is written that way).
pub fn parse_entries(content: &str) -> Vec<HandoffEntry> {
    let mut entries = Vec::new();
    let mut current_heading: Option<String> = None;
    let mut current_lines: Vec<&str> = Vec::new();

    for line in content.lines() {
        if let Some(heading_text) = line.strip_prefix("## ") {
            // Flush previous entry
            if let Some(h) = current_heading.take() {
                let body = current_lines.join("\n").trim().to_string();
                entries.push(HandoffEntry { heading: h, body });
                current_lines.clear();
            }
            current_heading = Some(heading_text.to_string());
        } else if current_heading.is_some() {
            current_lines.push(line);
        }
    }

    // Flush last entry
    if let Some(h) = current_heading {
        let body = current_lines.join("\n").trim().to_string();
        entries.push(HandoffEntry { heading: h, body });
    }

    entries
}

// ── Commands ────────────────────────────────────────────────────────────

pub fn cmd_handoff_last(n: usize) -> Result<()> {
    let root = util::find_project_root().ok_or_else(|| anyhow!("Not in a git repository"))?;
    let path = resolve_handoff_path(&root);
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("No handoff file found at {}", path.display()))?;

    let entries = parse_entries(&content);
    if entries.is_empty() {
        return Err(anyhow!("No handoff entries found"));
    }

    let count = n.min(entries.len());
    for (i, entry) in entries.iter().take(count).enumerate() {
        if i > 0 {
            println!("\n---\n");
        }
        println!("## {}\n", entry.heading);
        println!("{}", entry.body);
    }
    Ok(())
}

pub fn cmd_handoff_list() -> Result<()> {
    let root = util::find_project_root().ok_or_else(|| anyhow!("Not in a git repository"))?;
    let path = resolve_handoff_path(&root);
    let content = std::fs::read_to_string(&path)
        .with_context(|| format!("No handoff file found at {}", path.display()))?;

    let entries = parse_entries(&content);
    if entries.is_empty() {
        return Err(anyhow!("No handoff entries found"));
    }

    for entry in &entries {
        println!("{}", entry.heading);
    }
    Ok(())
}

pub fn cmd_handoff_path() -> Result<()> {
    let root = util::find_project_root().ok_or_else(|| anyhow!("Not in a git repository"))?;
    let path = resolve_handoff_path(&root);
    println!("{}", path.display());
    Ok(())
}

// ── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn resolve_memory_dir_encodes_path() {
        let root = Path::new("/home/user/projects/myrepo");
        let dir = resolve_memory_dir(root);
        let expected = util::home()
            .join(".claude/projects/-home-user-projects-myrepo/memory");
        assert_eq!(dir, expected);
    }

    #[test]
    fn resolve_memory_dir_replaces_underscores() {
        let root = Path::new("/home/user/enter_thebrana/thebrana");
        let dir = resolve_memory_dir(root);
        let expected = util::home()
            .join(".claude/projects/-home-user-enter-thebrana-thebrana/memory");
        assert_eq!(dir, expected);
    }

    #[test]
    fn encode_path_legacy_preserves_underscores() {
        let root = Path::new("/home/user/enter_thebrana");
        let encoded = encode_path_legacy(root);
        assert_eq!(encoded, "-home-user-enter_thebrana");
    }

    #[test]
    fn resolve_handoff_path_appends_filename() {
        let root = Path::new("/home/user/repo");
        let path = resolve_handoff_path(root);
        assert!(path.ends_with("memory/session-handoff.md"));
    }

    #[test]
    fn parse_entries_empty_content() {
        let entries = parse_entries("");
        assert!(entries.is_empty());
    }

    #[test]
    fn parse_entries_single_entry() {
        let content = "# Session Handoff\n\n## 2026-03-30 — Built feature X\n\n**Accomplished:**\n- Did thing A\n- Did thing B\n";
        let entries = parse_entries(content);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].heading, "2026-03-30 — Built feature X");
        assert!(entries[0].body.contains("Did thing A"));
    }

    #[test]
    fn parse_entries_multiple() {
        let content = "\
## 2026-03-30 — Session 2

**Accomplished:**
- Built content skill

## 2026-03-30 — Session 1

**Accomplished:**
- Fixed scheduler
";
        let entries = parse_entries(content);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].heading, "2026-03-30 — Session 2");
        assert_eq!(entries[1].heading, "2026-03-30 — Session 1");
        assert!(entries[0].body.contains("content skill"));
        assert!(entries[1].body.contains("scheduler"));
    }

    #[test]
    fn parse_entries_preserves_subsections() {
        let content = "\
## 2026-03-30 — Session

**Accomplished:**
- Thing

### Subsection

Details here

**Next:**
- Do stuff
";
        let entries = parse_entries(content);
        assert_eq!(entries.len(), 1);
        assert!(entries[0].body.contains("### Subsection"));
        assert!(entries[0].body.contains("Details here"));
    }

    #[test]
    fn parse_entries_no_h2_headings() {
        let content = "# Title\n\nSome text without sections\n";
        let entries = parse_entries(content);
        assert!(entries.is_empty());
    }
}
