//! The recall bundle (t-3537, ADR-099): at most 8 typed pointers for one task.
//! Design: docs/architecture/features/recall-bundle.md §"Bundle assembly".
//!
//! `compute_bundle` refreshes the index, queries the two memory legs and runs the pure
//! stages in [`assemble`]. A pointer is a note's file stem plus its `description` line,
//! never the body. Everything fails open: a bundle can be empty or partial, and the
//! result says which legs and checks degraded.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use serde::Serialize;

use crate::memory::{
    FreshnessReport, MemoryFileRef, list_memory_listing, memory_file_identity, memory_file_stamp,
    refresh_fts_dirs,
};
use crate::search::{DocRef, HybridProvider, LegStatus, RecallScope, SearchHit};

/// Pointers in a bundle at most.
pub const MAX_POINTERS: usize = 8;
/// Pointers of one type at most (v1; tuning only through the gates).
pub const MAX_PER_TYPE: usize = 3;
/// Characters in a gist at most.
pub const GIST_MAX_CHARS: usize = 160;
/// Characters in the query at most.
pub const QUERY_MAX_CHARS: usize = 500;
/// Candidates fetched from each leg.
const CANDIDATE_POOL: usize = 40;
/// Weight of a note with a derived supersession signal.
const DERIVED_SUPERSEDED_WEIGHT: f64 = 0.5;

// ── input ────────────────────────────────────────────────────────────────────

/// What the bundle needs to know about a task. Description, context and notes are
/// deliberately absent: the v1 query is subject + tags only (gates-v1), so a ticket's
/// own pointer text cannot leak into retrieval.
#[derive(Debug, Clone)]
pub struct BundleTask {
    pub id: String,
    pub subject: String,
    pub tags: Vec<String>,
}

/// The v1 query: the subject, then the tags, space-separated, capped.
pub fn build_query(task: &BundleTask) -> String {
    let mut parts: Vec<&str> = vec![task.subject.trim()];
    parts.extend(task.tags.iter().map(|t| t.trim()));
    let joined = parts.into_iter().filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" ");
    joined.chars().take(QUERY_MAX_CHARS).collect::<String>().trim_end().to_string()
}

// ── note parsing ─────────────────────────────────────────────────────────────

/// The few frontmatter fields (and one body signal) the bundle reads from a note.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NoteMeta {
    /// The note opens with a `---` frontmatter block.
    pub has_frontmatter: bool,
    /// `metadata.type`, else the top-level `type`.
    pub type_: Option<String>,
    pub description: Option<String>,
    pub status: Option<String>,
    /// `to:` of every `type: supersedes` relation.
    pub supersedes: Vec<String>,
    /// Targets of `superseded by [[x]]` in the body.
    pub superseded_by: Vec<String>,
}

fn unquote(v: &str) -> &str {
    let v = v.trim();
    for q in ['"', '\''] {
        if v.len() >= 2 && v.starts_with(q) && v.ends_with(q) {
            return &v[1..v.len() - 1];
        }
    }
    v
}

/// Parse a note's frontmatter and body. A note that does not open with a `---` line has
/// no frontmatter, so no field is read from it; the body signal is still read.
pub fn parse_note(content: &str) -> NoteMeta {
    let mut meta = NoteMeta::default();
    let mut lines = content.lines().peekable();
    let mut body_start = 0usize;
    if lines.peek().map(|l| l.trim()) == Some("---") {
        meta.has_frontmatter = true;
        lines.next();
        let mut consumed = 1usize;
        let mut top_type: Option<String> = None;
        let mut meta_type: Option<String> = None;
        let mut section = String::new();
        let mut rel_type: Option<String> = None;
        let mut pending_fold: Option<String> = None; // description: > / |
        let mut closed = false;
        for line in lines.by_ref() {
            consumed += 1;
            if line.trim() == "---" {
                closed = true;
                break;
            }
            let indented = line.starts_with(' ') || line.starts_with('\t');
            if let Some(buf) = pending_fold.as_mut() {
                if indented || line.trim().is_empty() {
                    if !line.trim().is_empty() {
                        if !buf.is_empty() {
                            buf.push(' ');
                        }
                        buf.push_str(line.trim());
                    }
                    continue;
                }
                meta.description = Some(std::mem::take(buf));
                pending_fold = None;
            }
            let t = line.trim();
            if !indented {
                section.clear();
                rel_type = None;
                let Some((k, v)) = t.split_once(':') else { continue };
                let v = v.trim();
                match k.trim() {
                    "type" if !v.is_empty() => top_type = Some(unquote(v).to_string()),
                    "status" if !v.is_empty() => meta.status = Some(unquote(v).to_string()),
                    "description" if v == ">" || v == "|" || v == ">-" || v == "|-" => {
                        pending_fold = Some(String::new())
                    }
                    "description" if !v.is_empty() => meta.description = Some(unquote(v).to_string()),
                    "metadata" | "relations" => section = k.trim().to_string(),
                    _ => {}
                }
                continue;
            }
            match section.as_str() {
                "metadata" => {
                    if let Some(v) = t.strip_prefix("type:") {
                        let v = unquote(v);
                        if !v.is_empty() {
                            meta_type = Some(v.to_string());
                        }
                    }
                }
                "relations" => {
                    let item = t.strip_prefix('-').map(str::trim).unwrap_or(t);
                    if let Some(v) = item.strip_prefix("type:") {
                        rel_type = Some(unquote(v).to_string());
                    } else if let Some(v) = item.strip_prefix("to:")
                        && rel_type.as_deref() == Some("supersedes")
                    {
                        meta.supersedes.push(unquote(v).to_string());
                    }
                }
                _ => {}
            }
        }
        if let Some(buf) = pending_fold.take()
            && !buf.is_empty()
        {
            meta.description = Some(buf);
        }
        meta.type_ = meta_type.or(top_type);
        // An unclosed block has no body to speak of.
        body_start = if closed { consumed } else { usize::MAX };
        if !closed {
            meta.type_ = None;
        }
    }
    if body_start != usize::MAX {
        let body: String = content.lines().skip(body_start).collect::<Vec<_>>().join("\n");
        meta.superseded_by = superseded_by_targets(&body);
    }
    meta
}

/// Targets of `superseded by [[x]]` (case-insensitive), at most 3, in order.
fn superseded_by_targets(body: &str) -> Vec<String> {
    const NEEDLE: &str = "superseded by";
    // ASCII-only folding keeps byte offsets identical to `body`.
    let lower = body.to_ascii_lowercase();
    let mut out: Vec<String> = Vec::new();
    let mut from = 0usize;
    while let Some(i) = lower[from..].find(NEEDLE) {
        let after = from + i + NEEDLE.len();
        let rest = body.get(after..).unwrap_or("").trim_start();
        if let Some(inner) = rest.strip_prefix("[[")
            && let Some(end) = inner.find("]]")
        {
            let t = inner[..end].trim().to_string();
            if !t.is_empty() && !out.contains(&t) {
                out.push(t);
            }
        }
        from = after;
        if out.len() >= 3 {
            break;
        }
    }
    out
}

/// Whether a file is a memory entry: it has a type (frontmatter or filename prefix) or at
/// least a frontmatter block. Logs and state files (`sessions.md`, `session-handoff.md`,
/// `event-log.md`) have neither; the same definition as `memory.rs` uses for "not a memory
/// entry" (user decision 2026-10-15).
pub fn is_memory_entry(file_type: &str, meta: &NoteMeta) -> bool {
    meta.has_frontmatter || meta.type_.is_some() || !file_type.is_empty()
}

/// One line, whitespace collapsed, at most [`GIST_MAX_CHARS`] characters (159 + `…`).
pub fn make_gist(description: Option<&str>) -> Option<String> {
    let collapsed = description?.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.is_empty() {
        return None;
    }
    if collapsed.chars().count() <= GIST_MAX_CHARS {
        return Some(collapsed);
    }
    let mut cut: String = collapsed.chars().take(GIST_MAX_CHARS - 1).collect();
    cut.push('…');
    Some(cut)
}

// ── stages ───────────────────────────────────────────────────────────────────

/// A retrieved note, read and parsed, before the stages.
#[derive(Debug, Clone)]
pub struct Candidate {
    pub path: PathBuf,
    /// The file stem: the pointer's `ref`.
    pub stem: String,
    pub slug: String,
    /// The type from the filename prefix (`""` when there is none).
    pub file_type: String,
    pub rrf: f64,
    pub meta: NoteMeta,
}

/// One entry of a bundle.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Pointer {
    #[serde(rename = "type")]
    pub ptype: String,
    #[serde(rename = "ref")]
    pub ref_: String,
    pub gist: Option<String>,
    pub rank: usize,
    pub flags: Vec<String>,
}

/// `(file type, slug)` → `(newest stamp, that file's stem)`, over the scope's folders.
pub type NewestStamps = HashMap<(String, String), (String, String)>;

/// The newest dated file per `(type, slug)` among `files` (undated files have no stamp).
pub fn newest_stamps(files: &[MemoryFileRef]) -> NewestStamps {
    let mut out: NewestStamps = HashMap::new();
    for f in files {
        let Some(stem) = f.path.file_stem().and_then(|s| s.to_str()) else { continue };
        let Some(stamp) = memory_file_stamp(stem) else { continue };
        let key = (f.mtype.clone(), f.slug.clone());
        if out.get(&key).is_none_or(|(s, _)| stamp > s.as_str()) {
            out.insert(key, (stamp.to_string(), stem.to_string()));
        }
    }
    out
}

/// A `supersedes`/`superseded by` reference reduced to a bare name: last path segment,
/// no `.md`, no `[[ ]]`.
fn bare_name(r: &str) -> String {
    let r = r.trim().trim_start_matches("[[").trim_end_matches("]]").trim();
    let last = r.rsplit('/').next().unwrap_or(r);
    last.strip_suffix(".md").unwrap_or(last).to_string()
}

/// The stages of ADR-099 on already-read candidates: scope, type, supersession, order,
/// quota and cut, gist. Pure.
pub fn assemble(cands: Vec<Candidate>, scope: &RecallScope, newest: &NewestStamps) -> Vec<Pointer> {
    // 1 scope
    let cands: Vec<Candidate> = cands.into_iter().filter(|c| scope.allows(&c.path)).collect();

    // 3 supersession, authoritative part: the ADR-057 status and supersedes-targets
    let targets: HashSet<String> =
        cands.iter().flat_map(|c| c.meta.supersedes.iter().map(|t| bare_name(t))).collect();
    let cands: Vec<Candidate> = cands
        .into_iter()
        .filter(|c| {
            let dead = c.meta.status.as_deref().is_some_and(|s| s.trim().eq_ignore_ascii_case("superseded"));
            let targeted = targets.contains(&c.stem) || targets.contains(&c.slug);
            !dead && !targeted
        })
        .collect();

    // 3 supersession, derived part: down-weight and flag, never drop
    let mut scored: Vec<(f64, Candidate, Vec<String>)> = cands
        .into_iter()
        .map(|c| {
            let mut flags: Vec<String> = Vec::new();
            if let Some(stamp) = memory_file_stamp(&c.stem)
                && let Some((newest_stamp, newer_stem)) = newest.get(&(c.file_type.clone(), c.slug.clone()))
                && stamp < newest_stamp.as_str()
            {
                flags.push(format!("derived-superseded:{newer_stem}"));
            }
            for by in &c.meta.superseded_by {
                flags.push(format!("derived-superseded:{}", bare_name(by)));
            }
            let weight = if flags.is_empty() { 1.0 } else { DERIVED_SUPERSEDED_WEIGHT };
            (c.rrf * weight, c, flags)
        })
        .collect();

    // 4 order
    scored.sort_by(|a, b| {
        b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.1.stem.cmp(&b.1.stem))
    });

    // 2 type, 5 quota and cut, 6 gist
    let mut per_type: HashMap<String, usize> = HashMap::new();
    let mut out: Vec<Pointer> = Vec::new();
    for (_, c, flags) in scored {
        if out.len() >= MAX_POINTERS {
            break;
        }
        let ptype = c
            .meta
            .type_
            .clone()
            .or_else(|| (!c.file_type.is_empty()).then(|| c.file_type.clone()))
            .unwrap_or_else(|| "note".to_string());
        let n = per_type.entry(ptype.clone()).or_insert(0);
        if *n >= MAX_PER_TYPE {
            continue;
        }
        *n += 1;
        out.push(Pointer {
            ptype,
            ref_: c.stem,
            gist: make_gist(c.meta.description.as_deref()),
            rank: out.len() + 1,
            flags,
        });
    }
    out
}

// ── orchestration ────────────────────────────────────────────────────────────

/// Everything `compute_bundle` needs from its surroundings; the CLI builds it from the
/// real paths, tests from fixtures and stub legs.
pub struct BundleEnv<'a> {
    pub scope: RecallScope,
    /// The project folder name (`-home-…-repo`), for the output only.
    pub project: Option<String>,
    /// The scope's `(label, folder)` pairs, for the freshness check and twin detection.
    pub dirs: Vec<(String, PathBuf)>,
    pub knowledge_db: PathBuf,
    pub fts_db: PathBuf,
    pub provider: &'a HybridProvider,
    pub refresh_budget: Duration,
    pub unembedded_wait: Duration,
}

#[derive(Debug, Clone, Serialize)]
pub struct BundleScope {
    pub project: Option<String>,
    pub global: bool,
}

/// Per-leg outcome in the bundle's own words: `fts` is the keyword leg, `vector` the
/// memory-vector leg.
#[derive(Debug, Clone, Serialize)]
pub struct BundleLegs {
    pub fts: LegStatus,
    pub vector: LegStatus,
}

#[derive(Debug, Clone, Serialize)]
pub struct BundleFreshness {
    #[serde(flatten)]
    pub report: FreshnessReport,
    /// In-scope notes without a current vector; `None` when it could not be counted.
    pub unembedded: Option<usize>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Bundle {
    pub task: String,
    pub scope: BundleScope,
    pub shown: bool,
    pub legs: BundleLegs,
    pub pointers: Vec<Pointer>,
    /// Candidates that could not be read as text and were left out.
    pub skipped_unreadable: usize,
    /// Candidates that are logs or state files, not memory entries, and were left out.
    pub skipped_non_entries: usize,
    pub elapsed_ms: u64,
    pub freshness: BundleFreshness,
}

/// Refresh the index, query the legs, read the candidates, run the stages. Never fails:
/// every problem shows up in `legs`, `freshness` or `skipped_unreadable`.
pub fn compute_bundle(task: &BundleTask, env: &BundleEnv) -> Bundle {
    let started = Instant::now();

    let report = refresh_fts_dirs(&env.dirs, &env.fts_db, env.refresh_budget);

    let query = build_query(task);
    let (hits, status) = env.provider.query_with_status(&query, CANDIDATE_POOL);

    let listing = list_memory_listing(&env.dirs);
    let newest = newest_stamps(&listing.files);

    let (cands, skipped_unreadable, skipped_non_entries) = read_candidates(hits);
    let pointers = assemble(cands, &env.scope, &newest);

    let unembedded =
        crate::memory_vectors::unembedded_count(&env.knowledge_db, &listing.files, env.unembedded_wait).ok();

    Bundle {
        task: task.id.clone(),
        scope: BundleScope { project: env.project.clone(), global: true },
        shown: true,
        legs: BundleLegs { fts: status.keyword, vector: status.semantic },
        pointers,
        skipped_unreadable,
        skipped_non_entries,
        elapsed_ms: started.elapsed().as_millis() as u64,
        freshness: BundleFreshness { report, unembedded },
    }
}

/// Memory-file hits only (knowledge-store rows are out in v1), each read once. A note
/// that cannot be read as text is counted, never treated as empty.
fn read_candidates(hits: Vec<SearchHit>) -> (Vec<Candidate>, usize, usize) {
    let mut seen: HashSet<PathBuf> = HashSet::new();
    let mut out = Vec::new();
    let (mut skipped, mut non_entries) = (0usize, 0usize);
    for h in hits {
        let DocRef::MemoryFile { path, .. } = h.doc else { continue };
        if !seen.insert(path.clone()) {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()).map(str::to_string) else { continue };
        let Ok(content) = fs::read_to_string(&path) else {
            skipped += 1;
            continue;
        };
        let (file_type, slug) = memory_file_identity(&stem);
        let meta = parse_note(&content);
        if !is_memory_entry(&file_type, &meta) {
            non_entries += 1;
            continue;
        }
        out.push(Candidate { meta, path, stem, slug, file_type, rrf: h.rrf_score });
    }
    (out, skipped, non_entries)
}

/// The human format: one line per pointer, grouped by type, flagged notes marked.
pub fn format_human(b: &Bundle) -> String {
    let mut out = format!(
        "Recall bundle for {} — {} pointer(s) (fts {}, vector {})\n",
        b.task,
        b.pointers.len(),
        b.legs.fts.as_str(),
        b.legs.vector.as_str()
    );
    let mut types: Vec<&str> = Vec::new();
    for p in &b.pointers {
        if !types.contains(&p.ptype.as_str()) {
            types.push(&p.ptype);
        }
    }
    for t in types {
        out.push_str(&format!("{t}\n"));
        for p in b.pointers.iter().filter(|p| p.ptype == t) {
            out.push_str(&format!("  {}. {}", p.rank, p.ref_));
            if let Some(g) = &p.gist {
                out.push_str(&format!(" — {g}"));
            }
            if !p.flags.is_empty() {
                out.push_str(&format!("  [{}]", p.flags.join(", ")));
            }
            out.push('\n');
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::{list_memory_listing, reindex_fts_dirs};
    use crate::search::{
        DocRef, HybridProvider, LegStatus, RecallScope, SearchHit, SearchProvider,
    };
    use crate::vector::{EMBED_DIM, Embedder};
    use std::collections::HashMap;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::time::Duration;
    use tempfile::tempdir;

    // ── builders ──────────────────────────────────────────────────────────────

    fn meta() -> NoteMeta {
        NoteMeta::default()
    }

    fn cand(stem: &str, rrf: f64, m: NoteMeta) -> Candidate {
        let (file_type, slug) = crate::memory::memory_file_identity(stem);
        Candidate {
            path: PathBuf::from(format!("/h/.claude/memory/{stem}.md")),
            stem: stem.to_string(),
            slug,
            file_type,
            rrf,
            meta: m,
        }
    }

    fn scope() -> RecallScope {
        RecallScope::Dirs(vec![PathBuf::from("/h/.claude/memory")])
    }

    fn refs(p: &[Pointer]) -> Vec<&str> {
        p.iter().map(|x| x.ref_.as_str()).collect()
    }

    // ── query (user decision 2026-10-15: subject + tags only) ─────────────────

    #[test]
    fn query_is_subject_and_tags_only() {
        let t = BundleTask {
            id: "t-1".into(),
            subject: "Fix reindex TEMPFAIL".into(),
            tags: vec!["ruflo".into(), "scheduler".into()],
        };
        assert_eq!(build_query(&t), "Fix reindex TEMPFAIL ruflo scheduler");
    }

    #[test]
    fn query_with_no_subject_and_no_tags_is_empty() {
        let t = BundleTask { id: "t-1".into(), subject: "  ".into(), tags: vec![] };
        assert_eq!(build_query(&t), "");
    }

    #[test]
    fn query_is_capped() {
        let t = BundleTask { id: "t-1".into(), subject: "word ".repeat(400), tags: vec![] };
        assert!(build_query(&t).chars().count() <= QUERY_MAX_CHARS);
    }

    // ── note parsing ─────────────────────────────────────────────────────────

    #[test]
    fn type_from_a_flat_top_level_field() {
        let m = parse_note("---\nname: x\ntype: pattern\ndescription: d\n---\nbody");
        assert_eq!(m.type_.as_deref(), Some("pattern"));
        assert_eq!(m.description.as_deref(), Some("d"));
    }

    #[test]
    fn type_from_the_metadata_block_and_it_wins_over_a_top_level_field() {
        let m = parse_note("---\nname: x\ntype: reference\nmetadata:\n  type: feedback\n---\nbody");
        assert_eq!(m.type_.as_deref(), Some("feedback"));
    }

    #[test]
    fn a_note_without_frontmatter_has_no_type_and_no_description() {
        let m = parse_note("just text\n---\ntype: pattern\n---\n");
        assert_eq!((m.type_, m.description), (None, None));
    }

    #[test]
    fn description_quoted_and_folded() {
        let q = parse_note("---\ndescription: \"quoted: with colon\"\n---\n");
        assert_eq!(q.description.as_deref(), Some("quoted: with colon"));
        let folded = parse_note("---\ndescription: >\n  first line\n  second line\nname: x\n---\n");
        assert_eq!(folded.description.as_deref(), Some("first line second line"));
    }

    #[test]
    fn status_and_supersedes_relations_are_read() {
        let m = parse_note(
            "---\nstatus: Superseded\nrelations:\n  - type: supersedes\n    to: atoms/pattern_old.md\n  - type: informs\n    to: pattern_other\n---\n",
        );
        assert_eq!(m.status.as_deref(), Some("Superseded"));
        assert_eq!(m.supersedes, vec!["atoms/pattern_old.md"]);
    }

    #[test]
    fn prose_superseded_by_is_read_from_the_body_only() {
        let body = parse_note("---\nname: x\n---\nThis was superseded by [[pattern_new]] in 2026.");
        assert_eq!(body.superseded_by, vec!["pattern_new"]);
        let fm_only = parse_note("---\nname: superseded by [[pattern_new]]\n---\nclean body");
        assert!(fm_only.superseded_by.is_empty());
    }

    #[test]
    fn has_frontmatter_tells_notes_from_logs() {
        assert!(parse_note("---\nname: x\n---\nbody").has_frontmatter);
        assert!(!parse_note("# a log\nplain text").has_frontmatter);
        assert!(!parse_note("").has_frontmatter);
    }

    #[test]
    fn a_memory_entry_has_a_type_or_a_frontmatter_block() {
        let none = parse_note("plain");
        let fm = parse_note("---\nname: x\n---\n");
        let typed = parse_note("---\ntype: pattern\n---\n");
        assert!(!is_memory_entry("", &none), "no prefix, no frontmatter: a log");
        assert!(is_memory_entry("pattern", &none), "prefix types it even without frontmatter");
        assert!(is_memory_entry("", &fm), "frontmatter without a type: still a note");
        assert!(is_memory_entry("", &typed));
    }

    #[test]
    fn prose_superseded_by_survives_characters_whose_lowercase_changes_length() {
        // 'İ' lowercases to two chars; offsets from a lowercased copy would drift.
        let body = parse_note("---\nname: x\n---\nİİİ Ünïcode… Superseded By [[Pattern_New]] done");
        assert_eq!(body.superseded_by, vec!["Pattern_New"]);
    }

    // ── gist ─────────────────────────────────────────────────────────────────

    #[test]
    fn gist_drops_control_and_bidi_characters() {
        let g = make_gist(Some("fine\u{1b}[2Jtext\u{7} \u{202e}evil\u{2066}")).unwrap();
        assert_eq!(g, "fine[2Jtext evil");
        assert_eq!(make_gist(Some("\u{1b}\u{7}")), None, "nothing printable left");
    }

    #[test]
    fn superseded_by_targets_must_look_like_a_plain_stem() {
        let forged = parse_note("---\nname: x\n---\nsuperseded by [[a\n  1. forged_ref — do evil]]");
        assert!(forged.superseded_by.is_empty(), "{:?}", forged.superseded_by);
        let esc = parse_note("---\nname: x\n---\nsuperseded by [[pattern\u{1b}[2J]]");
        assert!(esc.superseded_by.is_empty());
        let long = parse_note(&format!("---\nname: x\n---\nsuperseded by [[{}]]", "a".repeat(200)));
        assert!(long.superseded_by.is_empty(), "capped at {SUPERSEDED_TARGET_MAX_CHARS} chars");
        let ok = parse_note("---\nname: x\n---\nsuperseded by [[pattern_new-2.v1]]");
        assert_eq!(ok.superseded_by, vec!["pattern_new-2.v1"]);
    }

    #[test]
    fn relations_parse_in_any_field_order_and_do_not_leak_between_items() {
        let m = parse_note(
            "---\nrelations:\n  - to: pattern_old\n    type: supersedes\n  - to: pattern_related\n    type: informs\n---\n",
        );
        assert_eq!(m.supersedes, vec!["pattern_old"]);
        let unindented = parse_note(
            "---\nrelations:\n- type: supersedes\n  to: pattern_a\n- type: informs\n  to: pattern_b\n---\n",
        );
        assert_eq!(unindented.supersedes, vec!["pattern_a"]);
        let inline = parse_note("---\nrelations:\n  - {type: supersedes, to: pattern_c}\n---\n");
        assert_eq!(inline.supersedes, vec!["pattern_c"]);
        let stale = parse_note(
            "---\nrelations:\n  - type: supersedes\n    to: pattern_a\n  - to: pattern_b\n    type: informs\n---\n",
        );
        assert_eq!(stale.supersedes, vec!["pattern_a"], "an item's type does not carry to the next");
    }

    #[test]
    fn status_and_description_are_read_from_the_metadata_block_too() {
        let m = parse_note(
            "---\nname: x\nmetadata:\n  type: pattern\n  status: superseded\n  description: nested gist\n---\n",
        );
        assert_eq!(m.status.as_deref(), Some("superseded"));
        assert_eq!(m.description.as_deref(), Some("nested gist"));
        let both = parse_note("---\ndescription: top\nmetadata:\n  description: nested\n---\n");
        assert_eq!(both.description.as_deref(), Some("top"), "top level wins");
    }

    #[test]
    fn gist_is_the_description_capped_at_160() {
        assert_eq!(make_gist(None), None);
        assert_eq!(make_gist(Some("   ")), None);
        assert_eq!(make_gist(Some("a  b\nc")), Some("a b c".to_string()));
        let exact = "x".repeat(160);
        assert_eq!(make_gist(Some(&exact)), Some(exact.clone()));
        let long = "y".repeat(161);
        let g = make_gist(Some(&long)).unwrap();
        assert_eq!(g.chars().count(), 160);
        assert!(g.ends_with('…'));
    }

    // ── stages ───────────────────────────────────────────────────────────────

    #[test]
    fn scope_excludes_other_project_and_archived_notes_must_fire() {
        let mut other = cand("pattern_client-secret", 0.9, meta());
        other.path = PathBuf::from("/h/.claude/projects/-w-client/memory/pattern_client-secret.md");
        let mut archived = cand("pattern_archived", 0.8, meta());
        archived.path = PathBuf::from("/h/.claude/memory/archive/pattern_archived.md");
        let mine = cand("pattern_mine", 0.1, meta());

        let out = assemble(vec![other, archived, mine], &scope(), &HashMap::new());

        assert_eq!(refs(&out), vec!["pattern_mine"]);
    }

    #[test]
    fn type_precedence_metadata_then_top_level_then_filename_then_note() {
        let with_meta = NoteMeta { type_: Some("feedback".into()), ..meta() };
        let out = assemble(
            vec![
                cand("pattern_a", 0.4, with_meta),
                cand("reference_b", 0.3, meta()),
                cand("plainname", 0.2, meta()),
            ],
            &scope(),
            &HashMap::new(),
        );
        let types: Vec<&str> = out.iter().map(|p| p.ptype.as_str()).collect();
        assert_eq!(types, vec!["feedback", "reference", "note"]);
    }

    #[test]
    fn superseded_status_is_dropped_in_any_case() {
        let dead = NoteMeta { status: Some("Superseded".into()), ..meta() };
        let live = NoteMeta { status: Some("active".into()), ..meta() };
        let out = assemble(
            vec![cand("pattern_dead", 0.9, dead), cand("pattern_live", 0.1, live)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_live"]);
    }

    #[test]
    fn the_target_of_a_supersedes_relation_is_dropped() {
        let newer = NoteMeta { supersedes: vec!["atoms/pattern_old.md".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_old", 0.9, meta()), cand("pattern_new", 0.5, newer)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_new"]);
    }

    #[test]
    fn a_slug_only_target_must_match_the_same_type() {
        // A project note naming `scraping` must not remove a global pattern of that slug.
        let hostile = NoteMeta { supersedes: vec!["scraping".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_scraping", 0.9, meta()), cand("project_hostile", 0.5, hostile)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_scraping", "project_hostile"]);

        // A full stem names exactly one note, whatever the types.
        let exact = NoteMeta { supersedes: vec!["pattern_scraping.md".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_scraping", 0.9, meta()), cand("project_exact", 0.5, exact)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["project_exact"]);
    }

    #[test]
    fn a_slug_target_spares_the_newest_dated_twin() {
        let old = "pattern_x_2026-08-23T10-00-00";
        let new = "pattern_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("pattern".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        let by = NoteMeta { supersedes: vec!["[[x]]".into()], ..meta() };
        let out = assemble(
            vec![cand(old, 0.5, meta()), cand(new, 0.4, meta()), cand("pattern_by", 0.1, by)],
            &scope(),
            &twins,
        );
        assert_eq!(refs(&out), vec![new, "pattern_by"], "the live twin stays, the old one goes");
    }

    #[test]
    fn type_spelling_does_not_split_the_quota() {
        let mut c = Vec::new();
        for (i, ty) in ["pattern", "Pattern", " PATTERN ", "pattern", "Pattern"].iter().enumerate() {
            let m = NoteMeta { type_: Some(ty.to_string()), ..meta() };
            c.push(cand(&format!("plain{i}"), 0.5 - i as f64 * 0.01, m));
        }
        let out = assemble(c, &scope(), &HashMap::new());
        assert_eq!(out.len(), MAX_PER_TYPE);
        assert!(out.iter().all(|p| p.ptype == "pattern"));
    }

    #[test]
    fn an_undated_note_is_not_flagged_against_a_dated_twin() {
        // "Older dated twin" (ADR-099 §3): only a dated file can be older.
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(
            ("feedback".into(), "x".into()),
            ("2026-08-24T12-00-00".into(), "feedback_x_2026-08-24T12-00-00".into()),
        );
        let out = assemble(vec![cand("feedback_x", 0.4, meta())], &scope(), &twins);
        assert!(out[0].flags.is_empty());
    }

    #[test]
    fn the_target_may_be_named_by_slug_or_wikilink() {
        let a = NoteMeta { supersedes: vec!["[[old-slug]]".into()], ..meta() };
        let out = assemble(
            vec![cand("pattern_old-slug", 0.9, meta()), cand("pattern_a", 0.5, a)],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_a"]);
    }

    #[test]
    fn an_older_dated_twin_is_down_weighted_and_flagged_not_dropped() {
        let old = "feedback_x_2026-08-23T10-00-00";
        let new = "feedback_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("feedback".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        // The old twin scores higher than the rival before the weight, lower after.
        let out = assemble(
            vec![cand(old, 0.04, meta()), cand("pattern_rival", 0.03, meta())],
            &scope(),
            &twins,
        );
        assert_eq!(refs(&out), vec!["pattern_rival", old]);
        assert_eq!(out[1].flags, vec![format!("derived-superseded:{new}")]);
        assert!(out[0].flags.is_empty());
    }

    #[test]
    fn the_newest_twin_is_not_flagged() {
        let new = "feedback_x_2026-08-24T12-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("feedback".into(), "x".into()), ("2026-08-24T12-00-00".into(), new.into()));
        let out = assemble(vec![cand(new, 0.04, meta())], &scope(), &twins);
        assert!(out[0].flags.is_empty());
    }

    #[test]
    fn prose_superseded_by_down_weights_and_flags_once_even_with_a_twin() {
        let old = "feedback_x_2026-08-23T10-00-00";
        let mut twins: NewestStamps = HashMap::new();
        twins.insert(("feedback".into(), "x".into()), ("2026-08-24T12-00-00".into(), "feedback_x_2026-08-24T12-00-00".into()));
        let m = NoteMeta { superseded_by: vec!["pattern_y".into()], ..meta() };
        let out = assemble(
            vec![cand(old, 0.04, m), cand("pattern_rival", 0.03, meta())],
            &scope(),
            &twins,
        );
        // Weight applied once (0.04 * 0.5 = 0.02 < 0.03), both causes flagged.
        assert_eq!(refs(&out), vec!["pattern_rival", old]);
        assert_eq!(out[1].flags.len(), 2);
        assert!(out[1].flags.contains(&"derived-superseded:pattern_y".to_string()));
    }

    #[test]
    fn at_most_three_per_type_and_eight_in_all_with_other_types_filling() {
        let mut c = Vec::new();
        for i in 0..5 {
            c.push(cand(&format!("pattern_p{i}"), 0.50 - i as f64 * 0.01, meta()));
        }
        for i in 0..3 {
            c.push(cand(&format!("feedback_f{i}"), 0.30 - i as f64 * 0.01, meta()));
        }
        for i in 0..4 {
            c.push(cand(&format!("project_j{i}"), 0.20 - i as f64 * 0.01, meta()));
        }
        let out = assemble(c, &scope(), &HashMap::new());

        assert_eq!(out.len(), MAX_POINTERS);
        let count = |t: &str| out.iter().filter(|p| p.ptype == t).count();
        assert_eq!((count("pattern"), count("feedback"), count("project")), (3, 3, 2));
        assert_eq!(out.iter().map(|p| p.rank).collect::<Vec<_>>(), (1..=8).collect::<Vec<_>>());
    }

    #[test]
    fn ties_break_by_stem_so_the_bundle_is_deterministic() {
        let out = assemble(
            vec![cand("pattern_b", 0.1, meta()), cand("pattern_a", 0.1, meta())],
            &scope(),
            &HashMap::new(),
        );
        assert_eq!(refs(&out), vec!["pattern_a", "pattern_b"]);
    }

    #[test]
    fn a_pointer_carries_the_gist_from_the_description_only() {
        let m = NoteMeta { description: Some("what it is".into()), ..meta() };
        let out = assemble(vec![cand("pattern_a", 0.1, m), cand("pattern_b", 0.05, meta())], &scope(), &HashMap::new());
        assert_eq!(out[0].gist.as_deref(), Some("what it is"));
        assert_eq!(out[1].gist, None);
    }

    #[test]
    fn newest_stamps_finds_the_latest_twin_per_type_and_slug() {
        let tmp = tempdir().unwrap();
        let d = tmp.path().join("memory");
        fs::create_dir_all(&d).unwrap();
        for n in [
            "feedback_x_2026-08-23T10-00-00.md",
            "feedback_x_2026-08-24T12-00-00.md",
            "feedback_y_2026-08-01T00-00-00.md",
            "pattern_x.md",
        ] {
            fs::write(d.join(n), "t").unwrap();
        }
        let files = list_memory_listing(&[("global".into(), d)]).files;

        let m = newest_stamps(&files);

        assert_eq!(m[&("feedback".to_string(), "x".to_string())].1, "feedback_x_2026-08-24T12-00-00");
        assert_eq!(m[&("feedback".to_string(), "y".to_string())].0, "2026-08-01T00-00-00");
        assert!(!m.contains_key(&("pattern".to_string(), "x".to_string())), "undated notes have no stamp");
    }

    // ── compute_bundle (real FTS on fixture dirs; embedder and timing faked) ───

    struct ConstEmbedder;
    impl Embedder for ConstEmbedder {
        fn embed(&self, _text: &str) -> Option<Vec<f32>> {
            let mut v = vec![0.0; EMBED_DIM];
            v[0] = 1.0;
            Some(v)
        }
    }

    struct World {
        _tmp: tempfile::TempDir,
        home: PathBuf,
        dirs: Vec<(String, PathBuf)>,
        mine: PathBuf,
        global: PathBuf,
        client: PathBuf,
        fts: PathBuf,
        db: PathBuf,
        scope: RecallScope,
    }

    /// Global memory, this project's memory (root /w/my_repo) and another client's.
    fn world() -> World {
        let tmp = tempdir().unwrap();
        let home = tmp.path().to_path_buf();
        let global = home.join(".claude/memory");
        let mine = home.join(".claude/projects/-w-my-repo/memory");
        let client = home.join(".claude/projects/-w-client/memory");
        for d in [&global, &mine, &client] {
            fs::create_dir_all(d).unwrap();
        }
        let dirs = vec![("global".to_string(), global.clone()), ("project".to_string(), mine.clone())];
        let scope = RecallScope::project_in(&home, Some(std::path::Path::new("/w/my_repo")));
        World { fts: home.join("index.db"), db: home.join("knowledge.db"), _tmp: tmp, home, dirs, mine, global, client, scope }
    }

    fn write_note(dir: &std::path::Path, name: &str, desc: &str, body: &str) {
        let path = dir.join(name);
        fs::write(&path, format!("---\ndescription: {desc}\n---\n{body}")).unwrap();
        // Outside the racily-clean window, so a refresh settles in one pass.
        let t = std::time::SystemTime::now() - Duration::from_secs(60);
        fs::File::options().write(true).open(&path).unwrap().set_modified(t).unwrap();
    }

    fn env<'a>(w: &'a World, provider: &'a HybridProvider) -> BundleEnv<'a> {
        BundleEnv {
            scope: w.scope.clone(),
            project: Some("-w-my-repo".to_string()),
            dirs: w.dirs.clone(),
            knowledge_db: w.db.clone(),
            fts_db: w.fts.clone(),
            provider,
            refresh_budget: Duration::from_secs(5),
            unembedded_wait: Duration::from_millis(200),
        }
    }

    fn task(subject: &str) -> BundleTask {
        BundleTask { id: "t-9".into(), subject: subject.into(), tags: vec![] }
    }

    #[test]
    fn a_note_written_after_the_index_build_reaches_the_bundle_must_fire() {
        let w = world();
        write_note(&w.global, "pattern_old.md", "old", "alpha");
        let all = vec![("global".into(), w.global.clone()), ("project".into(), w.mine.clone())];
        reindex_fts_dirs(&all, &w.fts).unwrap();
        write_note(&w.mine, "pattern_zebra-crossing.md", "crossing zebras", "zebra zebra");
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("zebra"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_zebra-crossing"]);
        assert_eq!(b.pointers[0].gist.as_deref(), Some("crossing zebras"));
        assert_eq!(b.freshness.report.stale_notes, 1);
        assert_eq!(b.legs.fts, LegStatus::Ok);
    }

    #[test]
    fn another_clients_better_match_is_never_in_the_bundle_must_fire() {
        let w = world();
        write_note(&w.global, "pattern_mine.md", "mine", "scraping once");
        write_note(&w.client, "pattern_client.md", "client secrets", "scraping scraping scraping");
        let all = vec![
            ("global".into(), w.global.clone()),
            ("project".into(), w.mine.clone()),
            ("project".into(), w.client.clone()),
        ];
        reindex_fts_dirs(&all, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_mine"]);
    }

    #[test]
    fn json_shape_has_the_documented_keys_and_no_note_body() {
        let w = world();
        write_note(&w.global, "pattern_a.md", "the gist", "SENTINEL-BODY-TEXT scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));
        let v = serde_json::to_value(&b).unwrap();

        assert_eq!(v["task"], "t-9");
        assert_eq!(v["scope"]["project"], "-w-my-repo");
        assert_eq!(v["scope"]["global"], true);
        assert_eq!(v["shown"], true);
        assert_eq!(v["legs"]["fts"], "ok");
        assert_eq!(v["legs"]["vector"], "error", "no vector store in this fixture");
        let p = &v["pointers"][0];
        assert_eq!((p["type"].as_str(), p["ref"].as_str(), p["rank"].as_u64()), (Some("pattern"), Some("pattern_a"), Some(1)));
        assert_eq!(p["gist"], "the gist");
        assert!(v["freshness"]["outcome"].is_object() || v["freshness"]["outcome"].is_string());
        assert!(v["freshness"].get("unembedded").is_some());
        assert!(v.get("elapsed_ms").is_some() && v.get("skipped_unreadable").is_some());
        assert_eq!(v["skipped_non_entries"], 0);
        assert!(!v.to_string().contains("SENTINEL-BODY-TEXT"), "pointer, not paste");
    }

    struct Fixed(Vec<SearchHit>);
    impl SearchProvider for Fixed {
        fn query(&self, _q: &str, _k: usize) -> Vec<SearchHit> {
            self.0.clone()
        }
    }
    struct Slow;
    impl SearchProvider for Slow {
        fn query(&self, _q: &str, _k: usize) -> Vec<SearchHit> {
            std::thread::sleep(Duration::from_secs(3));
            Vec::new()
        }
    }

    #[test]
    fn knowledge_store_rows_are_left_out_in_v1() {
        let w = world();
        write_note(&w.global, "pattern_a.md", "a", "x");
        let hits = vec![
            SearchHit { doc: DocRef::KnowledgeEntry { key: "knowledge:feed:x".into(), namespace: "knowledge".into() }, snippet: "s".into(), rrf_score: 0.0 },
            SearchHit {
                doc: DocRef::MemoryFile { path: w.global.join("pattern_a.md"), slug: "a".into(), mtype: "pattern".into(), scope: "global".into() },
                snippet: "s".into(),
                rrf_score: 0.0,
            },
        ];
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = HybridProvider::new(Arc::new(Fixed(hits)), Arc::new(Fixed(vec![])));

        let b = compute_bundle(&task("anything"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_a"]);
    }

    #[test]
    fn both_legs_timing_out_gives_an_empty_marked_bundle_not_a_failure() {
        let w = world();
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = HybridProvider::with_deadlines(Arc::new(Slow), Arc::new(Slow), Duration::from_millis(50), Duration::from_millis(100));

        let started = std::time::Instant::now();
        let b = compute_bundle(&task("anything"), &env(&w, &provider));

        assert!(b.pointers.is_empty());
        assert_eq!((b.legs.fts, b.legs.vector), (LegStatus::Timeout, LegStatus::Timeout));
        assert!(started.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn an_empty_query_still_returns_a_bundle() {
        let w = world();
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("  "), &env(&w, &provider));

        assert!(b.pointers.is_empty());
    }

    #[test]
    fn a_candidate_that_cannot_be_read_as_text_is_skipped_and_counted() {
        let w = world();
        write_note(&w.global, "pattern_good.md", "good", "scraping");
        write_note(&w.global, "pattern_bad.md", "bad", "scraping scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        // Corrupt it after indexing: the index still finds it, the read now fails.
        fs::write(w.global.join("pattern_bad.md"), b"\xff\xfe\xfd scraping").unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_good"]);
        assert_eq!(b.skipped_unreadable, 1);
    }

    #[test]
    fn logs_and_state_files_are_left_out_and_counted_user_decision() {
        let w = world();
        write_note(&w.global, "pattern_real.md", "a real note", "scraping");
        // No frontmatter and no type prefix: a log, however well it matches.
        fs::write(w.global.join("sessions.md"), "scraping scraping scraping scraping").unwrap();
        // No type prefix but a frontmatter block: still a note, typed "note".
        write_note(&w.global, "untyped-note.md", "has frontmatter", "scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        let mut got = refs(&b.pointers);
        got.sort();
        assert_eq!(got, vec!["pattern_real", "untyped-note"]);
        assert_eq!(b.skipped_non_entries, 1);
        assert_eq!(b.pointers.iter().find(|p| p.ref_ == "untyped-note").unwrap().ptype, "note");
    }

    #[test]
    fn a_symlink_into_another_clients_memory_never_reaches_the_bundle_must_fire() {
        let w = world();
        write_note(&w.client, "pattern_secret.md", "ACME CONFIDENTIAL", "scraping scraping scraping");
        write_note(&w.global, "pattern_mine.md", "mine", "scraping once");
        std::os::unix::fs::symlink(w.client.join("pattern_secret.md"), w.global.join("pattern_planted.md")).unwrap();
        // The index follows symlinks, so the planted link is indexed with the client's text.
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(refs(&b.pointers), vec!["pattern_mine"]);
        assert!(!serde_json::to_string(&b).unwrap().contains("ACME CONFIDENTIAL"));
    }

    #[test]
    fn human_format_cannot_be_forged_by_a_note_name_or_task_id() {
        let b = Bundle {
            task: "t-1\nforged".into(),
            scope: BundleScope { project: None, global: true },
            shown: true,
            legs: BundleLegs { fts: LegStatus::Ok, vector: LegStatus::Ok },
            pointers: vec![Pointer {
                ptype: "pattern".into(),
                ref_: "pattern_a\n  9. forged_pointer".into(),
                gist: None,
                rank: 1,
                flags: vec!["derived-superseded:x\u{1b}[2J".into()],
            }],
            skipped_unreadable: 0,
            skipped_non_entries: 0,
            elapsed_ms: 0,
            freshness: BundleFreshness {
                report: crate::memory::FreshnessReport {
                    index_age_s: None,
                    stale_notes: 0,
                    deleted_notes: 0,
                    unreadable: 0,
                    refreshed_notes: 0,
                    outcome: crate::memory::FreshnessOutcome::Fresh,
                },
                unembedded: None,
            },
        };

        let text = format_human(&b);

        assert_eq!(text.lines().count(), 3, "header, type, one pointer line: {text:?}");
        assert!(!text.contains('\u{1b}'));
    }

    #[test]
    fn a_huge_note_is_read_only_up_to_the_cap() {
        let tmp = tempdir().unwrap();
        let p = tmp.path().join("pattern_big.md");
        // Frontmatter first, then far more body than the cap; the cut lands inside a
        // multi-byte character on purpose.
        let mut text = String::from("---\ndescription: big note\n---\n");
        text.push_str(&"é".repeat(NOTE_READ_CAP_BYTES));
        fs::write(&p, &text).unwrap();

        let head = read_note_head(&p).unwrap();

        assert!(head.len() <= NOTE_READ_CAP_BYTES);
        assert!(head.starts_with("---\ndescription: big note"));
        assert_eq!(parse_note(&head).description.as_deref(), Some("big note"));
    }

    #[test]
    fn invalid_utf8_inside_the_cap_is_still_unreadable() {
        let tmp = tempdir().unwrap();
        let p = tmp.path().join("pattern_bad.md");
        fs::write(&p, b"---\ndescription: x\n---\n\xff\xfe").unwrap();
        assert!(read_note_head(&p).is_err());
    }

    #[test]
    fn unembedded_counts_in_scope_notes_without_a_vector() {
        let w = world();
        write_note(&w.global, "pattern_a.md", "a", "scraping");
        reindex_fts_dirs(&w.dirs, &w.fts).unwrap();
        let provider = crate::vector::bundle_provider(&w.fts, &w.db, Arc::new(ConstEmbedder), w.scope.clone());

        let b = compute_bundle(&task("scraping"), &env(&w, &provider));

        assert_eq!(b.freshness.unembedded, Some(1));
    }

    #[test]
    fn the_home_fixture_is_not_the_real_home() {
        // Guard: fixtures never read the real ~/.claude.
        let w = world();
        assert!(w.home.starts_with(std::env::temp_dir()) || w.home.starts_with("/tmp"));
    }
}
