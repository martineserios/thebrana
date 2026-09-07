//! Project descriptor vectors — one embedding per portfolio project (t-3307).
//!
//! The link-scoring pass needs to ask "which project is this about?". Cosine
//! over each repo's raw `CLAUDE.md` answers that badly: sibling client repos
//! share the same boilerplate and the same stack vocabulary (Next.js,
//! Supabase, FastAPI), so they cross-tag each other. The signal that actually
//! separates them is a *curated* line — domain, customer, problem, and no
//! stack words at all.
//!
//! So the descriptor is authored by a human on the portfolio record
//! (`tasks-portfolio.json` → `projects[].descriptor`), and this module turns
//! those lines into a small on-disk table:
//!
//! ```text
//! project_vectors(slug PK, descriptor, descriptor_hash, source, updated_at, vec BLOB)
//! ```
//!
//! It lives in the same `~/.claude/memory/knowledge.db` the vector store
//! already owns ([`crate::vector`]) — one file for the scoring pass to open,
//! same `f32` LE BLOB encoding, same 384-dim [`Embedder`] seam.
//!
//! Embedding is the expensive part (a `ruflo` process per call), so a project
//! is re-embedded only when its descriptor text changes — detected by SHA-256
//! of the exact text that was embedded.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use rusqlite::{Connection, OpenFlags, params};

use crate::receipt::sha256_hex;
use crate::vector::{
    EMBED_DIM, Embedder, blob_to_vec, knowledge_db_path, truncate_chars, vec_to_blob,
};

/// Slug the brana system itself is stored under. Not a `tasks-portfolio.json`
/// record — thebrana is the workshop, not a portfolio project — so its
/// descriptor is composed from the repo's own docs by
/// [`thebrana_descriptor`].
pub const THEBRANA_SLUG: &str = "thebrana";

/// Curated line for thebrana, in the same domain/customer/problem register as
/// the portfolio descriptors.
pub const THEBRANA_DESCRIPTOR: &str =
    "The system that runs this portfolio: design specs and an operator layer of skills, \
     hooks and agents that carry one operator's intent from idea to shipped work across \
     every client and venture.";

/// Char budget for thebrana's composed embedding text. The embedding model
/// (all-MiniLM-L6-v2) truncates around 256 tokens, so appending all ~80
/// accepted ADR titles would silently drop most of them anyway; cap
/// explicitly instead of pretending the tail counts.
const THEBRANA_TEXT_BUDGET: usize = 1200;

/// One project's embeddable text, before embedding.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectDescriptor {
    /// Project slug — the primary key in the vector table.
    pub slug: String,
    /// The exact text that gets embedded.
    pub descriptor: String,
    /// Where the text came from: `portfolio` or `the-brana`.
    pub source: String,
}

/// A stored row of the project-vector table.
#[derive(Debug, Clone)]
pub struct ProjectVector {
    pub slug: String,
    pub descriptor: String,
    /// SHA-256 of `descriptor` at embed time — the re-embed trigger.
    pub descriptor_hash: String,
    pub source: String,
    pub updated_at: i64,
    pub vec: Vec<f32>,
}

// ── Store ─────────────────────────────────────────────────────────────────────

/// Canonical location of the project-vector table: the same store the
/// knowledge vectors live in, so the scoring pass opens one DB.
pub fn project_vectors_db_path() -> PathBuf {
    knowledge_db_path()
}

/// The `project_vectors` table in a brana-owned SQLite store.
pub struct ProjectVectorStore {
    db_path: PathBuf,
}

impl ProjectVectorStore {
    /// Open the store, creating the file and table if absent.
    pub fn open(db_path: impl Into<PathBuf>) -> Result<Self> {
        let db_path = db_path.into();
        if let Some(parent) = db_path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("creating {}", parent.display()))?;
        }
        let conn = Connection::open(&db_path)
            .with_context(|| format!("opening {}", db_path.display()))?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS project_vectors (
                slug            TEXT PRIMARY KEY,
                descriptor      TEXT NOT NULL,
                descriptor_hash TEXT NOT NULL,
                source          TEXT NOT NULL,
                updated_at      INTEGER NOT NULL,
                vec             BLOB NOT NULL
            );",
        )
        .context("creating project_vectors schema")?;
        Ok(Self { db_path })
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    fn conn(&self) -> Result<Connection> {
        Connection::open(&self.db_path)
            .with_context(|| format!("opening {}", self.db_path.display()))
    }

    /// Insert or replace one project's vector. `vec` must be `EMBED_DIM` long.
    pub fn upsert(
        &self,
        slug: &str,
        descriptor: &str,
        source: &str,
        updated_at: i64,
        vec: &[f32],
    ) -> Result<()> {
        if vec.len() != EMBED_DIM {
            bail!("vector for {slug} has {} dims, expected {EMBED_DIM}", vec.len());
        }
        self.conn()?
            .execute(
                "INSERT OR REPLACE INTO project_vectors
                     (slug, descriptor, descriptor_hash, source, updated_at, vec)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    slug,
                    descriptor,
                    sha256_hex(descriptor.as_bytes()),
                    source,
                    updated_at,
                    vec_to_blob(vec)
                ],
            )
            .with_context(|| format!("upserting project vector {slug}"))?;
        Ok(())
    }

    /// Stored hash of the descriptor last embedded for `slug`, if any.
    pub fn descriptor_hash(&self, slug: &str) -> Result<Option<String>> {
        let conn = self.conn()?;
        let mut stmt =
            conn.prepare("SELECT descriptor_hash FROM project_vectors WHERE slug = ?1")?;
        let mut rows = stmt.query(params![slug])?;
        Ok(match rows.next()? {
            Some(r) => Some(r.get(0)?),
            None => None,
        })
    }

    /// Every stored project vector, slug-ordered. This is what the scoring
    /// pass reads. Rows whose BLOB does not decode to `EMBED_DIM` floats are
    /// skipped rather than failing the read.
    pub fn all(&self) -> Result<Vec<ProjectVector>> {
        let conn = Connection::open_with_flags(
            &self.db_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .with_context(|| format!("opening {}", self.db_path.display()))?;
        let mut stmt = conn.prepare(
            "SELECT slug, descriptor, descriptor_hash, source, updated_at, vec
             FROM project_vectors ORDER BY slug",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, i64>(4)?,
                r.get::<_, Vec<u8>>(5)?,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (slug, descriptor, descriptor_hash, source, updated_at, blob) = row?;
            let Some(vec) = blob_to_vec(&blob) else { continue };
            out.push(ProjectVector {
                slug,
                descriptor,
                descriptor_hash,
                source,
                updated_at,
                vec,
            });
        }
        Ok(out)
    }

    /// Number of stored project vectors.
    /// Delete every vector whose slug is not in `keep`. The sync calls this so
    /// a project that leaves the portfolio (archived, renamed, descriptor
    /// blanked) leaves the table too — ADR-093 D2's "full recompute rebuilds
    /// the project set from the current portfolio" is only true if the table
    /// itself never carries stale slugs. Returns the removed slugs.
    pub fn prune_except(&self, keep: &[String]) -> Result<Vec<String>> {
        let conn = self.conn()?;
        let present: Vec<String> = conn
            .prepare("SELECT slug FROM project_vectors")?
            .query_map([], |r| r.get::<_, String>(0))?
            .collect::<std::result::Result<_, _>>()?;
        let mut removed = Vec::new();
        for slug in present {
            if !keep.iter().any(|k| k == &slug) {
                conn.execute("DELETE FROM project_vectors WHERE slug = ?1", params![slug])?;
                removed.push(slug);
            }
        }
        Ok(removed)
    }

    pub fn count(&self) -> Result<usize> {
        let n: i64 = self
            .conn()?
            .query_row("SELECT COUNT(*) FROM project_vectors", [], |r| r.get(0))?;
        Ok(n as usize)
    }
}

// ── Descriptor sourcing ───────────────────────────────────────────────────────

/// Pull `{slug, descriptor}` pairs out of a parsed `tasks-portfolio.json`.
///
/// Supports both the nested `clients[].projects[]` schema and the legacy flat
/// `projects[]` one. Projects with no `descriptor` (or a blank one) are
/// skipped — an uncurated project gets no vector rather than a vector built
/// from boilerplate, which is the whole point of the curation.
pub fn descriptors_from_portfolio(portfolio: &serde_json::Value) -> Vec<ProjectDescriptor> {
    let mut out = Vec::new();
    let mut push = |proj: &serde_json::Value| {
        let Some(slug) = proj["slug"].as_str().or_else(|| proj["name"].as_str()) else {
            return;
        };
        let text = proj["descriptor"].as_str().unwrap_or("").trim();
        if text.is_empty() {
            return;
        }
        out.push(ProjectDescriptor {
            slug: slug.to_string(),
            descriptor: text.to_string(),
            source: "portfolio".to_string(),
        });
    };

    if let Some(clients) = portfolio["clients"].as_array() {
        for client in clients {
            for proj in client["projects"].as_array().into_iter().flatten() {
                push(proj);
            }
        }
    } else if let Some(projects) = portfolio["projects"].as_array() {
        for proj in projects {
            push(proj);
        }
    }
    out
}

/// Compose thebrana's own embedding text from `docs_root`: the curated line,
/// the cover paragraph of `architecture/the-brana.md`, and the titles of the
/// accepted ADRs — a differentiated signal no client repo shares.
///
/// Fails open: a missing doc or decisions directory just contributes nothing,
/// leaving the curated line, so this never blocks a sync.
pub fn thebrana_descriptor(docs_root: &Path) -> ProjectDescriptor {
    let mut text = String::from(THEBRANA_DESCRIPTOR);

    if let Some(cover) = the_brana_cover(&docs_root.join("architecture").join("the-brana.md")) {
        text.push(' ');
        text.push_str(&cover);
    }

    let titles = accepted_adr_titles(&docs_root.join("architecture").join("decisions"));
    if !titles.is_empty() {
        text.push_str(" Decided: ");
        text.push_str(&titles.join("; "));
        text.push('.');
    }

    ProjectDescriptor {
        slug: THEBRANA_SLUG.to_string(),
        descriptor: truncate_chars(&text, THEBRANA_TEXT_BUDGET),
        source: "the-brana".to_string(),
    }
}

/// The blockquote paragraph under `## Cover` in `the-brana.md`, `>` stripped.
fn the_brana_cover(path: &Path) -> Option<String> {
    let content = std::fs::read_to_string(path).ok()?;
    let mut in_cover = false;
    for line in content.lines() {
        if line.trim_start().starts_with("## ") {
            in_cover = line.trim() == "## Cover";
            continue;
        }
        if in_cover && let Some(rest) = line.trim_start().strip_prefix("> ") {
            let quote = rest.trim();
            if !quote.is_empty() {
                return Some(quote.to_string());
            }
        }
    }
    None
}

/// Titles of every `ADR-*.md` in `dir` whose frontmatter says `status:
/// accepted`, filename-ordered so the composed text is stable across runs
/// (an unstable ordering would re-embed on every sync).
fn accepted_adr_titles(dir: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut files: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with("ADR-") && n.ends_with(".md"))
        })
        .collect();
    files.sort();

    files
        .iter()
        .filter_map(|p| {
            let content = std::fs::read_to_string(p).ok()?;
            frontmatter_status(&content)
                .filter(|s| s.eq_ignore_ascii_case("accepted"))
                .and(adr_title(&content))
        })
        .collect()
}

/// `status:` value from a `---`-delimited YAML frontmatter block.
fn frontmatter_status(content: &str) -> Option<&str> {
    let mut lines = content.lines();
    if lines.next()?.trim() != "---" {
        return None;
    }
    for line in lines {
        let line = line.trim();
        if line == "---" {
            return None;
        }
        if let Some(v) = line.strip_prefix("status:") {
            return Some(v.trim());
        }
    }
    None
}

/// First `# ` heading, with the `ADR-NNN: ` prefix stripped — the ADR number
/// carries no semantics for an embedding, the title does.
fn adr_title(content: &str) -> Option<String> {
    let heading = content.lines().find_map(|l| l.strip_prefix("# "))?.trim();
    let title = match heading.split_once(": ") {
        Some((prefix, rest)) if prefix.starts_with("ADR-") => rest.trim(),
        _ => heading,
    };
    Some(title.to_string())
}

// ── Sync ──────────────────────────────────────────────────────────────────────

/// Outcome of a [`sync_project_vectors`] run.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct SyncStats {
    /// Projects embedded this run (new or changed descriptor).
    pub embedded: Vec<String>,
    /// Projects whose descriptor was unchanged — no embedding call made.
    pub unchanged: Vec<String>,
    /// Projects the embedder could not embed. Any previously stored vector is
    /// left in place rather than being replaced with nothing.
    pub failed: Vec<String>,
    /// Slugs removed because no current descriptor names them.
    pub pruned: Vec<String>,
}

/// Embed every descriptor whose text changed since it was last stored, and
/// upsert it into `store`.
///
/// `force` re-embeds everything — for when the embedding model changes, which
/// the descriptor hash cannot see.
pub fn sync_project_vectors(
    descriptors: &[ProjectDescriptor],
    store: &ProjectVectorStore,
    embedder: &dyn Embedder,
    now: i64,
    force: bool,
) -> Result<SyncStats> {
    let mut stats = SyncStats::default();
    for d in descriptors {
        let hash = sha256_hex(d.descriptor.as_bytes());
        if !force && store.descriptor_hash(&d.slug)?.as_deref() == Some(hash.as_str()) {
            stats.unchanged.push(d.slug.clone());
            continue;
        }
        let Some(vec) = embedder.embed(&d.descriptor) else {
            stats.failed.push(d.slug.clone());
            continue;
        };
        store.upsert(&d.slug, &d.descriptor, &d.source, now, &vec)?;
        stats.embedded.push(d.slug.clone());
    }
    let keep: Vec<String> = descriptors.iter().map(|d| d.slug.clone()).collect();
    stats.pruned = store.prune_except(&keep)?;
    Ok(stats)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use tempfile::tempdir;

    /// Counts embed calls so "embed once, re-embed only on change" is testable.
    struct CountingEmbedder {
        calls: Mutex<Vec<String>>,
        fail_on: Option<String>,
    }

    impl CountingEmbedder {
        fn new() -> Self {
            Self { calls: Mutex::new(Vec::new()), fail_on: None }
        }
        fn failing(text: &str) -> Self {
            Self { calls: Mutex::new(Vec::new()), fail_on: Some(text.to_string()) }
        }
        fn call_count(&self) -> usize {
            self.calls.lock().unwrap().len()
        }
    }

    impl Embedder for CountingEmbedder {
        fn embed(&self, text: &str) -> Option<Vec<f32>> {
            self.calls.lock().unwrap().push(text.to_string());
            if self.fail_on.as_deref() == Some(text) {
                return None;
            }
            let mut v = vec![0.0_f32; EMBED_DIM];
            v[text.len() % EMBED_DIM] = 1.0;
            Some(v)
        }
    }

    fn descriptor(slug: &str, text: &str) -> ProjectDescriptor {
        ProjectDescriptor {
            slug: slug.to_string(),
            descriptor: text.to_string(),
            source: "portfolio".to_string(),
        }
    }

    // ── portfolio parsing ─────────────────────────────────────────────────────

    #[test]
    fn portfolio_nested_schema_yields_curated_descriptors() {
        let p = serde_json::json!({
            "clients": [
                {"slug": "nexeye", "projects": [
                    {"slug": "eyedetect", "path": "~/x", "descriptor": "Video surveillance for security operators."}
                ]},
                {"slug": "truper", "projects": [
                    {"slug": "truper", "path": "~/y", "descriptor": "Moneyless barter marketplace."}
                ]}
            ]
        });
        let d = descriptors_from_portfolio(&p);
        assert_eq!(d.len(), 2);
        assert_eq!(d[0].slug, "eyedetect");
        assert_eq!(d[0].source, "portfolio");
        assert_eq!(d[1].descriptor, "Moneyless barter marketplace.");
    }

    #[test]
    fn portfolio_legacy_flat_schema_supported() {
        let p = serde_json::json!({
            "projects": [{"slug": "thebrana", "path": "~/x", "descriptor": "Build the brain."}]
        });
        let d = descriptors_from_portfolio(&p);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].slug, "thebrana");
    }

    #[test]
    fn portfolio_skips_projects_without_a_descriptor() {
        let p = serde_json::json!({
            "clients": [{"slug": "c", "projects": [
                {"slug": "no-descriptor", "path": "~/x"},
                {"slug": "blank", "path": "~/y", "descriptor": "   "},
                {"slug": "curated", "path": "~/z", "descriptor": "A real line."}
            ]}]
        });
        let d = descriptors_from_portfolio(&p);
        assert_eq!(d.len(), 1, "only curated projects get a vector");
        assert_eq!(d[0].slug, "curated");
    }

    // ── store ─────────────────────────────────────────────────────────────────

    #[test]
    fn store_upsert_replaces_and_reads_back() {
        let tmp = tempdir().unwrap();
        let store = ProjectVectorStore::open(tmp.path().join("knowledge.db")).unwrap();
        assert_eq!(store.count().unwrap(), 0);

        let v = vec![0.5_f32; EMBED_DIM];
        store.upsert("truper", "Barter marketplace.", "portfolio", 100, &v).unwrap();
        store.upsert("truper", "Barter marketplace, revised.", "portfolio", 200, &v).unwrap();
        assert_eq!(store.count().unwrap(), 1);

        let all = store.all().unwrap();
        assert_eq!(all[0].descriptor, "Barter marketplace, revised.");
        assert_eq!(all[0].updated_at, 200);
        assert_eq!(all[0].vec.len(), EMBED_DIM);
        assert_eq!(all[0].descriptor_hash, sha256_hex(b"Barter marketplace, revised."));
    }

    #[test]
    fn store_rejects_wrong_dimensionality() {
        let tmp = tempdir().unwrap();
        let store = ProjectVectorStore::open(tmp.path().join("knowledge.db")).unwrap();
        assert!(store.upsert("x", "t", "portfolio", 1, &[0.1, 0.2]).is_err());
    }

    #[test]
    fn store_shares_the_db_with_the_knowledge_table() {
        let tmp = tempdir().unwrap();
        let db = tmp.path().join("knowledge.db");
        let knowledge = crate::vector::KnowledgeStore::open(&db).unwrap();
        knowledge.upsert("knowledge:url:a", "c", None, Some("url"), 1, &vec![0.1; EMBED_DIM]).unwrap();

        let store = ProjectVectorStore::open(&db).unwrap();
        store.upsert("truper", "Barter marketplace.", "portfolio", 1, &vec![0.2; EMBED_DIM]).unwrap();

        assert_eq!(knowledge.count().unwrap(), 1);
        assert_eq!(store.count().unwrap(), 1);
    }

    // ── sync ──────────────────────────────────────────────────────────────────

    #[test]
    fn sync_embeds_once_then_skips_unchanged() {
        let tmp = tempdir().unwrap();
        let store = ProjectVectorStore::open(tmp.path().join("knowledge.db")).unwrap();
        let emb = CountingEmbedder::new();
        let ds = vec![descriptor("a", "Grain brokerage."), descriptor("b", "Barter marketplace.")];

        let first = sync_project_vectors(&ds, &store, &emb, 1, false).unwrap();
        assert_eq!(first.embedded, vec!["a", "b"]);
        assert_eq!(emb.call_count(), 2);

        let second = sync_project_vectors(&ds, &store, &emb, 2, false).unwrap();
        assert_eq!(second.unchanged, vec!["a", "b"]);
        assert!(second.embedded.is_empty());
        assert_eq!(emb.call_count(), 2, "unchanged descriptors must not be re-embedded");
    }

    #[test]
    fn sync_re_embeds_only_the_changed_descriptor() {
        let tmp = tempdir().unwrap();
        let store = ProjectVectorStore::open(tmp.path().join("knowledge.db")).unwrap();
        let emb = CountingEmbedder::new();
        let ds = vec![descriptor("a", "Grain brokerage."), descriptor("b", "Barter marketplace.")];
        sync_project_vectors(&ds, &store, &emb, 1, false).unwrap();

        let edited = vec![descriptor("a", "Grain brokerage."), descriptor("b", "Moneyless barter marketplace.")];
        let stats = sync_project_vectors(&edited, &store, &emb, 2, false).unwrap();
        assert_eq!(stats.embedded, vec!["b"]);
        assert_eq!(stats.unchanged, vec!["a"]);
        assert_eq!(emb.call_count(), 3);

        let stored = store.all().unwrap();
        assert_eq!(stored[1].descriptor, "Moneyless barter marketplace.");
        assert_eq!(stored[1].updated_at, 2);
    }

    #[test]
    fn sync_force_re_embeds_everything() {
        let tmp = tempdir().unwrap();
        let store = ProjectVectorStore::open(tmp.path().join("knowledge.db")).unwrap();
        let emb = CountingEmbedder::new();
        let ds = vec![descriptor("a", "Grain brokerage.")];
        sync_project_vectors(&ds, &store, &emb, 1, false).unwrap();

        let stats = sync_project_vectors(&ds, &store, &emb, 2, true).unwrap();
        assert_eq!(stats.embedded, vec!["a"]);
        assert_eq!(emb.call_count(), 2);
    }

    #[test]
    fn sync_embed_failure_keeps_the_previous_vector() {
        let tmp = tempdir().unwrap();
        let store = ProjectVectorStore::open(tmp.path().join("knowledge.db")).unwrap();
        let ok = CountingEmbedder::new();
        sync_project_vectors(&[descriptor("a", "Grain brokerage.")], &store, &ok, 1, false).unwrap();

        let failing = CountingEmbedder::failing("Grain and oilseed brokerage.");
        let stats = sync_project_vectors(
            &[descriptor("a", "Grain and oilseed brokerage.")],
            &store,
            &failing,
            2,
            false,
        )
        .unwrap();
        assert_eq!(stats.failed, vec!["a"]);
        assert!(stats.embedded.is_empty());

        let stored = store.all().unwrap();
        assert_eq!(
            stored[0].descriptor, "Grain brokerage.",
            "failed embed must not clobber the stored vector"
        );
        assert_eq!(stored[0].updated_at, 1);
    }

    // ── thebrana composition ──────────────────────────────────────────────────

    fn docs_fixture(root: &Path) {
        let arch = root.join("architecture");
        let decisions = arch.join("decisions");
        std::fs::create_dir_all(&decisions).unwrap();
        std::fs::write(
            arch.join("the-brana.md"),
            "# The Brana\n\n**Status:** draft\n\n## Cover\n\n> The Brana is how brana turns intent into shipped work.\n\n## Space\n\n> not the cover\n",
        )
        .unwrap();
        std::fs::write(
            decisions.join("ADR-001-tasks-as-data.md"),
            "---\nstatus: accepted\n---\n# ADR-001: Tasks as a Data Layer\n\nbody\n",
        )
        .unwrap();
        std::fs::write(
            decisions.join("ADR-002-proposed-thing.md"),
            "---\nstatus: proposed\n---\n# ADR-002: Not Decided Yet\n\nbody\n",
        )
        .unwrap();
        std::fs::write(
            decisions.join("ADR-003-branch-strategy.md"),
            "---\nstatus: Accepted\n---\n# ADR-003: Branch Strategy\n\nbody\n",
        )
        .unwrap();
        std::fs::write(decisions.join("README.md"), "not an ADR\n").unwrap();
    }

    #[test]
    fn thebrana_text_carries_cover_and_accepted_adrs_only() {
        let tmp = tempdir().unwrap();
        docs_fixture(tmp.path());
        let d = thebrana_descriptor(tmp.path());

        assert_eq!(d.slug, THEBRANA_SLUG);
        assert_eq!(d.source, "the-brana");
        assert!(d.descriptor.starts_with(THEBRANA_DESCRIPTOR));
        assert!(d.descriptor.contains("turns intent into shipped work"));
        assert!(d.descriptor.contains("Tasks as a Data Layer"));
        assert!(d.descriptor.contains("Branch Strategy"), "case-insensitive status match");
        assert!(!d.descriptor.contains("Not Decided Yet"), "proposed ADRs are not decisions");
        assert!(!d.descriptor.contains("not the cover"));
        assert!(!d.descriptor.contains("ADR-001"), "ADR numbers carry no semantics");
    }

    #[test]
    fn thebrana_text_is_stable_across_runs() {
        let tmp = tempdir().unwrap();
        docs_fixture(tmp.path());
        assert_eq!(thebrana_descriptor(tmp.path()), thebrana_descriptor(tmp.path()));
    }

    #[test]
    fn thebrana_text_falls_back_to_the_curated_line() {
        let tmp = tempdir().unwrap();
        let d = thebrana_descriptor(tmp.path());
        assert_eq!(d.descriptor, THEBRANA_DESCRIPTOR, "missing docs must not block a sync");
    }

    #[test]
    fn thebrana_text_is_capped() {
        let tmp = tempdir().unwrap();
        let decisions = tmp.path().join("architecture").join("decisions");
        std::fs::create_dir_all(&decisions).unwrap();
        for i in 0..200 {
            std::fs::write(
                decisions.join(format!("ADR-{i:03}-x.md")),
                format!("---\nstatus: accepted\n---\n# ADR-{i:03}: A Reasonably Long Decision Title Here\n"),
            )
            .unwrap();
        }
        let d = thebrana_descriptor(tmp.path());
        assert!(
            d.descriptor.chars().count() <= THEBRANA_TEXT_BUDGET + 1,
            "budget + the ellipsis"
        );
    }

    #[test]
    fn sync_prunes_slugs_no_longer_in_the_descriptor_set() {
        let dir = tempdir().unwrap();
        let store = ProjectVectorStore::open(dir.path().join("k.db")).unwrap();
        let emb = CountingEmbedder::new();
        let d = |slug: &str| ProjectDescriptor {
            slug: slug.into(),
            descriptor: format!("{slug} descriptor"),
            source: "portfolio".into(),
        };
        sync_project_vectors(&[d("a"), d("b"), d("gone")], &store, &emb, 1, false).unwrap();
        assert_eq!(store.count().unwrap(), 3);
        let stats = sync_project_vectors(&[d("a"), d("b")], &store, &emb, 2, false).unwrap();
        assert_eq!(stats.pruned, vec!["gone".to_string()]);
        assert_eq!(stats.unchanged.len(), 2, "a and b unchanged, not re-embedded");
        let left: Vec<String> = store.all().unwrap().into_iter().map(|p| p.slug).collect();
        assert_eq!(left, vec!["a".to_string(), "b".to_string()]);
    }
}
