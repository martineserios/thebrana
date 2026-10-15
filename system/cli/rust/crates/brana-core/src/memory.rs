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
/// - pattern  + cross-project → {global_memory}/pattern_{slug}.md    (upsert, git-first)
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
        // t-3254: exact-match, mirroring ("user", "global") — ADR-038 §A lists
        // exactly one valid scope for pattern (cross-project). A wildcard here
        // let ANY scope (e.g. "project") pass through silently discarded,
        // always landing on the same global destination without telling the
        // caller their scope was ignored.
        ("pattern", "cross-project") => {
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

#[cfg(test)]
mod routing_tests {
    use super::*;
    use tempfile::tempdir;

    /// t-3254: ADR-038 §A lists exactly one valid scope for `pattern` —
    /// `cross-project`. Every other type (feedback/project/user) exact-matches
    /// its valid (type, scope) combos and rejects anything else via the
    /// catch-all bail. Before the fix, `("pattern", _)` was a wildcard that
    /// silently accepted (and ignored) ANY scope — including "project" — and
    /// always routed to the global destination. This must now be rejected the
    /// same way `("user", "project")` already is, not silently coerced.
    #[test]
    fn pattern_with_project_scope_is_rejected_not_silently_coerced() {
        let tmp = tempdir().unwrap();
        let root = tmp.path().join("project");
        std::fs::create_dir_all(&root).unwrap();

        let err = resolve_dest("pattern", "project", "some-slug", &root)
            .expect_err("scope=project is not a valid combination for type=pattern per ADR-038");
        assert!(
            err.to_string().contains("unsupported type/scope combination"),
            "error must explain the combo is unsupported, per the same message every \
             other type/scope mismatch uses: {err}"
        );
    }

    /// Symmetric case for scope=global — also not in the ADR-038 table for pattern.
    #[test]
    fn pattern_with_global_scope_is_rejected() {
        let tmp = tempdir().unwrap();
        let root = tmp.path().join("project");
        std::fs::create_dir_all(&root).unwrap();

        let err = resolve_dest("pattern", "global", "some-slug", &root)
            .expect_err("scope=global is not a valid combination for type=pattern per ADR-038");
        assert!(err.to_string().contains("unsupported type/scope combination"));
    }

    /// The one combination ADR-038 actually specifies for pattern must still work.
    #[test]
    fn pattern_with_cross_project_scope_still_resolves_to_global_memory_dir() {
        let tmp = tempdir().unwrap();
        let root = tmp.path().join("project");
        std::fs::create_dir_all(&root).unwrap();

        let dest = resolve_dest("pattern", "cross-project", "some-slug", &root)
            .expect("scope=cross-project is the ADR-038-sanctioned combination for pattern");
        assert!(
            dest.ends_with("pattern_some-slug.md"),
            "unexpected path: {}",
            dest.display()
        );
    }
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

/// The `YYYY-MM-DDTHH-MM-SS` stamp of a dated memory file stem
/// (`feedback_x_2026-08-24T12-37-56`), or `None` for an undated one (t-3537).
pub fn memory_file_stamp(stem: &str) -> Option<&str> {
    let (_, rest) = stem.split_once('_')?;
    let pos = rest.rfind('_')?;
    is_timestamp(&rest[pos + 1..]).then(|| &rest[pos + 1..])
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
    reindex_fts_dirs(&memory_dirs()?, db_path)
}

/// One curated memory file with the identity both recall legs must agree on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MemoryFileRef {
    pub scope: String,
    pub path: PathBuf,
    pub slug: String,
    pub mtype: String,
}

/// Derive `(mtype, slug)` from a memory file stem — the single rule shared by the
/// FTS5 index and the vector index so one file has one identity (t-3510).
///
/// `pattern_foo_2026-06-09T10-00-00` → `("pattern", "foo")`; a stem with no
/// `type_` prefix → `("", stem)`.
pub fn memory_file_identity(stem: &str) -> (String, String) {
    match stem.split_once('_') {
        Some((t, rest)) => (t.to_string(), slug_from_rest(rest).to_string()),
        None => (String::new(), stem.to_string()),
    }
}

/// Every memory scope directory: global + each `~/.claude/projects/*/memory/`.
///
/// Errors when `~/.claude/projects` exists but cannot be read: an unreadable root
/// must not silently become "no projects", or a rebuild would drop every project's
/// notes (t-3510 gate, F5). A missing root is fine (global only).
pub fn memory_dirs() -> Result<Vec<(String, PathBuf)>> {
    memory_dirs_in(&home())
}

/// [`memory_dirs`] rooted at an explicit home directory (testable).
pub fn memory_dirs_in(home_dir: &Path) -> Result<Vec<(String, PathBuf)>> {
    let mut dirs: Vec<(String, PathBuf)> = vec![("global".to_string(), home_dir.join(".claude/memory"))];
    let projects = home_dir.join(".claude/projects");
    match fs::read_dir(&projects) {
        Ok(entries) => {
            for entry in entries {
                let entry = entry.with_context(|| format!("reading {}", projects.display()))?;
                let mem_dir = entry.path().join("memory");
                // `is_dir()` would turn a stat error into "no memory dir" and drop
                // the project from a rebuild silently (t-3510 gate, iteration 2).
                match fs::metadata(&mem_dir) {
                    Ok(m) if m.is_dir() => dirs.push(("project".to_string(), mem_dir)),
                    Ok(_) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e).with_context(|| format!("checking {}", mem_dir.display())),
                }
            }
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e).with_context(|| format!("reading {}", projects.display())),
    }
    Ok(dirs)
}

/// What a scan of memory dirs found, and which dirs were read completely.
///
/// Three outcomes per dir (t-3510 gate, F5):
/// - *complete*: listed fully; its absent files may be pruned.
/// - *failed*: exists but could not be read (permissions, entry error mid-read).
///   Never treated as empty: rebuilds refuse and nothing under it is pruned.
/// - *missing*: does not exist (fresh machine, moved or unmounted dir). Rebuilds
///   skip it as they always did; nothing under it is pruned, and recall hides
///   hits whose file is gone.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct MemoryListing {
    pub files: Vec<MemoryFileRef>,
    pub complete_dirs: Vec<PathBuf>,
    pub failed_dirs: Vec<PathBuf>,
    pub missing_dirs: Vec<PathBuf>,
}

/// List the `*.md` files (excluding `MEMORY.md`) of each `(scope, dir)` pair, sorted
/// per directory, with their recall identity, recording which dirs listed fully.
pub fn list_memory_listing(dirs: &[(String, PathBuf)]) -> MemoryListing {
    let mut listing = MemoryListing::default();
    for (scope, dir) in dirs {
        let read = match fs::read_dir(dir) {
            Ok(read) => read,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                listing.missing_dirs.push(dir.clone());
                continue;
            }
            Err(_) => {
                listing.failed_dirs.push(dir.clone());
                continue;
            }
        };
        let mut complete = true;
        let mut paths: Vec<PathBuf> = Vec::new();
        for entry in read {
            match entry {
                Ok(e) => paths.push(e.path()),
                Err(_) => complete = false,
            }
        }
        paths.retain(|p| p.extension().map(|e| e == "md").unwrap_or(false));
        paths.retain(|p| p.file_name().map(|n| n != "MEMORY.md").unwrap_or(true));
        // Only files are notes (a symlink counts if it points at one). A folder
        // named `x.md` is not an unreadable note: counting it as one made the strict
        // rebuild abort and kept freshness from ever dropping the old row (t-3536).
        // A path whose type cannot be checked stays in, so the failure surfaces as
        // an unreadable note instead of the note silently vanishing.
        paths.retain(|p| fs::metadata(p).map(|m| m.is_file()).unwrap_or(true));
        paths.sort();
        for path in paths {
            let stem = path.file_stem().unwrap_or_default().to_string_lossy().to_string();
            let (mtype, slug) = memory_file_identity(&stem);
            listing.files.push(MemoryFileRef { scope: scope.clone(), path, slug, mtype });
        }
        if complete {
            listing.complete_dirs.push(dir.clone());
        } else {
            listing.failed_dirs.push(dir.clone());
        }
    }
    listing
}

/// The files of [`list_memory_listing`], for callers that only read (recall, tests).
pub fn list_memory_files(dirs: &[(String, PathBuf)]) -> Vec<MemoryFileRef> {
    list_memory_listing(dirs).files
}

/// Rebuild the FTS5 index from an explicit list of `(scope, dir)` pairs.
///
/// Extracted from [`reindex_fts`] so tests can point at temp dirs without
/// touching `$HOME`. Each `*.md` file (excluding `MEMORY.md`) becomes one
/// document; the slug/type are parsed from the filename, the body is indexed
/// verbatim. The table is dropped and recreated so the index never drifts from
/// the filesystem.
///
/// Refuses to rebuild when any existing dir fails to list, before touching the
/// table, so a transient read failure keeps the previous index instead of
/// committing a partial one (t-3510 gate, F5). Missing dirs are skipped.
pub fn reindex_fts_dirs(dirs: &[(String, PathBuf)], db_path: &Path) -> Result<usize> {
    let listing = list_memory_listing(dirs);
    if !listing.failed_dirs.is_empty() {
        anyhow::bail!(
            "memory reindex: could not list {} dir(s): {} (index left unchanged)",
            listing.failed_dirs.len(),
            listing.failed_dirs.iter().map(|d| d.display().to_string()).collect::<Vec<_>>().join(", ")
        );
    }
    if let Some(parent) = db_path.parent() {
        fs::create_dir_all(parent)?;
    }
    // Read every file before touching the index: an unreadable note aborts the
    // rebuild instead of being indexed as empty text (t-3510 gate, iteration 2).
    // The file's state is taken before its text, so a write in between shows up as
    // stale on the next freshness refresh rather than being missed (t-3536).
    let mut docs = Vec::with_capacity(listing.files.len());
    for f in listing.files {
        let state = file_state(&f.path)
            .map(|st| recorded_state(st, now_ns()))
            .with_context(|| format!("memory reindex: checking {} (index left unchanged)", f.path.display()))?;
        let content = fs::read_to_string(&f.path)
            .with_context(|| format!("memory reindex: reading {} (index left unchanged)", f.path.display()))?;
        docs.push((f, state, content));
    }

    let mut conn = Connection::open(db_path)
        .with_context(|| format!("opening FTS index db: {}", db_path.display()))?;

    let mut count = 0usize;
    // DROP, CREATE and every insert commit together, so a failure mid-rebuild
    // leaves the previous index in place rather than an empty one.
    let tx = conn.transaction()?;
    tx.execute_batch(
        "DROP TABLE IF EXISTS memory_fts;
         CREATE VIRTUAL TABLE memory_fts USING fts5(
             slug, mtype, scope, path UNINDEXED, content
         );
         DROP TABLE IF EXISTS memory_files;",
    )
    .context("creating memory_fts table")?;
    tx.execute_batch(FILE_STATE_SCHEMA).context("creating file-state tables")?;
    {
        let mut insert = tx.prepare(
            "INSERT INTO memory_fts (slug, mtype, scope, path, content)
             VALUES (?1, ?2, ?3, ?4, ?5)",
        )?;
        let mut record = tx.prepare(
            "INSERT OR REPLACE INTO memory_files (path, mtime_ns, size) VALUES (?1, ?2, ?3)",
        )?;

        for (f, (mtime_ns, size), content) in docs {
            let path = f.path.to_string_lossy();
            // Content read verbatim — bound parameter, no escaping needed.
            insert.execute(rusqlite::params![f.slug, f.mtype, f.scope, path, content])?;
            record.execute(rusqlite::params![path, mtime_ns, size])?;
            count += 1;
        }
    }
    stamp_refreshed_at(&tx)?;
    tx.commit()?;
    Ok(count)
}

// ── Index freshness (t-3536, ADR-099 §4a) ─────────────────────────────────────

/// Per-file state recorded alongside `memory_fts`, and the last refresh time.
const FILE_STATE_SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS memory_files (
        path     TEXT PRIMARY KEY,
        mtime_ns INTEGER NOT NULL,
        size     INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS memory_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );";

/// `(mtime in ns since the epoch, size in bytes)` — what freshness compares.
fn file_state(path: &Path) -> std::io::Result<(i64, i64)> {
    let meta = fs::metadata(path)?;
    let mtime_ns = meta
        .modified()?
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as i64)
        .unwrap_or(0);
    Ok((mtime_ns, meta.len() as i64))
}

/// Notes modified this close to the moment their state is recorded are recorded
/// as suspect: a same-size rewrite inside the same filesystem clock tick would
/// otherwise look unchanged ("racily clean"; git handles it the same way).
const RACY_WINDOW_NS: i64 = 2_000_000_000;

fn now_ns() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as i64)
        .unwrap_or(0)
}

/// The state to record for a note whose `state` was taken at `taken_ns`. A suspect
/// note is recorded with mtime 0, which never matches a real stat, so the next
/// check re-reads it once; by then its mtime is old enough to record as is.
fn recorded_state((mtime_ns, size): (i64, i64), taken_ns: i64) -> (i64, i64) {
    // Two-sided: a future mtime (clock skew, `touch -d`, a restore) cannot be shared
    // by a later rewrite, so it is recorded as is rather than re-read forever.
    if (mtime_ns - taken_ns).abs() < RACY_WINDOW_NS {
        (0, size)
    } else {
        (mtime_ns, size)
    }
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn stamp_refreshed_at(conn: &Connection) -> Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO memory_meta (key, value) VALUES ('refreshed_at', ?1)",
        [unix_now().to_string()],
    )
    .context("recording index refresh time")?;
    Ok(())
}

/// What a freshness check found and did. Never an error: a refresh that cannot
/// finish leaves the index as it was and says why (ADR-099 §4a fail-open).
///
/// The counts and `index_age_s` describe the index as the check found it, before
/// any refresh; `outcome` says whether the refresh brought it up to date.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct FreshnessReport {
    /// Seconds since the index was last built or refreshed; `None` for an index
    /// built before refresh times were recorded.
    pub index_age_s: Option<u64>,
    /// In-scope notes that were new or changed since the index last saw them.
    pub stale_notes: usize,
    /// Indexed in-scope notes whose file is gone.
    pub deleted_notes: usize,
    /// Stale notes that could not be read: skipped, their previous row kept.
    pub unreadable: usize,
    /// Stale notes this call re-indexed. Less than `stale_notes` when the budget
    /// ran out first: the rest wait for the next call.
    pub refreshed_notes: usize,
    pub outcome: FreshnessOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase", tag = "state", content = "reason")]
pub enum FreshnessOutcome {
    /// Nothing was stale; nothing was written.
    Fresh,
    /// Changes were written (unreadable notes, if any, kept their old rows).
    Refreshed,
    /// The index was left as it was.
    Stale(StaleReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum StaleReason {
    /// The budget ran out before the refresh could commit.
    Timeout,
    /// Another writer held the index longer than the remaining budget.
    Busy,
    /// Every stale note was unreadable, so there was nothing to write.
    Unreadable,
    /// The index is missing or could not be read or written.
    Error,
}

fn stale_reason(e: &rusqlite::Error) -> StaleReason {
    match e.sqlite_error_code() {
        Some(rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked) => StaleReason::Busy,
        _ => StaleReason::Error,
    }
}

/// Bring the FTS index up to date for the notes in `dirs` before a bundle query
/// (t-3536, ADR-099 §4a). Only notes whose recorded mtime or size differ (or that
/// the index has never seen) are re-read; rows whose file is gone are dropped,
/// but only under folders that listed completely. One transaction, written only
/// when something changed. `budget` bounds the whole call, lock waits included;
/// over budget or locked, it rolls back and reports the index as stale.
pub fn refresh_fts_dirs(
    dirs: &[(String, PathBuf)],
    db_path: &Path,
    budget: std::time::Duration,
) -> FreshnessReport {
    let mut report = FreshnessReport {
        index_age_s: None,
        stale_notes: 0,
        deleted_notes: 0,
        unreadable: 0,
        refreshed_notes: 0,
        outcome: FreshnessOutcome::Fresh,
    };
    report.outcome = match refresh_inner(dirs, db_path, budget, &mut report) {
        Ok(outcome) => outcome,
        Err(reason) => FreshnessOutcome::Stale(reason),
    };
    report
}

fn refresh_inner(
    dirs: &[(String, PathBuf)],
    db_path: &Path,
    budget: std::time::Duration,
    report: &mut FreshnessReport,
) -> std::result::Result<FreshnessOutcome, StaleReason> {
    /// Lock wait allowed for the commit even when the budget is spent, so written
    /// notes are not thrown away while a reader finishes. Bounds the overrun.
    const COMMIT_GRACE: std::time::Duration = std::time::Duration::from_millis(200);

    let started = std::time::Instant::now();
    let remaining = || budget.saturating_sub(started.elapsed());
    // `busy_timeout` is per lock wait, not a deadline: re-arm it from the
    // remaining budget before every statement so the waits add up to the budget.
    let arm = |conn: &Connection| conn.busy_timeout(remaining()).map_err(|e| stale_reason(&e));

    // No CREATE flag: a refresh never builds an index from nothing (that is
    // `brana memory reindex`), and never leaves an empty file behind.
    let mut conn = Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|_| StaleReason::Error)?;

    // ── Check phase: stats and reads, no write lock. Always runs, so staleness is
    // reported even when the budget is already spent. ──
    let has_table = |conn: &Connection, name: &str| -> std::result::Result<bool, StaleReason> {
        arm(conn)?;
        conn.query_row(
            "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [name],
            |r| r.get::<_, i64>(0),
        )
        .map(|n| n > 0)
        .map_err(|e| stale_reason(&e))
    };
    if !has_table(&conn, "memory_fts")? {
        return Err(StaleReason::Error);
    }
    let has_state = has_table(&conn, "memory_files")?;
    if has_table(&conn, "memory_meta")? {
        arm(&conn)?;
        let at: Option<String> = conn
            .query_row("SELECT value FROM memory_meta WHERE key = 'refreshed_at'", [], |r| r.get(0))
            .map(Some)
            .or_else(|e| match e {
                rusqlite::Error::QueryReturnedNoRows => Ok(None),
                e => Err(stale_reason(&e)),
            })?;
        report.index_age_s = at
            .and_then(|v| v.parse::<i64>().ok())
            .map(|t| (unix_now() - t).max(0) as u64);
    }
    let mut known: HashMap<String, (i64, i64)> = HashMap::new();
    if has_state {
        arm(&conn)?;
        let mut stmt = conn
            .prepare("SELECT path, mtime_ns, size FROM memory_files")
            .map_err(|e| stale_reason(&e))?;
        let rows = stmt
            .query_map([], |r| Ok((r.get::<_, String>(0)?, (r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))))
            .map_err(|e| stale_reason(&e))?;
        for row in rows {
            let (path, state) = row.map_err(|e| stale_reason(&e))?;
            known.insert(path, state);
        }
    }

    let listing = list_memory_listing(dirs);
    let taken_ns = now_ns();
    // Each path once, even when a folder is listed twice.
    let mut listed: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut stale: Vec<(MemoryFileRef, (i64, i64))> = Vec::new();
    for f in listing.files {
        let path = f.path.to_string_lossy().into_owned();
        if !listed.insert(path.clone()) {
            continue;
        }
        let Ok(state) = file_state(&f.path) else {
            // Vanished since the listing: left to the next check. Still there but
            // impossible to stat (a dangling symlink): reported, never ignored.
            if fs::symlink_metadata(&f.path).is_ok() {
                report.unreadable += 1;
            }
            continue;
        };
        if known.get(&path) != Some(&state) {
            stale.push((f, recorded_state(state, taken_ns)));
        }
    }

    // Deleted: an indexed row directly inside a folder that listed completely
    // whose path is no longer a listed note — the full rebuild's own rule, so a
    // path taken over by something that is not a note counts too. A missing or
    // unlistable folder prunes nothing.
    let mut deleted: Vec<String> = Vec::new();
    for dir in &listing.complete_dirs {
        let prefix = format!("{}/", dir.to_string_lossy().trim_end_matches('/'));
        arm(&conn)?;
        let mut stmt = conn
            .prepare(
                "SELECT path FROM memory_fts
                 WHERE substr(path, 1, length(?1)) = ?1 AND instr(substr(path, length(?1) + 1), '/') = 0",
            )
            .map_err(|e| stale_reason(&e))?;
        let rows = stmt
            .query_map([&prefix], |r| r.get::<_, String>(0))
            .map_err(|e| stale_reason(&e))?;
        for row in rows {
            let path = row.map_err(|e| stale_reason(&e))?;
            // Not listed AND confirmed: gone, or no longer a file. A path a racing
            // directory read missed, or one that cannot be checked, is kept.
            let not_a_note = match fs::metadata(&path) {
                Ok(m) => !m.is_file(),
                Err(e) => e.kind() == std::io::ErrorKind::NotFound,
            };
            if !listed.contains(&path) && not_a_note && !deleted.contains(&path) {
                deleted.push(path);
            }
        }
    }

    report.stale_notes = stale.len();
    report.deleted_notes = deleted.len();
    if stale.is_empty() && deleted.is_empty() {
        return Ok(FreshnessOutcome::Fresh);
    }
    if budget.is_zero() {
        return Err(StaleReason::Timeout); // a zero budget checks and writes nothing
    }

    // Read the stale notes before the write lock, so the transaction does no
    // file I/O and a note that stays unreadable (permissions, not UTF-8) never
    // makes a refresh lock the index for nothing. It is skipped and keeps its
    // previous row (decision 2026-10-15): a failed read is never indexed as empty
    // text and never drops the note. Reading stops at the budget, except that the
    // first readable note is always read: every call makes progress, so a backlog
    // larger than one budget (an old index's first refresh, a bulk import)
    // converges over calls instead of rolling back forever.
    let mut timed_out = false;
    let mut docs: Vec<(MemoryFileRef, (i64, i64), String)> = Vec::with_capacity(stale.len());
    for (f, state) in stale {
        if !docs.is_empty() && started.elapsed() >= budget {
            timed_out = true;
            break;
        }
        match fs::read_to_string(&f.path) {
            Ok(content) => docs.push((f, state, content)),
            Err(_) => report.unreadable += 1,
        }
    }
    if docs.is_empty() && deleted.is_empty() {
        return Err(if timed_out { StaleReason::Timeout } else { StaleReason::Unreadable });
    }

    // ── Write phase: one IMMEDIATE transaction ──
    arm(&conn)?;
    let tx = conn
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(|e| stale_reason(&e))?;
    let mut written = 0usize;
    let mut write = |tx: &rusqlite::Transaction| -> rusqlite::Result<()> {
        tx.execute_batch(FILE_STATE_SCHEMA)?;
        // `path` is UNINDEXED in FTS5, so `DELETE … WHERE path = ?` scans the whole
        // table per note; look every rowid up in one scan, inside the lock.
        let mut rowids: HashMap<String, Vec<i64>> = HashMap::new();
        {
            let mut stmt = tx.prepare("SELECT rowid, path FROM memory_fts")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
            for row in rows {
                let (rowid, path) = row?;
                rowids.entry(path).or_default().push(rowid);
            }
        }
        let mut drop_row = tx.prepare("DELETE FROM memory_fts WHERE rowid = ?1")?;
        let mut drop_state = tx.prepare("DELETE FROM memory_files WHERE path = ?1")?;
        let mut insert = tx.prepare(
            "INSERT INTO memory_fts (slug, mtype, scope, path, content) VALUES (?1, ?2, ?3, ?4, ?5)",
        )?;
        let mut record =
            tx.prepare("INSERT OR REPLACE INTO memory_files (path, mtime_ns, size) VALUES (?1, ?2, ?3)")?;

        for path in &deleted {
            for rowid in rowids.remove(path).into_iter().flatten() {
                drop_row.execute([rowid])?;
            }
            drop_state.execute([path])?;
        }
        // Note by note while the budget lasts, the first always. Each note is
        // written whole, so partial progress leaves a consistent index.
        for (f, (mtime_ns, size), content) in &docs {
            if written > 0 && started.elapsed() >= budget {
                timed_out = true;
                break;
            }
            let path = f.path.to_string_lossy().into_owned();
            for rowid in rowids.remove(&path).into_iter().flatten() {
                drop_row.execute([rowid])?;
            }
            insert.execute(rusqlite::params![f.slug, f.mtype, f.scope, path, content])?;
            rowids.insert(path.clone(), vec![tx.last_insert_rowid()]);
            record.execute(rusqlite::params![path, mtime_ns, size])?;
            written += 1;
        }
        tx.execute(
            "INSERT OR REPLACE INTO memory_meta (key, value) VALUES ('refreshed_at', ?1)",
            [unix_now().to_string()],
        )?;
        Ok(())
    };
    // An error drops `tx`: the whole refresh rolls back.
    write(&tx).map_err(|e| stale_reason(&e))?;
    tx.busy_timeout(remaining().max(COMMIT_GRACE)).map_err(|e| stale_reason(&e))?;
    tx.commit().map_err(|e| stale_reason(&e))?;
    report.refreshed_notes = written;
    if timed_out {
        return Err(StaleReason::Timeout); // progress committed; the rest next call
    }
    Ok(FreshnessOutcome::Refreshed)
}

/// Full-text search the embedded index, returning up to `limit` hits ranked by
/// FTS5 relevance. The query is tokenized into alphanumeric terms (joined with
/// implicit AND) so arbitrary user input — colons, quotes, hyphens — never
/// produces an FTS5 syntax error. An empty/symbol-only query returns no hits.
pub fn search_fts(db_path: &Path, query: &str, limit: usize) -> Result<Vec<MemoryHit>> {
    search_fts_in(db_path, query, limit, None)
}

/// [`search_fts`] limited to notes directly inside `dirs` (sub-folders such as
/// `archive/` are out); `None` searches everything. The limit is applied in SQL
/// before `LIMIT`, so out-of-scope notes cannot use up the result slots (t-3535).
///
/// A missing index is an error, and the index file is not created.
pub fn search_fts_in(
    db_path: &Path,
    query: &str,
    limit: usize,
    dirs: Option<&[PathBuf]>,
) -> Result<Vec<MemoryHit>> {
    let match_query = sanitize_fts_query(query);
    if match_query.is_empty() || dirs.is_some_and(|d| d.is_empty()) {
        return Ok(Vec::new());
    }
    // Read-only: a search never creates the index file or writes to it (journal
    // recovery included), whatever happens to the file between calls.
    let conn = Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .with_context(|| {
        format!("opening FTS index {} (missing? run `brana memory reindex`)", db_path.display())
    })?;

    // Each dir is bound as `<dir>/`: the path must start with it and hold no
    // further `/` after it.
    let prefixes: Vec<String> = dirs
        .unwrap_or(&[])
        .iter()
        .map(|d| format!("{}/", d.to_string_lossy().trim_end_matches('/')))
        .collect();
    let mut sql = String::from(
        "SELECT slug, mtype, scope, path,
                snippet(memory_fts, 4, '[', ']', ' … ', 12) AS snip
         FROM memory_fts
         WHERE memory_fts MATCH ?1",
    );
    if !prefixes.is_empty() {
        let clauses: Vec<String> = (3..3 + prefixes.len())
            .map(|n| {
                format!("(substr(path, 1, length(?{n})) = ?{n} AND instr(substr(path, length(?{n}) + 1), '/') = 0)")
            })
            .collect();
        sql.push_str(&format!(" AND ({})", clauses.join(" OR ")));
    }
    sql.push_str(" ORDER BY rank LIMIT ?2");

    let mut params: Vec<rusqlite::types::Value> =
        vec![match_query.into(), (limit as i64).into()];
    params.extend(prefixes.into_iter().map(rusqlite::types::Value::from));

    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(params), |row| {
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

#[cfg(test)]
mod identity_tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn identity_strips_type_prefix_and_timestamp() {
        assert_eq!(
            memory_file_identity("pattern_foo-bar_2026-06-09T10-00-00"),
            ("pattern".to_string(), "foo-bar".to_string())
        );
    }

    #[test]
    fn identity_without_type_prefix_has_empty_mtype() {
        assert_eq!(
            memory_file_identity("batrade-broker-role"),
            (String::new(), "batrade-broker-role".to_string())
        );
    }

    #[test]
    fn list_memory_files_skips_index_and_non_markdown_and_sorts() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        fs::create_dir_all(&mem).unwrap();
        fs::write(mem.join("pattern_b.md"), "b").unwrap();
        fs::write(mem.join("feedback_a.md"), "a").unwrap();
        fs::write(mem.join("MEMORY.md"), "index").unwrap();
        fs::write(mem.join("notes.txt"), "no").unwrap();

        let files = list_memory_files(&[("project".to_string(), mem.clone()), ("global".to_string(), tmp.path().join("missing"))]);
        let slugs: Vec<_> = files.iter().map(|f| f.slug.as_str()).collect();
        assert_eq!(slugs, vec!["a", "b"], "sorted by filename, MEMORY.md and .txt excluded, missing dir ignored");
        assert_eq!(files[0].scope, "project");
        assert_eq!(files[0].mtype, "feedback");
        assert_eq!(files[0].path, mem.join("feedback_a.md"));
    }

    #[test]
    fn fts_hit_identity_equals_list_identity() {
        // The two recall legs must agree on a file's identity or RRF cannot fuse them.
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        fs::create_dir_all(&mem).unwrap();
        fs::write(mem.join("pattern_scraping-tips_2026-06-09T10-00-00.md"), "web scraping tips").unwrap();
        let dirs = vec![("project".to_string(), mem)];
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&dirs, &db).unwrap();

        let hit = search_fts(&db, "scraping", 5).unwrap().remove(0);
        let f = list_memory_files(&dirs).remove(0);
        assert_eq!((hit.slug, hit.mtype, hit.scope, hit.path), (f.slug, f.mtype, f.scope, f.path.to_string_lossy().to_string()));
    }

    // ── t-3510 gate repair: F5 (failed reads are not empty reads) ──

    /// Root ignores mode bits, so permission tests are vacuous as root (same guard
    /// as brana-cli knowledge.rs).
    fn running_as_root() -> bool {
        unsafe extern "C" {
            fn geteuid() -> u32;
        }
        unsafe { geteuid() == 0 }
    }

    fn set_mode(dir: &std::path::Path, mode: u32) {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(dir, fs::Permissions::from_mode(mode)).unwrap();
    }

    #[test]
    fn listing_reports_failed_dirs_separately_from_complete_ones() {
        if running_as_root() {
            return;
        }
        let tmp = tempdir().unwrap();
        let ok = tmp.path().join("ok");
        let locked = tmp.path().join("locked");
        fs::create_dir_all(&ok).unwrap();
        fs::create_dir_all(&locked).unwrap();
        fs::write(ok.join("pattern_a.md"), "a").unwrap();
        fs::write(locked.join("pattern_b.md"), "b").unwrap();
        let missing = tmp.path().join("missing");
        set_mode(&locked, 0o000);

        let l = list_memory_listing(&[
            ("project".to_string(), ok.clone()),
            ("project".to_string(), locked.clone()),
            ("global".to_string(), missing.clone()),
        ]);
        set_mode(&locked, 0o755);

        assert_eq!(l.files.len(), 1);
        assert_eq!(l.complete_dirs, vec![ok]);
        assert_eq!(l.failed_dirs, vec![locked], "an unreadable dir is a failure, not empty");
        assert_eq!(l.missing_dirs, vec![missing], "a missing dir is neither complete nor failed");
    }

    #[test]
    fn reindex_skips_a_missing_dir_like_a_fresh_machine() {
        // A fresh machine has no ~/.claude/memory yet: reindex must still succeed.
        let tmp = tempdir().unwrap();
        let a = tmp.path().join("a");
        fs::create_dir_all(&a).unwrap();
        fs::write(a.join("pattern_alpha.md"), "alpha scraping").unwrap();
        let dirs = vec![("global".to_string(), tmp.path().join("no-such-dir")), ("project".to_string(), a)];
        let db = tmp.path().join("index.db");

        assert_eq!(reindex_fts_dirs(&dirs, &db).unwrap(), 1);
    }

    #[test]
    fn fts_provider_over_fetches_so_ghosts_do_not_crowd_out_live_hits() {
        // Critic #3: filtering ghosts after a top_k fetch can return nothing.
        use crate::search::{FTS5Provider, SearchProvider};
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        fs::create_dir_all(&mem).unwrap();
        for i in 0..3 {
            fs::write(mem.join(format!("pattern_ghost{i}.md")), "scraping scraping scraping scraping").unwrap();
        }
        fs::write(mem.join("pattern_live.md"), "scraping once among many other unrelated words here").unwrap();
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("project".to_string(), mem.clone())], &db).unwrap();
        for i in 0..3 {
            fs::remove_file(mem.join(format!("pattern_ghost{i}.md"))).unwrap();
        }

        let hits = FTS5Provider::new(db).query("scraping", 2);

        assert_eq!(hits.len(), 1, "the live hit must survive ghost filtering: {hits:?}");
    }

    #[test]
    fn reindex_refuses_a_partial_listing_and_keeps_the_existing_index() {
        if running_as_root() {
            return;
        }
        let tmp = tempdir().unwrap();
        let a = tmp.path().join("a");
        let b = tmp.path().join("b");
        fs::create_dir_all(&a).unwrap();
        fs::create_dir_all(&b).unwrap();
        fs::write(a.join("pattern_alpha.md"), "alpha scraping").unwrap();
        fs::write(b.join("pattern_beta.md"), "beta pricing").unwrap();
        let dirs = vec![("project".to_string(), a.clone()), ("project".to_string(), b.clone())];
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&dirs, &db).unwrap();

        set_mode(&b, 0o000);
        let res = reindex_fts_dirs(&dirs, &db);
        set_mode(&b, 0o755);

        assert!(res.is_err(), "a dir that fails to list must abort the rebuild");
        assert_eq!(search_fts(&db, "pricing", 5).unwrap().len(), 1, "old index untouched (no DROP before the check)");
    }

    #[test]
    fn memory_dirs_in_errors_when_the_projects_root_is_unreadable() {
        if running_as_root() {
            return;
        }
        let tmp = tempdir().unwrap();
        let projects = tmp.path().join(".claude/projects");
        fs::create_dir_all(projects.join("p1/memory")).unwrap();
        fs::create_dir_all(tmp.path().join(".claude/memory")).unwrap();

        let ok = memory_dirs_in(tmp.path()).unwrap();
        assert_eq!(ok.len(), 2, "global + one project");

        set_mode(&projects, 0o000);
        let res = memory_dirs_in(tmp.path());
        set_mode(&projects, 0o755);
        assert!(res.is_err(), "an unreadable projects root must not silently become 'no projects'");

        let empty_home = tempdir().unwrap();
        assert_eq!(memory_dirs_in(empty_home.path()).unwrap().len(), 1, "no projects root at all is fine: global only");
    }

    #[test]
    fn fts_provider_drops_hits_whose_file_was_deleted() {
        // F2 for the keyword leg: the weekly index must not surface deleted notes.
        use crate::search::{FTS5Provider, SearchProvider};
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        fs::create_dir_all(&mem).unwrap();
        fs::write(mem.join("pattern_gone.md"), "scraping ghost").unwrap();
        fs::write(mem.join("pattern_here.md"), "scraping alive").unwrap();
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("project".to_string(), mem.clone())], &db).unwrap();
        fs::remove_file(mem.join("pattern_gone.md")).unwrap();

        let hits = FTS5Provider::new(db).query("scraping", 5);

        assert_eq!(hits.len(), 1, "ghost hit surfaced: {hits:?}");
    }

    #[test]
    fn reindex_refuses_an_unreadable_file_and_keeps_the_existing_index() {
        // Gate iteration 2: an unreadable note must not be indexed as empty text.
        if running_as_root() {
            return;
        }
        let tmp = tempdir().unwrap();
        let a = tmp.path().join("a");
        fs::create_dir_all(&a).unwrap();
        fs::write(a.join("pattern_alpha.md"), "alpha scraping").unwrap();
        fs::write(a.join("pattern_beta.md"), "beta pricing").unwrap();
        let dirs = vec![("project".to_string(), a.clone())];
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&dirs, &db).unwrap();

        set_mode(&a.join("pattern_beta.md"), 0o000);
        let res = reindex_fts_dirs(&dirs, &db);
        set_mode(&a.join("pattern_beta.md"), 0o644);

        assert!(res.is_err(), "an unreadable file must abort the rebuild");
        assert_eq!(search_fts(&db, "pricing", 5).unwrap().len(), 1, "old index kept");
        assert_eq!(search_fts(&db, "scraping", 5).unwrap().len(), 1, "old index kept");
    }

    #[test]
    fn memory_dirs_in_errors_when_a_project_memory_dir_cannot_be_checked() {
        // Gate iteration 2: is_dir() swallowed stat errors, so an unreadable project
        // silently dropped out of the rebuild.
        if running_as_root() {
            return;
        }
        let tmp = tempdir().unwrap();
        let projects = tmp.path().join(".claude/projects");
        fs::create_dir_all(projects.join("p1/memory")).unwrap();
        fs::create_dir_all(projects.join("p2-no-memory")).unwrap();

        set_mode(&projects.join("p1"), 0o000);
        let res = memory_dirs_in(tmp.path());
        set_mode(&projects.join("p1"), 0o755);

        assert!(res.is_err(), "a project whose memory dir cannot be checked must not vanish silently");
        assert_eq!(memory_dirs_in(tmp.path()).unwrap().len(), 2, "global + p1; p2 has no memory dir");
    }
}

#[cfg(test)]
mod freshness_tests {
    //! Index freshness at bundle time (t-3536, ADR-099 §4a).
    use super::*;
    use std::fs;
    use std::time::{Duration, SystemTime};
    use tempfile::{tempdir, TempDir};

    const BUDGET: Duration = Duration::from_secs(5);

    /// Root ignores mode bits, so permission tests are vacuous as root.
    fn running_as_root() -> bool {
        unsafe extern "C" {
            fn geteuid() -> u32;
        }
        unsafe { geteuid() == 0 }
    }

    fn set_mode(p: &Path, mode: u32) {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(p, fs::Permissions::from_mode(mode)).unwrap();
    }

    /// Set a file's mtime relative to now (negative = in the past).
    fn set_mtime(p: &Path, offset_s: i64) {
        let now = SystemTime::now();
        let t = if offset_s >= 0 {
            now + Duration::from_secs(offset_s as u64)
        } else {
            now - Duration::from_secs((-offset_s) as u64)
        };
        fs::File::options().write(true).open(p).unwrap().set_modified(t).unwrap();
    }

    struct Fx {
        _tmp: TempDir,
        dir: PathBuf,
        db: PathBuf,
        dirs: Vec<(String, PathBuf)>,
    }

    /// One indexed note, `pattern_old.md` ("old alpha"), built by the full rebuild.
    fn fx() -> Fx {
        let tmp = tempdir().unwrap();
        let dir = tmp.path().join("memory");
        fs::create_dir_all(&dir).unwrap();
        write_note(&dir.join("pattern_old.md"), "old alpha");
        let db = tmp.path().join("index.db");
        let dirs = vec![("global".to_string(), dir.clone())];
        reindex_fts_dirs(&dirs, &db).unwrap();
        Fx { _tmp: tmp, dir, db, dirs }
    }

    /// Write a note dated a minute ago, outside the racily-clean window.
    fn write_note(p: &Path, body: &str) {
        fs::write(p, body).unwrap();
        set_mtime(p, -60);
    }

    fn found(db: &Path, q: &str) -> Vec<String> {
        let mut out: Vec<String> = search_fts(db, q, 10).unwrap().into_iter().map(|h| h.slug).collect();
        out.sort();
        out
    }

    #[test]
    fn a_note_written_after_the_index_build_is_found_after_refresh() {
        // Must-fire: without the refresh the new note is invisible.
        let f = fx();
        fs::write(f.dir.join("pattern_new.md"), "zebra crossing").unwrap();
        assert!(found(&f.db, "zebra").is_empty(), "fixture: not indexed yet");

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.stale_notes, 1);
        assert_eq!(r.outcome, FreshnessOutcome::Refreshed);
        assert_eq!(found(&f.db, "zebra"), vec!["new"]);
        assert_eq!(found(&f.db, "alpha"), vec!["old"], "untouched notes stay");
    }

    #[test]
    fn a_new_note_with_an_old_mtime_is_still_picked_up() {
        let f = fx();
        let p = f.dir.join("pattern_copied.md");
        fs::write(&p, "zebra copied in").unwrap();
        set_mtime(&p, -365 * 24 * 3600);

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.stale_notes, 1);
        assert_eq!(found(&f.db, "zebra"), vec!["copied"]);
    }

    #[test]
    fn an_edited_note_is_reindexed_with_its_new_text() {
        let f = fx();
        let p = f.dir.join("pattern_old.md");
        fs::write(&p, "old beta").unwrap();
        set_mtime(&p, 10);

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.stale_notes, 1);
        assert_eq!(found(&f.db, "beta"), vec!["old"]);
        assert!(found(&f.db, "alpha").is_empty(), "the old text is replaced, not duplicated");
    }

    #[test]
    fn a_deleted_note_is_dropped() {
        let f = fx();
        fs::remove_file(f.dir.join("pattern_old.md")).unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.deleted_notes, 1);
        assert_eq!(r.outcome, FreshnessOutcome::Refreshed);
        assert!(found(&f.db, "alpha").is_empty());
    }

    #[test]
    fn a_fresh_index_is_not_written() {
        let f = fx();
        let before = fs::metadata(&f.db).unwrap().modified().unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.outcome, FreshnessOutcome::Fresh);
        assert_eq!((r.stale_notes, r.deleted_notes, r.unreadable), (0, 0, 0));
        assert!(r.index_age_s.is_some_and(|a| a < 60), "built moments ago: {:?}", r.index_age_s);
        assert_eq!(fs::metadata(&f.db).unwrap().modified().unwrap(), before);
    }

    #[test]
    fn over_budget_rolls_back_and_keeps_the_stale_index() {
        let f = fx();
        fs::write(f.dir.join("pattern_new.md"), "zebra crossing").unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, Duration::ZERO);

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Timeout));
        assert_eq!(r.stale_notes, 1, "staleness is still reported");
        assert!(found(&f.db, "zebra").is_empty());
        assert_eq!(found(&f.db, "alpha"), vec!["old"]);
    }

    #[test]
    fn a_locked_index_falls_back_to_stale_within_the_budget() {
        let f = fx();
        fs::write(f.dir.join("pattern_new.md"), "zebra crossing").unwrap();
        let lock = Connection::open(&f.db).unwrap();
        lock.execute_batch("BEGIN EXCLUSIVE").unwrap();

        let started = std::time::Instant::now();
        let r = refresh_fts_dirs(&f.dirs, &f.db, Duration::from_millis(300));
        let waited = started.elapsed();
        lock.execute_batch("ROLLBACK").unwrap();

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Busy));
        // Every statement re-arms its lock wait from the remaining budget, so the
        // call as a whole stays near the budget, not a multiple of it.
        assert!(waited < Duration::from_millis(800), "waited {waited:?}, budget was 300 ms");
        assert_eq!(found(&f.db, "alpha"), vec!["old"]);
    }

    #[test]
    fn an_unreadable_note_keeps_its_old_row_and_other_changes_land() {
        if running_as_root() {
            return;
        }
        let f = fx();
        let old = f.dir.join("pattern_old.md");
        fs::write(&old, "old beta").unwrap();
        set_mtime(&old, 10);
        set_mode(&old, 0o000);
        write_note(&f.dir.join("pattern_new.md"), "zebra crossing");

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);
        set_mode(&old, 0o644);

        assert_eq!(r.unreadable, 1);
        assert_eq!(r.outcome, FreshnessOutcome::Refreshed);
        assert_eq!(found(&f.db, "zebra"), vec!["new"]);
        assert_eq!(found(&f.db, "alpha"), vec!["old"], "never emptied or dropped");
        assert!(found(&f.db, "beta").is_empty());

        // Readable again: the next refresh picks the edit up.
        let again = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);
        assert_eq!(again.stale_notes, 1);
        assert_eq!(found(&f.db, "beta"), vec!["old"]);
    }

    #[test]
    fn a_folder_that_cannot_be_listed_keeps_its_rows() {
        if running_as_root() {
            return;
        }
        let f = fx();
        let other = f._tmp.path().join("project-memory");
        fs::create_dir_all(&other).unwrap();
        fs::write(other.join("pattern_gamma.md"), "gamma ray").unwrap();
        let dirs = vec![f.dirs[0].clone(), ("project".to_string(), other.clone())];
        reindex_fts_dirs(&dirs, &f.db).unwrap();

        set_mode(&other, 0o000);
        let r = refresh_fts_dirs(&dirs, &f.db, BUDGET);
        set_mode(&other, 0o755);

        assert_eq!(r.deleted_notes, 0);
        assert_eq!(found(&f.db, "gamma"), vec!["gamma"]);
    }

    #[test]
    fn a_missing_folder_keeps_its_rows() {
        let f = fx();
        let other = f._tmp.path().join("project-memory");
        fs::create_dir_all(&other).unwrap();
        fs::write(other.join("pattern_gamma.md"), "gamma ray").unwrap();
        let dirs = vec![f.dirs[0].clone(), ("project".to_string(), other.clone())];
        reindex_fts_dirs(&dirs, &f.db).unwrap();
        fs::rename(&other, f._tmp.path().join("moved-away")).unwrap();

        let r = refresh_fts_dirs(&dirs, &f.db, BUDGET);

        assert_eq!(r.deleted_notes, 0, "a vanished folder (unmounted, moved) prunes nothing");
        assert_eq!(found(&f.db, "gamma"), vec!["gamma"]);
    }

    #[test]
    fn an_index_from_an_older_build_is_refreshed_once() {
        let f = fx();
        // An older binary's index: memory_fts only, no file-state tables.
        Connection::open(&f.db)
            .unwrap()
            .execute_batch("DROP TABLE IF EXISTS memory_files; DROP TABLE IF EXISTS memory_meta;")
            .unwrap();

        let first = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);
        let second = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(first.index_age_s, None, "no build time recorded yet");
        assert_eq!((first.stale_notes, first.outcome.clone()), (1, FreshnessOutcome::Refreshed));
        assert_eq!(second.outcome, FreshnessOutcome::Fresh);
        assert_eq!(found(&f.db, "alpha"), vec!["old"], "re-indexed once, not duplicated");
    }

    #[test]
    fn a_backlog_larger_than_the_budget_converges_over_calls() {
        // Must-fire: an all-or-nothing refresh that times out never catches up
        // (measured 2026-10-15: a 402-note first refresh took 1.6 s).
        let f = fx();
        for i in 0..60 {
            write_note(&f.dir.join(format!("pattern_bulk-{i}.md")), &format!("bulk note {i}"));
        }
        let tiny = Duration::from_nanos(1);

        let first = refresh_fts_dirs(&f.dirs, &f.db, tiny);
        assert_eq!(first.outcome, FreshnessOutcome::Stale(StaleReason::Timeout));
        assert!(first.refreshed_notes >= 1, "every non-zero budget makes progress");

        let mut calls = 1;
        while refresh_fts_dirs(&f.dirs, &f.db, tiny).outcome != FreshnessOutcome::Fresh {
            calls += 1;
            assert!(calls <= 61, "did not converge");
        }
        assert_eq!(search_fts(&f.db, "bulk", 100).unwrap().len(), 60);
    }

    #[test]
    fn a_completed_refresh_reports_how_many_notes_it_wrote() {
        let f = fx();
        fs::write(f.dir.join("pattern_new.md"), "zebra crossing").unwrap();
        fs::remove_file(f.dir.join("pattern_old.md")).unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!((r.refreshed_notes, r.deleted_notes, r.outcome), (1, 1, FreshnessOutcome::Refreshed));
    }

    #[test]
    fn a_note_replaced_by_a_non_note_is_dropped_even_though_its_path_exists() {
        // Second variant of "deleted": the path still exists but is no longer a
        // note (here a folder took its name), so "file gone" never fires; the
        // listing — the rebuild's own rule — decides.
        let f = fx();
        fs::remove_file(f.dir.join("pattern_old.md")).unwrap();
        fs::create_dir(f.dir.join("pattern_old.md")).unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.deleted_notes, 1);
        assert!(found(&f.db, "alpha").is_empty());
    }

    #[test]
    fn an_unreadable_first_note_does_not_block_progress() {
        if running_as_root() {
            return;
        }
        let f = fx();
        let stuck = f.dir.join("pattern_aaa-stuck.md");
        write_note(&stuck, "stuck");
        set_mode(&stuck, 0o000);
        write_note(&f.dir.join("pattern_zzz-new.md"), "zebra crossing");

        let r = refresh_fts_dirs(&f.dirs, &f.db, Duration::from_nanos(1));
        set_mode(&stuck, 0o644);

        assert_eq!(r.refreshed_notes, 1, "the first readable note always goes through: {r:?}");
        assert_eq!(found(&f.db, "zebra"), vec!["zzz-new"]);
    }

    #[test]
    fn only_unreadable_changes_take_no_write_lock() {
        if running_as_root() {
            return;
        }
        let f = fx();
        let stuck = f.dir.join("pattern_stuck.md");
        write_note(&stuck, "stuck");
        set_mode(&stuck, 0o000);
        // A writer holds the reserved lock: a refresh that tried to write would
        // report Busy; one that knows it has nothing to write never asks.
        let other = Connection::open(&f.db).unwrap();
        other.execute_batch("BEGIN IMMEDIATE").unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, Duration::from_millis(200));
        other.execute_batch("ROLLBACK").unwrap();
        set_mode(&stuck, 0o644);

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Unreadable));
        assert_eq!(r.unreadable, 1);
    }

    #[test]
    fn a_write_error_rolls_the_whole_refresh_back() {
        let f = fx();
        // The failing note sorts last, so an earlier note is already written when
        // the error hits: only a whole-transaction rollback leaves nothing behind.
        write_note(&f.dir.join("pattern_fine.md"), "zebra crossing");
        write_note(&f.dir.join("pattern_zboom.md"), "zebra boom");
        let c = Connection::open(&f.db).unwrap();
        c.execute_batch(
            "CREATE TRIGGER boom BEFORE INSERT ON memory_files WHEN NEW.path LIKE '%boom%'
             BEGIN SELECT RAISE(ABORT, 'boom'); END;",
        )
        .unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Error));
        assert_eq!(r.refreshed_notes, 0);
        assert!(found(&f.db, "zebra").is_empty(), "nothing from a failed refresh commits");
        assert_eq!(found(&f.db, "alpha"), vec!["old"]);
    }

    #[test]
    fn a_folder_listed_twice_does_not_duplicate_rows() {
        let f = fx();
        write_note(&f.dir.join("pattern_new.md"), "zebra crossing");
        let twice = vec![f.dirs[0].clone(), ("project".to_string(), f.dir.clone())];

        refresh_fts_dirs(&twice, &f.db, BUDGET);

        assert_eq!(search_fts(&f.db, "zebra", 10).unwrap().len(), 1);
    }

    #[test]
    fn a_same_size_rewrite_in_the_same_clock_tick_is_not_missed() {
        // Racily clean: the state recorded for a note modified moments before it
        // was recorded cannot prove a later same-size rewrite in the same tick is
        // different, so such a note is re-read on the next check.
        let f = fx();
        let p = f.dir.join("pattern_quick.md");
        fs::write(&p, "first word").unwrap();
        let tick = fs::metadata(&p).unwrap().modified().unwrap();
        refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        fs::write(&p, "other word").unwrap(); // same size
        fs::File::options().write(true).open(&p).unwrap().set_modified(tick).unwrap();
        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.stale_notes, 1);
        assert_eq!(found(&f.db, "other"), vec!["quick"]);
    }

    #[test]
    fn a_folder_named_like_a_note_is_not_a_note_and_does_not_break_the_rebuild() {
        let f = fx();
        fs::create_dir(f.dir.join("pattern_folder.md")).unwrap();

        let listing = list_memory_listing(&f.dirs);
        assert!(listing.files.iter().all(|x| !x.path.ends_with("pattern_folder.md")));
        assert!(reindex_fts_dirs(&f.dirs, &f.db).is_ok(), "a folder is not an unreadable note");
    }

    #[test]
    fn a_missing_index_is_reported_stale_and_never_created() {
        let f = fx();
        let missing = f._tmp.path().join("no-index.db");

        let r = refresh_fts_dirs(&f.dirs, &missing, BUDGET);

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Error));
        assert!(!missing.exists());
    }

    #[test]
    fn a_writer_blocking_only_the_write_phase_falls_back_within_the_budget() {
        // RESERVED lets readers in, so the check phase runs and the wait happens
        // at BEGIN IMMEDIATE.
        let f = fx();
        write_note(&f.dir.join("pattern_new.md"), "zebra crossing");
        let other = Connection::open(&f.db).unwrap();
        other.execute_batch("BEGIN IMMEDIATE").unwrap();

        let started = std::time::Instant::now();
        let r = refresh_fts_dirs(&f.dirs, &f.db, Duration::from_millis(300));
        let waited = started.elapsed();
        other.execute_batch("ROLLBACK").unwrap();

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Busy));
        assert_eq!(r.stale_notes, 1, "the check phase ran");
        assert!(waited < Duration::from_millis(800), "waited {waited:?}, budget was 300 ms");
        assert!(found(&f.db, "zebra").is_empty());
    }

    #[test]
    fn a_note_that_is_not_text_keeps_its_old_row_without_permission_tricks() {
        // Root-independent unreadable note: invalid UTF-8 fails read_to_string.
        let f = fx();
        let old = f.dir.join("pattern_old.md");
        fs::write(&old, [0xff_u8, 0xfe, 0xfd]).unwrap();
        set_mtime(&old, -30);
        write_note(&f.dir.join("pattern_new.md"), "zebra crossing");

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!((r.unreadable, r.outcome), (1, FreshnessOutcome::Refreshed));
        assert_eq!(found(&f.db, "alpha"), vec!["old"], "old row kept");
        assert_eq!(found(&f.db, "zebra"), vec!["new"]);
    }

    #[test]
    fn a_note_that_is_not_text_never_takes_the_write_lock() {
        // Root-independent twin of the permission case: invalid UTF-8 opens fine but
        // fails to read; it must be found before the lock, or every call would lock
        // the index, scan it and roll back.
        let f = fx();
        let bad = f.dir.join("pattern_cp1252.md");
        fs::write(&bad, [0x63_u8, 0x61, 0x66, 0xe9]).unwrap();
        set_mtime(&bad, -60);
        let other = Connection::open(&f.db).unwrap();
        other.execute_batch("BEGIN IMMEDIATE").unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, Duration::from_millis(200));
        other.execute_batch("ROLLBACK").unwrap();

        assert_eq!(r.outcome, FreshnessOutcome::Stale(StaleReason::Unreadable));
        assert_eq!(r.unreadable, 1);
    }

    #[test]
    fn a_future_dated_note_settles_instead_of_being_rewritten_forever() {
        // Clock skew, `touch -d`, a restore: a later rewrite cannot share a future
        // tick, so it is recorded as is and the next check is fresh.
        let f = fx();
        let p = f.dir.join("pattern_future.md");
        fs::write(&p, "from the future").unwrap();
        set_mtime(&p, 3600);

        refresh_fts_dirs(&f.dirs, &f.db, BUDGET);
        let again = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(again.outcome, FreshnessOutcome::Fresh);
    }

    #[test]
    fn the_rebuild_records_a_just_written_note_as_suspect() {
        // Must-fire for the rebuild side of racily clean: a note written moments
        // before the rebuild is re-read on the next check.
        let f = fx();
        let p = f.dir.join("pattern_quick.md");
        fs::write(&p, "first word").unwrap();
        let tick = fs::metadata(&p).unwrap().modified().unwrap();
        reindex_fts_dirs(&f.dirs, &f.db).unwrap();

        fs::write(&p, "other word").unwrap(); // same size, same tick
        fs::File::options().write(true).open(&p).unwrap().set_modified(tick).unwrap();
        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(found(&f.db, "other"), vec!["quick"], "{r:?}");
    }

    #[test]
    fn a_dangling_symlink_is_reported_unreadable_not_ignored() {
        let f = fx();
        std::os::unix::fs::symlink(f.dir.join("gone-target.md"), f.dir.join("pattern_link.md")).unwrap();

        let r = refresh_fts_dirs(&f.dirs, &f.db, BUDGET);

        assert_eq!(r.unreadable, 1, "{r:?}");
    }
}
