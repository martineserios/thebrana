//! SearchProvider trait — pluggable recall seam (t-2109 / t-2091).
//!
//! Two concrete implementations live here:
//!   - `FTS5Provider`   — keyword recall over the embedded SQLite+FTS5 index
//!   - `RufloProvider`  — semantic/vector recall via the ruflo binary
//!
//! A third impl (`HybridProvider`) dispatches both in parallel and merges
//! results via RRF; it is implemented as a separate step blocked on this one.

use std::path::PathBuf;
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
}
