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
    /// columns on every `vector-sync` run. This call owns the synced columns
    /// only; enrichment survives untouched. (Sync itself additionally lifts
    /// the extraction tags an ingest write carried — see
    /// [`extraction_from_tags`] — but never through this method.)
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
    /// enum values. Called by sync for rows whose tags carry the fields
    /// ([`extraction_from_tags`]).
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

    /// Every row `filter` selects, with its vector decoded — the bulk read the
    /// post-sync scoring pass runs on (t-3311).
    ///
    /// Read-only and lock-free by construction: the pass runs inside
    /// `vector-sync`, which must never contend with the whole-invocation
    /// `lock_pipeline()` the 4h drain cron holds (ADR-093 D2).
    ///
    /// Rows whose BLOB does not decode to `EMBED_DIM` floats are skipped
    /// rather than failing the read — one unreadable row must not cost a
    /// whole pass. Key-ordered, so a capped consumer slices the same rows in
    /// the same order every run.
    pub fn rows_with_vec(&self, filter: RowFilter) -> Result<Vec<KnowledgeRow>> {
        let conn = Connection::open_with_flags(
            &self.db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .with_context(|| format!("opening {}", self.db_path.display()))?;
        let mut stmt = conn
            .prepare("SELECT key, tags, source, vec FROM knowledge ORDER BY key")
            .context("preparing knowledge row scan")?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, Option<String>>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, Vec<u8>>(3)?,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (key, tags, source, blob) = row?;
            if !filter.selects(tags.as_deref(), source.as_deref()) {
                continue;
            }
            let Some(vec) = blob_to_vec(&blob) else { continue };
            out.push(KnowledgeRow { key, tags, source, vec });
        }
        Ok(out)
    }

    /// Every scored row whose relevance to `target` is at or above
    /// `min_score`, best score first (t-3313).
    ///
    /// `target` is a portfolio slug read out of `relevant_projects`, or
    /// [`crate::project_vectors::THEBRANA_SLUG`], which reads the separate
    /// `for_thebrana` column — thebrana is scored by plain cosine and never
    /// appears in `relevant_projects` (ADR-093 D2).
    ///
    /// Read-only and lock-free, like [`Self::rows_with_vec`]: this is a
    /// listing over what the pass already committed, so it never re-scores,
    /// never embeds and never writes. Rows the pass has not reached
    /// (`relevant_projects IS NULL`) simply do not appear.
    ///
    /// Ties break on `key` so two runs over an unchanged store print the same
    /// order.
    pub fn rows_relevant_to(&self, target: &str, min_score: f32) -> Result<Vec<RelevantRow>> {
        let for_thebrana = target == crate::project_vectors::THEBRANA_SLUG;
        let conn = Connection::open_with_flags(
            &self.db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .with_context(|| format!("opening {}", self.db_path.display()))?;
        let mut stmt = conn
            .prepare(
                "SELECT key, content, created_at, action_type, relevant_projects, for_thebrana
                 FROM knowledge",
            )
            .context("preparing relevance listing scan")?;
        let rows = stmt.query_map([], |r| {
            Ok(RelevantRowRaw {
                key: r.get(0)?,
                content: r.get(1)?,
                created_at: r.get(2)?,
                action_type: r.get(3)?,
                relevant_projects: r.get(4)?,
                for_thebrana: r.get(5)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            let row = row?;
            let score = if for_thebrana {
                row.for_thebrana
            } else {
                row.relevant_projects.as_deref().and_then(|j| project_score(j, target))
            };
            let Some(score) = score.filter(|s| *s >= min_score) else { continue };
            out.push(RelevantRow {
                key: row.key,
                score,
                action_type: row.action_type,
                content: row.content,
                created_at: row.created_at,
            });
        }
        out.sort_by(|a, b| b.score.total_cmp(&a.score).then_with(|| a.key.cmp(&b.key)));
        Ok(out)
    }

    /// Number of stored entries.
    pub fn count(&self) -> Result<usize> {
        let n: i64 = self
            .conn()?
            .query_row("SELECT COUNT(*) FROM knowledge", [], |r| r.get(0))?;
        Ok(n as usize)
    }
}

/// One `knowledge` row as [`KnowledgeStore::rows_with_vec`] returns it.
#[derive(Debug, Clone, PartialEq)]
pub struct KnowledgeRow {
    pub key: String,
    /// The stored tags field, verbatim — parse with [`parse_tags`].
    pub tags: Option<String>,
    pub source: Option<String>,
    pub vec: Vec<f32>,
}

/// One scored row as [`KnowledgeStore::rows_relevant_to`] returns it.
#[derive(Debug, Clone, PartialEq)]
pub struct RelevantRow {
    pub key: String,
    /// The stored relevance of this row to the queried target.
    pub score: f32,
    /// `tool-to-evaluate | technique-to-adopt | …`, or `None` if the
    /// extraction pass never reached the row.
    pub action_type: Option<String>,
    /// The stored `content` — the extracted summary for a link capture, the
    /// transcript for a YouTube one. Callers snippet it.
    pub content: String,
    /// Unix epoch seconds.
    pub created_at: i64,
}

impl RelevantRow {
    /// The score at the precision it should be *reported* at — four decimals,
    /// matching what `run_relevance_pass` stores.
    ///
    /// JSON needs this: `serde_json::Value` has no `f32`, so an unrounded
    /// widening renders 0.31 as 0.3100000023841858. Comparisons stay on the
    /// `f32` in [`Self::score`]; this is the display gauge only.
    pub fn score_rounded(&self) -> f64 {
        round_reported_score(self.score)
    }
}

/// Four-decimal gauge for a reported cosine score. See
/// [`RelevantRow::score_rounded`].
pub fn round_reported_score(score: f32) -> f64 {
    (score as f64 * 10_000.0).round() / 10_000.0
}

/// The columns one listing row is assembled from, before the target's score is
/// resolved out of them.
struct RelevantRowRaw {
    key: String,
    content: String,
    created_at: i64,
    action_type: Option<String>,
    relevant_projects: Option<String>,
    for_thebrana: Option<f32>,
}

/// The score a `relevant_projects` JSON blob records for `project`, if any.
///
/// Malformed JSON yields `None` rather than an error: the listing must stay
/// readable over a store one bad row got into, and a row with no parseable
/// score has no place in a score-ordered list anyway.
pub fn project_score(relevant_projects: &str, project: &str) -> Option<f32> {
    let parsed: serde_json::Value = serde_json::from_str(relevant_projects).ok()?;
    for entry in parsed.as_array()? {
        if entry.get("project").and_then(|p| p.as_str()) == Some(project) {
            return entry.get("score").and_then(|s| s.as_f64()).map(|s| s as f32);
        }
    }
    None
}

/// Which rows a bulk read selects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowFilter {
    /// Every row with a decodable vector.
    All,
    /// Link captures and intelligence-feed items only — never thebrana's own
    /// indexed doc chunks, which are ~2,800 of the store's rows and have no
    /// project to be "relevant to" (ADR-093 D2 read path).
    LinkAndFeed,
}

impl RowFilter {
    pub fn selects(self, tags: Option<&str>, source: Option<&str>) -> bool {
        match self {
            RowFilter::All => true,
            RowFilter::LinkAndFeed => is_link_or_feed_row(tags, source),
        }
    }
}

/// Platform tags a link capture carries, as `process-url` writes them
/// (`resolve_store_value`) and as the ~300 historical captures that predate
/// the explicit marker carry them. `other` — `classify_platform`'s catch-all —
/// is deliberately absent: matching it would sweep in rows that are not link
/// captures at all.
pub const LINK_PLATFORM_TAGS: &[&str] =
    &["linkedin", "github", "youtube", "substack", "arxiv", "twitter"];

/// Explicit capture-source markers, matched with or without a `source:`
/// prefix: the one `process-url` writes going forward (t-3312) and the one
/// `feed-ruflo-index.sh` already writes on every feed item.
pub const LINK_SOURCE_MARKERS: &[&str] = &["link-capture", "intelligence-feed"];

/// Is this row a link capture or an intelligence-feed item?
///
/// Decided on tags first, because `vector-sync` stamps every migrated row's
/// `source` as `memory_entries` — the discriminating marker lives in the tags
/// CSV it copies across. A caller that does write a real `source`
/// (`link-capture`) is honoured too rather than silently excluded.
pub fn is_link_or_feed_row(tags: Option<&str>, source: Option<&str>) -> bool {
    let mut tokens = parse_tags(tags.unwrap_or(""));
    tokens.extend(parse_tags(source.unwrap_or("")));
    tokens.iter().any(|token| {
        let t = token.as_str();
        let t = t.strip_prefix("source:").unwrap_or(t);
        LINK_PLATFORM_TAGS.contains(&t) || LINK_SOURCE_MARKERS.contains(&t)
    })
}

/// Split a stored tags field into tokens.
///
/// ruflo stores the `--tags` CSV verbatim on the `memory store` path, while
/// the feed indexer writes a JSON array (`["type:feed", …]`), so both shapes
/// are accepted. Anything else degrades to a CSV split rather than yielding
/// nothing — an unparseable tags field must not silently drop a row out of
/// the scoring population.
pub fn parse_tags(raw: &str) -> Vec<String> {
    let trimmed = raw.trim();
    if trimmed.starts_with('[')
        && let Ok(parsed) = serde_json::from_str::<Vec<String>>(trimmed)
    {
        return parsed.into_iter().map(|t| t.trim().to_string()).filter(|t| !t.is_empty()).collect();
    }
    trimmed.split(',').map(|t| t.trim().to_string()).filter(|t| !t.is_empty()).collect()
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
///
/// One exception, and it is not a later pass: rows whose tags carry the
/// t-3312 extraction fields get those lifted into the `entities` /
/// `action_type` columns here ([`extraction_from_tags`]) — the ingest pump
/// derived them but had no row to write them to. Idempotent: the same tags
/// lift to the same columns on every run.
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
        if let Some(x) = extraction_from_tags(c.tags.as_deref()) {
            store.set_extraction(key, x.entities.as_deref(), x.action_type.as_deref())?;
        }
        stats.migrated += 1;
    }
    Ok(stats)
}

/// Tag prefixes the extraction fields travel under, from the ingest write
/// (`commands/knowledge.rs::extraction_tags`) to the lift below. Public so
/// the writer and the reader share one definition of the protocol rather than
/// two literals that can drift apart.
pub const ACTION_TAG_PREFIX: &str = "action:";
pub const ENTITY_TAG_PREFIX: &str = "entity:";

/// Split a stored tag list into tags, accepting either encoding: the CSV the
/// store call hands ruflo on the command line, or a JSON array if ruflo
/// persisted it that way. Which one lands in the `tags` column is ruflo's
/// business, and a wrong guess here would silently lift nothing.
fn tag_list(tags: &str) -> Vec<String> {
    if let Ok(parsed) = serde_json::from_str::<Vec<String>>(tags) {
        return parsed.into_iter().map(|t| t.trim().to_string()).collect();
    }
    tags.split(',').map(|t| t.trim().to_string()).collect()
}

/// The extraction fields a synced row carried on its tags, in column shape.
#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct TaggedExtraction {
    /// JSON array of entity strings.
    pub entities: Option<String>,
    pub action_type: Option<String>,
}

/// Read the t-3312 extraction tags off a synced row's stored tag list.
///
/// The ruflo row is the queue between the ingest pump and this one: ingest
/// runs the LLM call but has no `knowledge.db` row to write to yet (the row is
/// created here, up to 20 minutes later), so the fields travel as tags and are
/// lifted into the columns on the sync that first commits the row.
///
/// `None` when the row carries neither tag — a row that was never extracted
/// (every pre-t-3312 capture, every YouTube/LongForm row, every feed item)
/// must leave the columns as they are rather than have them written NULL.
pub(crate) fn extraction_from_tags(tags: Option<&str>) -> Option<TaggedExtraction> {
    let tags = tag_list(tags?);
    let mut action_type = None;
    let mut entities: Vec<String> = Vec::new();
    for tag in tags.iter().map(String::as_str) {
        if let Some(a) = tag.strip_prefix(ACTION_TAG_PREFIX) {
            // First wins — a row carrying two action tags is malformed, and
            // picking one deterministically beats letting the last write win.
            if action_type.is_none() {
                action_type = Some(a.to_string());
            }
        } else if let Some(e) = tag.strip_prefix(ENTITY_TAG_PREFIX) {
            if !e.is_empty() {
                entities.push(e.to_string());
            }
        }
    }
    if action_type.is_none() && entities.is_empty() {
        return None;
    }
    // An extracted row with no entities stores `[]`, not NULL: the extraction
    // ran and found none, which is not the same as never having run.
    Some(TaggedExtraction {
        entities: Some(serde_json::to_string(&entities).unwrap_or_else(|_| "[]".to_string())),
        action_type,
    })
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

    // ── relevance listing (t-3313) ────────────────────────────────────────────

    #[test]
    fn project_score_reads_the_named_project_only() {
        let json = r#"[{"project":"eyedetect","score":0.31},{"project":"crea","score":0.27}]"#;
        assert_eq!(project_score(json, "eyedetect"), Some(0.31));
        assert_eq!(project_score(json, "crea"), Some(0.27));
        assert_eq!(project_score(json, "unlock"), None);
        // A row the pass scored against nothing, and one it never reached.
        assert_eq!(project_score("[]", "crea"), None);
        assert_eq!(project_score("not json", "crea"), None);
    }

    /// A store with three scored rows plus one the pass never reached.
    fn relevance_listing_fixture(db: &Path) -> KnowledgeStore {
        let store = KnowledgeStore::open(db).unwrap();
        let rows = [
            ("knowledge:url:hi", "high scorer", 1_700_000_000_i64, "crea", 0.31_f32, Some("tool-to-evaluate")),
            ("knowledge:url:lo", "low scorer", 1_700_086_400_i64, "crea", 0.26_f32, None),
            ("knowledge:url:other", "other client", 1_700_172_800_i64, "eyedetect", 0.40_f32, Some("read-later")),
        ];
        for (key, content, created, project, score, action) in rows {
            store.upsert(key, content, None, Some("link-capture"), created, &unit(0)).unwrap();
            let json = format!(r#"[{{"project":"{project}","score":{score}}}]"#);
            // thebrana's score is the same on every row, so ordering there is
            // decided by the key tie-break alone.
            store.set_relevance(key, Some(&json), Some(0.33)).unwrap();
            store.set_extraction(key, None, action).unwrap();
        }
        store.upsert("knowledge:url:unscored", "never scored", None, Some("link-capture"), 5, &unit(1)).unwrap();
        store
    }

    #[test]
    fn relevant_rows_are_filtered_by_project_and_sorted_by_score() {
        let tmp = tempdir().unwrap();
        let store = relevance_listing_fixture(&tmp.path().join("knowledge.db"));

        let rows = store.rows_relevant_to("crea", 0.0).unwrap();
        assert_eq!(
            rows.iter().map(|r| r.key.as_str()).collect::<Vec<_>>(),
            vec!["knowledge:url:hi", "knowledge:url:lo"],
            "another client's rows and the unscored row must not appear"
        );
        assert_eq!(rows[0].score, 0.31);
        assert_eq!(rows[0].action_type.as_deref(), Some("tool-to-evaluate"));
        assert_eq!(rows[0].content, "high scorer");
        assert_eq!(rows[0].created_at, 1_700_000_000);
        assert_eq!(rows[1].action_type, None, "an unextracted row still lists");
    }

    #[test]
    fn relevant_min_score_is_inclusive_and_narrows() {
        let tmp = tempdir().unwrap();
        let store = relevance_listing_fixture(&tmp.path().join("knowledge.db"));

        // Inclusive, matching the scoring pass's own `>= threshold`.
        assert_eq!(store.rows_relevant_to("crea", 0.31).unwrap().len(), 1);
        assert_eq!(store.rows_relevant_to("crea", 0.26).unwrap().len(), 2);
        // The spec's provisional 0.5 floor sits above this embedder's ceiling.
        assert!(store.rows_relevant_to("crea", 0.5).unwrap().is_empty());
        // An unregistered slug has no vector and therefore no scored rows.
        assert!(store.rows_relevant_to("lexia", 0.0).unwrap().is_empty());
    }

    #[test]
    fn relevant_thebrana_reads_its_own_column_and_ties_break_on_key() {
        let tmp = tempdir().unwrap();
        let store = relevance_listing_fixture(&tmp.path().join("knowledge.db"));

        let rows = store.rows_relevant_to(crate::project_vectors::THEBRANA_SLUG, 0.0).unwrap();
        assert_eq!(
            rows.iter().map(|r| r.key.as_str()).collect::<Vec<_>>(),
            vec!["knowledge:url:hi", "knowledge:url:lo", "knowledge:url:other"],
            "for_thebrana spans every scored row, and equal scores sort by key"
        );
        assert!(rows.iter().all(|r| r.score == 0.33));
        assert!(store.rows_relevant_to("thebrana", 0.4).unwrap().is_empty());
    }

    // ── bulk read / row filter (t-3311) ───────────────────────────────────────

    #[test]
    fn parse_tags_accepts_csv_json_and_junk() {
        assert_eq!(parse_tags("linkedin,agents"), vec!["linkedin", "agents"]);
        assert_eq!(parse_tags(" linkedin , agents "), vec!["linkedin", "agents"]);
        // The feed indexer writes a JSON array, `memory store` writes a CSV.
        assert_eq!(
            parse_tags(r#"["type:feed","feed:simon","source:intelligence-feed"]"#),
            vec!["type:feed", "feed:simon", "source:intelligence-feed"]
        );
        assert!(parse_tags("").is_empty());
        assert!(parse_tags("  ").is_empty());
        // Unparseable JSON degrades to a CSV split rather than dropping the row.
        assert_eq!(parse_tags("[not json"), vec!["[not json"]);
    }

    #[test]
    fn row_filter_selects_link_and_feed_rows_only() {
        // Historical captures carry a bare platform tag …
        assert!(is_link_or_feed_row(Some("linkedin,agents"), Some("memory_entries")));
        assert!(is_link_or_feed_row(Some("youtube,transcript,auto"), Some("memory_entries")));
        // … new ones carry the explicit marker (t-3312) …
        assert!(is_link_or_feed_row(Some("source:link-capture,scraping"), Some("memory_entries")));
        // … and feed items carry theirs, as a JSON array.
        assert!(is_link_or_feed_row(
            Some(r#"["type:feed","feed:simon","source:intelligence-feed"]"#),
            Some("memory_entries")
        ));
        // A real `source` column is honoured too.
        assert!(is_link_or_feed_row(None, Some("link-capture")));

        // thebrana's own indexed doc chunks are the population this excludes.
        assert!(!is_link_or_feed_row(Some("doc,architecture"), Some("memory_entries")));
        assert!(!is_link_or_feed_row(None, None));
        assert!(!is_link_or_feed_row(Some(""), Some("memory_entries")));
        // `other` is classify_platform's catch-all, not a capture marker.
        assert!(!is_link_or_feed_row(Some("other,notes"), Some("memory_entries")));
    }

    #[test]
    fn rows_with_vec_returns_only_the_scorable_population() {
        let tmp = tempdir().unwrap();
        let store = KnowledgeStore::open(tmp.path().join("knowledge.db")).unwrap();
        store
            .upsert("knowledge:url:link", "a capture", Some("linkedin,agents"), Some("memory_entries"), 1, &unit(0))
            .unwrap();
        store
            .upsert(
                "knowledge:feed:item",
                "a feed item",
                Some(r#"["type:feed","source:intelligence-feed"]"#),
                Some("memory_entries"),
                2,
                &unit(1),
            )
            .unwrap();
        store
            .upsert("knowledge:doc:chunk", "a doc chunk", Some("doc,architecture"), Some("memory_entries"), 3, &unit(2))
            .unwrap();

        let all = store.rows_with_vec(RowFilter::All).unwrap();
        assert_eq!(all.len(), 3);

        let scorable = store.rows_with_vec(RowFilter::LinkAndFeed).unwrap();
        let keys: Vec<&str> = scorable.iter().map(|r| r.key.as_str()).collect();
        assert_eq!(keys, vec!["knowledge:feed:item", "knowledge:url:link"], "key-ordered");
        assert_eq!(scorable[0].vec.len(), EMBED_DIM, "the vector is decoded, not raw bytes");
    }

    #[test]
    fn rows_with_vec_skips_an_undecodable_blob_instead_of_failing() {
        let tmp = tempdir().unwrap();
        let db = tmp.path().join("knowledge.db");
        let store = KnowledgeStore::open(&db).unwrap();
        store
            .upsert("knowledge:url:good", "ok", Some("github"), Some("memory_entries"), 1, &unit(0))
            .unwrap();

        // A truncated BLOB — one bad row must not cost the whole pass.
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute(
            "INSERT INTO knowledge (key, content, tags, source, created_at, vec)
             VALUES ('knowledge:url:bad', 'c', 'github', 'memory_entries', 2, ?1)",
            rusqlite::params![vec![0u8; 8]],
        )
        .unwrap();
        drop(conn);

        let rows = store.rows_with_vec(RowFilter::LinkAndFeed).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].key, "knowledge:url:good");
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

    // ── t-3312: extraction tags lifted into the columns by sync ───────────

    /// Set the `tags` CSV on an already-inserted fake row.
    fn tag_row(path: &Path, key: &str, tags: &str) {
        rusqlite::Connection::open(path)
            .unwrap()
            .execute("UPDATE memory_entries SET tags = ?2 WHERE key = ?1", rusqlite::params![key, tags])
            .unwrap();
    }

    #[test]
    fn extraction_from_tags_reads_action_and_entities() {
        let x = extraction_from_tags(Some(
            "github,scraping,source:link-capture,action:tool-to-evaluate,entity:Scrapy,entity:Python",
        ))
        .expect("tags carry the fields");
        assert_eq!(x.action_type.as_deref(), Some("tool-to-evaluate"));
        assert_eq!(x.entities.as_deref(), Some(r#"["Scrapy","Python"]"#));
    }

    #[test]
    fn extraction_from_tags_reads_a_json_array_tag_column_too() {
        // The store call passes CSV, but the `tags` column belongs to ruflo —
        // a JSON-array encoding must lift the same fields, not silently none.
        let x = extraction_from_tags(Some(r#"["github","action:read-later","entity:Scrapy"]"#))
            .expect("json-encoded tags carry the fields");
        assert_eq!(x.action_type.as_deref(), Some("read-later"));
        assert_eq!(x.entities.as_deref(), Some(r#"["Scrapy"]"#));
    }

    #[test]
    fn extraction_from_tags_action_only_stores_empty_entity_array() {
        // "extraction ran, found no entities" is not the same state as
        // "never extracted", so this is `[]`, not NULL.
        let x = extraction_from_tags(Some("linkedin,action:none")).expect("action tag alone counts");
        assert_eq!(x.entities.as_deref(), Some("[]"));
        assert_eq!(x.action_type.as_deref(), Some("none"));
    }

    #[test]
    fn extraction_from_tags_none_when_row_was_never_extracted() {
        assert_eq!(extraction_from_tags(None), None);
        assert_eq!(extraction_from_tags(Some("")), None);
        assert_eq!(extraction_from_tags(Some("youtube,transcript,source:link-capture")), None);
    }

    #[test]
    fn migrate_lifts_extraction_tags_into_columns() {
        let tmp = tempdir().unwrap();
        let src = tmp.path().join("live.db");
        let dest = tmp.path().join("knowledge.db");
        fake_memory_entries(&src, &[("knowledge:url:a", "content a", Some(unit(0)), 100)]);
        tag_row(&src, "knowledge:url:a", "github,scraping,source:link-capture,action:read-later,entity:Scrapy");

        migrate_from_memory_entries(std::slice::from_ref(&src), &dest).unwrap();
        let store = KnowledgeStore::open(&dest).unwrap();
        let e = store.enrichment("knowledge:url:a").unwrap().unwrap();
        assert_eq!(e.entities.as_deref(), Some(r#"["Scrapy"]"#));
        assert_eq!(e.action_type.as_deref(), Some("read-later"));

        // Idempotent: a second sync of the same row lifts the same values.
        migrate_from_memory_entries(std::slice::from_ref(&src), &dest).unwrap();
        assert_eq!(store.enrichment("knowledge:url:a").unwrap().unwrap(), e);
    }

    #[test]
    fn migrate_leaves_columns_alone_for_untagged_rows() {
        // A row that never carried the tags (pre-t-3312 captures, YouTube,
        // feed items) must not have its columns written NULL by a sync.
        let tmp = tempdir().unwrap();
        let src = tmp.path().join("live.db");
        let dest = tmp.path().join("knowledge.db");
        fake_memory_entries(&src, &[("knowledge:url:a", "content a", Some(unit(0)), 100)]);
        migrate_from_memory_entries(std::slice::from_ref(&src), &dest).unwrap();

        let store = KnowledgeStore::open(&dest).unwrap();
        store.set_extraction("knowledge:url:a", Some(r#"["Scrapy"]"#), Some("tool-to-evaluate")).unwrap();

        migrate_from_memory_entries(std::slice::from_ref(&src), &dest).unwrap();
        let e = store.enrichment("knowledge:url:a").unwrap().unwrap();
        assert_eq!(e.entities.as_deref(), Some(r#"["Scrapy"]"#));
        assert_eq!(e.action_type.as_deref(), Some("tool-to-evaluate"));
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
