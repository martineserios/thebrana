//! Local vector recall — brana-owned knowledge store + brute-force cosine search.
//!
//! Replaces `RufloProvider`'s broken retrieval stack (HNSW index desync, silent
//! no-op rebuilds — t-2620) with a store we own: `~/.claude/memory/knowledge.db`,
//! vectors as `f32` LE BLOBs, exact cosine scan per query. No index to desync;
//! at ~4.4k × 384-dim vectors a full scan is sub-millisecond in Rust. Revisit
//! only at ~100k entries (docs/architecture/features/local-vector-recall.md).
//!
//! Embedding generation stays external (ruflo ONNX, all-MiniLM-L6-v2 384d) —
//! injected via the [`Embedder`] trait so search is testable without it.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::Result;

use crate::search::{DocRef, SearchHit, SearchProvider};

/// Embedding dimensionality (all-MiniLM-L6-v2).
pub const EMBED_DIM: usize = 384;

// ── Store ─────────────────────────────────────────────────────────────────────

/// Brana-owned knowledge store at `~/.claude/memory/knowledge.db`.
///
/// Schema: `knowledge(key PRIMARY KEY, content, tags, source, created_at, vec BLOB)`.
/// `vec` is `EMBED_DIM` little-endian `f32`s (1,536 bytes).
pub struct KnowledgeStore {
    db_path: PathBuf,
}

impl KnowledgeStore {
    /// Open the store, creating the file and schema if absent.
    pub fn open(db_path: impl Into<PathBuf>) -> Result<Self> {
        let _ = db_path;
        todo!("t-2620 FIX")
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    /// Insert or replace an entry. `vec` must be `EMBED_DIM` long.
    pub fn upsert(
        &self,
        key: &str,
        content: &str,
        tags: Option<&str>,
        source: Option<&str>,
        created_at: i64,
        vec: &[f32],
    ) -> Result<()> {
        let _ = (key, content, tags, source, created_at, vec);
        todo!("t-2620 FIX")
    }

    /// Number of stored entries.
    pub fn count(&self) -> Result<usize> {
        todo!("t-2620 FIX")
    }
}

// ── Cosine ────────────────────────────────────────────────────────────────────

/// Cosine similarity of two equal-length vectors. Returns 0.0 for zero-norm inputs.
pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let _ = (a, b);
    todo!("t-2620 FIX")
}

// ── Embedder seam ─────────────────────────────────────────────────────────────

/// Query-text → vector. Production impl shells out to ruflo's ONNX embedding
/// generation (the one ruflo layer that works — spec §Keep). Tests inject fakes.
pub trait Embedder: Send + Sync {
    /// `None` = embedding unavailable (binary missing, timeout) — search fails open.
    fn embed(&self, text: &str) -> Option<Vec<f32>>;
}

// ── VectorProvider ────────────────────────────────────────────────────────────

/// Semantic recall over [`KnowledgeStore`] by brute-force cosine scan.
///
/// Fail-open contract (matches `RufloProvider`): missing DB, failed embedding,
/// or any error → empty vec, never a panic.
pub struct VectorProvider {
    db_path: PathBuf,
    embedder: Arc<dyn Embedder>,
    /// Hits below this cosine similarity are dropped.
    threshold: f32,
}

impl VectorProvider {
    pub fn new(db_path: impl Into<PathBuf>, embedder: Arc<dyn Embedder>) -> Self {
        Self {
            db_path: db_path.into(),
            embedder,
            threshold: 0.0,
        }
    }

    pub fn with_threshold(mut self, t: f32) -> Self {
        self.threshold = t;
        self
    }
}

impl SearchProvider for VectorProvider {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
        let _ = (q, top_k);
        todo!("t-2620 FIX")
    }
}

// ── Migration ─────────────────────────────────────────────────────────────────

/// Outcome of a [`migrate_from_memory_entries`] run.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct MigrateStats {
    /// Rows read across all sources (namespace `knowledge`).
    pub scanned: usize,
    /// Rows written to the destination store.
    pub migrated: usize,
    /// Rows skipped: no parseable embedding.
    pub skipped_no_embedding: usize,
    /// Rows dropped as older duplicates of a key seen in a fresher source row.
    pub deduped: usize,
}

/// One-time salvage migration: union `memory_entries` rows (namespace
/// `knowledge`) from every source DB, dedup by `key` preferring the row with
/// the newest `updated_at`, convert the JSON-array embedding text to an `f32`
/// LE BLOB, and upsert into the destination [`KnowledgeStore`].
///
/// Sources may include rotated `memory.db.corrupt-*` files — the 2026-08-03
/// rotation passes `integrity_check` and carries the 3,801 embedded rows the
/// live DB lost (t-2615). Rows without a parseable embedding are counted in
/// `skipped_no_embedding`, never silently dropped.
pub fn migrate_from_memory_entries(sources: &[PathBuf], dest: &Path) -> Result<MigrateStats> {
    let _ = (sources, dest);
    todo!("t-2620 FIX")
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    /// Deterministic fake: maps known phrases to fixed unit-ish vectors.
    struct FakeEmbedder;

    fn unit(dim_hot: usize) -> Vec<f32> {
        let mut v = vec![0.0_f32; EMBED_DIM];
        v[dim_hot] = 1.0;
        v
    }

    impl Embedder for FakeEmbedder {
        fn embed(&self, text: &str) -> Option<Vec<f32>> {
            match text {
                "rust web scraping" => Some(unit(0)),
                "engineering effectiveness" => Some(unit(1)),
                "no-embedding-available" => None,
                _ => Some(unit(2)),
            }
        }
    }

    // ── cosine ────────────────────────────────────────────────────────────────

    #[test]
    fn cosine_self_match_is_one() {
        let v = unit(3);
        assert!((cosine(&v, &v) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn cosine_orthogonal_is_zero() {
        assert!(cosine(&unit(0), &unit(1)).abs() < 1e-6);
    }

    #[test]
    fn cosine_zero_norm_is_zero_not_nan() {
        let z = vec![0.0_f32; EMBED_DIM];
        let c = cosine(&z, &unit(0));
        assert_eq!(c, 0.0, "zero-norm input must yield 0.0, got {c}");
    }

    // ── store ─────────────────────────────────────────────────────────────────

    #[test]
    fn store_upsert_and_count_roundtrip() {
        let tmp = tempdir().unwrap();
        let store = KnowledgeStore::open(tmp.path().join("knowledge.db")).unwrap();
        assert_eq!(store.count().unwrap(), 0);

        store
            .upsert("knowledge:url:a", "Scrapy is a scraping framework", None, Some("url"), 1, &unit(0))
            .unwrap();
        store
            .upsert("knowledge:url:b", "Engineering effectiveness over output", None, Some("url"), 2, &unit(1))
            .unwrap();
        assert_eq!(store.count().unwrap(), 2);

        // Upsert same key — replaces, not duplicates.
        store
            .upsert("knowledge:url:a", "Scrapy, revised", None, Some("url"), 3, &unit(0))
            .unwrap();
        assert_eq!(store.count().unwrap(), 2);
    }

    // ── provider ──────────────────────────────────────────────────────────────

    fn seeded_store(dir: &Path) -> PathBuf {
        let db = dir.join("knowledge.db");
        let store = KnowledgeStore::open(&db).unwrap();
        store
            .upsert("knowledge:url:scrapy", "Scrapy Python scraping framework", None, None, 1, &unit(0))
            .unwrap();
        store
            .upsert("knowledge:url:effectiveness", "Prioritize impact over output volume", None, None, 2, &unit(1))
            .unwrap();
        store
            .upsert("knowledge:url:other", "Unrelated content", None, None, 3, &unit(2))
            .unwrap();
        db
    }

    #[test]
    fn provider_returns_topic_match_as_knowledge_entry() {
        let tmp = tempdir().unwrap();
        let db = seeded_store(tmp.path());
        let provider = VectorProvider::new(db, Arc::new(FakeEmbedder));

        let hits = provider.query("rust web scraping", 2);
        assert!(!hits.is_empty(), "topic query must return the seeded entry");
        match &hits[0].doc {
            DocRef::KnowledgeEntry { key, namespace } => {
                assert_eq!(key, "knowledge:url:scrapy", "nearest vector must rank first");
                assert_eq!(namespace, "knowledge");
            }
            other => panic!("expected KnowledgeEntry, got {other:?}"),
        }
    }

    #[test]
    fn provider_honors_top_k_and_threshold() {
        let tmp = tempdir().unwrap();
        let db = seeded_store(tmp.path());

        let all = VectorProvider::new(&db, Arc::new(FakeEmbedder)).query("rust web scraping", 10);
        assert!(all.len() <= 10);

        // threshold 0.9: only the exact-direction match survives.
        let strict = VectorProvider::new(&db, Arc::new(FakeEmbedder))
            .with_threshold(0.9)
            .query("rust web scraping", 10);
        assert_eq!(strict.len(), 1, "only the cos≈1.0 hit passes threshold 0.9");
    }

    #[test]
    fn provider_missing_db_returns_empty_no_panic() {
        let provider = VectorProvider::new("/nonexistent/knowledge.db", Arc::new(FakeEmbedder));
        assert!(provider.query("anything", 5).is_empty());
    }

    #[test]
    fn provider_failed_embedding_returns_empty_no_panic() {
        let tmp = tempdir().unwrap();
        let db = seeded_store(tmp.path());
        let provider = VectorProvider::new(db, Arc::new(FakeEmbedder));
        assert!(provider.query("no-embedding-available", 5).is_empty());
    }

    // ── migration ─────────────────────────────────────────────────────────────

    /// Build a fake ruflo `memory_entries` DB matching the live schema subset
    /// the migration reads: key, namespace, content, embedding (JSON text),
    /// tags, created_at, updated_at.
    fn fake_memory_entries(path: &Path, rows: &[(&str, &str, Option<Vec<f32>>, i64)]) {
        let conn = rusqlite::Connection::open(path).unwrap();
        conn.execute_batch(
            "CREATE TABLE memory_entries (
                id TEXT PRIMARY KEY,
                key TEXT NOT NULL,
                namespace TEXT DEFAULT 'default',
                content TEXT NOT NULL,
                embedding TEXT,
                tags TEXT,
                created_at INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL DEFAULT 0,
                UNIQUE(namespace, key)
            );",
        )
        .unwrap();
        for (i, (key, content, vec, updated)) in rows.iter().enumerate() {
            let emb: Option<String> = vec.as_ref().map(|v| {
                let parts: Vec<String> = v.iter().map(|f| f.to_string()).collect();
                format!("[{}]", parts.join(","))
            });
            conn.execute(
                "INSERT INTO memory_entries (id, key, namespace, content, embedding, created_at, updated_at)
                 VALUES (?1, ?2, 'knowledge', ?3, ?4, ?5, ?5)",
                rusqlite::params![i.to_string(), key, content, emb, updated],
            )
            .unwrap();
        }
    }

    #[test]
    fn migrate_unions_dedups_and_converts() {
        let tmp = tempdir().unwrap();
        let old = tmp.path().join("corrupt-salvage.db");
        let live = tmp.path().join("live.db");
        // Old (salvage) source: 3 rows, one without embedding.
        fake_memory_entries(
            &old,
            &[
                ("knowledge:url:a", "old content a", Some(unit(0)), 100),
                ("knowledge:url:b", "content b", Some(unit(1)), 100),
                ("knowledge:url:noemb", "unembedded", None, 100),
            ],
        );
        // Live source: newer duplicate of a + one fresh row.
        fake_memory_entries(
            &live,
            &[
                ("knowledge:url:a", "NEW content a", Some(unit(0)), 200),
                ("knowledge:url:c", "content c", Some(unit(2)), 200),
            ],
        );

        let dest = tmp.path().join("knowledge.db");
        let stats =
            migrate_from_memory_entries(&[old, live], &dest).unwrap();

        assert_eq!(stats.scanned, 5);
        assert_eq!(stats.migrated, 3, "a (deduped), b, c");
        assert_eq!(stats.skipped_no_embedding, 1);
        assert_eq!(stats.deduped, 1);

        let store = KnowledgeStore::open(&dest).unwrap();
        assert_eq!(store.count().unwrap(), 3);

        // The newest duplicate won, and its vector round-trips through search.
        let provider = VectorProvider::new(&dest, Arc::new(FakeEmbedder));
        let hits = provider.query("rust web scraping", 1); // unit(0) direction = key a
        assert_eq!(hits.len(), 1);
        match &hits[0].doc {
            DocRef::KnowledgeEntry { key, .. } => assert_eq!(key, "knowledge:url:a"),
            other => panic!("expected KnowledgeEntry, got {other:?}"),
        }
        assert!(
            hits[0].snippet.contains("NEW"),
            "newest duplicate must win, got: {}",
            hits[0].snippet
        );
    }

    #[test]
    fn migrate_empty_sources_yields_empty_store() {
        let tmp = tempdir().unwrap();
        let dest = tmp.path().join("knowledge.db");
        let stats = migrate_from_memory_entries(&[], &dest).unwrap();
        assert_eq!(stats, MigrateStats::default());
        assert_eq!(KnowledgeStore::open(&dest).unwrap().count().unwrap(), 0);
    }
}
