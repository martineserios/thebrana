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
/// 2. Parse each filename: type_slug or type_slug_YYYY-MM-DDTHH-MM-SS.
///    Files with no `type_` prefix (e.g. `{slug}.md`, the naming used by
///    Claude's auto-memory system prompt) fall back to the `metadata.type`
///    field in the file's YAML frontmatter — see `parse_frontmatter_type`.
///    A file with neither a `type_` prefix nor any frontmatter at all is not
///    a memory entry (e.g. an auto-appended flywheel log) and is skipped.
/// 3. Group by (type_slug) key; prefer the newest dated file per key
///    (dated beats plain-slug; newer timestamp beats older)
/// 4. Write MEMORY.md with one entry per key, linking to the winning file
///
/// Before the frontmatter fallback (t-24), every file using the `{slug}.md`
/// naming was silently dropped — a project whose memory dir contains only
/// such files regenerated to an EMPTY index while every underlying file
/// stayed on disk untouched, discovered live 2026-08-05 (truper, 13 files).
pub fn index_memory(scope: &str, project_root: &Path) -> Result<()> {
    let mem_dir = match scope {
        "project" => resolve_memory_dir(project_root),
        "global" => home().join(".claude/memory"),
        other => bail!("invalid scope '{}' for index; use: project, global", other),
    };
    index_memory_dir(&mem_dir)
}

/// Testable core of `index_memory` — operates directly on a memory directory,
/// bypassing project-root resolution so it can run against a `tempdir()` fixture.
fn index_memory_dir(mem_dir: &Path) -> Result<()> {
    if !mem_dir.exists() {
        bail!("memory dir does not exist: {}", mem_dir.display());
    }

    let mut entries: Vec<PathBuf> = fs::read_dir(mem_dir)?
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

        let (key, is_dated, sort_stem) = if let Some((type_part, rest)) = stem.split_once('_') {
            let slug = slug_from_rest(rest);
            (format!("{}_{}", type_part, slug), is_dated_filename(rest), stem.clone())
        } else {
            match parse_frontmatter_type(path) {
                None => continue, // no frontmatter at all — not a memory entry
                Some(ty) => {
                    let type_part = ty.unwrap_or_else(|| "memory".to_string());
                    (format!("{}_{}", type_part, stem), false, stem.clone())
                }
            }
        };

        match best.entry(key) {
            Entry::Vacant(e) => {
                e.insert((path.clone(), is_dated, sort_stem));
            }
            Entry::Occupied(mut e) => {
                let (_, existing_dated, existing_stem) = e.get();
                // Dated beats plain-slug; among dated, newer stem (lexicographic) wins
                if is_dated && (!existing_dated || &sort_stem > existing_stem) {
                    e.insert((path.clone(), is_dated, sort_stem));
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

/// Parse `metadata.type` from a memory file's YAML frontmatter, for files whose
/// filename has no `{type}_` prefix (t-24 — the auto-memory system prompt names
/// files `{slug}.md` and records the type under a nested `metadata: \n  type: X`
/// block instead of in the filename).
///
/// Returns:
/// - `None` — no frontmatter block at all (file doesn't open with a `---` line).
///   Not a memory entry: e.g. an auto-appended flywheel log with no YAML header.
/// - `Some(None)` — frontmatter present, but no `type` field found under `metadata:`.
/// - `Some(Some(ty))` — frontmatter present with a `type` field.
fn parse_frontmatter_type(path: &Path) -> Option<Option<String>> {
    let content = fs::read_to_string(path).ok()?;
    let mut lines = content.lines();
    if lines.next()?.trim() != "---" {
        return None;
    }
    let mut in_metadata = false;
    for line in lines {
        if line.trim() == "---" {
            return Some(None);
        }
        if !line.starts_with(' ') && !line.starts_with('\t') {
            in_metadata = line.trim_end().trim_end_matches(':') == "metadata";
            continue;
        }
        if in_metadata {
            if let Some(rest) = line.trim().strip_prefix("type:") {
                let ty = rest.trim().trim_matches('"').trim_matches('\'');
                if !ty.is_empty() {
                    return Some(Some(ty.to_string()));
                }
            }
        }
    }
    // Frontmatter block never closed — still treat as present-but-typeless
    // rather than as "no frontmatter", since a `---` header was found.
    Some(None)
}

#[cfg(test)]
mod index_tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    fn write(dir: &Path, name: &str, body: &str) {
        fs::create_dir_all(dir).unwrap();
        fs::write(dir.join(name), body).unwrap();
    }

    #[test]
    fn adr038_type_prefixed_files_index_as_before() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "pattern_jwt-auth.md", "some content");
        write(&mem, "feedback_redis-cache.md", "some content");
        index_memory_dir(&mem).unwrap();

        let idx = fs::read_to_string(mem.join("MEMORY.md")).unwrap();
        assert!(idx.contains("pattern_jwt-auth"), "index:\n{idx}");
        assert!(idx.contains("feedback_redis-cache"), "index:\n{idx}");
    }

    /// Regression for t-24: files named `{slug}.md` (no `{type}_` prefix — the
    /// naming Claude's auto-memory system prompt uses) were silently dropped by
    /// `index_memory`, wiping MEMORY.md to an empty header on projects whose
    /// memory dir contained only this style (live 2026-08-05, truper, 13 files).
    #[test]
    fn frontmatter_fallback_recovers_unprefixed_files() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(
            &mem,
            "truper-transaction-shape.md",
            "---\nname: truper-transaction-shape\ndescription: test\nmetadata:\n  type: project\n---\n\nbody\n",
        );
        write(
            &mem,
            "worktree-merge-from-main.md",
            "---\nname: worktree-merge-from-main\ndescription: test\nmetadata: \n  node_type: memory\n  type: feedback\n---\n\nbody\n",
        );
        index_memory_dir(&mem).unwrap();

        let idx = fs::read_to_string(mem.join("MEMORY.md")).unwrap();
        assert!(
            idx.contains("project_truper-transaction-shape"),
            "frontmatter type=project must be recovered; index:\n{idx}"
        );
        assert!(
            idx.contains("feedback_worktree-merge-from-main"),
            "frontmatter type=feedback must be recovered even with a leading space after 'metadata:'; index:\n{idx}"
        );
    }

    #[test]
    fn unprefixed_file_with_no_frontmatter_type_gets_memory_fallback() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "untyped-note.md", "---\nname: untyped-note\n---\n\nbody\n");
        index_memory_dir(&mem).unwrap();

        let idx = fs::read_to_string(mem.join("MEMORY.md")).unwrap();
        assert!(
            idx.contains("memory_untyped-note"),
            "frontmatter present but no type field -> 'memory' fallback; index:\n{idx}"
        );
    }

    /// Files with no YAML frontmatter at all (e.g. an auto-appended flywheel log)
    /// are not memory entries and must stay excluded, exactly as before t-24.
    #[test]
    fn unprefixed_file_with_no_frontmatter_at_all_is_skipped() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "sessions.md", "### Session abc123 (2026-07-31T17:27:31Z)\n- Events: 1124\n");
        index_memory_dir(&mem).unwrap();

        let idx = fs::read_to_string(mem.join("MEMORY.md")).unwrap();
        assert_eq!(idx.trim(), "# Memory Index", "non-memory file must not appear; index:\n{idx}");
    }

    #[test]
    fn mixed_directory_never_regresses_to_fewer_entries_than_valid_files() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write(&mem, "pattern_a.md", "x");
        write(&mem, "b-topic.md", "---\nname: b-topic\nmetadata:\n  type: project\n---\n");
        write(&mem, "c-topic.md", "---\nname: c-topic\nmetadata:\n  type: feedback\n---\n");
        write(&mem, "sessions.md", "not a memory file, no frontmatter\n");
        index_memory_dir(&mem).unwrap();

        let idx = fs::read_to_string(mem.join("MEMORY.md")).unwrap();
        let entry_count = idx.lines().filter(|l| l.starts_with("- [")).count();
        assert_eq!(entry_count, 3, "3 valid memory files (a, b-topic, c-topic); index:\n{idx}");
    }
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
