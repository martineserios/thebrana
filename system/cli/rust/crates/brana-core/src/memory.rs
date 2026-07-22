use anyhow::{bail, Context, Result};
use chrono::Utc;
use rusqlite::Connection;
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

// ── Embedded FTS5 recall index (t-2094) ──────────────────────────────────
//
// A self-contained, zero-ops full-text index over the markdown memory files.
// Replaces the brittle JSONL → embed → ruflo pipeline (index-patterns.sh +
// bulk-index.mjs): no JSONL intermediate, no jq escaping, no embedding model,
// no ruflo dependency. Content is inserted via bound parameters, so quotes,
// colons, braces and other markdown junk index without escaping fragility.
//
// Schema (FTS5 virtual table, rebuilt wholesale on each reindex):
//   memory_fts(slug, mtype, scope, path UNINDEXED, content)
//
// This is the first concrete slice of the recall seam (t-2091): the ruflo-free
// counterpart to `brana knowledge search`. The pluggable SearchProvider trait
// (t-2091) later selects between this and the ruflo-backed provider by config.

/// A single full-text search hit from the embedded memory index.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct MemoryHit {
    pub slug: String,
    pub mtype: String,
    pub scope: String,
    pub path: String,
    pub snippet: String,
}

/// Canonical path to the embedded FTS5 index database.
pub fn fts_index_path() -> PathBuf {
    home().join(".claude/memory/index.db")
}

/// Rebuild the FTS5 index from all memory scopes: global + every
/// `~/.claude/projects/*/memory/` directory. The `project_root` parameter
/// is accepted for forward-compatibility but not used — we always do a
/// full cross-project scan so the index mirrors what `index-patterns.sh`
/// produced.
pub fn reindex_fts(_project_root: &Path, db_path: &Path) -> Result<usize> {
    let h = home();
    let mut dirs: Vec<(String, PathBuf)> = vec![
        ("global".to_string(), h.join(".claude/memory")),
    ];
    // Glob all project memory dirs
    let projects_base = h.join(".claude/projects");
    if let Ok(entries) = fs::read_dir(&projects_base) {
        for entry in entries.flatten() {
            let mem_dir = entry.path().join("memory");
            if mem_dir.is_dir() {
                dirs.push(("project".to_string(), mem_dir));
            }
        }
    }
    reindex_fts_dirs(&dirs, db_path)
}

/// Rebuild the FTS5 index from an explicit list of `(scope, dir)` pairs.
///
/// Extracted from [`reindex_fts`] so tests can point at temp dirs without
/// touching `$HOME`. Each `*.md` file (excluding `MEMORY.md`) becomes one
/// document; the slug/type are parsed from the filename, the body is indexed
/// verbatim. The table is dropped and recreated so the index never drifts from
/// the filesystem.
pub fn reindex_fts_dirs(dirs: &[(String, PathBuf)], db_path: &Path) -> Result<usize> {
    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut conn = Connection::open(db_path)
        .with_context(|| format!("opening FTS index db: {}", db_path.display()))?;

    conn.execute_batch(
        "DROP TABLE IF EXISTS memory_fts;
         CREATE VIRTUAL TABLE memory_fts USING fts5(
             slug, mtype, scope, path UNINDEXED, content
         );",
    )
    .context("creating memory_fts table")?;

    let mut count = 0usize;
    let tx = conn.transaction()?;
    {
        let mut insert = tx.prepare(
            "INSERT INTO memory_fts (slug, mtype, scope, path, content)
             VALUES (?1, ?2, ?3, ?4, ?5)",
        )?;

        for (scope, dir) in dirs {
            if !dir.exists() {
                continue;
            }
            let mut paths: Vec<PathBuf> = fs::read_dir(dir)?
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.extension().map(|e| e == "md").unwrap_or(false))
                .filter(|p| p.file_name().map(|n| n != "MEMORY.md").unwrap_or(true))
                .collect();
            paths.sort();

            for path in &paths {
                let stem = path
                    .file_stem()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_string();
                let (mtype, slug) = match stem.split_once('_') {
                    Some((t, rest)) => (t.to_string(), slug_from_rest(rest).to_string()),
                    None => (String::new(), stem.clone()),
                };
                // Content read verbatim — bound parameter, no escaping needed.
                let content = fs::read_to_string(path).unwrap_or_default();
                insert.execute(rusqlite::params![
                    slug,
                    mtype,
                    scope,
                    path.to_string_lossy(),
                    content,
                ])?;
                count += 1;
            }
        }
    }
    tx.commit()?;
    Ok(count)
}

/// Full-text search the embedded index, returning up to `limit` hits ranked by
/// FTS5 relevance. The query is tokenized into alphanumeric terms (joined with
/// implicit AND) so arbitrary user input — colons, quotes, hyphens — never
/// produces an FTS5 syntax error. An empty/symbol-only query returns no hits.
pub fn search_fts(db_path: &Path, query: &str, limit: usize) -> Result<Vec<MemoryHit>> {
    let match_query = sanitize_fts_query(query);
    if match_query.is_empty() {
        return Ok(Vec::new());
    }
    let conn = Connection::open(db_path)
        .with_context(|| format!("opening FTS index db: {}", db_path.display()))?;

    let mut stmt = conn.prepare(
        "SELECT slug, mtype, scope, path,
                snippet(memory_fts, 4, '[', ']', ' … ', 12) AS snip
         FROM memory_fts
         WHERE memory_fts MATCH ?1
         ORDER BY rank
         LIMIT ?2",
    )?;

    let rows = stmt.query_map(rusqlite::params![match_query, limit as i64], |row| {
        Ok(MemoryHit {
            slug: row.get(0)?,
            mtype: row.get(1)?,
            scope: row.get(2)?,
            path: row.get(3)?,
            snippet: row.get(4)?,
        })
    })?;

    let mut hits = Vec::new();
    for r in rows {
        hits.push(r?);
    }
    Ok(hits)
}

/// Tokenize a free-text query into a safe FTS5 MATCH expression. Splits on
/// non-alphanumerics, wraps each term as a quoted string token (so FTS5 treats
/// it literally — no `-`-as-NOT or bareword-operator surprises), and joins with
/// `OR`. Returns an empty string when no usable terms remain.
///
/// `OR` (not implicit AND) so verbose, natural-language queries degrade
/// gracefully: a query mixing one salient term with several incidental ones no
/// longer requires a single doc to contain *all* of them (which collapsed to
/// zero/wrong hits — t-2293). FTS5 `ORDER BY rank` (BM25, IDF-weighted) then
/// floats the doc matching the rarest/most terms to the top. Single-term queries
/// are unaffected — one token makes AND and OR identical.
fn sanitize_fts_query(q: &str) -> String {
    q.split(|c: char| !c.is_alphanumeric())
        .filter(|t| !t.is_empty())
        .map(|t| format!("\"{t}\""))
        .collect::<Vec<_>>()
        .join(" OR ")
}

#[cfg(test)]
mod fts_tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn write(dir: &Path, name: &str, body: &str) {
        fs::create_dir_all(dir).unwrap();
        fs::write(dir.join(name), body).unwrap();
    }

    #[test]
    fn reindex_and_search_roundtrip() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "pattern_jwt-auth.md", "JWT validation middleware for token login");
        write(&mem, "feedback_redis-cache.md", "Use an in-memory LRU cache, not Redis");
        let db = tmp.path().join("index.db");

        let n = reindex_fts_dirs(&[("global".into(), mem.clone())], &db).unwrap();
        assert_eq!(n, 2, "both markdown files indexed");

        let hits = search_fts(&db, "jwt token", 10).unwrap();
        assert_eq!(hits.len(), 1, "only the jwt doc matches");
        assert_eq!(hits[0].slug, "jwt-auth");
        assert_eq!(hits[0].mtype, "pattern");
        assert_eq!(hits[0].scope, "global");
    }

    /// Regression for t-2094: the entry that crashed the JSONL/bulk-index
    /// pipeline — content with unescaped quotes, braces, colons and `**Why:**`.
    /// With bound-parameter inserts it indexes and is searchable without any
    /// escaping fragility.
    #[test]
    fn malformed_content_indexes_without_crash() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        let nasty = r#"**Why:** mdpdf has no native Mermaid renderer. Ubuntu 23.10+ AppArmor blocks Puppeteer's sandbox, so puppeteer.json must contain `{"args":["--no-sandbox","--disable-setuid-sandbox"]}`. Validated end-to-end 2026-04-14."#;
        write(&mem, "pattern_mdpdf-mermaid_2026-04-14T10-00-00.md", nasty);
        let db = tmp.path().join("index.db");

        let n = reindex_fts_dirs(&[("global".into(), mem.clone())], &db).unwrap();
        assert_eq!(n, 1, "the previously-crashing entry indexes cleanly");

        let hits = search_fts(&db, "mdpdf mermaid puppeteer", 10).unwrap();
        assert_eq!(hits.len(), 1);
        // dated suffix stripped → clean slug
        assert_eq!(hits[0].slug, "mdpdf-mermaid");
    }

    #[test]
    fn empty_or_symbol_query_returns_no_hits() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "pattern_x.md", "some content here");
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();

        assert!(search_fts(&db, "", 10).unwrap().is_empty());
        assert!(search_fts(&db, "  :::  ", 10).unwrap().is_empty());
    }

    /// Regression for t-2293: a verbose, multi-term query must degrade gracefully.
    /// The old sanitizer joined tokens with an implicit AND, so a query mixing one
    /// salient rare term with several common terms required a single doc to contain
    /// *all* of them — collapsing to zero/wrong hits. OR-joining + BM25 `rank`
    /// (IDF-weighted) surfaces the doc matching the rarest/most terms, matching the
    /// single-term result.
    #[test]
    fn verbose_query_degrades_gracefully_to_salient_doc() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        // Salient doc: the only one carrying the rare terms "active"/"epic".
        write(
            &mem,
            "pattern_active-epic-two-copies.md",
            "active_epic lives in two places: deployed cache and repo state",
        );
        // Filler docs saturate the COMMON query terms so their IDF is low —
        // none contain active/epic. Under AND the verbose query hits nothing.
        write(&mem, "note_a.md", "backlog focus resolution project scoped roadmap");
        write(&mem, "note_b.md", "backlog focus resolution project scoped triage");
        write(&mem, "note_c.md", "backlog focus resolution project scoped review");
        write(&mem, "note_d.md", "backlog focus resolution project scoped grooming");
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();

        let verbose = "active_epic backlog focus resolution project-scoped";
        let hits = search_fts(&db, verbose, 10).unwrap();
        assert!(
            !hits.is_empty(),
            "verbose query must not collapse to empty (old implicit-AND join did)"
        );
        assert_eq!(
            hits[0].slug, "active-epic-two-copies",
            "BM25 IDF must float the rare-term doc above common-term filler"
        );
        // Verbose top hit agrees with the single salient-term query (the AC).
        let single = search_fts(&db, "active_epic", 10).unwrap();
        assert_eq!(
            single[0].slug, hits[0].slug,
            "verbose top hit matches single-term top hit"
        );
    }

    #[test]
    fn reindex_is_idempotent_and_drops_stale() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "pattern_one.md", "alpha beta gamma");
        let db = tmp.path().join("index.db");

        reindex_fts_dirs(&[("global".into(), mem.clone())], &db).unwrap();
        assert_eq!(search_fts(&db, "alpha", 10).unwrap().len(), 1);

        // Remove the file and reindex — stale entry must disappear (full rebuild).
        fs::remove_file(mem.join("pattern_one.md")).unwrap();
        write(&mem, "pattern_two.md", "delta epsilon");
        let n = reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();
        assert_eq!(n, 1);
        assert!(search_fts(&db, "alpha", 10).unwrap().is_empty(), "stale doc gone");
        assert_eq!(search_fts(&db, "delta", 10).unwrap().len(), 1);
    }
}
