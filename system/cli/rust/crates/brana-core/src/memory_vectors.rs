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

use crate::memory::{MemoryFileRef, memory_file_identity};
use crate::search::DocRef;
use crate::vector::{EMBED_DIM, Embedder, KnowledgeStore, parse_tags, truncate_chars};

/// `source` column value marking a row as an embedded memory file.
pub const MEMORY_SOURCE: &str = "memory-file";

/// Characters of file text passed to the embedder (MiniLM truncates near this anyway).
pub const EMBED_CHARS: usize = 1500;

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

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Embed new or changed files, skip unchanged ones, prune rows whose file is gone.
///
/// - A file whose stored `content` equals the file on disk is `unchanged`: the
///   embedder is not called.
/// - A file the embedder cannot embed (or that cannot be read) is `failed`. It
///   leaves no new row; an older row for it, if any, is kept rather than pruned,
///   so a transient embedder outage never deletes working recall.
/// - Rows of source [`MEMORY_SOURCE`] whose file is not in `files` are pruned.
///   An empty `files` list prunes nothing: an empty scan means discovery found
///   nothing (bad `$HOME`, unmounted dir), not that every memory was deleted.
///   Rows from other sources are never touched.
pub fn embed_memory_files(
    store: &KnowledgeStore,
    files: &[MemoryFileRef],
    embedder: &dyn Embedder,
) -> Result<EmbedStats> {
    let mut stats = EmbedStats { scanned: files.len(), ..Default::default() };
    let mut live: HashSet<String> = HashSet::new();

    for f in files {
        let key = memory_row_key(&f.path);
        live.insert(key.clone());

        let Ok(content) = std::fs::read_to_string(&f.path) else {
            stats.failed += 1;
            continue;
        };
        if store.content_of(&key)?.as_deref() == Some(content.as_str()) {
            stats.unchanged += 1;
            continue;
        }
        let text: String = content.chars().take(EMBED_CHARS).collect();
        let Some(vec) = embedder.embed(&text).filter(|v| v.len() == EMBED_DIM) else {
            stats.failed += 1;
            continue;
        };
        let tags = format!("memory-file,scope:{}", f.scope);
        store.upsert(&key, &content, Some(&tags), Some(MEMORY_SOURCE), now_ms(), &vec)?;
        stats.embedded += 1;
    }

    if !files.is_empty() {
        for key in store.keys_with_source(MEMORY_SOURCE)? {
            if !live.contains(&key) && store.delete(&key)? {
                stats.pruned += 1;
            }
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
    let path = PathBuf::from(key.strip_prefix(KEY_PREFIX)?);
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
    use crate::memory::{list_memory_files, reindex_fts_dirs};
    use crate::search::{FTS5Provider, HybridProvider, SearchProvider};
    use crate::vector::{VectorProvider, EMBED_DIM};
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
        let files = list_memory_files(&dirs(&f));

        let stats = embed_memory_files(&store, &files, &Fake::new()).unwrap();

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
        let files = list_memory_files(&dirs(&f));
        let e = Fake::new();
        embed_memory_files(&store, &files, &e).unwrap();
        let calls_after_first = e.calls();

        let stats = embed_memory_files(&store, &files, &e).unwrap();

        assert_eq!(stats, EmbedStats { scanned: 1, unchanged: 1, ..Default::default() });
        assert_eq!(e.calls(), calls_after_first, "unchanged file must not hit the embedder");
    }

    #[test]
    fn changed_file_is_reembedded() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

        put(&f, "pattern_a.md", "alpha pricing now");
        let stats = embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

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
        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();
        assert_eq!(store.count().unwrap(), 3);

        fs::remove_file(f.mem.join("pattern_b.md")).unwrap();
        let stats = embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

        assert_eq!(stats.pruned, 1);
        assert_eq!(store.count().unwrap(), 2, "b pruned; a and the foreign row remain");
    }

    #[test]
    fn unembeddable_file_is_counted_failed_and_leaves_no_row() {
        let f = fixture();
        put(&f, "pattern_bad.md", "UNEMBEDDABLE");
        let store = KnowledgeStore::open(&f.db).unwrap();

        let stats = embed_memory_files(&store, &list_memory_files(&dirs(&f)), &Fake::new()).unwrap();

        assert_eq!(stats, EmbedStats { scanned: 1, failed: 1, ..Default::default() });
        assert_eq!(store.count().unwrap(), 0);
    }

    #[test]
    fn empty_scan_prunes_nothing() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

        // Discovery found nothing (bad HOME, unmounted dir): must not wipe the index.
        let stats = embed_memory_files(&store, &[], &e).unwrap();

        assert_eq!(stats, EmbedStats::default());
        assert_eq!(store.count().unwrap(), 1);
    }

    #[test]
    fn failed_reembed_keeps_the_old_row() {
        let f = fixture();
        put(&f, "pattern_a.md", "alpha scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let e = Fake::new();
        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

        // File changes to something the embedder refuses: old working row must survive.
        put(&f, "pattern_a.md", "alpha UNEMBEDDABLE");
        let stats = embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

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

        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &e).unwrap();

        assert!(e.longest() <= EMBED_CHARS, "embedder saw {} chars", e.longest());
    }

    #[test]
    fn memory_doc_ref_roundtrips_identity_and_ignores_foreign_rows() {
        let f = fixture();
        put(&f, "pattern_scraping-tips_2026-06-09T10-00-00.md", "scraping");
        let store = KnowledgeStore::open(&f.db).unwrap();
        let files = list_memory_files(&dirs(&f));
        embed_memory_files(&store, &files, &Fake::new()).unwrap();

        let key = memory_row_key(&files[0].path);
        let row = store.rows_with_vec(crate::vector::RowFilter::All).unwrap().remove(0);
        let doc = memory_doc_ref(&key, row.tags.as_deref(), Some(MEMORY_SOURCE)).expect("memory row maps");
        assert_eq!(
            doc,
            DocRef::MemoryFile {
                path: files[0].path.clone(),
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
        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &Fake::new()).unwrap();

        let provider = VectorProvider::new(&f.db, Arc::new(Fake::new())).with_memory_files(true);
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
        embed_memory_files(&store, &list_memory_files(&dirs(&f)), &Fake::new()).unwrap();

        let hits = VectorProvider::new(&f.db, Arc::new(Fake::new())).query("scraping question", 5);

        assert!(
            hits.iter().all(|h| matches!(h.doc, DocRef::KnowledgeEntry { .. })),
            "memory-file rows leaked into the default provider: {hits:?}"
        );
        assert_eq!(hits.len(), 1);
    }

    #[test]
    fn hybrid_fuses_fts_and_vector_signals_for_the_same_memory_file() {
        let f = fixture();
        put(&f, "pattern_scraping-tips.md", "web scraping tips for crawlers");
        put(&f, "pattern_other.md", "gardening notes about pricing of seeds");
        let d = dirs(&f);
        reindex_fts_dirs(&d, &f.fts).unwrap();
        let store = KnowledgeStore::open(&f.db).unwrap();
        embed_memory_files(&store, &list_memory_files(&d), &Fake::new()).unwrap();

        let fts = Arc::new(FTS5Provider::new(f.fts.clone())) as Arc<dyn SearchProvider>;
        let vec = Arc::new(VectorProvider::new(&f.db, Arc::new(Fake::new())).with_memory_files(true))
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
        embed_memory_files(&store, &list_memory_files(&d), &Fake::new()).unwrap();

        let fts = Arc::new(FTS5Provider::new(f.fts.clone())) as Arc<dyn SearchProvider>;
        let vec = Arc::new(VectorProvider::new(&f.db, Arc::new(Fake::new())).with_memory_files(true))
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
}
