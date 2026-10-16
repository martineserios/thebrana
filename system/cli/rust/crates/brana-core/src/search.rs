//! SearchProvider trait — pluggable recall seam (t-2109 / t-2091).
//!
//! Two concrete implementations live here:
//!   - `FTS5Provider`   — keyword recall over the embedded SQLite+FTS5 index
//!   - `RufloProvider`  — semantic/vector recall via the ruflo binary
//!
//! A third impl (`HybridProvider`) dispatches both in parallel and merges
//! results via RRF; it is implemented as a separate step blocked on this one.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::mpsc::RecvTimeoutError;
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

    /// Like [`query`](Self::query), but a backend that cannot search (missing
    /// index, no query embedding, unreadable store) returns `Err` instead of an
    /// empty list, so "nothing matched" and "could not search" stay apart (t-3535).
    /// The default wraps `query`, for providers with no failure signal of their own.
    fn try_query(&self, q: &str, top_k: usize) -> anyhow::Result<Vec<SearchHit>> {
        Ok(self.query(q, top_k))
    }
}

/// Outcome of one recall leg (t-3535, recall-bundle spec §Gate-2 amendments).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LegStatus {
    /// Searched and returned hits.
    Ok,
    /// Searched and matched nothing.
    Empty,
    /// Missed its deadline; its results, if any, were dropped.
    Timeout,
    /// Could not search (missing index or embedder, store error, crashed leg).
    Error,
}

impl LegStatus {
    /// The lowercase spelling used in JSON and human output.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Ok => "ok",
            Self::Empty => "empty",
            Self::Timeout => "timeout",
            Self::Error => "error",
        }
    }
}

/// Per-leg outcome of a [`HybridProvider`] query, in dispatch order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HybridStatus {
    pub keyword: LegStatus,
    pub semantic: LegStatus,
    /// One entry per `with_extra` leg, in the order they were added.
    pub extras: Vec<LegStatus>,
}

// ── RecallScope ───────────────────────────────────────────────────────────────

/// Which memory notes a recall may return (t-3535, ADR-099 §2).
///
/// `All` is plain recall: every project's memory. `Dirs` keeps only notes directly
/// inside the listed folders; sub-folders such as `archive/` are out. Knowledge-store
/// entries carry no path and are not filtered here.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum RecallScope {
    #[default]
    All,
    Dirs(Vec<PathBuf>),
}

impl RecallScope {
    /// The current project plus global memory, resolved from the main checkout so
    /// every worktree of a repo gets the same scope.
    pub fn current_project() -> Self {
        Self::project_in(&crate::util::home(), crate::util::find_session_root().as_deref())
    }

    /// Testable variant of [`current_project`](Self::current_project). Both folder
    /// encodings are included because both exist on disk. Without a resolvable
    /// project the scope is global memory only: it never widens on a lookup miss.
    pub fn project_in(home: &Path, session_root: Option<&Path>) -> Self {
        let mut dirs = vec![home.join(".claude/memory")];
        if let Some(root) = session_root {
            let projects = home.join(".claude/projects");
            for name in [
                crate::util::encode_project_dir(root),
                crate::util::encode_project_dir_legacy(root),
            ] {
                let dir = projects.join(name).join("memory");
                if !dirs.contains(&dir) {
                    dirs.push(dir);
                }
            }
        }
        Self::Dirs(dirs)
    }

    /// Whether a memory note at `path` is in scope: it sits directly in a scope folder and,
    /// if it is a symlink, resolves to a file directly in a scope folder too. Without the
    /// second half a link planted in global memory could surface another project's note
    /// (t-3537 gate). Anything that cannot be shown to be a plain note in scope is refused:
    /// a path that cannot be checked, a link that cannot be resolved, a folder, a FIFO (t-3542).
    ///
    /// Limits, stated rather than hidden: a hard link is another name for the same file, so a
    /// hard link planted in a scope folder to an out-of-scope file reads as in scope (the
    /// filesystem offers no check; the folders are user-private, ADR-095). The scope folders
    /// themselves are trusted by name. There is a window between this check and the open.
    pub fn allows(&self, path: &Path) -> bool {
        match self {
            Self::All => true,
            Self::Dirs(dirs) => {
                if !path.parent().is_some_and(|p| dirs.iter().any(|d| d == p)) {
                    return false;
                }
                // Only a plain note is in scope: a path that cannot be checked (the callers open
                // what this passes), a folder or a FIFO (opening one blocks) is refused.
                match std::fs::symlink_metadata(path) {
                    Ok(m) if m.file_type().is_symlink() => resolves_into(path, dirs),
                    Ok(m) => m.is_file(),
                    Err(_) => false,
                }
            }
        }
    }

    /// The allowed folders, or `None` for no restriction.
    pub fn dirs(&self) -> Option<&[PathBuf]> {
        match self {
            Self::All => None,
            Self::Dirs(dirs) => Some(dirs),
        }
    }
}

/// Whether the symlink at `path` ends at a file directly inside one of `dirs`
/// (compared after resolving the folders too, so a scope reached through a link works).
fn resolves_into(path: &Path, dirs: &[PathBuf]) -> bool {
    let Ok(real) = std::fs::canonicalize(path) else { return false };
    if !real.is_file() {
        return false;
    }
    let Some(parent) = real.parent() else { return false };
    dirs.iter().any(|d| std::fs::canonicalize(d).is_ok_and(|cd| cd == parent))
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
    scope: RecallScope,
}

impl FTS5Provider {
    pub fn new(db_path: PathBuf) -> Self {
        Self { db_path, scope: RecallScope::All }
    }

    /// Limit hits to notes in scope; applied inside the SQL query (t-3535).
    pub fn with_scope(mut self, scope: RecallScope) -> Self {
        self.scope = scope;
        self
    }
}

impl SearchProvider for FTS5Provider {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
        self.try_query(q, top_k).unwrap_or_default()
    }

    fn try_query(&self, q: &str, top_k: usize) -> anyhow::Result<Vec<SearchHit>> {
        // Over-fetch so ghost hits filtered below cannot crowd out live ones.
        let hits = crate::memory::search_fts_in(&self.db_path, q, top_k * 2 + 5, self.scope.dirs())?;
        Ok(hits.into_iter()
            // The index is rebuilt weekly; a note deleted since then must not
            // surface with a dangling path (t-3510 gate, F2).
            .filter(|h| std::path::Path::new(&h.path).exists())
            // The SQL prefix is lexical; a symlink in scope must also resolve into scope.
            .filter(|h| self.scope.allows(std::path::Path::new(&h.path)))
            .take(top_k)
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
            .collect())
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
        self.try_query(q, top_k).unwrap_or_default()
    }

    fn try_query(&self, q: &str, top_k: usize) -> anyhow::Result<Vec<SearchHit>> {
        let Some(raw) = crate::ruflo::ruflo_memory_search_raw(
            q,
            &self.namespace,
            top_k,
            self.threshold,
            true, // json: true — required for full key names
        ) else {
            anyhow::bail!("ruflo search failed (absent, timed out or exited non-zero)");
        };
        parse_ruflo_hits(&raw, &self.namespace)
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
// Lenient form kept for the parser contract tests; production goes through
// `parse_ruflo_hits`, which reports unparsable output as an error.
#[cfg(test)]
fn parse_ruflo_json(raw: &str, namespace: &str) -> Vec<SearchHit> {
    parse_ruflo_hits(raw, namespace).unwrap_or_default()
}

/// [`parse_ruflo_json`] that keeps "no JSON array" and "malformed JSON" apart from
/// an empty result (t-3535): output without a parsable array is an error.
fn parse_ruflo_hits(raw: &str, namespace: &str) -> anyhow::Result<Vec<SearchHit>> {
    let Some(start) = find_json_array_start(raw) else {
        anyhow::bail!("ruflo output has no JSON array");
    };
    let arr = serde_json::from_str::<Vec<serde_json::Value>>(&raw[start..])
        .map_err(|e| anyhow::anyhow!("ruflo output is not a JSON array: {e}"))?;
    Ok(arr.into_iter()
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
        .collect())
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

/// Parallel-dispatch recall provider: queries a keyword leg (`FTS5Provider`), a
/// semantic leg (in production a knowledge-entry `VectorProvider`; historically
/// `RufloProvider`) and any extra legs added with `with_extra` (the memory-file
/// vector leg, t-3510) simultaneously, then merges results with Reciprocal Rank
/// Fusion (k=20, no dedup — see ADR-058 §5–6). Semantic and extra legs share one
/// absolute deadline.
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
    /// Further ranked lists fused with the two above (t-3510): they share the
    /// semantic leg's deadline and degrade the same way.
    extras: Vec<Arc<dyn SearchProvider>>,
    fts5_deadline: Duration,
    ruflo_deadline: Duration,
}

impl HybridProvider {
    /// Construct with production deadlines (FTS5: 500ms, ruflo: 2s).
    pub fn new(fts5: Arc<dyn SearchProvider>, ruflo: Arc<dyn SearchProvider>) -> Self {
        Self {
            fts5,
            ruflo,
            extras: Vec::new(),
            fts5_deadline: FTS5_DEADLINE,
            ruflo_deadline: RUFLO_DEADLINE,
        }
    }

    /// Add another ranked list to the fusion. A document confirmed by several lists
    /// accumulates RRF score across all of them. Used by recall to rank curated memory
    /// files apart from the much larger knowledge store.
    pub fn with_extra(mut self, provider: Arc<dyn SearchProvider>) -> Self {
        self.extras.push(provider);
        self
    }

    /// Construct with custom deadlines — for testing and configuration.
    pub fn with_deadlines(
        fts5: Arc<dyn SearchProvider>,
        ruflo: Arc<dyn SearchProvider>,
        fts5_deadline: Duration,
        ruflo_deadline: Duration,
    ) -> Self {
        Self { fts5, ruflo, extras: Vec::new(), fts5_deadline, ruflo_deadline }
    }
}

impl HybridProvider {
    /// [`query`](SearchProvider::query) plus each leg's outcome, so a caller can
    /// tell a degraded result (a leg timed out or failed) from a genuine miss
    /// (t-3535). The hits are exactly what `query` returns.
    pub fn query_with_status(&self, q: &str, top_k: usize) -> (Vec<SearchHit>, HybridStatus) {
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

        // Budgets run from dispatch: the clock starts before the first leg spawns.
        let start = Instant::now();

        thread::spawn(move || { let _ = tx_fts5.send(fts5.try_query(&q_fts5, fetch)); });
        thread::spawn(move || { let _ = tx_ruflo.send(ruflo.try_query(&q_ruflo, fetch)); });

        // Extra legs are dispatched with the others and share the semantic budget.
        let extra_rx: Vec<_> = self
            .extras
            .iter()
            .map(|p| {
                let p = Arc::clone(p);
                let q = Arc::clone(&q);
                let (tx, rx) = mpsc::channel();
                thread::spawn(move || { let _ = tx.send(p.try_query(&q, fetch)); });
                rx
            })
            .collect();

        // Ruflo budget starts from dispatch, not from when FTS5 returns.
        // Worst-case wall-clock = RUFLO_DEADLINE.
        let (fts5_results, keyword) = leg_outcome(rx_fts5.recv_timeout(fts5_dl));
        let ruflo_budget = ruflo_dl.saturating_sub(start.elapsed());
        let (ruflo_results, semantic) = leg_outcome(rx_ruflo.recv_timeout(ruflo_budget));

        let mut lists = vec![fts5_results, ruflo_results];
        let mut extras = Vec::with_capacity(extra_rx.len());
        for rx in extra_rx {
            let budget = ruflo_dl.saturating_sub(start.elapsed());
            let (hits, status) = leg_outcome(rx.recv_timeout(budget));
            lists.push(hits);
            extras.push(status);
        }
        (rrf_merge(lists, K, top_k), HybridStatus { keyword, semantic, extras })
    }
}

impl SearchProvider for HybridProvider {
    fn query(&self, q: &str, top_k: usize) -> Vec<SearchHit> {
        self.query_with_status(q, top_k).0
    }
}

/// Map one leg's channel result to its hits and status. A dropped sender (the leg
/// thread panicked) is an error, not a timeout, and returns at once.
fn leg_outcome(
    received: Result<anyhow::Result<Vec<SearchHit>>, RecvTimeoutError>,
) -> (Vec<SearchHit>, LegStatus) {
    match received {
        Ok(Ok(hits)) if hits.is_empty() => (hits, LegStatus::Empty),
        Ok(Ok(hits)) => (hits, LegStatus::Ok),
        Ok(Err(_)) | Err(RecvTimeoutError::Disconnected) => (Vec::new(), LegStatus::Error),
        Err(RecvTimeoutError::Timeout) => (Vec::new(), LegStatus::Timeout),
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
    fn hybrid_extra_provider_adds_its_own_ranked_list() {
        // fts5: [a]   ruflo: [b]   extra: [c, a]
        // c appears only via the extra leg; a is confirmed by fts5 + extra and must lead.
        let fts5  = FixedProvider::fixed(vec![h("a")]);
        let ruflo = FixedProvider::fixed(vec![h("b")]);
        let extra = FixedProvider::fixed(vec![h("c"), h("a")]);
        let hits = HybridProvider::new(fts5, ruflo).with_extra(extra).query("q", 10);
        let keys: Vec<_> = hits
            .iter()
            .map(|x| match &x.doc { DocRef::KnowledgeEntry { key, .. } => key.clone(), _ => String::new() })
            .collect();
        assert_eq!(keys[0], "a", "two-leg confirmation ranks first: {keys:?}");
        assert!(keys.contains(&"c".to_string()), "extra-only doc must appear: {keys:?}");
        assert!(keys.contains(&"b".to_string()));
    }

    #[test]
    fn hybrid_extra_timeout_degrades_to_the_other_legs() {
        let fts5  = FixedProvider::fixed(vec![h("from-fts5")]);
        let ruflo = FixedProvider::fixed(vec![h("from-ruflo")]);
        let extra = FixedProvider::delayed(vec![h("from-extra")], Duration::from_millis(400));
        let hybrid = HybridProvider::with_deadlines(
            fts5, ruflo,
            Duration::from_millis(50),
            Duration::from_millis(100),
        )
        .with_extra(extra);
        let hits = hybrid.query("q", 10);
        assert_eq!(hits.len(), 2, "slow extra leg must be dropped, not awaited: {hits:?}");
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

    // ── Per-leg status (t-3535) ───────────────────────────────────────────────

    struct FailingProvider;
    impl SearchProvider for FailingProvider {
        fn query(&self, _q: &str, _top_k: usize) -> Vec<SearchHit> {
            Vec::new()
        }
        fn try_query(&self, _q: &str, _top_k: usize) -> anyhow::Result<Vec<SearchHit>> {
            anyhow::bail!("backend down")
        }
    }

    struct PanickingProvider;
    impl SearchProvider for PanickingProvider {
        fn query(&self, _q: &str, _top_k: usize) -> Vec<SearchHit> {
            panic!("leg crashed")
        }
    }

    fn keys(hits: &[SearchHit]) -> Vec<String> {
        hits.iter()
            .map(|x| match &x.doc {
                DocRef::KnowledgeEntry { key, .. } => key.clone(),
                DocRef::MemoryFile { slug, .. } => slug.clone(),
            })
            .collect()
    }

    #[test]
    fn hybrid_status_reports_ok_timeout_empty_and_error_per_leg() {
        // Margins are wide so a loaded machine cannot flip a status: instant legs
        // get a full second, the late leg sleeps ten times past its deadline.
        let hybrid = HybridProvider::with_deadlines(
            FixedProvider::fixed(vec![h("a")]),
            FixedProvider::delayed(vec![h("late")], Duration::from_secs(10)),
            Duration::from_secs(2),
            Duration::from_secs(1),
        )
        .with_extra(FixedProvider::fixed(vec![]))
        .with_extra(Arc::new(FailingProvider));

        let (hits, status) = hybrid.query_with_status("q", 10);

        assert_eq!(
            status,
            HybridStatus {
                keyword: LegStatus::Ok,
                semantic: LegStatus::Timeout,
                extras: vec![LegStatus::Empty, LegStatus::Error],
            }
        );
        assert_eq!(keys(&hits), vec!["a"]);
    }

    #[test]
    fn hybrid_status_keyword_timeout_and_semantic_error() {
        let hybrid = HybridProvider::with_deadlines(
            FixedProvider::delayed(vec![h("slow")], Duration::from_secs(10)),
            Arc::new(FailingProvider),
            Duration::from_millis(300),
            Duration::from_secs(2),
        );

        let (hits, status) = hybrid.query_with_status("q", 10);

        assert_eq!(status.keyword, LegStatus::Timeout);
        assert_eq!(status.semantic, LegStatus::Error);
        assert!(status.extras.is_empty());
        assert!(hits.is_empty());
    }

    #[test]
    fn hybrid_status_a_crashed_leg_is_error_not_timeout() {
        // A panicking leg drops its sender: that is a failure, not a slow backend.
        let hybrid = HybridProvider::with_deadlines(
            FixedProvider::fixed(vec![h("a")]),
            Arc::new(PanickingProvider),
            Duration::from_millis(500),
            Duration::from_millis(1500),
        );

        let started = Instant::now();
        let (_hits, status) = hybrid.query_with_status("q", 10);

        assert_eq!(status.semantic, LegStatus::Error);
        assert!(started.elapsed() < Duration::from_millis(1000), "a crash must not wait out the deadline");
    }

    #[test]
    fn hybrid_query_returns_the_same_hits_as_query_with_status() {
        let make = || {
            HybridProvider::new(
                FixedProvider::fixed(vec![h("a"), h("b")]),
                FixedProvider::fixed(vec![h("b"), h("c")]),
            )
        };
        let plain = make().query("q", 10);
        let (with_status, _) = make().query_with_status("q", 10);
        assert_eq!(keys(&plain), keys(&with_status));
    }

    #[test]
    fn fts5_try_query_errors_on_a_missing_index_without_creating_it() {
        let tmp = tempdir().unwrap();
        let db = tmp.path().join("index.db");

        assert!(FTS5Provider::new(db.clone()).try_query("jwt", 5).is_err());
        assert!(!db.exists(), "a status probe must not create an empty index");
    }

    #[test]
    fn fts5_try_query_is_ok_with_hits_and_ok_empty_without() {
        let tmp = tempdir().unwrap();
        let mem = tmp.path().join("memory");
        write_mem(&mem, "pattern_jwt-auth.md", "JWT token validation");
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), mem)], &db).unwrap();
        let fts = FTS5Provider::new(db);

        assert_eq!(fts.try_query("jwt", 5).unwrap().len(), 1);
        assert!(fts.try_query("zzzunmatched", 5).unwrap().is_empty());
    }

    // ── RecallScope (t-3535) ──────────────────────────────────────────────────

    #[test]
    fn recall_scope_project_allows_global_and_current_project_top_level_only() {
        // Real files: `allows` refuses a path it cannot check (t-3542).
        let tmp = tempdir().unwrap();
        let home = tmp.path();
        let scope = RecallScope::project_in(home, Some(std::path::Path::new("/w/my_repo")));
        let mk = |rel: &str| {
            let p = home.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(&p, "x").unwrap();
            p
        };

        assert!(scope.allows(&mk(".claude/memory/pattern_a.md")), "global");
        assert!(scope.allows(&mk(".claude/projects/-w-my-repo/memory/x.md")), "current encoding");
        assert!(scope.allows(&mk(".claude/projects/-w-my_repo/memory/x.md")), "legacy encoding");
        assert!(!scope.allows(&mk(".claude/projects/-w-client/memory/x.md")), "other project");
        assert!(!scope.allows(&mk(".claude/memory/archive/x.md")), "archived subfolder");
        assert!(RecallScope::All.allows(&home.join(".claude/projects/-w-client/memory/x.md")));
    }

    #[test]
    fn recall_scope_without_a_session_root_is_global_only() {
        // Fails closed: an unresolvable project must not widen the scope.
        let scope = RecallScope::project_in(std::path::Path::new("/h"), None);
        assert_eq!(scope, RecallScope::Dirs(vec![PathBuf::from("/h/.claude/memory")]));
    }

    #[test]
    fn fts5_scope_excludes_other_project_rows_before_the_top_k_cut() {
        // Must-fire: twelve stronger other-project hits outrank the one in-scope note.
        // Filtering after the LIMIT (even with over-fetch) would return nothing.
        let tmp = tempdir().unwrap();
        let global = tmp.path().join(".claude/memory");
        let other = tmp.path().join(".claude/projects/-w-client/memory");
        write_mem(&global, "pattern_mine.md", "a long note that mentions jwt once among many other words here");
        for i in 0..12 {
            write_mem(&other, &format!("pattern_client-{i}.md"), "jwt jwt jwt");
        }
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("global".into(), global.clone()), ("project".into(), other)], &db).unwrap();

        let unscoped = FTS5Provider::new(db.clone()).query("jwt", 1);
        let scoped = FTS5Provider::new(db)
            .with_scope(RecallScope::Dirs(vec![global.clone()]))
            .query("jwt", 1);

        assert_ne!(keys(&unscoped), vec!["mine"], "fixture must rank other-project notes first");
        assert_eq!(keys(&scoped), vec!["mine"]);
    }

    #[test]
    fn hybrid_status_reports_ok_and_timeout_for_extra_legs() {
        let hybrid = HybridProvider::with_deadlines(
            FixedProvider::fixed(vec![]),
            FixedProvider::fixed(vec![h("k")]),
            Duration::from_secs(2),
            Duration::from_secs(1),
        )
        .with_extra(FixedProvider::fixed(vec![h("x")]))
        .with_extra(FixedProvider::delayed(vec![h("late")], Duration::from_secs(10)));

        let (hits, status) = hybrid.query_with_status("q", 10);

        assert_eq!(
            status,
            HybridStatus {
                keyword: LegStatus::Empty,
                semantic: LegStatus::Ok,
                extras: vec![LegStatus::Ok, LegStatus::Timeout],
            }
        );
        let mut got = keys(&hits);
        got.sort();
        assert_eq!(got, vec!["k", "x"]);
    }

    #[test]
    fn ruflo_output_without_a_json_array_is_an_error_not_empty() {
        assert!(parse_ruflo_hits("[INFO] embedding model failed to load", "knowledge").is_err());
        assert!(parse_ruflo_hits("[{\"key\": \"broken\"", "knowledge").is_err());
        assert!(parse_ruflo_hits("[INFO] ok\n[]", "knowledge").unwrap().is_empty());
        assert_eq!(parse_ruflo_hits("[{\"key\":\"k\",\"value\":\"v\"}]", "knowledge").unwrap().len(), 1);
    }

    // ── symlinks cannot smuggle an out-of-scope note into scope (t-3537 gate) ───

    #[test]
    fn allows_rejects_a_symlink_into_another_projects_memory() {
        let tmp = tempdir().unwrap();
        let mine = tmp.path().join("mine");
        let client = tmp.path().join("client");
        fs::create_dir_all(&mine).unwrap();
        fs::create_dir_all(&client).unwrap();
        fs::write(client.join("pattern_secret.md"), "client secret").unwrap();
        fs::write(mine.join("pattern_real.md"), "mine").unwrap();
        std::os::unix::fs::symlink(client.join("pattern_secret.md"), mine.join("pattern_link.md")).unwrap();
        std::os::unix::fs::symlink(mine.join("pattern_real.md"), mine.join("pattern_alias.md")).unwrap();
        std::os::unix::fs::symlink(mine.join("gone.md"), mine.join("pattern_dangling.md")).unwrap();
        let scope = RecallScope::Dirs(vec![mine.clone()]);

        assert!(scope.allows(&mine.join("pattern_real.md")));
        assert!(!scope.allows(&mine.join("pattern_link.md")), "resolves into another project");
        assert!(scope.allows(&mine.join("pattern_alias.md")), "resolves to an in-scope note");
        assert!(!scope.allows(&mine.join("pattern_dangling.md")), "cannot be shown to be in scope");
    }

    #[test]
    fn allows_follows_a_scope_folder_that_is_itself_reached_through_a_symlink() {
        let tmp = tempdir().unwrap();
        let real = tmp.path().join("real-mem");
        fs::create_dir_all(&real).unwrap();
        fs::write(real.join("pattern_a.md"), "a").unwrap();
        let via = tmp.path().join("via");
        std::os::unix::fs::symlink(&real, &via).unwrap();
        fs::write(real.join("pattern_target.md"), "t").unwrap();
        std::os::unix::fs::symlink(real.join("pattern_target.md"), real.join("pattern_l.md")).unwrap();
        let scope = RecallScope::Dirs(vec![via.clone()]);

        assert!(scope.allows(&via.join("pattern_l.md")), "link resolves into the same real folder");
    }

    #[test]
    fn allows_refuses_a_path_it_cannot_check_and_anything_that_is_not_a_plain_file() {
        let tmp = tempdir().unwrap();
        let mine = tmp.path().join("mine");
        fs::create_dir_all(&mine).unwrap();
        let scope = RecallScope::Dirs(vec![mine.clone()]);

        // A path whose type cannot be checked is not shown to be in scope (the bundle opens
        // what `allows` passes, so "unknown" must mean no).
        assert!(!scope.allows(&mine.join("pattern_missing.md")), "lstat fails: refuse");

        // A folder named like a note, and a FIFO (opening it blocks forever), are not notes.
        fs::create_dir(mine.join("pattern_folder.md")).unwrap();
        assert!(!scope.allows(&mine.join("pattern_folder.md")), "a directory is not a note");
        let fifo = mine.join("pattern_fifo.md");
        let ok = std::process::Command::new("mkfifo").arg(&fifo).status().map(|s| s.success()).unwrap_or(false);
        if ok {
            assert!(!scope.allows(&fifo), "a FIFO is not a note");
        }

        fs::write(mine.join("pattern_real.md"), "x").unwrap();
        assert!(scope.allows(&mine.join("pattern_real.md")), "a plain note is still allowed");
    }

    #[test]
    fn fts5_scope_excludes_a_symlink_that_resolves_out_of_scope() {
        let tmp = tempdir().unwrap();
        let mine = tmp.path().join("mine");
        let client = tmp.path().join("client");
        write_mem(&client, "pattern_secret.md", "jwt jwt jwt client secret");
        write_mem(&mine, "pattern_real.md", "jwt once");
        std::os::unix::fs::symlink(client.join("pattern_secret.md"), mine.join("pattern_link.md")).unwrap();
        let db = tmp.path().join("index.db");
        reindex_fts_dirs(&[("project".into(), mine.clone())], &db).unwrap();

        let hits = FTS5Provider::new(db).with_scope(RecallScope::Dirs(vec![mine])).query("jwt", 10);

        let slugs: Vec<_> = hits.iter().map(|h| match &h.doc { DocRef::MemoryFile { slug, .. } => slug.clone(), _ => String::new() }).collect();
        assert_eq!(slugs, vec!["real"], "the symlink's target text must not surface: {slugs:?}");
    }
}
