//! Semantic index over curated memory files (t-3510).
//!
//! `brana recall` fuses FTS5 keyword search with exact-cosine search over
//! `knowledge.db`. That store is fed from ruflo's `memory_entries`, so the curated
//! memory files were found by keyword only. This module embeds them with the
//! existing [`Embedder`] seam into the same `knowledge` table and maps the rows
//! back to [`DocRef::MemoryFile`] with the identity the FTS leg uses, so the RRF
//! merge fuses both signals for one document.
//!
//! Spec: docs/architecture/features/recall-memory-file-vectors.md

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use anyhow::Result;

use crate::memory::{MemoryListing, memory_file_identity};
use crate::search::DocRef;
use crate::vector::{EMBED_DIM, Embedder, KnowledgeStore, parse_tags, truncate_chars};

/// `source` column value marking a row as an embedded memory file.
pub const MEMORY_SOURCE: &str = "memory-file";

/// Characters of file text passed to the embedder (MiniLM truncates near this anyway).
pub const EMBED_CHARS: usize = 1500;

/// Version tag stored on every memory-file row: embedder model, dimension and
/// [`EMBED_CHARS`]. A row without the current tag is re-embedded even if its
/// content is unchanged, so a model or truncation change never mixes old and new
/// vectors silently (t-3510 gate, F3). Bump it whenever any of those change.
pub const EMBED_VERSION: &str = "emb:minilm-l6-384:1500";

/// Outcome of one [`embed_memory_files`] run.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct EmbedStats {
    pub scanned: usize,
    pub embedded: usize,
    pub unchanged: usize,
    pub pruned: usize,
    pub failed: usize,
}

const KEY_PREFIX: &str = "memory-file:";

/// Row key for a memory file: `memory-file:<absolute path>`.
pub fn memory_row_key(path: &Path) -> String {
    format!("{KEY_PREFIX}{}", path.to_string_lossy())
}

/// The file path a memory-file row key points at.
pub fn memory_row_path(key: &str) -> Option<PathBuf> {
    key.strip_prefix(KEY_PREFIX).map(PathBuf::from)
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Embed new or changed files, skip unchanged ones, prune rows whose file is gone.
///
/// - A file whose stored `content` equals the file on disk and whose row carries
///   the current [`EMBED_VERSION`] is `unchanged`: the embedder is not called.
///   `force` re-embeds every file regardless.
/// - A file the embedder cannot embed (or that cannot be read) is `failed`. It
///   leaves no new row; an older row for it, if any, is kept rather than pruned,
///   so a transient embedder outage never deletes working recall.
/// - A row of source [`MEMORY_SOURCE`] is pruned only when its file is absent
///   from a dir that listed *completely*. A dir that failed to list or is missing
///   (unreadable, unmounted, moved) prunes nothing, so a read failure never
///   deletes recall (t-3510 gate, F5); recall hides hits whose file is gone.
///   Rows from other sources are never touched.
pub fn embed_memory_files(
    store: &KnowledgeStore,
    listing: &MemoryListing,
    embedder: &dyn Embedder,
    force: bool,
) -> Result<EmbedStats> {
    let mut stats = EmbedStats { scanned: listing.files.len(), ..Default::default() };
    let mut live: HashSet<String> = HashSet::new();

    for f in &listing.files {
        let key = memory_row_key(&f.path);
        live.insert(key.clone());

        let Ok(content) = std::fs::read_to_string(&f.path) else {
            stats.failed += 1;
            continue;
        };
        if !force {
            if let Some((stored, tags)) = store.content_and_tags_of(&key)? {
                let current = parse_tags(tags.as_deref().unwrap_or("")).iter().any(|t| t == EMBED_VERSION);
                if stored == content && current {
                    stats.unchanged += 1;
                    continue;
                }
            }
        }
        let text: String = content.chars().take(EMBED_CHARS).collect();
        let Some(vec) = embedder.embed(&text).filter(|v| v.len() == EMBED_DIM) else {
            stats.failed += 1;
            continue;
        };
        let tags = format!("memory-file,scope:{},{EMBED_VERSION}", f.scope);
        store.upsert(&key, &content, Some(&tags), Some(MEMORY_SOURCE), now_ms(), &vec)?;
        stats.embedded += 1;
    }

    for key in store.keys_with_source(MEMORY_SOURCE)? {
        if live.contains(&key) {
            continue;
        }
        let in_complete_dir = memory_row_path(&key)
            .and_then(|p| p.parent().map(Path::to_path_buf))
            .is_some_and(|dir| listing.complete_dirs.contains(&dir));
        if in_complete_dir && store.delete(&key)? {
            stats.pruned += 1;
        }
    }
    Ok(stats)
}

/// Map a `knowledge` row to its [`DocRef`] when it is an embedded memory file.
///
/// Identity is rebuilt from the key's path with [`memory_file_identity`], the same
/// rule the FTS index uses, so both legs produce equal `DocRef`s for one file.
pub fn memory_doc_ref(key: &str, tags: Option<&str>, source: Option<&str>) -> Option<DocRef> {
    if source != Some(MEMORY_SOURCE) {
        return None;
    }
    let path = memory_row_path(key)?;
    let stem = path.file_stem()?.to_string_lossy().to_string();
    let (mtype, slug) = memory_file_identity(&stem);
    let scope = parse_tags(tags.unwrap_or(""))
        .iter()
        .find_map(|t| t.strip_prefix("scope:").map(str::to_string))
        .unwrap_or_else(|| "project".to_string());
    Some(DocRef::MemoryFile { path, slug, mtype, scope })
}

/// Short display snippet for a memory-file vector hit: the body after the
/// frontmatter block, truncated.
pub fn memory_snippet(content: &str, max: usize) -> String {
    let body = content
        .strip_prefix("---\n")
        .and_then(|rest| rest.find("\n---").map(|i| &rest[i + 4..]))
        .unwrap_or(content)
        .trim();
    let body = if body.is_empty() { content.trim() } else { body };
    truncate_chars(body, max)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::{list_memory_listing, reindex_fts_dirs, MemoryListing};
    use crate::search::{FTS5Provider, HybridProvider, SearchProvider};
    use crate::vector::{CachedEmbedder, MemoryScope, VectorProvider, EMBED_DIM};
    use std::fs;
    use std::sync::{Arc, Mutex};
    use tempfile::{tempdir, TempDir};

    fn unit(hot: usize) -> Vec<f32> {
        let mut v = vec![0.0_f32; EMBED_DIM];
        v[hot] = 1.0;
        v
    }

    /// Keyword-steered fake: "scraping" → axis 0, "pricing" → axis 1, else axis 2.
    /// Text containing "UNEMBEDDABLE" yields None. Records every text it embeds.
    struct Fake {
        seen: Mutex<Vec<String>>,
    }

    impl Fake {
        fn new() -> Self {
            Self { seen: Mutex::new(Vec::new()) }
        }
        fn calls(&self) -> usize {
            self.seen.lock().unwrap().len()
        }
        fn longest(&self) -> usize {
            self.seen.lock().unwrap().iter().map(|s| s.chars().count()).max().unwrap_or(0)
        }
    }

    impl Embedder for Fake {
        fn embed(&self, text: &str) -> Option<Vec<f32>> {
            self.seen.lock().unwrap().push(text.to_string());
            if text.contains("UNEMBEDDABLE") {
                None
            } else if text.contains("scraping") {
                Some(unit(0))
            } else if text.contains("pricing") {
                Some(unit(1))
            } else {
                Some(unit(2))
            }
        }
    }

    struct Fixture {
        _tmp: TempDir,
        mem: std::path::PathBuf,
        db: std::path::PathBuf,
        fts: std::path::PathBuf,
    }

    fn fixture() -> Fixture {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        fs::create_dir_all(&mem).unwrap();
        let db = tmp.path().join("knowledge.db");
        let fts = tmp.path().join("index.db");
        Fixture { _tmp: tmp, mem, db, fts }
    }

    fn put(f: &Fixture, name: &str, body: &str) {
        fs::write(f.mem.join(name), body).unwrap();
    }

    fn dirs(f: &Fixture) -> Vec<(String, std::path::PathBuf)> {
        vec![("project".to_string(), f.mem.clone())]
    }

    #[test]
    fn embed_inserts_rows_marked_as_memory_files() {
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "---\nname: x\n---\nweb scraping tips");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let files = list_memory_listing(&dirs(&f));

        let stats = embed_memory_files(&store, &files, &Fake::new(), false).unwrap();

        assert_eq!(stats, EmbedStats { scanned: 1, embedded: 1, ..Default::default() });
        assert_eq!(store.count().unwrap(), 1);
        let key = memory_row_key(&f.mem.join("pattern_scraping-tips.md"));
        assert!(key.starts_with("memory-file:"), "key was {key}");
        assert_eq!(store.keys_with_source(MEMORY_SOURCE).unwrap(), vec![key]);
    }

    #[test]
    fn second_run_skips_unchanged_files_without_embedding() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let files = list_memory_listing(&dirs(&f));
        let e = Fake::new();
        embed_memory_files(&store, &files, &e, false).unwrap();
        let calls_after_first = e.calls();

        let stats = embed_memory_files(&store, &files, &e, false).unwrap();

        assert_eq!(stats, EmbedStats { scanned: 1, unchanged: 1, ..Default::default() });
        assert_eq!(e.calls(), calls_after_first, "unchanged file must not hit the embedder");
    }

    #[test]
    fn changed_file_is_reembedded() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        put(&f, "pattern_a.md", "alpha pricing now");
        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        assert_eq!(stats.embedded, 1);
        assert_eq!(stats.unchanged, 0);
        assert_eq!(store.count().unwrap(), 1, "update in place, no duplicate row");
    }

    #[test]
    fn rows_for_deleted_files_are_pruned_but_other_rows_survive() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        put(&f, "pattern_b.md", "beta pricing");
        let store = KnowledgeStore::open(&f.db).unwrap();
        // A non-memory row (e.g. copied from ruflo) must never be pruned.
        store.upsert("knowledge:url:x", "link", None, Some("memory_entries"), 1, &unit(2)).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();
        assert_eq!(store.count().unwrap(), 3);

        fs::remove_file(f.mem.join("pattern_b.md")).unwrap();
        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        assert_eq!(stats.pruned, 1);
        assert_eq!(store.count().unwrap(), 2, "b pruned; a and the foreign row remain");
    }

    #[test]
    fn unembeddable_file_is_counted_failed_and_leaves_no_row() {
        let f = fixture();
        put(&f, "pattern_bad.md", "UNEMBEDDABLE");
        let store = KnowledgeStore::open(&f.db).unwrap();

        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &Fake::new(), false).unwrap();

        assert_eq!(stats, EmbedStats { scanned: 1, failed: 1, ..Default::default() });
        assert_eq!(store.count().unwrap(), 0);
    }

    #[test]
    fn empty_scan_prunes_nothing() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        // Discovery found nothing (bad HOME, unmounted dir): must not wipe the index.
        let stats = embed_memory_files(&store, &MemoryListing::default(), &e, false).unwrap();

        assert_eq!(stats, EmbedStats::default());
        assert_eq!(store.count().unwrap(), 1);
    }

    #[test]
    fn failed_reembed_keeps_the_old_row() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        // File changes to something the embedder refuses: old working row must survive.
        put(&f, "pattern_a.md", "alpha UNEMBEDDABLE");
        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        assert_eq!(stats.failed, 1);
        assert_eq!(stats.pruned, 0);
        assert_eq!(store.count().unwrap(), 1);
    }

    #[test]
    fn embedder_input_is_truncated_to_embed_chars() {
        let f = fixture();
        put(&f, "pattern_long.md", &"scraping ".repeat(1000));
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();

        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        assert!(e.longest() <= EMBED_CHARS, "embedder saw {} chars", e.longest());
    }

    #[test]
    fn memory_doc_ref_roundtrips_identity_and_ignores_foreign_rows() {
        let f = fixture();
        put(&f, "pattern_scraping-tips_2026-06-09T10-00-00.md", "scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let files = list_memory_listing(&dirs(&f));
        embed_memory_files(&store, &files, &Fake::new(), false).unwrap();

        let key = memory_row_key(&files.files[0].path);
        let row = store.rows_with_vec(crate::vector::RowFilter::All).unwrap().remove(0);
        let doc = memory_doc_ref(&key, row.tags.as_deref(), Some(MEMORY_SOURCE)).expect("memory row maps");
        assert_eq!(
            doc,
            DocRef::MemoryFile {
                path: files.files[0].path.clone(),
                slug: "scraping-tips".to_string(),
                mtype: "pattern".to_string(),
                scope: "project".to_string(),
            }
        );
        assert_eq!(memory_doc_ref("knowledge:url:x", None, Some("memory_entries")), None);
    }

    #[test]
    fn snippet_skips_frontmatter_and_truncates() {
        let s = memory_snippet("---\nname: x\ndescription: d\n---\nThe body text here.", 300);
        assert_eq!(s, "The body text here.");
        assert_eq!(memory_snippet("no frontmatter at all", 300), "no frontmatter at all");
        assert!(memory_snippet(&"x".repeat(400), 300).chars().count() <= 301);
    }

    #[test]
    fn vector_provider_returns_memory_file_docref_and_keeps_knowledge_entries() {
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "web scraping tips");
        let store = KnowledgeStore::open(&f.db).unwrap();
        store.upsert("knowledge:url:p", "pricing page", None, Some("memory_entries"), 1, &unit(1)).unwrap();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &Fake::new(), false).unwrap();

        let provider = VectorProvider::new(&f.db, Arc::new(Fake::new())).with_memory_scope(MemoryScope::Include);
        let scraping = provider.query("scraping question", 5);
        assert!(matches!(scraping[0].doc, DocRef::MemoryFile { .. }), "got {:?}", scraping[0].doc);
        let pricing = provider.query("pricing question", 5);
        assert!(matches!(pricing[0].doc, DocRef::KnowledgeEntry { .. }), "got {:?}", pricing[0].doc);
    }

    #[test]
    fn default_provider_excludes_memory_files_so_knowledge_search_stays_knowledge_only() {
        // `brana knowledge search` documents "the vector store holds only knowledge: entries".
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "web scraping tips");
        let store = KnowledgeStore::open(&f.db).unwrap();
        store.upsert("knowledge:url:p", "pricing page", None, Some("memory_entries"), 1, &unit(1)).unwrap();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &Fake::new(), false).unwrap();

        let hits = VectorProvider::new(&f.db, Arc::new(Fake::new())).query("scraping question", 5);

        assert!(
            hits.iter().all(|h| matches!(h.doc, DocRef::KnowledgeEntry { .. })),
            "memory-file rows leaked into the default provider: {hits:?}"
        );
        assert_eq!(hits.len(), 1);
    }

    /// Embeds "mixed" text halfway between axis 0 and axis 2 (cosine 0.5 with a
    /// "scraping" query), everything else as `Fake` does.
    struct FakeMixed(Fake);
    impl Embedder for FakeMixed {
        fn embed(&self, text: &str) -> Option<Vec<f32>> {
            if text.contains("mixed") {
                let mut v = vec![0.0_f32; EMBED_DIM];
                v[0] = 0.5;
                v[2] = 0.866_025_4;
                return Some(v);
            }
            self.0.embed(text)
        }
    }

    #[test]
    fn memory_files_crowded_out_of_a_shared_pool_surface_through_their_own_leg() {
        // Measured on the live store: the answer memory file ranked 1st among memory files
        // but 42nd among all rows, behind ~6,600 knowledge entries, so the shared vector
        // leg's candidate pool (20) never reached it. A dedicated memory leg ranks them apart.
        let f = fixture();
        put(&f, "pattern_notes.md", "mixed notes zzz");
        let d = dirs(&f);
        reindex_fts_dirs(&d, &f.fts).unwrap();
        let store = KnowledgeStore::open(&f.db).unwrap();
        for i in 0..30 {
            store
                .upsert(&format!("knowledge:url:{i}"), "closer knowledge row", None, Some("memory_entries"), 1, &unit(0))
                .unwrap();
        }
        embed_memory_files(&store, &list_memory_listing(&d), &FakeMixed(Fake::new()), false).unwrap();
        let q = "scraping q";

        // Shared leg: the file is below 30 closer rows, outside the 20-candidate pool.
        let fts = Arc::new(FTS5Provider::new(f.fts.clone())) as Arc<dyn SearchProvider>;
        let shared = Arc::new(
            VectorProvider::new(&f.db, Arc::new(FakeMixed(Fake::new()))).with_memory_scope(MemoryScope::Include),
        ) as Arc<dyn SearchProvider>;
        let crowded = HybridProvider::new(fts.clone(), shared).query(q, 5);
        assert!(
            !crowded.iter().any(|h| matches!(h.doc, DocRef::MemoryFile { .. })),
            "precondition: the shared pool must crowd the memory file out: {crowded:?}"
        );

        // The production wiring: knowledge-only plus memory-only legs, fused three ways.
        let fused = crate::vector::recall_provider(&f.fts, &f.db, Arc::new(FakeMixed(Fake::new()))).query(q, 5);
        assert!(
            fused.iter().any(|h| matches!(&h.doc, DocRef::MemoryFile { slug, .. } if slug == "notes")),
            "memory leg must surface the file: {fused:?}"
        );
    }

    #[test]
    fn memory_only_scope_returns_just_memory_files() {
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "web scraping tips");
        let store = KnowledgeStore::open(&f.db).unwrap();
        store.upsert("knowledge:url:p", "scraping knowledge row", None, Some("memory_entries"), 1, &unit(0)).unwrap();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &Fake::new(), false).unwrap();

        let hits = VectorProvider::new(&f.db, Arc::new(Fake::new()))
            .with_memory_scope(MemoryScope::Only)
            .query("scraping question", 5);

        assert_eq!(hits.len(), 1);
        assert!(matches!(hits[0].doc, DocRef::MemoryFile { .. }));
    }

    #[test]
    fn cached_embedder_embeds_a_shared_query_once_across_threads() {
        let inner = Arc::new(Fake::new());
        let cached = Arc::new(CachedEmbedder::new(inner.clone()));
        let handles: Vec<_> = (0..4)
            .map(|_| {
                let c = cached.clone();
                std::thread::spawn(move || c.embed("scraping question"))
            })
            .collect();
        for h in handles {
            assert!(h.join().unwrap().is_some());
        }
        assert_eq!(inner.calls(), 1, "four legs, one embedding");

        cached.embed("pricing question");
        assert_eq!(inner.calls(), 2, "a different text is embedded afresh");
    }

    #[test]
    fn hybrid_fuses_fts_and_vector_signals_for_the_same_memory_file() {
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "web scraping tips for crawlers");
        put(&f, "pattern_other.md", "gardening notes about pricing of seeds");
        let d = dirs(&f);
        reindex_fts_dirs(&d, &f.fts).unwrap();
        let store = KnowledgeStore::open(&f.db).unwrap();
        embed_memory_files(&store, &list_memory_listing(&d), &Fake::new(), false).unwrap();

        let fts = Arc::new(FTS5Provider::new(f.fts.clone())) as Arc<dyn SearchProvider>;
        let vec = Arc::new(VectorProvider::new(&f.db, Arc::new(Fake::new())).with_memory_scope(MemoryScope::Include))
            as Arc<dyn SearchProvider>;
        let fts_alone = fts.query("scraping", 5);
        let hybrid = HybridProvider::new(fts, vec).query("scraping", 5);

        let top = &hybrid[0];
        assert!(matches!(&top.doc, DocRef::MemoryFile { slug, .. } if slug == "scraping-tips"));
        // One doc found by both legs must accumulate: strictly more than a single-leg RRF score.
        let single_leg = 1.0 / (20.0 + 1.0);
        assert!(top.rrf_score > single_leg + 1e-9, "no fusion: {} vs {}", top.rrf_score, single_leg);
        assert_eq!(fts_alone.len(), 1);
    }

    #[test]
    fn vector_leg_finds_a_paraphrase_that_keyword_search_misses() {
        // Query shares no token with the file, only the embedding axis ("scraping" vs "crawler").
        let f = fixture();
        put(&f, "pattern_crawler.md", "notes on the crawler and scraping");
        let d = dirs(&f);
        reindex_fts_dirs(&d, &f.fts).unwrap();
        let store = KnowledgeStore::open(&f.db).unwrap();
        embed_memory_files(&store, &list_memory_listing(&d), &Fake::new(), false).unwrap();

        let fts = Arc::new(FTS5Provider::new(f.fts.clone())) as Arc<dyn SearchProvider>;
        let vec = Arc::new(VectorProvider::new(&f.db, Arc::new(Fake::new())).with_memory_scope(MemoryScope::Include))
            as Arc<dyn SearchProvider>;
        assert!(fts.query("harvest extraction", 5).is_empty(), "keyword leg must miss");
        let hybrid = HybridProvider::new(fts, Arc::new(VectorProviderScraping(vec))).query("harvest extraction", 5);
        assert!(matches!(&hybrid[0].doc, DocRef::MemoryFile { slug, .. } if slug == "crawler"));
    }

    /// Steers the query embedding toward axis 0 regardless of text: models a paraphrase
    /// that is semantically near the file but lexically disjoint.
    struct VectorProviderScraping(Arc<dyn SearchProvider>);
    impl SearchProvider for VectorProviderScraping {
        fn query(&self, _q: &str, top_k: usize) -> Vec<crate::search::SearchHit> {
            self.0.query("scraping paraphrase", top_k)
        }
    }

    // ── t-3510 gate repair: F5 (partial scan), F3 (version, --force), F2 (ghost rows) ──

    fn unreadable(dir: &std::path::Path) {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o000)).unwrap();
    }

    fn readable(dir: &std::path::Path) {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o755)).unwrap();
    }

    #[test]
    fn rows_under_an_unreadable_dir_are_not_pruned() {
        // F5: one project dir unreadable while others list fine must not wipe its rows.
        let f = fixture();
        let other = f._tmp.path().join("other-memory");
        fs::create_dir_all(&other).unwrap();
        put(&f, "pattern_a.md", "alpha scraping");
        fs::write(other.join("pattern_b.md"), "beta pricing").unwrap();
        let d = vec![("project".to_string(), f.mem.clone()), ("project".to_string(), other.clone())];
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&d), &e, false).unwrap();
        assert_eq!(store.count().unwrap(), 2);

        unreadable(&other);
        let listing = list_memory_listing(&d);
        let stats = embed_memory_files(&store, &listing, &e, false).unwrap();
        readable(&other);

        assert_eq!(listing.failed_dirs, vec![other.clone()], "the unreadable dir is reported, not treated as empty");
        assert_eq!(stats.pruned, 0, "rows under a dir that failed to list must survive");
        assert_eq!(store.count().unwrap(), 2);
    }

    #[test]
    fn rows_under_a_listed_dir_are_still_pruned_when_their_file_is_gone() {
        // F5 must-fire counterpart: a dir that listed completely prunes its deleted files.
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        put(&f, "pattern_b.md", "beta pricing");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        fs::remove_file(f.mem.join("pattern_a.md")).unwrap();
        fs::remove_file(f.mem.join("pattern_b.md")).unwrap();
        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        assert_eq!(stats.pruned, 2, "an existing, readable, now-empty dir prunes its rows");
        assert_eq!(store.count().unwrap(), 0);
    }

    #[test]
    fn row_from_an_older_embedding_version_is_reembedded() {
        // F3: same content but no current version marker must not be skipped as unchanged.
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let key = memory_row_key(&f.mem.join("pattern_a.md"));
        store
            .upsert(&key, "alpha scraping", Some("memory-file,scope:project"), Some(MEMORY_SOURCE), 1, &unit(2))
            .unwrap();
        let e = Fake::new();

        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        assert_eq!(stats.embedded, 1, "old-version row re-embedded");
        assert_eq!(stats.unchanged, 0);
        assert_eq!(e.calls(), 1);
        let second = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();
        assert_eq!(second.unchanged, 1, "current-version row is skipped next time");
        assert!(EMBED_VERSION.starts_with("emb:"), "version marker is a tag: {EMBED_VERSION}");
    }

    #[test]
    fn embed_version_matches_the_embedding_constants() {
        assert_eq!(EMBED_VERSION, format!("emb:minilm-l6-{EMBED_DIM}:{EMBED_CHARS}"), "bump EMBED_VERSION with the constants");
    }

    #[test]
    fn rows_under_a_missing_dir_are_kept() {
        // A dir that vanished (unmounted, moved) prunes nothing; F2 hides its rows instead.
        let f = fixture();
        let other = f._tmp.path().join("other-memory");
        fs::create_dir_all(&other).unwrap();
        fs::write(other.join("pattern_b.md"), "beta pricing").unwrap();
        let d = vec![("project".to_string(), other.clone())];
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&d), &e, false).unwrap();

        fs::remove_dir_all(&other).unwrap();
        let stats = embed_memory_files(&store, &list_memory_listing(&d), &e, false).unwrap();

        assert_eq!(stats.pruned, 0);
        assert_eq!(store.count().unwrap(), 1);
    }

    #[test]
    fn force_reembeds_unchanged_files() {
        // F3: --force re-embeds even current rows.
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, false).unwrap();

        let stats = embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &e, true).unwrap();

        assert_eq!(stats.embedded, 1);
        assert_eq!(stats.unchanged, 0);
        assert_eq!(e.calls(), 2);
    }

    #[test]
    fn vector_leg_drops_rows_whose_file_was_deleted() {
        // F2: a ghost row (file deleted, embed-memory not rerun) never surfaces.
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "web scraping tips");
        let store = KnowledgeStore::open(&f.db).unwrap();
        embed_memory_files(&store, &list_memory_listing(&dirs(&f)), &Fake::new(), false).unwrap();
        fs::remove_file(f.mem.join("pattern_scraping-tips.md")).unwrap();

        let hits = VectorProvider::new(&f.db, Arc::new(Fake::new()))
            .with_memory_scope(MemoryScope::Only)
            .query("scraping question", 5);

        assert!(hits.is_empty(), "ghost memory row surfaced: {hits:?}");
        assert_eq!(store.count().unwrap(), 1, "the row itself stays until embed-memory prunes it");
    }
}
