use anyhow::{bail, Result};
use chrono::Utc;
use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use crate::session::resolve_memory_dir;
use crate::util::home;

/// Write a memory entry to the destination determined by type + scope (ADR-038).
///
/// Routing:
/// - feedback + project  → {project_memory}/feedback_{slug}_{ts}.md  (dated, parallel-safe)
/// - feedback + global   → {global_memory}/feedback_{slug}_{ts}.md   (dated)
/// - project  + project  → {project_memory}/project_{slug}.md        (upsert)
/// - user     + global   → {global_memory}/user_{slug}.md            (upsert)
/// - pattern  + any      → {global_memory}/pattern_{slug}.md         (upsert, git-first)
pub fn write_memory(
    memory_type: &str,
    scope: &str,
    slug: &str,
    content: &str,
    project_root: &Path,
) -> Result<PathBuf> {
    let dest = resolve_dest(memory_type, scope, slug, project_root)?;
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&dest, content)?;
    Ok(dest)
}

fn resolve_dest(
    memory_type: &str,
    scope: &str,
    slug: &str,
    project_root: &Path,
) -> Result<PathBuf> {
    validate_type(memory_type)?;
    match (memory_type, scope) {
        ("feedback", "project") => {
            let dir = resolve_memory_dir(project_root);
            Ok(dir.join(format!("feedback_{}_{}.md", slug, timestamp_now())))
        }
        ("feedback", "global") => {
            let dir = home().join(".claude/memory");
            Ok(dir.join(format!("feedback_{}_{}.md", slug, timestamp_now())))
        }
        ("project", "project") => {
            let dir = resolve_memory_dir(project_root);
            Ok(dir.join(format!("project_{}.md", slug)))
        }
        ("user", "global") => {
            let dir = home().join(".claude/memory");
            Ok(dir.join(format!("user_{}.md", slug)))
        }
        ("pattern", _) => {
            let dir = home().join(".claude/memory");
            Ok(dir.join(format!("pattern_{}.md", slug)))
        }
        ("convention", _) | ("field-note", _) | ("adr", _) => {
            bail!(
                "type '{}' is not yet implemented; use: feedback, project, user, or pattern",
                memory_type
            )
        }
        _ => {
            bail!(
                "unsupported type/scope combination '{}/{}'; see ADR-038 routing table",
                memory_type,
                scope
            )
        }
    }
}

fn validate_type(t: &str) -> Result<()> {
    match t {
        "feedback" | "project" | "user" | "pattern" | "convention" | "field-note" | "adr" => {
            Ok(())
        }
        other => bail!(
            "invalid memory type '{}': expected one of: feedback, project, user, pattern, convention, field-note, adr",
            other
        ),
    }
}

fn timestamp_now() -> String {
    Utc::now().format("%Y-%m-%dT%H-%M-%S").to_string()
}

/// Regenerate MEMORY.md from the filesystem (ADR-038 §D).
///
/// Algorithm:
/// 1. Scan all *.md files in the memory dir (excluding MEMORY.md itself)
/// 2. Parse each filename: type_slug or type_slug_YYYY-MM-DDTHH-MM-SS
/// 3. Group by (type_slug) key; prefer the newest dated file per key
///    (dated beats plain-slug; newer timestamp beats older)
/// 4. Write MEMORY.md with one entry per key, linking to the winning file
pub fn index_memory(scope: &str, project_root: &Path) -> Result<()> {
    let mem_dir = match scope {
        "project" => resolve_memory_dir(project_root),
        "global" => home().join(".claude/memory"),
        other => bail!("invalid scope '{}' for index; use: project, global", other),
    };

    if !mem_dir.exists() {
        bail!("memory dir does not exist: {}", mem_dir.display());
    }

    let mut entries: Vec<PathBuf> = fs::read_dir(&mem_dir)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().map(|e| e == "md").unwrap_or(false))
        .filter(|p| {
            p.file_name()
                .map(|n| n != "MEMORY.md")
                .unwrap_or(true)
        })
        .collect();
    entries.sort();

    // key → (best_path, is_dated, best_stem)
    let mut best: HashMap<String, (PathBuf, bool, String)> = HashMap::new();

    for path in &entries {
        let stem = path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let Some((type_part, rest)) = stem.split_once('_') else {
            continue;
        };
        let slug = slug_from_rest(rest);
        let key = format!("{}_{}", type_part, slug);
        let is_dated = is_dated_filename(rest);

        match best.entry(key) {
            Entry::Vacant(e) => {
                e.insert((path.clone(), is_dated, stem));
            }
            Entry::Occupied(mut e) => {
                let (_, existing_dated, existing_stem) = e.get();
                // Dated beats plain-slug; among dated, newer stem (lexicographic) wins
                if is_dated && (!existing_dated || &stem > existing_stem) {
                    e.insert((path.clone(), is_dated, stem));
                }
            }
        }
    }

    let mut keys: Vec<_> = best.keys().cloned().collect();
    keys.sort();

    let mut lines = vec!["# Memory Index\n".to_string()];
    for key in &keys {
        let (path, _, _) = &best[key];
        let filename = path.file_name().unwrap_or_default().to_string_lossy();
        lines.push(format!("- [{}]({})", key, filename));
    }

    fs::write(mem_dir.join("MEMORY.md"), lines.join("\n") + "\n")?;
    Ok(())
}

/// Extract slug from the "rest" part of a filename (everything after the type prefix).
///
/// "tdd-no-exceptions_2026-05-19T14-00-00" → "tdd-no-exceptions"
/// "tdd-no-exceptions"                     → "tdd-no-exceptions"
/// "batrade-broker-role"                   → "batrade-broker-role"
fn slug_from_rest(rest: &str) -> &str {
    if let Some(pos) = rest.rfind('_') {
        if is_timestamp(&rest[pos + 1..]) {
            return &rest[..pos];
        }
    }
    rest
}

/// Does the rest part contain a timestamp suffix?
fn is_dated_filename(rest: &str) -> bool {
    if let Some(pos) = rest.rfind('_') {
        return is_timestamp(&rest[pos + 1..]);
    }
    false
}

/// Is this string a YYYY-MM-DDTHH-MM-SS timestamp (19 chars, specific separators at fixed positions)?
fn is_timestamp(s: &str) -> bool {
    s.len() == 19
        && s.as_bytes().get(4) == Some(&b'-')
        && s.as_bytes().get(7) == Some(&b'-')
        && s.as_bytes().get(10) == Some(&b'T')
        && s.as_bytes().get(13) == Some(&b'-')
        && s.as_bytes().get(16) == Some(&b'-')
}
