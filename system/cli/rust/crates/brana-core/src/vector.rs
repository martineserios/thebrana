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

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use rusqlite::{Connection, OpenFlags, params};

use crate::search::{DocRef, SearchHit, SearchProvider};

/// Embedding dimensionality (all-MiniLM-L6-v2).
pub const EMBED_DIM: usize = 384;

/// Canonical store location: `~/.claude/memory/knowledge.db` — brana-owned,
/// deliberately outside `~/.swarm/` and its rotation machinery (t-2615/t-2619).
pub fn knowledge_db_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".claude").join("memory").join("knowledge.db")
}

// ── Store ─────────────────────────────────────────────────────────────────────

/// Enrichment columns added after the original schema (t-3310), as
/// `(name, type)` pairs. Added by ALTER-if-missing on every [`KnowledgeStore::open`].
///
/// All are nullable: `NULL` means "not enriched yet", which is what every row
/// written by `vector-sync` looks like until the scoring pass (t-3311) and the
/// richer extraction (t-3312) fill them in.
const ENRICHMENT_COLUMNS: &[(&str, &str)] = &[
    // JSON `[{"project": "<slug>", "score": <f32>}]` — link-signal relevance.
    ("relevant_projects", "TEXT"),
    // Relevance of the entry to thebrana itself.
    ("for_thebrana", "REAL"),
    // JSON `["<entity>", …]` from the extraction prompt.
    ("entities", "TEXT"),
    // `tool-to-evaluate | technique-to-adopt | read-later | competitor-intel | none`.
    ("action_type", "TEXT"),
];

/// Brana-owned knowledge store at `~/.claude/memory/knowledge.db`.
///
/// Schema: `knowledge(key PRIMARY KEY, content, tags, source, created_at, vec BLOB,
/// relevant_projects, for_thebrana, entities, action_type)`.
/// `vec` is `EMBED_DIM` little-endian `f32`s (1,536 bytes).
///
/// The four enrichment columns are real columns on purpose (ADR-093): never
/// JSON stuffed into `content`, which recall prints verbatim and FTS5 indexes.
pub struct KnowledgeStore {
    db_path: PathBuf,
}

impl KnowledgeStore {
    /// Open the store, creating the file and schema if absent and running the
    /// idempotent enrichment-column migration.
    ///
    /// Holds only the path — connections are opened per operation, matching
    /// `FTS5Provider`'s idiom (`rusqlite::Connection` is `!Send`).
    pub fn open(db_path: impl Into<PathBuf>) -> Result<Self> {
        let db_path = db_path.into();
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("creating {}", parent.display()))?;
        }
        let conn = Connection::open(&db_path)
            .with_context(|| format!("opening {}", db_path.display()))?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS knowledge (
                key        TEXT PRIMARY KEY,
                content    TEXT NOT NULL,
                tags       TEXT,
                source     TEXT,
                created_at INTEGER NOT NULL,
                vec        BLOB NOT NULL
            );",
        )
        .context("creating knowledge schema")?;
        migrate_enrichment_columns(&conn)?;
        Ok(Self { db_path })
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    fn conn(&self) -> Result<Connection> {
        Connection::open(&self.db_path)
            .with_context(|| format!("opening {}", self.db_path.display()))
    }

    /// Insert an entry, or update the synced columns of an existing one.
    /// `vec` must be `EMBED_DIM` long.
    ///
    /// Deliberately `ON CONFLICT DO UPDATE`, not `INSERT OR REPLACE`: replace
    /// deletes the row and reinserts it, which would null out the enrichment
    /// columns on every `vector-sync` run. Sync owns the synced columns only;
    /// enrichment survives untouched.
    pub fn upsert(
        &self,
        key: &str,
        content: &str,
        tags: Option<&str>,
        source: Option<&str>,
        created_at: i64,
        vec: &[f32],
    ) -> Result<()> {
        if vec.len() != EMBED_DIM {
            bail!("vector for {key} has {} dims, expected {EMBED_DIM}", vec.len());
        }
        self.conn()?
            .execute(
                "INSERT INTO knowledge (key, content, tags, source, created_at, vec)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(key) DO UPDATE SET
                     content    = excluded.content,
                     tags       = excluded.tags,
                     source     = excluded.source,
                     created_at = excluded.created_at,
                     vec        = excluded.vec",
                params![key, content, tags, source, created_at, vec_to_blob(vec)],
            )
            .with_context(|| format!("upserting {key}"))?;
        Ok(())
    }

    /// Write the scoring-pass columns for an existing entry (t-3311).
    /// `relevant_projects` is JSON `[{"project", "score"}]`. Unknown keys are
    /// a no-op — the pass scores rows it read from this same store.
    pub fn set_relevance(
        &self,
        key: &str,
        relevant_projects: Option<&str>,
        for_thebrana: Option<f32>,
    ) -> Result<()> {
        self.conn()?
            .execute(
                "UPDATE knowledge SET relevant_projects = ?2, for_thebrana = ?3 WHERE key = ?1",
                params![key, relevant_projects, for_thebrana],
            )
            .with_context(|| format!("setting relevance for {key}"))?;
        Ok(())
    }

    /// Write the extraction columns for an existing entry (t-3312).
    /// `entities` is a JSON array; `action_type` one of the extraction prompt's
    /// enum values.
    pub fn set_extraction(
        &self,
        key: &str,
        entities: Option<&str>,
        action_type: Option<&str>,
    ) -> Result<()> {
        self.conn()?
            .execute(
                "UPDATE knowledge SET entities = ?2, action_type = ?3 WHERE key = ?1",
                params![key, entities, action_type],
            )
            .with_context(|| format!("setting extraction for {key}"))?;
        Ok(())
    }

    /// The enrichment columns of one entry, if it exists.
    pub fn enrichment(&self, key: &str) -> Result<Option<Enrichment>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare(
            "SELECT relevant_projects, for_thebrana, entities, action_type
             FROM knowledge WHERE key = ?1",
        )?;
        let mut rows = stmt.query(params![key])?;
        Ok(match rows.next()? {
            Some(r) => Some(Enrichment {
                relevant_projects: r.get(0)?,
                for_thebrana: r.get(1)?,
                entities: r.get(2)?,
                action_type: r.get(3)?,
            }),
            None => None,
        })
    }

    /// Number of stored entries.
    pub fn count(&self) -> Result<usize> {
        let n: i64 = self
            .conn()?
            .query_row("SELECT COUNT(*) FROM knowledge", [], |r| r.get(0))?;
        Ok(n as usize)
    }
}

/// The enrichment columns of one `knowledge` row, as stored. `None` on a field
/// means that pass has not run for the entry yet.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Enrichment {
    /// JSON `[{"project", "score"}]`, or `None` if unscored.
    pub relevant_projects: Option<String>,
    pub for_thebrana: Option<f32>,
    /// JSON array of entity strings, or `None` if not extracted.
    pub entities: Option<String>,
    pub action_type: Option<String>,
}

/// Add any missing [`ENRICHMENT_COLUMNS`] to an existing `knowledge` table.
///
/// Idempotent by construction: the column set is read from
/// `PRAGMA table_info` first, so a fresh db and an already-migrated one both
/// end up with exactly one copy of each column. SQLite has no
/// `ADD COLUMN IF NOT EXISTS`, hence the pragma.
fn migrate_enrichment_columns(conn: &Connection) -> Result<()> {
    let existing: Vec<String> = {
        let mut stmt = conn
            .prepare("PRAGMA table_info(knowledge)")
            .context("reading knowledge table_info")?;
        let names = stmt.query_map([], |r| r.get::<_, String>(1))?;
        names
            .collect::<rusqlite::Result<Vec<String>>>()
            .context("reading knowledge columns")?
    };
    for (name, ty) in ENRICHMENT_COLUMNS {
        if existing.iter().any(|c| c == name) {
            continue;
        }
        conn.execute_batch(&format!("ALTER TABLE knowledge ADD COLUMN {name} {ty};"))
            .with_context(|| format!("adding knowledge.{name}"))?;
    }
    Ok(())
}

/// Encode a vector as little-endian `f32` bytes.
pub(crate) fn vec_to_blob(v: &[f32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(v.len() * 4);
    for f in v {
        out.extend_from_slice(&f.to_le_bytes());
    }
    out
}

/// Decode a little-endian `f32` BLOB. `None` if the byte length is not a
/// multiple of 4 or the dimensionality is wrong.
pub(crate) fn blob_to_vec(blob: &[u8]) -> Option<Vec<f32>> {
    if blob.len() != EMBED_DIM * 4 {
        return None;
    }
    Some(
        blob.chunks_exact(4)
            .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
            .collect(),
    )
}

// ── Cosine ────────────────────────────────────────────────────────────────────

/// Cosine similarity of two equal-length vectors. Returns 0.0 for zero-norm inputs.
pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let mut dot = 0.0_f32;
    let mut na = 0.0_f32;
    let mut nb = 0.0_f32;
    for (x, y) in a.iter().zip(b.iter()) {
        dot += x * y;
        na += x * x;
        nb += y * y;
    }
    let denom = (na.sqrt()) * (nb.sqrt());
    if denom == 0.0 { 0.0 } else { dot / denom }
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
        if q.trim().is_empty() || top_k == 0 || !self.db_path.exists() {
            return Vec::new();
        }
        let Some(qvec) = self.embedder.embed(q) else {
            return Vec::new();
        };
        if qvec.len() != EMBED_DIM {
            return Vec::new();
        }
        let Ok(conn) = Connection::open_with_flags(
            &self.db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        ) else {
            return Vec::new();
        };
        let Ok(mut stmt) = conn.prepare("SELECT key, content, vec FROM knowledge") else {
            return Vec::new();
        };
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Vec<u8>>(2)?,
            ))
        });
        let Ok(rows) = rows else { return Vec::new() };

        let mut scored: Vec<(f32, String, String)> = rows
            .filter_map(|row| {
                let (key, content, blob) = row.ok()?;
                let v = blob_to_vec(&blob)?;
                let score = cosine(&qvec, &v);
                (score >= self.threshold).then_some((score, key, content))
            })
            .collect();
        scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        scored.truncate(top_k);

        scored
            .into_iter()
            .map(|(score, key, content)| SearchHit {
                doc: DocRef::KnowledgeEntry {
                    key,
                    namespace: "knowledge".to_string(),
                },
                snippet: truncate_chars(&content, 300),
                // Cosine similarity at the provider level — single-provider
                // callers (knowledge search, t-2734) display it directly.
                // HybridProvider overwrites this during RRF merge, so the
                // "0.0 until merged" contract only relaxes, never breaks.
                rrf_score: score as f64,
            })
            .collect()
    }
}

/// Truncate at a char boundary, appending `…` when shortened.
pub(crate) fn truncate_chars(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let mut out: String = s.chars().take(max).collect();
    out.push('…');
    out
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
///
/// Re-runnable: for keys already in the destination this updates the synced
/// columns in place, so enrichment written by later passes ([`Enrichment`])
/// survives every sync.
pub fn migrate_from_memory_entries(sources: &[PathBuf], dest: &Path) -> Result<MigrateStats> {
    struct Candidate {
        content: String,
        tags: Option<String>,
        created_at: i64,
        updated_at: i64,
        vec: Vec<f32>,
    }

    let mut stats = MigrateStats::default();
    let mut best: HashMap<String, Candidate> = HashMap::new();

    for src in sources {
        let conn = Connection::open_with_flags(
            src,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .with_context(|| format!("opening source {}", src.display()))?;
        let mut stmt = conn
            .prepare(
                "SELECT key, content, embedding, tags, created_at, updated_at
                 FROM memory_entries WHERE namespace = 'knowledge'",
            )
            .with_context(|| format!("querying memory_entries in {}", src.display()))?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, Option<String>>(3)?,
                r.get::<_, i64>(4)?,
                r.get::<_, i64>(5)?,
            ))
        })?;

        for row in rows {
            let (key, content, embedding, tags, created_at, updated_at) = row?;
            stats.scanned += 1;
            let vec = embedding
                .as_deref()
                .and_then(|e| serde_json::from_str::<Vec<f32>>(e).ok())
                .filter(|v| v.len() == EMBED_DIM);
            let Some(vec) = vec else {
                stats.skipped_no_embedding += 1;
                continue;
            };
            let cand = Candidate { content, tags, created_at, updated_at, vec };
            match best.entry(key) {
                std::collections::hash_map::Entry::Vacant(e) => {
                    e.insert(cand);
                }
                std::collections::hash_map::Entry::Occupied(mut e) => {
                    stats.deduped += 1;
                    if cand.updated_at > e.get().updated_at {
                        e.insert(cand);
                    }
                }
            }
        }
    }

    let store = KnowledgeStore::open(dest)?;
    for (key, c) in &best {
        store.upsert(key, &c.content, c.tags.as_deref(), Some("memory_entries"), c.created_at, &c.vec)?;
        stats.migrated += 1;
    }
    Ok(stats)
}

/// Cheap readability probe: can `path` be opened and its `memory_entries`
/// table stepped? Used by `vector-sync` to skip unreadable/corrupt sources
/// with a warning instead of failing the whole batch.
pub fn probe_memory_entries(path: &Path) -> bool {
    let Ok(conn) = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    ) else {
        return false;
    };
    conn.query_row("SELECT COUNT(*) FROM memory_entries WHERE namespace='knowledge'", [], |r| {
        r.get::<_, i64>(0)
    })
    .is_ok()
}

// ── Production embedder ───────────────────────────────────────────────────────

/// Query-text embedding via `ruflo embeddings generate -t <q> -o json` — the
/// one ruflo layer the spec keeps (ONNX all-MiniLM-L6-v2, 384d). Fails open:
/// any resolution/spawn/parse failure returns `None`.
pub struct RufloEmbedder;

impl Embedder for RufloEmbedder {
    fn embed(&self, text: &str) -> Option<Vec<f32>> {
        let bin = crate::ruflo::resolve_ruflo_binary()?;
        let out = std::process::Command::new(bin)
            .args(["embeddings", "generate", "-t", text, "-o", "json"])
            .output()
            .ok()?;
        let stdout = String::from_utf8_lossy(&out.stdout);
        // Node preamble may precede the JSON object — scan for the first '{'.
        let start = stdout.find('{')?;
        let v: serde_json::Value = serde_json::from_str(stdout[start..].trim()).ok()?;
        let emb = v.get("embedding")?.as_array()?;
        let vec: Vec<f32> = emb.iter().filter_map(|x| x.as_f64().map(|f| f as f32)).collect();
        (vec.len() == EMBED_DIM).then_some(vec)
    }
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

    // ── enrichment migration (t-3310) ─────────────────────────────────────────

    /// Column names of the `knowledge` table, in declaration order.
    fn knowledge_columns(db: &Path) -> Vec<String> {
        let conn = rusqlite::Connection::open(db).unwrap();
        let mut stmt = conn.prepare("PRAGMA table_info(knowledge)").unwrap();
        let cols = stmt.query_map([], |r| r.get::<_, String>(1)).unwrap();
        cols.map(|c| c.unwrap()).collect()
    }

    #[test]
    fn migration_adds_enrichment_columns_to_a_fresh_db() {
        let tmp = tempdir().unwrap();
        let db = tmp.path().join("knowledge.db");
        KnowledgeStore::open(&db).unwrap();

        let cols = knowledge_columns(&db);
        for (name, _) in ENRICHMENT_COLUMNS {
            assert!(cols.iter().any(|c| c == name), "missing column {name} in {cols:?}");
        }
    }

    #[test]
    fn migration_is_idempotent_on_an_already_migrated_db() {
        let tmp = tempdir().unwrap();
        let db = tmp.path().join("knowledge.db");
        KnowledgeStore::open(&db).unwrap();
        let first = knowledge_columns(&db);

        // Re-open twice more — ALTER-if-missing must not duplicate or fail.
        KnowledgeStore::open(&db).unwrap();
        let store = KnowledgeStore::open(&db).unwrap();
        assert_eq!(knowledge_columns(&db), first, "re-open must not change the column set");

        // And the store still works after the no-op migration.
        store.upsert("knowledge:url:a", "content", None, None, 1, &unit(0)).unwrap();
        assert_eq!(store.count().unwrap(), 1);
    }

    #[test]
    fn migration_upgrades_a_pre_migration_db_in_place() {
        let tmp = tempdir().unwrap();
        let db = tmp.path().join("knowledge.db");
        // The original schema, exactly as shipped before t-3310.
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute_batch(
            "CREATE TABLE knowledge (
                key        TEXT PRIMARY KEY,
                content    TEXT NOT NULL,
                tags       TEXT,
                source     TEXT,
                created_at INTEGER NOT NULL,
                vec        BLOB NOT NULL
            );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO knowledge (key, content, tags, source, created_at, vec)
             VALUES ('knowledge:url:old', 'legacy row', NULL, 'url', 7, ?1)",
            rusqlite::params![vec_to_blob(&unit(0))],
        )
        .unwrap();
        drop(conn);

        let store = KnowledgeStore::open(&db).unwrap();
        for (name, _) in ENRICHMENT_COLUMNS {
            assert!(knowledge_columns(&db).iter().any(|c| c == name), "missing {name}");
        }
        // The pre-existing row survives, unenriched.
        assert_eq!(store.count().unwrap(), 1);
        assert_eq!(
            store.enrichment("knowledge:url:old").unwrap(),
            Some(Enrichment::default()),
            "an unenriched legacy row reads back as all-NULL"
        );
    }

    #[test]
    fn enrichment_writes_read_back_and_unknown_key_is_none() {
        let tmp = tempdir().unwrap();
        let store = KnowledgeStore::open(tmp.path().join("knowledge.db")).unwrap();
        store.upsert("knowledge:url:a", "content", None, Some("link-capture"), 1, &unit(0)).unwrap();

        store
            .set_relevance("knowledge:url:a", Some(r#"[{"project":"truper","score":0.71}]"#), Some(0.42))
            .unwrap();
        store
            .set_extraction("knowledge:url:a", Some(r#"["Scrapy"]"#), Some("tool-to-evaluate"))
            .unwrap();

        let e = store.enrichment("knowledge:url:a").unwrap().unwrap();
        assert_eq!(e.relevant_projects.as_deref(), Some(r#"[{"project":"truper","score":0.71}]"#));
        assert_eq!(e.for_thebrana, Some(0.42));
        assert_eq!(e.entities.as_deref(), Some(r#"["Scrapy"]"#));
        assert_eq!(e.action_type.as_deref(), Some("tool-to-evaluate"));

        assert_eq!(store.enrichment("knowledge:url:missing").unwrap(), None);
    }

    #[test]
    fn upsert_preserves_enrichment_and_updates_synced_columns() {
        let tmp = tempdir().unwrap();
        let store = KnowledgeStore::open(tmp.path().join("knowledge.db")).unwrap();
        store.upsert("knowledge:url:a", "first", None, Some("url"), 1, &unit(0)).unwrap();
        store.set_relevance("knowledge:url:a", Some("[]"), Some(0.9)).unwrap();
        store.set_extraction("knowledge:url:a", Some(r#"["a"]"#), Some("read-later")).unwrap();

        // A later sync of the same key rewrites content/tags/source/vec …
        store.upsert("knowledge:url:a", "second", Some("t"), Some("url"), 2, &unit(1)).unwrap();
        assert_eq!(store.count().unwrap(), 1);

        // … and leaves the enrichment columns alone.
        let e = store.enrichment("knowledge:url:a").unwrap().unwrap();
        assert_eq!(e.relevant_projects.as_deref(), Some("[]"));
        assert_eq!(e.for_thebrana, Some(0.9));
        assert_eq!(e.entities.as_deref(), Some(r#"["a"]"#));
        assert_eq!(e.action_type.as_deref(), Some("read-later"));
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
    fn sync_round_trip_keeps_the_enrichment_columns() {
        let tmp = tempdir().unwrap();
        let src = tmp.path().join("live.db");
        let dest = tmp.path().join("knowledge.db");
        fake_memory_entries(&src, &[("knowledge:url:a", "content a", Some(unit(0)), 100)]);

        // First sync, then a scoring/extraction pass writes the new columns.
        migrate_from_memory_entries(std::slice::from_ref(&src), &dest).unwrap();
        let store = KnowledgeStore::open(&dest).unwrap();
        store
            .set_relevance("knowledge:url:a", Some(r#"[{"project":"truper","score":0.6}]"#), Some(0.31))
            .unwrap();
        store
            .set_extraction("knowledge:url:a", Some(r#"["Scrapy"]"#), Some("technique-to-adopt"))
            .unwrap();

        // A later sync sees a newer version of the same row.
        fake_memory_entries(
            &tmp.path().join("live2.db"),
            &[("knowledge:url:a", "NEWER content a", Some(unit(0)), 200)],
        );
        let stats =
            migrate_from_memory_entries(&[tmp.path().join("live2.db")], &dest).unwrap();
        assert_eq!(stats.migrated, 1);

        // Newest row won on the synced columns …
        let provider = VectorProvider::new(&dest, Arc::new(FakeEmbedder));
        let hits = provider.query("rust web scraping", 1);
        assert_eq!(hits.len(), 1);
        assert!(hits[0].snippet.contains("NEWER"), "newest row must win: {}", hits[0].snippet);

        // … and the enrichment columns were not dropped by the upsert.
        let e = store.enrichment("knowledge:url:a").unwrap().unwrap();
        assert_eq!(e.relevant_projects.as_deref(), Some(r#"[{"project":"truper","score":0.6}]"#));
        assert_eq!(e.for_thebrana, Some(0.31));
        assert_eq!(e.entities.as_deref(), Some(r#"["Scrapy"]"#));
        assert_eq!(e.action_type.as_deref(), Some("technique-to-adopt"));
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
