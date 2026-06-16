//! SearchProvider trait — pluggable recall seam (t-2109 / t-2091).
//!
//! Two concrete implementations live here:
//!   - `FTS5Provider`   — keyword recall over the embedded SQLite+FTS5 index
//!   - `RufloProvider`  — semantic/vector recall via the ruflo binary
//!
//! A third impl (`HybridProvider`) dispatches both in parallel and merges
//! results via RRF; it is implemented as a separate step blocked on this one.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, mpsc};
use std::thread;
use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};

// ── Public types ──────────────────────────────────────────────────────────────

/// Typed document identity — structurally prevents cross-backend false dedup.
///
/// `MemoryFile` and `KnowledgeEntry` can never be equal by type, which is
/// correct: FTS5 indexes filesystem files; ruflo indexes semantic entries.
/// These are independent write paths and are never the same document.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum DocRef {
    /// A memory markdown file indexed by the embedded FTS5 store.
    MemoryFile {
        path: PathBuf,
        slug: String,
        mtype: String,
        scope: String,
    },
    /// A knowledge entry stored in the ruflo vector database.
    KnowledgeEntry { key: String, namespace: String },
}

/// A single result from a `SearchProvider::query` call.
///
/// `rrf_score` is `0.0` at the provider level; it is set by `HybridProvider`
/// during RRF merge. Single-provider callers may ignore it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchHit {
    pub doc: DocRef,
    pub snippet: String,
    /// Reciprocal Rank Fusion score — 0.0 when produced by a single provider.
    pub rrf_score: f64,
}

/// A recall backend. Both implementations must be `Send + Sync` so
/// `HybridProvider` can dispatch them from separate threads.
pub trait SearchProvider: Send + Sync {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit>;
}

// ── FTS5Provider ──────────────────────────────────────────────────────────────

/// Keyword recall over the embedded SQLite+FTS5 memory index.
///
/// Opens a new `rusqlite::Connection` per `query()` call — `rusqlite::Connection`
/// is `!Send`, so holding it as struct state would prevent `FTS5Provider: Send`.
/// Connection-per-query is correct for this workload; the index is read-only
/// during recall and SQLite WAL mode handles concurrent readers.
pub struct FTS5Provider {
    db_path: PathBuf,
}

impl FTS5Provider {
    pub fn new(db_path: PathBuf) -> Self {
        Self { db_path }
    }
}

impl SearchProvider for FTS5Provider {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
        let hits = crate::memory::search_fts(&self.db_path, q, top_k)
            .unwrap_or_default();
        hits.into_iter()
            .map(|h| SearchHit {
                doc: DocRef::MemoryFile {
                    path: PathBuf::from(&h.path),
                    slug: h.slug,
                    mtype: h.mtype,
                    scope: h.scope,
                },
                snippet: h.snippet,
                rrf_score: 0.0,
            })
            .collect()
    }
}

// ── RufloProvider ─────────────────────────────────────────────────────────────

/// Semantic/vector recall via the ruflo binary.
///
/// Returns an empty vec when ruflo is absent, times out, or returns no results.
/// The caller should always fail-open on empty results.
///
/// Uses `--json` mode unconditionally — table output from ruflo truncates long
/// keys (`knowledge:feed:re...`), making them unusable as `DocRef` identities.
pub struct RufloProvider {
    namespace: String,
    threshold: Option<f64>,
}

impl RufloProvider {
    pub fn new(namespace: impl Into<String>) -> Self {
        Self {
            namespace: namespace.into(),
            threshold: None,
        }
    }

    pub fn with_threshold(mut self, t: f64) -> Self {
        self.threshold = Some(t);
        self
    }
}

impl SearchProvider for RufloProvider {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
        let Some(raw) = crate::ruflo::ruflo_memory_search_raw(
            q,
            &self.namespace,
            top_k,
            self.threshold,
            true, // json: true — required for full key names
        ) else {
            return Vec::new();
        };
        parse_ruflo_json(&raw, &self.namespace)
    }
}

/// Parse a ruflo `--json` response into `SearchHit`s.
///
/// Ruflo prefixes stdout with ONNX/Node preamble and `[INFO]` log lines before
/// the JSON array. We scan for the first `[` that opens a real array (followed
/// by `{` or `]`) — the same heuristic used in `brana-cli::commands::knowledge`.
/// Duplication is intentional: `brana-core` cannot depend on `brana-cli`.
///
/// Expected element shape: `{"key": "...", "value": "...", "score": 0.0}`
fn parse_ruflo_json(raw: &str, namespace: &str) -> Vec<SearchHit> {
    let Some(start) = find_json_array_start(raw) else {
        return Vec::new();
    };
    let Ok(arr) = serde_json::from_str::<Vec<serde_json::Value>>(&raw[start..]) else {
        return Vec::new();
    };
    arr.into_iter()
        .filter_map(|e| {
            let key = e["key"].as_str()?.to_string();
            let snippet = e["value"].as_str().unwrap_or("").to_string();
            Some(SearchHit {
                doc: DocRef::KnowledgeEntry {
                    key,
                    namespace: namespace.to_string(),
                },
                snippet,
                rrf_score: 0.0,
            })
        })
        .collect()
}

/// Scan for the byte offset of the first `[` that opens a JSON array,
/// skipping `[INFO]`, `[WARN]`, and similar log markers.
fn find_json_array_start(text: &str) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'[' {
            let mut j = i + 1;
            while j < bytes.len() && matches!(bytes[j], b' ' | b'\n' | b'\r' | b'\t') {
                j += 1;
            }
            if j < bytes.len() && matches!(bytes[j], b'{' | b']') {
                return Some(i);
            }
        }
        i += 1;
    }
    None
}

// ── HybridProvider ────────────────────────────────────────────────────────────

/// Production deadlines — see ADR-058 §9 for calibration rationale.
const FTS5_DEADLINE: Duration = Duration::from_millis(500);
const RUFLO_DEADLINE: Duration = Duration::from_secs(2);
/// RRF rank-smoothing constant — calibrated for corpus list lengths 3–21 (ADR-058 §6).
const K: usize = 20;
/// Minimum candidate pool fetched from each provider before RRF truncation.
const MIN_CANDIDATE_POOL: usize = 20;

/// Parallel-dispatch recall provider that queries `FTS5Provider` and
/// `RufloProvider` simultaneously, then merges results with Reciprocal Rank
/// Fusion (k=20, no dedup — see ADR-058 §5–6).
///
/// Degrades gracefully on timeout:
/// - FTS5 misses its 500ms deadline → ruflo-only results (not empty).
/// - Ruflo misses its 2s deadline   → FTS5-only results (not empty).
/// - Both timeout                   → empty vec.
///
/// Ruflo's budget is measured from dispatch start, not from when FTS5 returns.
/// Worst-case wall-clock = `RUFLO_DEADLINE` (2s), not 2.5s.
pub struct HybridProvider {
    fts5: Arc<dyn SearchProvider>,
    ruflo: Arc<dyn SearchProvider>,
    fts5_deadline: Duration,
    ruflo_deadline: Duration,
}

impl HybridProvider {
    /// Construct with production deadlines (FTS5: 500ms, ruflo: 2s).
    pub fn new(fts5: Arc<dyn SearchProvider>, ruflo: Arc<dyn SearchProvider>) -> Self {
        Self { fts5, ruflo, fts5_deadline: FTS5_DEADLINE, ruflo_deadline: RUFLO_DEADLINE }
    }

    /// Construct with custom deadlines — for testing and configuration.
    pub fn with_deadlines(
        fts5: Arc<dyn SearchProvider>,
        ruflo: Arc<dyn SearchProvider>,
        fts5_deadline: Duration,
        ruflo_deadline: Duration,
    ) -> Self {
        Self { fts5, ruflo, fts5_deadline, ruflo_deadline }
    }
}

impl SearchProvider for HybridProvider {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
        let q: Arc<str> = Arc::from(q);
        let fetch = top_k.max(MIN_CANDIDATE_POOL);

        let fts5        = Arc::clone(&self.fts5);
        let ruflo       = Arc::clone(&self.ruflo);
        let q_fts5      = Arc::clone(&q);
        let q_ruflo     = Arc::clone(&q);
        let fts5_dl     = self.fts5_deadline;
        let ruflo_dl    = self.ruflo_deadline;

        let (tx_fts5,  rx_fts5)  = mpsc::channel();
        let (tx_ruflo, rx_ruflo) = mpsc::channel();

        thread::spawn(move || { let _ = tx_fts5.send(fts5.query(&q_fts5, fetch)); });
        thread::spawn(move || { let _ = tx_ruflo.send(ruflo.query(&q_ruflo, fetch)); });

        // Ruflo budget starts from dispatch, not from when FTS5 returns.
        // Worst-case wall-clock = RUFLO_DEADLINE.
        let start         = Instant::now();
        let fts5_results  = rx_fts5.recv_timeout(fts5_dl).unwrap_or_default();
        let ruflo_budget  = ruflo_dl.saturating_sub(start.elapsed());
        let ruflo_results = rx_ruflo.recv_timeout(ruflo_budget).unwrap_or_default();

        rrf_merge(vec![fts5_results, ruflo_results], K, top_k)
    }
}

/// Reciprocal Rank Fusion across multiple ranked lists.
///
/// `score(doc) = Σ 1/(k + rank)` where rank is 1-indexed within each list.
/// Documents appearing in multiple lists accumulate additive score — dual-backend
/// confirmation is genuine relevance signal (ADR-058 §6, no-dedup rationale).
fn rrf_merge(lists: Vec<Vec<SearchHit>>, k: usize, top_k: usize) -> Vec<SearchHit> {
    let mut scores: HashMap<DocRef, (f64, SearchHit)> = HashMap::new();
    for list in lists {
        for (i, hit) in list.into_iter().enumerate() {
            let rank  = i + 1;
            let score = 1.0 / (k + rank) as f64;
            scores
                .entry(hit.doc.clone())
                .and_modify(|(s, _)| *s += score)
                .or_insert((score, hit));
        }
    }
    let mut out: Vec<SearchHit> = scores
        .into_values()
        .map(|(score, mut hit)| {
            hit.rrf_score = score;
            hit
        })
        .collect();
    out.sort_by(|a, b| {
        b.rrf_score
            .partial_cmp(&a.rrf_score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    out.truncate(top_k);
    out
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::reindex_fts_dirs;
    use serial_test::serial;
    use std::fs;
    use tempfile::tempdir;

    fn write_mem(dir: &std::path::Path, name: &str, body: &str) {
        fs::create_dir_all(dir).unwrap();
        fs::write(dir.join(name), body).unwrap();
    }

    // ── FTS5Provider contract tests ───────────────────────────────────────────

    #[test]
    fn fts5_returns_memory_file_docref() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write_mem(&mem, "pattern_jwt-auth.md", "JWT token validation");
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();

        let provider = FTS5Provider::new(db);
        let hits = provider.query("jwt token", 10);

        assert!(!hits.is_empty(), "should find the jwt doc");
        for h in &hits {
            assert!(
                matches!(h.doc, DocRef::MemoryFile { .. }),
                "all FTS5 hits must be MemoryFile variants, got {:?}", h.doc
            );
        }
    }

    #[test]
    fn fts5_empty_query_returns_empty() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write_mem(&mem, "pattern_x.md", "some content here");
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();

        let provider = FTS5Provider::new(db);
        assert!(provider.query("", 10).is_empty());
        assert!(provider.query("  :::  ", 10).is_empty());
    }

    #[test]
    fn fts5_top_k_is_honored() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        for i in 0..5 {
            write_mem(&mem, &format!("pattern_doc{i}.md"), "shared keyword content");
        }
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();

        let provider = FTS5Provider::new(db);
        let hits = provider.query("shared keyword content", 2);
        assert!(hits.len() <= 2, "top_k=2 must cap results, got {}", hits.len());
    }

    #[test]
    fn fts5_hit_fields_match_indexed_entry() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write_mem(&mem, "feedback_my-rule.md", "unique phrase xyzzy");
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();

        let provider = FTS5Provider::new(db);
        let hits = provider.query("unique phrase xyzzy", 10);
        assert_eq!(hits.len(), 1);

        match &hits[0].doc {
            DocRef::MemoryFile { slug, mtype, scope, path } => {
                assert_eq!(slug, "my-rule");
                assert_eq!(mtype, "feedback");
                assert_eq!(scope, "global");
                assert!(path.to_string_lossy().ends_with("feedback_my-rule.md"));
            }
            other => panic!("expected MemoryFile, got {other:?}"),
        }
    }

    // ── RufloProvider contract tests ──────────────────────────────────────────

    #[test]
    #[serial]
    fn ruflo_absent_returns_empty_no_panic() {
        let prev = std::env::var("RUFLO_BIN").ok();
        unsafe { std::env::set_var("RUFLO_BIN", "/nonexistent-ruflo-brana-test") };

        let provider = RufloProvider::new("knowledge");
        let hits = provider.query("anything", 5);

        unsafe {
            match prev {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
        }

        assert!(hits.is_empty(), "absent ruflo must return empty, not panic");
    }

    #[test]
    fn ruflo_json_parse_returns_knowledge_entry_docref() {
        // Feed a well-formed ruflo JSON response directly into parse_ruflo_json.
        let raw = r#"[
            {"key":"knowledge:pattern:jwt-auth:0","value":"JWT auth pattern snippet","score":0.72},
            {"key":"knowledge:feedback:redis:0","value":"Redis cache note","score":0.55}
        ]"#;

        let hits = parse_ruflo_json(raw, "knowledge");
        assert_eq!(hits.len(), 2);
        for h in &hits {
            assert!(
                matches!(h.doc, DocRef::KnowledgeEntry { .. }),
                "all ruflo hits must be KnowledgeEntry variants, got {:?}", h.doc
            );
        }
    }

    #[test]
    fn ruflo_json_parse_skips_preamble_log_lines() {
        // Simulate ruflo output with [INFO] preamble before the JSON array.
        let raw = "[INFO] Loading ONNX model...\n[INFO] Ready.\n[\n  {\"key\":\"k:x\",\"value\":\"v\",\"score\":0.5}\n]";
        let hits = parse_ruflo_json(raw, "knowledge");
        assert_eq!(hits.len(), 1);
        match &hits[0].doc {
            DocRef::KnowledgeEntry { key, namespace } => {
                assert_eq!(key, "k:x");
                assert_eq!(namespace, "knowledge");
            }
            other => panic!("expected KnowledgeEntry, got {other:?}"),
        }
    }

    #[test]
    fn ruflo_json_parse_empty_array_returns_empty() {
        let hits = parse_ruflo_json("[]", "knowledge");
        assert!(hits.is_empty());
    }

    #[test]
    fn ruflo_json_parse_garbage_returns_empty() {
        assert!(parse_ruflo_json("", "knowledge").is_empty());
        assert!(parse_ruflo_json("not json at all", "knowledge").is_empty());
        assert!(parse_ruflo_json("[INFO] no array follows", "knowledge").is_empty());
    }

    // ── HybridProvider helpers ────────────────────────────────────────────────

    struct FixedProvider {
        hits: Vec<SearchHit>,
        delay: Option<Duration>,
    }

    impl FixedProvider {
        fn fixed(hits: Vec<SearchHit>) -> Arc<Self> {
            Arc::new(Self { hits, delay: None })
        }
        fn delayed(hits: Vec<SearchHit>, delay: Duration) -> Arc<Self> {
            Arc::new(Self { hits, delay: Some(delay) })
        }
    }

    impl SearchProvider for FixedProvider {
        fn query(&self, _q: &str, top_k: usize) -> Vec<SearchHit> {
            if let Some(d) = self.delay { std::thread::sleep(d); }
            self.hits.iter().cloned().take(top_k).collect()
        }
    }

    fn ke(key: &str) -> DocRef {
        DocRef::KnowledgeEntry { key: key.to_string(), namespace: "test".to_string() }
    }
    fn h(key: &str) -> SearchHit {
        SearchHit { doc: ke(key), snippet: key.to_string(), rrf_score: 0.0 }
    }

    // ── HybridProvider contract tests ─────────────────────────────────────────

    #[test]
    fn hybrid_rrf_dual_signal_doc_ranks_first() {
        // fts5: [a, b]   ruflo: [b, c]
        // b appears in both — additive RRF score → must rank above a and c.
        let fts5  = FixedProvider::fixed(vec![h("a"), h("b")]);
        let ruflo = FixedProvider::fixed(vec![h("b"), h("c")]);
        let hits = HybridProvider::new(fts5, ruflo).query("q", 10);
        assert!(!hits.is_empty());
        match &hits[0].doc {
            DocRef::KnowledgeEntry { key, .. } => assert_eq!(key, "b", "dual-signal doc must rank first"),
            other => panic!("expected KnowledgeEntry, got {other:?}"),
        }
        assert!(hits[0].rrf_score > 0.0);
    }

    #[test]
    fn hybrid_rrf_score_set_on_every_result() {
        let fts5  = FixedProvider::fixed(vec![h("x")]);
        let ruflo = FixedProvider::fixed(vec![h("y")]);
        for result in HybridProvider::new(fts5, ruflo).query("q", 10) {
            assert!(result.rrf_score > 0.0, "every result must have rrf_score > 0");
        }
    }

    #[test]
    fn hybrid_empty_ruflo_returns_fts5_results() {
        let fts5  = FixedProvider::fixed(vec![h("x")]);
        let ruflo = FixedProvider::fixed(vec![]);
        let hits = HybridProvider::new(fts5, ruflo).query("q", 10);
        assert_eq!(hits.len(), 1);
        match &hits[0].doc {
            DocRef::KnowledgeEntry { key, .. } => assert_eq!(key, "x"),
            _ => panic!("wrong docref"),
        }
    }

    #[test]
    fn hybrid_empty_fts5_returns_ruflo_results() {
        let fts5  = FixedProvider::fixed(vec![]);
        let ruflo = FixedProvider::fixed(vec![h("y")]);
        let hits = HybridProvider::new(fts5, ruflo).query("q", 10);
        assert_eq!(hits.len(), 1);
        match &hits[0].doc {
            DocRef::KnowledgeEntry { key, .. } => assert_eq!(key, "y"),
            _ => panic!("wrong docref"),
        }
    }

    #[test]
    fn hybrid_top_k_truncates_output() {
        let hits20: Vec<_> = (0..20).map(|i| h(&format!("doc{i}"))).collect();
        let fts5  = FixedProvider::fixed(hits20.clone());
        let ruflo = FixedProvider::fixed(hits20);
        let out = HybridProvider::new(fts5, ruflo).query("q", 3);
        assert_eq!(out.len(), 3, "top_k=3 must truncate, got {}", out.len());
    }

    #[test]
    fn hybrid_fetches_min_candidate_pool_for_small_top_k() {
        // 20 unique docs per provider (no overlap) → 40 unique entries after RRF.
        // top_k=5 → must return exactly 5 (not top_k entries from each provider).
        let fts5_hits:  Vec<_> = (0..20).map(|i| h(&format!("fts5-{i}"))).collect();
        let ruflo_hits: Vec<_> = (0..20).map(|i| h(&format!("ruflo-{i}"))).collect();
        let fts5  = FixedProvider::fixed(fts5_hits);
        let ruflo = FixedProvider::fixed(ruflo_hits);
        let out = HybridProvider::new(fts5, ruflo).query("q", 5);
        assert_eq!(out.len(), 5);
    }

    #[test]
    fn hybrid_fts5_timeout_degrades_to_ruflo_only() {
        // fts5 sleeps 150ms > fts5_deadline=50ms → timeout → ruflo-only (not empty).
        let fts5  = FixedProvider::delayed(vec![h("from-fts5")], Duration::from_millis(150));
        let ruflo = FixedProvider::fixed(vec![h("from-ruflo")]);
        let hybrid = HybridProvider::with_deadlines(
            fts5, ruflo,
            Duration::from_millis(50),
            Duration::from_millis(500),
        );
        let hits = hybrid.query("q", 10);
        assert!(!hits.is_empty(), "must degrade to ruflo-only, not empty");
        assert!(
            hits.iter().any(|h| matches!(&h.doc, DocRef::KnowledgeEntry { key, .. } if key == "from-ruflo")),
            "ruflo result must be present"
        );
        assert!(
            !hits.iter().any(|h| matches!(&h.doc, DocRef::KnowledgeEntry { key, .. } if key == "from-fts5")),
            "fts5 result must be absent (timed out)"
        );
    }

    #[test]
    fn hybrid_ruflo_timeout_degrades_to_fts5_only() {
        // ruflo sleeps 250ms > ruflo_deadline=100ms → timeout → fts5-only (not empty).
        let fts5  = FixedProvider::fixed(vec![h("from-fts5")]);
        let ruflo = FixedProvider::delayed(vec![h("from-ruflo")], Duration::from_millis(250));
        let hybrid = HybridProvider::with_deadlines(
            fts5, ruflo,
            Duration::from_millis(500),
            Duration::from_millis(100),
        );
        let hits = hybrid.query("q", 10);
        assert!(!hits.is_empty(), "must degrade to fts5-only, not empty");
        assert!(
            hits.iter().any(|h| matches!(&h.doc, DocRef::KnowledgeEntry { key, .. } if key == "from-fts5")),
            "fts5 result must be present"
        );
        assert!(
            !hits.iter().any(|h| matches!(&h.doc, DocRef::KnowledgeEntry { key, .. } if key == "from-ruflo")),
            "ruflo result must be absent (timed out)"
        );
    }

    #[test]
    fn hybrid_ruflo_budget_from_dispatch_start() {
        // Proves budget starts from dispatch, not from fts5 return.
        //
        // fts5: sleeps 50ms. ruflo: sleeps 130ms. ruflo_deadline: 100ms.
        //
        // With dispatch-start budget (correct):
        //   At t=50 (fts5 returns), elapsed=50ms.
        //   ruflo_budget = 100-50 = 50ms. Ruflo needs 130-50=80ms more → TIMEOUT.
        //
        // With fts5-return budget (incorrect):
        //   Ruflo would get 100ms from t=50 → absolute deadline t=150.
        //   Ruflo completes at t=130 < t=150 → would succeed.
        //
        // Test passes only if implementation uses dispatch-start budget.
        let fts5  = FixedProvider::delayed(vec![h("from-fts5")],  Duration::from_millis(50));
        let ruflo = FixedProvider::delayed(vec![h("from-ruflo")], Duration::from_millis(130));
        let hybrid = HybridProvider::with_deadlines(
            fts5, ruflo,
            Duration::from_millis(500),
            Duration::from_millis(100),
        );
        let hits = hybrid.query("q", 10);
        assert!(
            hits.iter().any(|h| matches!(&h.doc, DocRef::KnowledgeEntry { key, .. } if key == "from-fts5")),
            "fts5 result must be present"
        );
        assert!(
            !hits.iter().any(|h| matches!(&h.doc, DocRef::KnowledgeEntry { key, .. } if key == "from-ruflo")),
            "ruflo must timeout — budget starts from dispatch, not from fts5 return"
        );
    }
}
