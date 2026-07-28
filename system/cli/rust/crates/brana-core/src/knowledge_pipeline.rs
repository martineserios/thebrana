//! Knowledge pipeline — state management, URL extraction, allow-list enforcement,
//! and `claude` CLI shell-out for Tier 1/2/3 LLM calls.
//!
//! Implements the inbox→dimensions pipeline spec:
//! `docs/architecture/features/inbox-to-dimensions-pipeline.md`
//!
//! # Content sourcing (v1)
//! LinkedIn posts are behind a login wall. v1 uses event-log signals only:
//! author slug + title signal from the URL path + hashtags the user added at
//! capture time. No HTTP fetches. Full content fetch is deferred to v2 (t-1144).
//!
//! # LLM calls
//! Shells out to the `claude` CLI binary (`--print --output-format json`).
//! No Anthropic API key required. Binary resolved via `resolve_claude_binary()`.

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::util::home;

// ── Layer C agy contract ──────────────────────────────────────────────────────
//
// call_gemini_json() is a CLI-native (Layer C) shell-out — not Layer B (MCP/agy_delegate).
// Guarantees enforced here: version pin, 120s timeout, stdio isolation, "Error:" detection.
// Guarantees NOT enforced here: /tmp/ invariant, structured JSON error types (Layer B only).
// Callers MUST call check_agy_version() once per batch before spawning concurrent workers.

/// Minimum agy version this CLI layer is validated against (floor, not exact).
/// Any installed agy >= this floor passes — newer agy releases no longer break
/// the nightly learning loop. Should match AGY_MIN_VERSION in
/// brana-mcp/src/tools/agy_delegate.rs.
/// Upgrade procedure: validate new version → raise floor → confirm JSON contract → commit.
pub const AGY_CLI_MIN_VERSION: &str = "1.0.10";

/// Hard ceiling per agy call — matches ADR-041 §5.
pub const AGY_CLI_TIMEOUT_SECS: u64 = 120;

// ── State types ──────────────────────────────────────────────────────────────

/// Processing status of a single URL through the pipeline tiers.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum UrlStatus {
    /// Not yet processed by Tier 1.
    Unprocessed,
    /// Tier 1 scored < 3 — not relevant to known dimensions.
    Irrelevant,
    /// Tier 1 scored ≥ 3 — queued for Tier 2 cluster assignment.
    Tier1Passed,
    /// Tier 2 assigned to a dimension cluster.
    Tier2Clustered,
    /// Tier 3 synthesised into a draft file.
    Tier3Drafted,
}

/// Per-URL entry in the pipeline state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UrlEntry {
    pub status: UrlStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tier1_score: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tier1_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cluster_topic: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dimension_target: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub draft_path: Option<String>,
    /// ISO date the URL was logged in the event log (YYYY-MM-DD).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logged_date: Option<String>,
    /// Author slug extracted from the LinkedIn URL path.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    /// Human-readable title signal extracted from the LinkedIn URL path.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title_signal: Option<String>,
    /// Hashtags captured at event log time.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    /// Platform classification: linkedin | github | substack | arxiv | other
    #[serde(skip_serializing_if = "Option::is_none")]
    pub platform: Option<String>,
    /// Provenance source tag (e.g. "telegram", "ingest", "event-log").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    /// Post body fetched by a browser pre-pass.
    ///
    /// Still not consumed by tier1 scoring. The *fetch mechanism* this field
    /// was waiting on now exists — [`fetch_url_content`], built under ADR-070
    /// and exposed as `brana knowledge process-url` — but wiring it into the
    /// pipeline remains t-1144's gated decision (the pipeline must complete
    /// at least one fully validated cycle first), so nothing populates this
    /// field yet.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fetched_content: Option<String>,
}

impl UrlEntry {
    pub fn new_unprocessed(logged_date: Option<String>) -> Self {
        Self {
            status: UrlStatus::Unprocessed,
            tier1_score: None,
            tier1_reason: None,
            cluster_topic: None,
            dimension_target: None,
            draft_path: None,
            logged_date,
            author: None,
            title_signal: None,
            tags: Vec::new(),
            platform: None,
            source: None,
            fetched_content: None,
        }
    }
}

/// Top-level pipeline state — serialised to `~/.swarm/knowledge-pipeline-state.json`.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct PipelineState {
    #[serde(default)]
    pub last_tier1_run: Option<String>,
    #[serde(default)]
    pub last_tier2_run: Option<String>,
    /// Whether the hard draft cap (10) has been acknowledged by the user.
    #[serde(default)]
    pub draft_cap_acknowledged: bool,
    /// Map of URL → entry.
    #[serde(default)]
    pub urls: HashMap<String, UrlEntry>,
}

// ── State file path ──────────────────────────────────────────────────────────

/// Canonical state file path: `~/.swarm/knowledge-pipeline-state.json`.
pub fn pipeline_state_path() -> PathBuf {
    home().join(".swarm/knowledge-pipeline-state.json")
}

/// Canonical lock file path: `~/.swarm/knowledge-pipeline.lock` (reserved in the
/// write allow-list since inception; acquired since t-2247).
pub fn pipeline_lock_path() -> PathBuf {
    home().join(".swarm/knowledge-pipeline.lock")
}

// ── Pipeline lock (t-2247) ───────────────────────────────────────────────────

/// Take the exclusive advisory pipeline lock at `lock_path`. Blocking: on
/// contention prints a notice and waits. Held until the returned `File` drops
/// (or the process dies — kernel releases flock, no stale-lock handling).
///
/// Acquired exactly once per CLI entry point. Composed calls (`run` → process
/// core) must NOT re-acquire: `File::lock()` is not reentrant, so same-thread
/// re-acquisition deadlocks.
pub fn lock_pipeline_at(lock_path: &Path) -> Result<std::fs::File> {
    if let Some(dir) = lock_path.parent() {
        std::fs::create_dir_all(dir)
            .with_context(|| format!("creating lock dir {}", dir.display()))?;
    }
    let f = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(lock_path)
        .with_context(|| format!("opening pipeline lock {}", lock_path.display()))?;
    match f.try_lock() {
        Ok(()) => {}
        Err(std::fs::TryLockError::WouldBlock) => {
            eprintln!("  waiting for knowledge-pipeline lock (another run active)…");
            f.lock()
                .with_context(|| format!("acquiring pipeline lock {}", lock_path.display()))?;
        }
        Err(std::fs::TryLockError::Error(e)) => {
            return Err(e).with_context(|| {
                format!("acquiring pipeline lock {}", lock_path.display())
            });
        }
    }
    Ok(f)
}

/// Take the pipeline lock at the canonical path.
pub fn lock_pipeline() -> Result<std::fs::File> {
    lock_pipeline_at(&pipeline_lock_path())
}

// ── State R/W ────────────────────────────────────────────────────────────────

/// Load pipeline state from disk. Returns an empty state if the file does not exist.
pub fn load_state(path: &Path) -> Result<PipelineState> {
    if !path.exists() {
        return Ok(PipelineState::default());
    }
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("reading pipeline state from {}", path.display()))?;
    let state: PipelineState = serde_json::from_str(&raw)
        .with_context(|| format!("parsing pipeline state from {}", path.display()))?;
    Ok(state)
}

/// Save pipeline state to disk atomically (write to `.tmp`, then rename).
pub fn save_state(path: &Path, state: &PipelineState) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating state dir {}", parent.display()))?;
    }
    let json = serde_json::to_string_pretty(state)?;
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, &json)
        .with_context(|| format!("writing temp state to {}", tmp.display()))?;
    std::fs::rename(&tmp, path)
        .with_context(|| format!("renaming {} → {}", tmp.display(), path.display()))?;
    Ok(())
}

// ── Event log URL extraction ─────────────────────────────────────────────────

/// Signals extracted from a single event-log line for a LinkedIn URL.
#[derive(Debug, Clone, PartialEq)]
pub struct UrlEventEntry {
    pub url: String,
    /// Author slug from the URL path (e.g. `walid-boulanouar`).
    pub author: String,
    /// Title signal from the URL path slug (e.g. `everyone using claude code`).
    pub title_signal: String,
    /// Hashtags the user added when logging (e.g. `["claude-code", "cost"]`).
    pub tags: Vec<String>,
    /// ISO date the URL was logged (YYYY-MM-DD).
    pub logged_date: String,
}

/// Derive (author, title_signal) from a non-LinkedIn URL.
/// author  = registrable domain stripped of TLD (e.g. "github", "arxiv")
/// title_signal = last meaningful path segments joined by spaces
fn url_fallback_signals(url: &str) -> (String, String) {
    // Strip scheme
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))
        .unwrap_or(url);

    let (host, path) = rest.split_once('/').unwrap_or((rest, ""));

    // author: second-to-last host label (e.g. "github" from "github.com")
    let author = host
        .split('.')
        .rev()
        .nth(1) // skip TLD, take next label
        .unwrap_or(host)
        .to_string();

    // title_signal: path segments, stripped of query/fragment, joined by spaces
    let clean_path = path.split('?').next().unwrap_or("").split('#').next().unwrap_or("");
    let title_signal = clean_path
        .split('/')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let title_signal = if title_signal.is_empty() { author.clone() } else { title_signal };

    (author, title_signal)
}

/// Parse author and title_signal out of a `linkedin.com/posts/{slug}` URL path.
///
/// Expected slug patterns:
/// - `{author}_{title-words}-share-{id}-{code}`
/// - `{author}_{title-words}-ugcPost-{id}-{code}`
/// - `{author}_{title-words}-activity-{id}-{code}`
/// - `{author}_{title-words}-pulse-{id}-{code}`
///
/// Returns `None` if the URL does not match the expected structure.
pub fn parse_linkedin_url(url: &str) -> Option<(String, String)> {
    let posts_prefix = "linkedin.com/posts/";
    let slug_start = url.find(posts_prefix)? + posts_prefix.len();
    let slug = &url[slug_start..];
    let slug = slug.split('?').next().unwrap_or(slug);
    let slug = slug.split('#').next().unwrap_or(slug);
    let slug = slug.trim_end_matches('/');

    let (author_raw, rest) = slug.split_once('_')?;
    let title_raw = strip_linkedin_suffix(rest).unwrap_or(rest);

    let author = author_raw.to_string();
    let title_signal = title_raw.replace('-', " ");

    if author.is_empty() || title_signal.is_empty() {
        return None;
    }
    Some((author, title_signal))
}

/// Strip the trailing identifier suffix from a LinkedIn post slug's title portion.
fn strip_linkedin_suffix(rest: &str) -> Option<&str> {
    for marker in &["-share-", "-ugcPost-", "-activity-", "-pulse-"] {
        if let Some(pos) = rest.rfind(marker) {
            return Some(&rest[..pos]);
        }
    }
    None
}

/// Extract `#tag` strings from a log line (strips the `#` prefix, lowercased).
pub fn extract_tags_from_line(line: &str) -> Vec<String> {
    line.split_whitespace()
        .filter(|w| w.starts_with('#') && w.len() > 1)
        .map(|w| w.trim_start_matches('#').to_lowercase())
        .collect()
}

/// Parse all LinkedIn URL entries from a single event-log file's content.
///
/// The event log format uses `## YYYY-MM-DD` date headers and lines like:
/// `- HH:MM — https://www.linkedin.com/posts/... #tag1 #tag2`
pub fn parse_event_log(
    content: &str,
    known_urls: &std::collections::HashSet<String>,
) -> Vec<UrlEventEntry> {
    let mut entries = Vec::new();
    let mut current_date = String::from("unknown");

    for line in content.lines() {
        let line = line.trim();

        // Track date headers: `## 2026-04-08`
        if line.starts_with("## 20") {
            let date_part = line.trim_start_matches('#').trim();
            current_date = date_part
                .split_whitespace()
                .next()
                .unwrap_or(date_part)
                .to_string();
            continue;
        }

        let url = match line.split_whitespace().find(|t| t.starts_with("https://")) {
            Some(u) => u.trim_end_matches(')').trim_end_matches(',').to_string(),
            None => continue,
        };

        if known_urls.contains(&url) {
            continue;
        }

        let (author, title_signal) = match parse_linkedin_url(&url) {
            Some(pair) => pair,
            None => url_fallback_signals(&url),
        };

        let tags = extract_tags_from_line(line);

        entries.push(UrlEventEntry {
            url,
            author,
            title_signal,
            tags,
            logged_date: current_date.clone(),
        });
    }

    entries
}

/// Collect event-log files from `{projects_dir}/*/memory/event-log.md`.
pub fn find_event_log_files_in(projects_dir: &Path) -> Vec<PathBuf> {
    let mut logs = Vec::new();
    let Ok(entries) = std::fs::read_dir(projects_dir) else {
        return logs;
    };
    for entry in entries.flatten() {
        let log = entry.path().join("memory/event-log.md");
        if log.exists() {
            logs.push(log);
        }
    }
    logs.sort();
    logs
}

/// Collect event-log files from `~/.claude/projects/*/memory/event-log.md`.
pub fn find_event_log_files() -> Vec<PathBuf> {
    find_event_log_files_in(&home().join(".claude/projects"))
}

/// Resolve the `brana-knowledge` repo root.
///
/// Resolution order:
/// 1. `$BRANA_KNOWLEDGE_ROOT` env var
/// 2. Sibling of the thebrana git repo root (`../brana-knowledge/` relative to repo root)
/// 3. `~/enter_thebrana/brana-knowledge/`
pub fn find_brana_knowledge_root() -> Option<PathBuf> {
    if let Ok(v) = std::env::var("BRANA_KNOWLEDGE_ROOT") {
        let p = PathBuf::from(v);
        if p.exists() {
            return Some(p);
        }
    }

    // Try sibling of git repo root
    if let Ok(out) = std::process::Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if out.status.success() {
            let repo = PathBuf::from(String::from_utf8_lossy(&out.stdout).trim().to_string());
            if let Some(parent) = repo.parent() {
                let sibling = parent.join("brana-knowledge");
                if sibling.exists() {
                    return Some(sibling);
                }
            }
        }
    }

    // Fallback: well-known path
    let fallback = home().join("enter_thebrana/brana-knowledge");
    if fallback.exists() {
        return Some(fallback);
    }

    None
}

/// List dimension topic slugs from `{brana_knowledge_root}/dimensions/*.md`.
/// Used to populate the Tier 1/2 LLM prompts.
pub fn list_dimension_slugs(brana_knowledge_root: &Path) -> Vec<String> {
    let dim_dir = brana_knowledge_root.join("dimensions");
    if !dim_dir.exists() {
        return Vec::new();
    }
    let Ok(entries) = std::fs::read_dir(&dim_dir) else {
        return Vec::new();
    };
    let mut slugs: Vec<String> = entries
        .flatten()
        .filter_map(|e| {
            let p = e.path();
            if p.extension().and_then(|x| x.to_str()) == Some("md") {
                p.file_stem()
                    .and_then(|s| s.to_str())
                    .map(|s| s.to_string())
            } else {
                None
            }
        })
        .collect();
    slugs.sort();
    slugs
}

/// Extract all unprocessed LinkedIn URL entries from all event logs.
pub fn extract_unprocessed_urls(state: &PipelineState) -> Result<Vec<UrlEventEntry>> {
    extract_unprocessed_urls_in(state, &home().join(".claude/projects"))
}

/// Tier-1 candidates: union of state-queued `Unprocessed` entries (the `ingest`
/// path — t-2247 fix: these were previously invisible, making ingest a write-only
/// queue) and event-log URLs not yet in state. State entries first, sorted by URL.
pub fn extract_unprocessed_urls_in(
    state: &PipelineState,
    projects_dir: &Path,
) -> Result<Vec<UrlEventEntry>> {
    let known: std::collections::HashSet<String> = state.urls.keys().cloned().collect();

    let mut queued: Vec<(&String, &UrlEntry)> = state
        .urls
        .iter()
        .filter(|(_, e)| e.status == UrlStatus::Unprocessed)
        .collect();
    queued.sort_by(|a, b| a.0.cmp(b.0));

    let mut all: Vec<UrlEventEntry> = queued
        .into_iter()
        .map(|(url, e)| {
            let (author, title_signal) = match (e.author.clone(), e.title_signal.clone()) {
                (Some(a), Some(t)) => (a, t),
                _ => parse_linkedin_url(url).unwrap_or_else(|| url_fallback_signals(url)),
            };
            UrlEventEntry {
                url: url.clone(),
                author,
                title_signal,
                tags: e.tags.clone(),
                logged_date: e.logged_date.clone().unwrap_or_else(|| "unknown".to_string()),
            }
        })
        .collect();

    // Event-log URLs not yet in state (original sourcing — `known` excludes
    // everything above, so the union is duplicate-free by construction).
    for log_path in find_event_log_files_in(projects_dir) {
        let content = std::fs::read_to_string(&log_path)
            .with_context(|| format!("reading event log {}", log_path.display()))?;
        all.extend(parse_event_log(&content, &known));
    }
    Ok(all)
}

// ── Path allow-list ──────────────────────────────────────────────────────────

/// Returns `true` if `path` is within the pipeline's allowed write paths.
///
/// Allowed:
/// - `{brana_knowledge_root}/drafts/**`
/// - `{brana_knowledge_root}/drafts-archive/**`
/// - `~/.swarm/knowledge-pipeline-state.json` (and `.tmp`)
/// - `~/.swarm/knowledge-pipeline.lock`
/// - `~/.claude/knowledge-pipeline-report.md`
pub fn is_allowed_write_path(path: &Path, brana_knowledge_root: &Path) -> bool {
    let h = home();

    let allowed_prefixes = [
        brana_knowledge_root.join("drafts"),
        brana_knowledge_root.join("drafts-archive"),
    ];
    let allowed_exact = [
        h.join(".swarm/knowledge-pipeline-state.json"),
        h.join(".swarm/knowledge-pipeline-state.tmp"),
        h.join(".swarm/knowledge-pipeline.lock"),
        h.join(".claude/knowledge-pipeline-report.md"),
    ];

    for prefix in &allowed_prefixes {
        if path.starts_with(prefix) {
            return true;
        }
    }
    for exact in &allowed_exact {
        if path == exact {
            return true;
        }
    }
    false
}

/// Assert that a write target is allowed. Returns `Err` with a clear message if not.
pub fn assert_allowed_write(path: &Path, brana_knowledge_root: &Path) -> Result<()> {
    if !is_allowed_write_path(path, brana_knowledge_root) {
        bail!(
            "Layer-1 protection: write to '{}' is outside the pipeline's allowed paths. \
             The pipeline only writes to brana-knowledge/drafts/, drafts-archive/, \
             and ~/.swarm/knowledge-pipeline-*.",
            path.display()
        );
    }
    Ok(())
}

// ── Draft cap ────────────────────────────────────────────────────────────────

pub const DRAFT_CAP: usize = 10;

/// Count `.md` draft files in `{brana_knowledge_root}/drafts/`.
pub fn count_drafts(brana_knowledge_root: &Path) -> usize {
    let drafts_dir = brana_knowledge_root.join("drafts");
    if !drafts_dir.exists() {
        return 0;
    }
    std::fs::read_dir(&drafts_dir)
        .map(|entries| {
            entries
                .flatten()
                .filter(|e| {
                    e.path()
                        .extension()
                        .and_then(|x| x.to_str())
                        .map(|x| x == "md")
                        .unwrap_or(false)
                })
                .count()
        })
        .unwrap_or(0)
}

// ── Ingest — source-agnostic URL entry point ─────────────────────────────────

/// Extract all `http(s)://` URLs from arbitrary text.
///
/// Terminates each URL at whitespace or `<>`. Strips trailing punctuation
/// (`,.;:"')`). Deduplicates within the result set (first occurrence wins).
pub fn extract_urls_from_text(text: &str) -> Vec<String> {
    let mut urls: Vec<String> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut pos = 0;

    while pos < text.len() {
        let remaining = &text[pos..];
        let https_off = remaining.find("https://");
        let http_off = remaining.find("http://");
        let start = match (https_off, http_off) {
            (None, None) => break,
            (Some(a), None) => a,
            (None, Some(b)) => b,
            (Some(a), Some(b)) => a.min(b),
        };

        let abs = pos + start;
        let url_text = &text[abs..];
        let end = url_text
            .find(|c: char| c.is_whitespace() || matches!(c, '<' | '>'))
            .unwrap_or(url_text.len());
        let url = url_text[..end].trim_end_matches(|c: char| ",.;:\"')>".contains(c));

        if !url.is_empty() && !seen.contains(url) {
            seen.insert(url.to_string());
            urls.push(url.to_string());
        }
        pos = abs + end.max(1);
    }
    urls
}

/// Classify a URL's platform.
///
/// Returns one of: `"linkedin"`, `"github"`, `"substack"`, `"arxiv"`, `"other"`.
pub fn classify_platform(url: &str) -> &'static str {
    if url.contains("linkedin.com") {
        "linkedin"
    } else if url.contains("github.com") {
        "github"
    } else if url.contains("substack.com") {
        "substack"
    } else if url.contains("arxiv.org") {
        "arxiv"
    } else {
        "other"
    }
}

/// Result of a URL content fetch (ADR-070 three-tier fetch mechanism).
#[derive(Debug, Clone, PartialEq)]
pub struct FetchedContent {
    pub text: String,
    pub platform: &'static str,
}

/// Fetch a URL's content via the tier appropriate to its platform: `ureq`
/// for public URLs, a headless `claude -p --mcp-config` shell-out to
/// `linkedin-scraper-mcp` for LinkedIn.
///
/// Returns `Ok(None)` — distinct from `Err` — when a LinkedIn post could
/// not be found in the author's fetched feed (ADR-070 §Tier-2 correction:
/// `linkedin-scraper-mcp` has no arbitrary-URL fetch tool, only a fuzzy
/// author-feed match). Public URLs never produce `Ok(None)`: they either
/// fetch or error.
///
/// Never acquires [`lock_pipeline`] — this function is shared with a future
/// t-1144 for populating `UrlEntry.fetched_content` inside the pipeline's
/// locked `process_core` call graph, so it must stay lock-free itself
/// (ADR-070 §Lock discipline; see `test_lock_discipline_source_tripwires`
/// in `brana-cli/src/commands/knowledge.rs`).
pub fn fetch_url_content(url: &str) -> Result<Option<FetchedContent>> {
    let platform = classify_platform(url);
    if platform == "linkedin" {
        return Ok(fetch_linkedin_content(url)?.map(|text| FetchedContent { text, platform }));
    }
    let text = fetch_public_url(url)?;
    Ok(Some(FetchedContent { text, platform }))
}

/// Timeout for the LinkedIn MCP shell-out: server-side tool timeout is 90s
/// (`linkedin_mcp_server` `TOOL_TIMEOUT_SECONDS`) plus MCP server cold-start
/// (spawning Python, launching headless Chromium) plus buffer — longer than
/// `call_claude_json`'s plain-text 180s budget would allow on its own.
const LINKEDIN_MCP_TIMEOUT_SECS: u64 = 240;

/// Resolve the `linkedin-scraper-mcp` binary path.
///
/// Resolution order (mirrors `resolve_ruflo_binary`/`resolve_agy_binary`/
/// `resolve_claude_binary` — install location is machine-specific):
/// 1. `$LINKEDIN_SCRAPER_MCP_BIN` env var
/// 2. `~/.local/bin/linkedin-scraper-mcp` (the `uv tool install` default)
/// 3. `PATH` (via `which`)
pub fn resolve_linkedin_scraper_binary() -> Option<PathBuf> {
    if let Ok(v) = std::env::var("LINKEDIN_SCRAPER_MCP_BIN") {
        let p = PathBuf::from(&v);
        if p.exists() {
            return Some(p);
        }
    }

    let local_bin = home().join(".local/bin/linkedin-scraper-mcp");
    if local_bin.exists() {
        return Some(local_bin);
    }

    if let Ok(out) = std::process::Command::new("which").arg("linkedin-scraper-mcp").output() {
        if out.status.success() {
            let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !path.is_empty() {
                return Some(PathBuf::from(path));
            }
        }
    }

    None
}

/// Timeout for the `--status` session probe. Much shorter than the fetch
/// budget: it inspects a local cookie profile, it does not scrape.
const LINKEDIN_STATUS_TIMEOUT_SECS: u64 = 30;

/// Marker `linkedin-scraper-mcp --status` prints on a usable session
/// (observed 2026-07-28: `✅ Session is valid (profile: …)`). Matched
/// without the emoji so a cosmetic change to the prefix doesn't trip it.
const LINKEDIN_SESSION_OK_MARKER: &str = "Session is valid";

/// Probe LinkedIn session health via `linkedin-scraper-mcp --status`.
/// Runs before any fetch is attempted, so an expired login fails loudly
/// at the start of an unattended run instead of looking like an empty feed.
fn check_linkedin_session(binary: &std::path::Path) -> Result<()> {
    let mut child = std::process::Command::new(binary)
        .arg("--status")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning {} --status", binary.display()))?;

    let timeout = std::time::Duration::from_secs(LINKEDIN_STATUS_TIMEOUT_SECS);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!(
                        "`linkedin-scraper-mcp --status` timed out after \
                         {LINKEDIN_STATUS_TIMEOUT_SECS}s — run \
                         `linkedin-scraper-mcp --login` to refresh the session"
                    );
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => bail!("`linkedin-scraper-mcp --status` wait error: {e}"),
        }
    }

    let out = child.wait_with_output()?;
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    resolve_session_health(out.status.success(), &combined)
}

/// Decide session health from the `--status` probe's outcome.
///
/// Fail-closed by design: a usable session must be *positively* confirmed
/// by the marker. Treating a zero exit alone as healthy would let a change
/// in the probe's output silently turn every unattended run into a no-op —
/// exactly the "must not silently succeed on an expired session" constraint
/// this check exists to enforce (feature spec §Constraints).
fn resolve_session_health(probe_succeeded: bool, output: &str) -> Result<()> {
    if probe_succeeded && output.contains(LINKEDIN_SESSION_OK_MARKER) {
        return Ok(());
    }
    let detail = output.trim();
    let detail = if detail.is_empty() { "(no output)" } else { detail };
    bail!(
        "LinkedIn session is not usable — run `linkedin-scraper-mcp --login` to refresh it.\n\
         `linkedin-scraper-mcp --status` reported: {detail}"
    )
}

/// RAII guard for the scoped MCP config temp file — removed on drop
/// (including on early `?` returns from callers), so a crashed/erroring
/// call never leaves the file behind.
struct ScopedMcpConfig {
    path: PathBuf,
}

impl Drop for ScopedMcpConfig {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Process-wide counter disambiguating temp mcp-config filenames. PID alone
/// is not sufficient: batch mode calls `write_scoped_linkedin_mcp_config`
/// once per URL from within the *same* process, so two calls sharing a PID
/// would collide on one path — and one call's `Drop` cleanup could then
/// delete another still-in-flight call's file (caught by
/// `write_scoped_linkedin_mcp_config_writes_expected_json` failing when run
/// alongside `scoped_mcp_config_removed_on_drop`).
static SCOPED_CONFIG_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Writes a scoped MCP config (JSON) containing only the
/// `linkedin-scraper-mcp` server entry, to a fresh temp file. Generated at
/// runtime rather than checked in statically — the binary path is
/// machine-specific (ADR-070 §Assumptions, corrected 2026-07-24).
fn write_scoped_linkedin_mcp_config(binary: &std::path::Path) -> Result<ScopedMcpConfig> {
    let config = serde_json::json!({
        "mcpServers": {
            "linkedin-scraper": {
                "command": binary.to_string_lossy(),
                "args": []
            }
        }
    });
    let n = SCOPED_CONFIG_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let path = std::env::temp_dir()
        .join(format!("brana-linkedin-mcp-{}-{n}.json", std::process::id()));
    std::fs::write(&path, config.to_string())
        .with_context(|| format!("writing scoped mcp-config to {}", path.display()))?;
    Ok(ScopedMcpConfig { path })
}

/// Call the `claude` CLI with a scoped `--mcp-config`/`--strict-mcp-config`/
/// `--allowedTools` for MCP-tool-using prompts. Distinct from
/// `call_claude_json` (text-only, no MCP) — new arg-building, no prior art
/// in this file; empirically verified live 2026-07-24 (ADR-070).
///
/// Flag order matters: clap's `<tools...>` for `--allowedTools` consumes
/// positional-looking args until the next recognized `--flag`, so the tool
/// list must be followed by another flag (`--output-format`) before the
/// trailing positional prompt, or the prompt gets swallowed into the tools
/// list.
fn call_claude_json_with_mcp(
    prompt: &str,
    mcp_config_path: &std::path::Path,
    allowed_tools: &[&str],
) -> Result<serde_json::Value> {
    let binary = resolve_claude_binary().ok_or_else(|| {
        anyhow::anyhow!(
            "claude CLI binary not found. Checked: $CLAUDE_PLUGIN_DATA/claude, \
             ~/.local/bin/claude, PATH. Install Claude Code first."
        )
    })?;

    let mut cmd = std::process::Command::new(&binary);
    cmd.arg("--print")
        .arg("--mcp-config")
        .arg(mcp_config_path)
        .arg("--strict-mcp-config")
        .arg("--allowedTools");
    for tool in allowed_tools {
        cmd.arg(tool);
    }
    cmd.arg("--output-format")
        .arg("json")
        .arg(prompt)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    let mut child = cmd
        .spawn()
        .with_context(|| format!("spawning claude binary at {}", binary.display()))?;

    let timeout = std::time::Duration::from_secs(LINKEDIN_MCP_TIMEOUT_SECS);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("claude CLI (MCP) timed out after {LINKEDIN_MCP_TIMEOUT_SECS}s");
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => bail!("claude wait error: {e}"),
        }
    }

    let output = child.wait_with_output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("claude CLI (MCP) exited non-zero: {stderr}");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let raw = parse_claude_stdout(&stdout)?;
    match extract_result_from_envelope(&raw) {
        Some(text) => {
            let cleaned = strip_code_fences(text.trim());
            match serde_json::from_str::<serde_json::Value>(cleaned) {
                Ok(v) => Ok(v),
                // The model's final text may be prose rather than pure
                // JSON (e.g. it narrates the tool call) — fall back to
                // treating the raw text as the value rather than erroring,
                // callers extract the field(s) they need from it.
                Err(_) => Ok(serde_json::Value::String(text)),
            }
        }
        None => Ok(raw),
    }
}

/// Tier 2: best-effort LinkedIn fetch via `linkedin-scraper-mcp`'s
/// `get_person_profile(sections="posts")` + fuzzy text match (ADR-070
/// §Tier-2 correction — no arbitrary-URL fetch tool exists). Returns
/// `Ok(None)` when the target post isn't found in the fetched feed (a real
/// miss, not a fetch failure).
fn fetch_linkedin_content(url: &str) -> Result<Option<String>> {
    let (author, title_signal) =
        parse_linkedin_url(url).unwrap_or_else(|| url_fallback_signals(url));

    let binary = resolve_linkedin_scraper_binary().ok_or_else(|| {
        anyhow::anyhow!(
            "linkedin-scraper-mcp binary not found — install with: uv tool install linkedin-scraper-mcp"
        )
    })?;
    check_linkedin_session(&binary)?;
    let config = write_scoped_linkedin_mcp_config(&binary)?;

    let prompt = format!(
        "Call get_person_profile with linkedin_username=\"{author}\" and sections=\"posts\". \
         Return ONLY JSON of the shape {{\"posts_text\": \"<the raw text of the posts section>\"}}."
    );
    let response = call_claude_json_with_mcp(
        &prompt,
        &config.path,
        &["mcp__linkedin-scraper__get_person_profile"],
    );

    resolve_linkedin_fetch(response, &title_signal)
}

/// Decide a Tier-2 fetch's outcome from the MCP shell-out's result.
///
/// Split out of [`fetch_linkedin_content`] so the three-way contract is
/// testable without spawning `claude -p --mcp-config` — the same
/// injectable-core convention as [`resolve_extraction`], which takes its
/// upstream call results as parameters for exactly this reason.
///
/// - `Err` in → `Err` out: the fetch itself broke (timeout, non-zero exit,
///   missing binary). Never degraded to a miss.
/// - Unparseable response shape → `Err`: a changed/failed tool output is a
///   failure, not evidence the post is absent.
/// - Feed fetched, post not in it → `Ok(None)`: a real miss.
fn resolve_linkedin_fetch(
    response: Result<serde_json::Value>,
    title_signal: &str,
) -> Result<Option<String>> {
    let response = response?;
    let posts_text = response
        .get("posts_text")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("unexpected response shape from linkedin fetch: {response}"))?;

    Ok(find_matching_post(posts_text, title_signal))
}

/// Best-effort match: finds the paragraph-ish chunk in `feed_text` (a raw
/// scraped posts feed) whose content overlaps most with `title_signal`
/// (derived from the post URL's slug). Requires at least half the
/// significant (>3 char) signal words to appear, to avoid weak false
/// positives. Returns `None` — a real "not in this feed" miss — rather
/// than a low-confidence guess.
fn find_matching_post(feed_text: &str, title_signal: &str) -> Option<String> {
    let signal_words: Vec<String> = title_signal
        .split_whitespace()
        .filter(|w| w.len() > 3)
        .map(|w| w.to_lowercase())
        .collect();
    if signal_words.is_empty() {
        return None;
    }

    let mut best: Option<(&str, usize)> = None;
    for chunk in feed_text.split("\n\n").filter(|c| !c.trim().is_empty()) {
        let lower = chunk.to_lowercase();
        let hits = signal_words.iter().filter(|w| lower.contains(w.as_str())).count();
        if hits > 0 && best.is_none_or(|(_, best_hits)| hits > best_hits) {
            best = Some((chunk, hits));
        }
    }

    best.filter(|(_, hits)| *hits * 2 >= signal_words.len())
        .map(|(chunk, _)| chunk.trim().to_string())
}

/// Tier 1: plain HTTP GET + HTML-to-text, for public (non-LinkedIn) URLs.
/// Uses `ureq` (already a workspace dependency, ADR-024 convention) — no
/// new HTTP client dependency.
fn fetch_public_url(url: &str) -> Result<String> {
    let response = ureq::get(url)
        .header("User-Agent", "brana-knowledge-process-url/1.0")
        .call()
        .with_context(|| format!("fetch failed: {url}"))?;
    let body = response
        .into_body()
        .read_to_string()
        .with_context(|| format!("failed to read response body: {url}"))?;
    Ok(strip_html_to_text(&body))
}

/// Minimal, dependency-free HTML-to-text: drops `<script>`/`<style>`
/// blocks, strips remaining tags, collapses whitespace. Not a full HTML
/// parser (no new dependency beyond the already-present `regex-lite`) —
/// good enough for LLM-facing extraction, not structured scraping.
fn strip_html_to_text(html: &str) -> String {
    static TAG_RE: std::sync::OnceLock<regex_lite::Regex> = std::sync::OnceLock::new();
    let tag_re = TAG_RE.get_or_init(|| regex_lite::Regex::new(r"<[^>]+>").unwrap());

    let no_script = strip_tag_block(html, "script");
    let no_style = strip_tag_block(&no_script, "style");
    let stripped = tag_re.replace_all(&no_style, " ");
    stripped.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Removes every `<tag ...>...</tag>` block (case-sensitive on the tag
/// name; HTML is lowercase in practice for `script`/`style`). An unclosed
/// opening tag drops the rest of the document rather than looping forever.
fn strip_tag_block(html: &str, tag: &str) -> String {
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    let mut out = String::new();
    let mut rest = html;
    loop {
        match rest.find(&open) {
            Some(start) => {
                out.push_str(&rest[..start]);
                match rest[start..].find(&close) {
                    Some(end_rel) => rest = &rest[start + end_rel + close.len()..],
                    None => break,
                }
            }
            None => {
                out.push_str(rest);
                break;
            }
        }
    }
    out
}

/// Result of an `ingest_urls` call.
pub struct IngestResult {
    /// URLs newly added to pipeline state as `Unprocessed`.
    pub queued: usize,
    /// URLs already present in state (any status) — skipped.
    pub duplicates: usize,
}

/// Ingest a slice of URLs into pipeline state.
///
/// - Deduplicates: URLs already in `state.urls` (regardless of status) are skipped.
/// - Platform-tags each new URL via [`classify_platform`].
/// - Derives `author` / `title_signal` from LinkedIn URL parser or fallback signals.
/// - `source`: optional provenance tag stored on each new entry (e.g. `"telegram"`).
pub fn ingest_urls(urls: &[String], source: Option<&str>, state: &mut PipelineState) -> IngestResult {
    let mut result = IngestResult { queued: 0, duplicates: 0 };

    for url in urls {
        if state.urls.contains_key(url.as_str()) {
            result.duplicates += 1;
            continue;
        }

        let (author, title_signal) = parse_linkedin_url(url)
            .unwrap_or_else(|| url_fallback_signals(url));

        let entry = UrlEntry {
            author: Some(author),
            title_signal: Some(title_signal),
            platform: Some(classify_platform(url).to_string()),
            source: source.map(|s| s.to_string()),
            ..UrlEntry::new_unprocessed(None)
        };

        state.urls.insert(url.clone(), entry);
        result.queued += 1;
    }

    result
}

// ── Insight extraction (ADR-070 three-tier fallback: agy → claude -p → raw) ──

/// Extracted insight from fetched URL content.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExtractedInsight {
    pub summary: String,
    pub topic: String,
    pub extraction_skipped: bool,
}

/// Truncation length for the raw-text fallback tier (both agy and claude -p failed).
const EXTRACTION_RAW_TRUNCATE_CHARS: usize = 2000;

/// Extract an insight (summary + topic) from fetched content via a
/// three-tier fallback: agy → `claude -p` → truncated raw text. Only
/// degrades to raw text if *both* agy and claude fail — a nightly agy
/// outage alone never blocks the batch or degrades quality (ADR-070
/// Assumptions).
pub fn extract_insight(content: &str, platform: &str) -> ExtractedInsight {
    let prompt = extraction_prompt(content);
    let agy_result = call_gemini_json(&prompt);
    resolve_extraction(agy_result, || call_claude_json(&prompt, None), content, platform)
}

fn extraction_prompt(content: &str) -> String {
    format!(
        "Summarize the following content into a short knowledge-base insight. \
         Respond ONLY with JSON of the shape {{\"summary\": \"...\", \"topic\": \"...\"}} \
         (topic = a short 1-3 word category label). Content:\n\n{content}"
    )
}

/// Pure fallback decision, unit-testable without real subprocess calls: the
/// agy result is passed in already-attempted (avoids double-calling agy);
/// `claude_call` is only invoked if agy's result didn't parse. Falls back
/// to truncated raw content (flagged `extraction_skipped: true`, topic
/// defaults to `platform`) only if both fail.
fn resolve_extraction(
    agy_result: Result<serde_json::Value>,
    claude_call: impl FnOnce() -> Result<serde_json::Value>,
    content: &str,
    platform: &str,
) -> ExtractedInsight {
    if let Ok(v) = agy_result {
        if let Some(insight) = parse_extraction_response(&v, platform) {
            return insight;
        }
    }
    if let Ok(v) = claude_call() {
        if let Some(insight) = parse_extraction_response(&v, platform) {
            return insight;
        }
    }
    let truncated: String = content.chars().take(EXTRACTION_RAW_TRUNCATE_CHARS).collect();
    ExtractedInsight { summary: truncated, topic: platform.to_string(), extraction_skipped: true }
}

/// Parses `{"summary": "...", "topic": "..."}` from a model JSON response.
/// `summary` is required (`None` on a malformed/missing field — the caller
/// then falls through to the next tier); `topic` defaults to `platform`
/// when the model omits it.
fn parse_extraction_response(v: &serde_json::Value, platform: &str) -> Option<ExtractedInsight> {
    let summary = v.get("summary")?.as_str()?.to_string();
    let topic = v
        .get("topic")
        .and_then(|t| t.as_str())
        .unwrap_or(platform)
        .to_string();
    Some(ExtractedInsight { summary, topic, extraction_skipped: false })
}

// ── Gemini CLI shell-out (call_gemini_json — ADR-040 Tier1/Tier2 routing) ────

/// Check that the installed agy binary meets the [`AGY_CLI_MIN_VERSION`] floor.
/// Call once per batch before spawning concurrent workers to fail fast.
pub fn check_agy_version() -> Result<()> {
    let bin = resolve_agy_binary().ok_or_else(|| {
        anyhow::anyhow!("agy binary not found — install with: npm install -g agy")
    })?;
    check_agy_version_with_bin(&bin.to_string_lossy())
}

/// Testable core of the version check — accepts an explicit binary path.
pub fn check_agy_version_with_bin(bin: &str) -> Result<()> {
    let out = std::process::Command::new(bin)
        .arg("--version")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
        .with_context(|| "running agy --version")?;

    if !out.status.success() {
        bail!(
            "agy --version unavailable — cannot verify minimum version {AGY_CLI_MIN_VERSION}. \
             Binary exists but --version flag failed."
        );
    }

    let version = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if !crate::util::version_at_least(&version, AGY_CLI_MIN_VERSION) {
        bail!(
            "agy version too old: need >= {AGY_CLI_MIN_VERSION}, got {version} — \
             upgrade agy (npm i -g agy) or lower AGY_CLI_MIN_VERSION in knowledge_pipeline.rs"
        );
    }
    Ok(())
}

/// Resolve the `agy` (Gemini CLI) binary path.
///
/// Resolution order:
/// 1. `$AGY_BIN` env var
/// 2. `~/.local/bin/agy`
/// 3. `PATH` (via `which agy`)
pub fn resolve_agy_binary() -> Option<PathBuf> {
    if let Ok(v) = std::env::var("AGY_BIN") {
        let p = PathBuf::from(&v);
        if p.exists() {
            return Some(p);
        }
    }

    let local_bin = home().join(".local/bin/agy");
    if local_bin.exists() {
        return Some(local_bin);
    }

    if let Ok(out) = std::process::Command::new("which").arg("agy").output() {
        if out.status.success() {
            let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !path.is_empty() {
                return Some(PathBuf::from(path));
            }
        }
    }

    None
}

/// Call the `agy` Gemini CLI with `-p "<prompt>"` and return the parsed JSON response.
///
/// Layer C contract: version pin and [`AGY_CLI_TIMEOUT_SECS`] enforced. Caller must
/// invoke [`check_agy_version`] once before the first call in a batch. The /tmp/
/// invariant and structured failure types are Layer B (`agy_delegate.rs`) only.
///
/// Stdout is parsed as JSON after stripping code fences. Both stdout and stderr are
/// piped to prevent bleed into any parent JSON-RPC or MCP stream.
pub fn call_gemini_json(prompt: &str) -> Result<serde_json::Value> {
    let binary = resolve_agy_binary().ok_or_else(|| {
        anyhow::anyhow!(
            "agy binary not found — install with: npm install -g agy"
        )
    })?;

    let mut child = std::process::Command::new(&binary)
        .arg("-p")
        .arg(prompt)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning agy binary at {}", binary.display()))?;

    let timeout = std::time::Duration::from_secs(AGY_CLI_TIMEOUT_SECS);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("agy timed out after {AGY_CLI_TIMEOUT_SECS}s");
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => bail!("agy wait error: {e}"),
        }
    }

    let output = child.wait_with_output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        bail!("agy exited non-zero (exit {}): stdout={stdout} stderr={stderr}",
              output.status.code().unwrap_or(-1));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let trimmed = stdout.trim();

    // agy uses "Error: " prefix for user-visible errors (even on exit 0)
    if trimmed.starts_with("Error: ") {
        bail!("agy returned error: {trimmed}");
    }
    if trimmed.is_empty() {
        bail!("agy returned empty output");
    }

    let cleaned = strip_code_fences(trimmed);
    let parsed: serde_json::Value = serde_json::from_str(cleaned)
        .with_context(|| format!("parsing agy JSON response: {trimmed}"))?;
    Ok(parsed)
}

// ── Claude CLI shell-out (t-1145 spike) ──────────────────────────────────────

/// Resolve the `claude` CLI binary path.
///
/// Resolution order:
/// 1. `$CLAUDE_PLUGIN_DATA/claude`
/// 2. `~/.local/bin/claude`
/// 3. `PATH` (via `which claude`)
pub fn resolve_claude_binary() -> Option<PathBuf> {
    if let Ok(plugin_data) = std::env::var("CLAUDE_PLUGIN_DATA") {
        let p = PathBuf::from(&plugin_data).join("claude");
        if p.exists() {
            return Some(p);
        }
    }

    let local_bin = home().join(".local/bin/claude");
    if local_bin.exists() {
        return Some(local_bin);
    }

    if let Ok(out) = std::process::Command::new("which").arg("claude").output() {
        if out.status.success() {
            let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !path.is_empty() {
                return Some(PathBuf::from(path));
            }
        }
    }

    None
}

/// Build the argument list for a `claude --print --output-format json` invocation.
/// If `model` is `Some`, `--model <model>` is prepended before the prompt.
pub fn build_claude_args<'a>(prompt: &'a str, model: Option<&'a str>) -> Vec<&'a str> {
    let mut args = vec!["--print", "--output-format", "json"];
    if let Some(m) = model {
        args.push("--model");
        args.push(m);
    }
    args.push(prompt);
    args
}

/// Parse raw stdout from `claude --output-format json` into a single JSON value.
///
/// Handles three output shapes:
/// - Single JSON value (legacy): parsed directly
/// - JSON array (current batch): parsed as array
/// - NDJSON (newline-delimited): finds the last `{"type":"result",...}` line and
///   wraps it in an array so `extract_result_from_envelope` can handle it uniformly
fn parse_claude_stdout(stdout: &str) -> Result<serde_json::Value> {
    let trimmed = stdout.trim();
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(trimmed) {
        return Ok(v);
    }
    // NDJSON fallback: scan lines for the result entry
    let result_entry = trimmed
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line.trim()).ok())
        .find(|v| v.get("type").and_then(|t| t.as_str()) == Some("result"));
    match result_entry {
        Some(entry) => Ok(serde_json::Value::Array(vec![entry])),
        None => anyhow::bail!("parsing claude CLI envelope: {stdout}"),
    }
}

/// Extract the model's result text from the Claude CLI JSON envelope.
///
/// Handles two envelope shapes emitted by `--output-format json`:
/// - Legacy single-object: `{"type":"result","result":"<text>",...}`
/// - Array stream (current): `[{"type":"system",...}, ..., {"type":"result","result":"<text>",...}]`
fn extract_result_from_envelope(raw: &serde_json::Value) -> Option<String> {
    if let Some(arr) = raw.as_array() {
        arr.iter()
            .find(|v| v.get("type").and_then(|t| t.as_str()) == Some("result"))
            .and_then(|v| v.get("result").and_then(|r| r.as_str()))
            .map(|s| s.to_string())
    } else {
        raw.get("result").and_then(|v| v.as_str()).map(|s| s.to_string())
    }
}

/// Call the `claude` CLI with `--print --output-format json` and return the
/// parsed JSON response value. Timeout: 60 seconds.
///
/// The model is expected to respond with JSON only (as instructed in the prompt).
/// The CLI envelope is unwrapped via `extract_result_from_envelope` (handles both
/// legacy single-object and array-stream formats); the inner text is then JSON-parsed.
/// Pass `model = Some("claude-haiku-4-5-20251001")` to pin the model for cost
/// control; `None` uses the session default.
pub fn call_claude_json(prompt: &str, model: Option<&str>) -> Result<serde_json::Value> {
    let binary = resolve_claude_binary().ok_or_else(|| {
        anyhow::anyhow!(
            "claude CLI binary not found. Checked: $CLAUDE_PLUGIN_DATA/claude, \
             ~/.local/bin/claude, PATH. Install Claude Code first."
        )
    })?;

    let mut child = std::process::Command::new(&binary)
        .args(build_claude_args(prompt, model))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning claude binary at {}", binary.display()))?;

    let timeout = std::time::Duration::from_secs(180);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("claude CLI timed out after 180s");
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => bail!("claude wait error: {e}"),
        }
    }

    let output = child.wait_with_output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("claude CLI exited non-zero: {stderr}");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let raw: serde_json::Value = parse_claude_stdout(&stdout)?;

    let result_text = extract_result_from_envelope(&raw);

    if let Some(result_text) = result_text {
        let cleaned = strip_code_fences(result_text.trim());
        let inner: serde_json::Value = serde_json::from_str(cleaned)
            .with_context(|| format!("parsing model JSON response: {result_text}"))?;
        return Ok(inner);
    }

    Ok(raw)
}

/// Call the `claude` CLI and return the raw text result (no JSON parsing of the body).
/// Use this for prompts that produce prose/markdown, not structured JSON.
pub fn call_claude_text(prompt: &str) -> Result<String> {
    let binary = resolve_claude_binary().ok_or_else(|| {
        anyhow::anyhow!(
            "claude CLI binary not found. Checked: $CLAUDE_PLUGIN_DATA/claude, \
             ~/.local/bin/claude, PATH. Install Claude Code first."
        )
    })?;

    let mut child = std::process::Command::new(&binary)
        .args(["--print", "--output-format", "json", prompt])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning claude binary at {}", binary.display()))?;

    let timeout = std::time::Duration::from_secs(180);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("claude CLI timed out after 180s");
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => bail!("claude wait error: {e}"),
        }
    }

    let output = child.wait_with_output()?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("claude CLI exited non-zero: {stderr}");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let raw: serde_json::Value = parse_claude_stdout(&stdout)?;

    let result = extract_result_from_envelope(&raw).unwrap_or_else(|| stdout.trim().to_string());

    Ok(result)
}

/// Strip markdown code fences from model output.
/// Models sometimes wrap JSON in ```json ... ``` or ``` ... ``` blocks.
fn strip_code_fences(s: &str) -> &str {
    let s = s.strip_prefix("```json").unwrap_or(s);
    let s = s.strip_prefix("```").unwrap_or(s);
    let s = s.strip_suffix("```").unwrap_or(s);
    s.trim()
}

// ── append_event_log_entry ──────────────────────────────────────────────────

/// Append a URL entry to the event-log at `path`.
///
/// - Creates the file with a `# Event Log` title if absent.
/// - Inserts a `## YYYY-MM-DD` section for `date` if not already present.
/// - Appends `- HH:MM — <url> [#tag1 #tag2]` under that section.
///
/// This is the testable core. Public `append_event_log_entry` resolves the
/// real log path and current datetime before delegating here.
pub fn append_event_log_entry_at(
    path: &Path,
    date: &str,
    time: &str,
    url: &str,
    tags: &[&str],
) -> Result<()> {
    // Build the entry line: `- HH:MM — <url>` with optional ` #tag1 #tag2`
    let tag_suffix = if tags.is_empty() {
        String::new()
    } else {
        format!(
            " {}",
            tags.iter()
                .map(|t| format!("#{t}"))
                .collect::<Vec<_>>()
                .join(" ")
        )
    };
    let entry_line = format!("- {time} \u{2014} {url}{tag_suffix}");
    let date_header = format!("## {date}");

    // Read current content, or start with the canonical title
    let existing = if path.exists() {
        std::fs::read_to_string(path)
            .with_context(|| format!("reading {}", path.display()))?
    } else {
        String::new()
    };

    // Build new content
    let new_content = if existing.is_empty() {
        // New file: add title, date header, entry
        format!("# Event Log\n\n{date_header}\n\n{entry_line}\n")
    } else if existing.contains(&date_header) {
        // Date section exists — append entry after the last line in that section.
        // Strategy: find the date header, then insert the new entry at the end
        // of that section (before the next ## header or end-of-file).
        let mut lines: Vec<&str> = existing.lines().collect();
        // Find the line index of the date header
        let header_idx = lines
            .iter()
            .position(|l| l.trim() == date_header)
            .expect("header must be found after contains() check");

        // Find the insertion point: last non-empty line inside the section
        // (before the next ## header or end of file)
        let section_end = lines[header_idx + 1..]
            .iter()
            .position(|l| l.starts_with("## "))
            .map(|rel| header_idx + 1 + rel)
            .unwrap_or(lines.len());

        // Find the last non-empty line in the section to place entry after it
        let last_content_idx = lines[header_idx + 1..section_end]
            .iter()
            .rposition(|l| !l.trim().is_empty())
            .map(|rel| header_idx + 1 + rel + 1) // insert after
            .unwrap_or(section_end); // section is empty — insert at end

        lines.insert(last_content_idx, &entry_line);
        let mut result = lines.join("\n");
        // Preserve trailing newline if original had one
        if existing.ends_with('\n') && !result.ends_with('\n') {
            result.push('\n');
        }
        result
    } else {
        // No section for this date — append a new section at end
        let trimmed = existing.trim_end_matches('\n');
        format!("{trimmed}\n\n{date_header}\n\n{entry_line}\n")
    };

    // Ensure parent directory exists
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating dir {}", parent.display()))?;
    }

    std::fs::write(path, &new_content)
        .with_context(|| format!("writing {}", path.display()))?;

    Ok(())
}

/// Append a URL entry to the project's event-log.md.
///
/// Resolves the log path from `project_root` using `resolve_memory_dir`,
/// then delegates to `append_event_log_entry_at` with the current date/time.
pub fn append_event_log_entry(
    project_root: &Path,
    url: &str,
    tags: &[&str],
) -> Result<PathBuf> {
    use crate::session::resolve_memory_dir;
    use chrono::Local;

    let memory_dir = resolve_memory_dir(project_root);
    let log_path = memory_dir.join("event-log.md");
    let now = Local::now();
    let date = now.format("%Y-%m-%d").to_string();
    let time = now.format("%H:%M").to_string();
    append_event_log_entry_at(&log_path, &date, &time, url, tags)?;
    Ok(log_path)
}


// ─────────────────────────────────────────────────────────────────────────────
// Semantic dedup — ruflo-backed pre-filter for Tier1 (t-1668)
// ─────────────────────────────────────────────────────────────────────────────

/// Parse ruflo `memory search` stdout to determine if any results were returned.
/// Returns `true` when the output contains `[INFO] Found N results` where N > 0.
/// This is the sole source of truth for whether a topic is already in the knowledge base.
pub fn parse_semantic_dedup_output(output: &str) -> bool {
    output.lines().any(|line| {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("[INFO] Found ") {
            if let Some(n_str) = rest.split_whitespace().next() {
                return n_str.parse::<u32>().map(|n| n > 0).unwrap_or(false);
            }
        }
        false
    })
}

// ruflo helpers live in crate::ruflo — single source of truth.
use crate::ruflo::ruflo_memory_search_raw;

/// Check if a URL's topic is already well-represented in the knowledge base.
///
/// Calls `ruflo memory search` at the given similarity threshold. Returns `true`
/// when at least one result is found (topic covered). Safe default is `false`
/// (novel) when ruflo is unavailable or the call fails — the LLM scorer then
/// decides normally.
///
/// Threshold 0.85 calibrated from t-1589: max distinct-pair similarity = 0.59,
/// gap = 0.26. Only near-exact topic duplicates are caught, not loose overlaps.
pub fn check_semantic_dedup(title_signal: &str, threshold: f64) -> bool {
    ruflo_memory_search_raw(title_signal, "knowledge", 1, Some(threshold), false)
        .map(|raw| parse_semantic_dedup_output(&raw))
        .unwrap_or(false)
}

// ═════════════════════════════════════════════════════════════════════════════
// Tests
// ═════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use tempfile::TempDir;

    // ── strip_html_to_text / fetch_url_content ─────────────────────────

    #[test]
    fn strip_html_to_text_drops_script_and_style() {
        let html = "<html><head><style>.x{color:red}</style></head><body><script>alert(1)</script><p>Hello world</p></body></html>";
        assert_eq!(strip_html_to_text(html), "Hello world");
    }

    #[test]
    fn strip_html_to_text_collapses_whitespace() {
        let html = "<p>Hello\n\n   world  </p>  <p>again</p>";
        assert_eq!(strip_html_to_text(html), "Hello world again");
    }

    #[test]
    fn strip_html_to_text_empty_input_is_empty() {
        assert_eq!(strip_html_to_text(""), "");
    }

    #[test]
    fn strip_html_to_text_no_tags_passes_through() {
        assert_eq!(strip_html_to_text("just plain text"), "just plain text");
    }

    #[test]
    fn strip_html_to_text_unclosed_script_drops_rest_of_document() {
        // Boundary: malformed HTML (unclosed <script>) must not panic or
        // infinite-loop — dropping the remainder is an acceptable outcome.
        let html = "<p>before</p><script>var x = 1;";
        assert_eq!(strip_html_to_text(html), "before");
    }

    #[test]
    fn strip_tag_block_leaves_content_outside_block_untouched() {
        let html = "keep <script>drop this</script> keep too";
        assert_eq!(strip_tag_block(html, "script"), "keep  keep too");
    }

    /// Minimal local HTTP/1.1 server for one request — avoids adding a mock
    /// HTTP crate as a new dependency (spec Design: check before adding).
    fn serve_once(status_line: &str, body: &'static str) -> (std::net::SocketAddr, std::thread::JoinHandle<()>) {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let status_line = status_line.to_string();
        let handle = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buf = [0u8; 1024];
            let _ = stream.read(&mut buf);
            let response = format!(
                "{status_line}\r\nContent-Length: {}\r\nContent-Type: text/html\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = stream.write_all(response.as_bytes());
        });
        (addr, handle)
    }

    #[test]
    fn fetch_public_url_strips_html_from_response() {
        let (addr, handle) = serve_once("HTTP/1.1 200 OK", "<p>Real content</p>");
        let result = fetch_public_url(&format!("http://{addr}/"));
        handle.join().unwrap();
        assert_eq!(result.unwrap(), "Real content");
    }

    #[test]
    fn fetch_public_url_server_error_returns_err_not_panic() {
        let (addr, handle) = serve_once("HTTP/1.1 500 Internal Server Error", "boom");
        let result = fetch_public_url(&format!("http://{addr}/"));
        handle.join().unwrap();
        assert!(result.is_err(), "a 500 response must surface as Err");
    }

    #[test]
    fn fetch_public_url_connection_refused_returns_err_not_panic() {
        // Boundary: nothing listening on this port — must not panic.
        let result = fetch_public_url("http://127.0.0.1:1/");
        assert!(result.is_err());
    }

    #[test]
    fn fetch_url_content_public_url_sets_platform() {
        let (addr, handle) = serve_once("HTTP/1.1 200 OK", "<p>hi</p>");
        let result = fetch_url_content(&format!("http://{addr}/"));
        handle.join().unwrap();
        let content = result.unwrap().expect("public URLs never produce Ok(None)");
        assert_eq!(content.text, "hi");
        assert_eq!(content.platform, "other");
    }

    // ── LinkedIn Tier 2: find_matching_post (fuzzy fallback, ADR-070) ───
    // The process spawn in call_claude_json_with_mcp stays untested here
    // (empirically verified live instead — see ADR-070 §Empirical
    // validation). Everything downstream of it is not: resolve_linkedin_fetch
    // takes the shell-out's Result as a parameter, so the response-shape
    // and Ok(None)/Err decisions are covered below. The novel pure logic —
    // fuzzy matching — is tested here.

    #[test]
    fn find_matching_post_finds_high_overlap_chunk() {
        let feed = "Unrelated post about gardening tips and tricks.\n\n\
                     Excited to announce our new semantic layer for BigQuery, \
                     built for bounded agent traversal across graphs.\n\n\
                     Another unrelated post about coffee brewing methods.";
        let result = find_matching_post(feed, "bigquerys native semantic layer");
        assert!(result.unwrap().contains("semantic layer for BigQuery"));
    }

    #[test]
    fn find_matching_post_no_match_returns_none() {
        let feed = "A post about gardening.\n\nA post about coffee.";
        assert_eq!(find_matching_post(feed, "quantum computing breakthroughs"), None);
    }

    #[test]
    fn find_matching_post_empty_feed_returns_none() {
        assert_eq!(find_matching_post("", "some title signal"), None);
    }

    #[test]
    fn find_matching_post_only_short_words_returns_none() {
        // Boundary: title_signal with no words longer than 3 chars — no
        // reliable signal to match on, must not guess.
        assert_eq!(find_matching_post("some feed text here", "a it is to"), None);
    }

    #[test]
    fn find_matching_post_below_half_threshold_returns_none() {
        // Boundary: only 1 of 4 significant words overlaps — below the
        // half-threshold, must not weak-match.
        let feed = "This chunk mentions bigquery once and nothing else relevant.";
        let result = find_matching_post(feed, "bigquery semantic layer traversal");
        assert_eq!(result, None);
    }

    #[test]
    fn find_matching_post_picks_best_of_multiple_candidates() {
        let feed = "Weak match: mentions rust.\n\n\
                     Strong match: rust ownership borrow checker lifetimes explained.\n\n\
                     No match: totally unrelated content here.";
        let result = find_matching_post(feed, "rust ownership borrow checker lifetimes");
        assert!(result.unwrap().starts_with("Strong match"));
    }

    // ── LinkedIn Tier 2: resolve_linkedin_fetch — Ok(None) vs Err ───────
    // fetch_url_content's contract has three outcomes, not two: Ok(Some)
    // (found), Ok(None) (the author's feed fetched cleanly but this post
    // isn't in it), and Err (the fetch itself broke). Callers branch on
    // that Ok(None)/Err split — a miss is skipped, a failure is retried or
    // surfaced — so collapsing the two silently turns real breakage into
    // "nothing to see here". The find_matching_post tests above never see
    // the response envelope and so cannot cover it; these do.

    #[test]
    fn linkedin_fetch_post_not_in_feed_returns_ok_none() {
        // The core contract: feed fetched fine, target post absent.
        let response = serde_json::json!({
            "posts_text": "A post about gardening.\n\nA post about coffee brewing."
        });
        let result = resolve_linkedin_fetch(Ok(response), "quantum computing breakthroughs");
        assert!(
            matches!(&result, Ok(None)),
            "a clean fetch that lacks the post is a miss, not a failure — got {result:?}"
        );
    }

    #[test]
    fn linkedin_fetch_post_present_returns_ok_some() {
        let response = serde_json::json!({
            "posts_text": "Unrelated gardening post.\n\n\
                           Excited to announce our new semantic layer for BigQuery."
        });
        let found = resolve_linkedin_fetch(Ok(response), "bigquerys native semantic layer")
            .expect("a well-formed response must not error")
            .expect("the post is present in this feed");
        assert!(found.contains("semantic layer for BigQuery"));
    }

    #[test]
    fn linkedin_fetch_malformed_response_returns_err_not_ok_none() {
        // A broken response shape is a failure, not a miss. If this ever
        // degrades to Ok(None), every LinkedIn URL silently reports
        // "not found" the day the MCP tool changes its output shape.
        let response = serde_json::json!({"unexpected": "shape"});
        let result = resolve_linkedin_fetch(Ok(response), "some title signal");
        assert!(result.is_err(), "missing posts_text must be Err — got {result:?}");
    }

    #[test]
    fn linkedin_fetch_posts_text_wrong_type_returns_err() {
        // Boundary: key present, but not a string.
        let response = serde_json::json!({"posts_text": 42});
        let result = resolve_linkedin_fetch(Ok(response), "some title signal");
        assert!(result.is_err(), "non-string posts_text must be Err — got {result:?}");
    }

    #[test]
    fn linkedin_fetch_transport_error_propagates_as_err() {
        // Boundary: the shell-out itself failed (timeout, non-zero exit,
        // missing binary). Must stay Err — never degrade to a quiet miss.
        let result = resolve_linkedin_fetch(
            Err(anyhow::anyhow!("claude CLI (MCP) timed out after 240s")),
            "some title signal",
        );
        let err = result.expect_err("a transport failure must surface as Err");
        assert!(
            err.to_string().contains("timed out"),
            "the underlying cause must not be swallowed — got {err}"
        );
    }

    #[test]
    fn linkedin_fetch_empty_feed_returns_ok_none() {
        // Boundary: author has no posts, or the section came back empty.
        let response = serde_json::json!({"posts_text": ""});
        let result = resolve_linkedin_fetch(Ok(response), "some title signal");
        assert!(
            matches!(&result, Ok(None)),
            "an empty feed is a miss, not a failure — got {result:?}"
        );
    }

    // ── LinkedIn session health (t-2448) ────────────────────────────────
    // Probed before any LinkedIn fetch. The spec's hard constraint is
    // "must not silently succeed on an expired session — fail loud", so
    // this is deliberately fail-closed: a usable session must be
    // positively confirmed, and anything else is an error naming the
    // one-time remediation command.

    #[test]
    fn session_health_live_session_is_ok() {
        // Real observed output of `linkedin-scraper-mcp --status`, 2026-07-28.
        let output = "Current runtime: linux-amd64-container\n\
                      Login generation: 45810ed1-6728-4967-a4e7-a035e8952aaa\n\
                      ✅ Session is valid (profile: /home/u/.linkedin-mcp/profile)";
        assert!(resolve_session_health(true, output).is_ok());
    }

    #[test]
    fn session_health_dead_session_names_login_remediation() {
        // The contract t-2448 exists for: an unattended run must tell the
        // operator exactly how to fix it, not just that it failed.
        let err = resolve_session_health(false, "Session expired or not found")
            .expect_err("a dead session must be an error");
        assert!(
            err.to_string().contains("linkedin-scraper-mcp --login"),
            "the error must name the remediation command — got: {err}"
        );
    }

    #[test]
    fn session_health_zero_exit_without_marker_fails_closed() {
        // Boundary, and the load-bearing decision here: exit 0 alone is
        // NOT confirmation. If the probe's output format ever changes,
        // failing closed turns nightly runs loud instead of silently
        // fetching nothing — the failure mode the spec forbids.
        let err = resolve_session_health(true, "Current runtime: linux-amd64-container")
            .expect_err("exit 0 without the validity marker must not be treated as healthy");
        assert!(err.to_string().contains("linkedin-scraper-mcp --login"));
    }

    #[test]
    fn session_health_empty_output_fails_closed() {
        // Boundary: probe produced nothing at all.
        assert!(resolve_session_health(true, "").is_err());
    }

    #[test]
    fn session_health_checked_before_any_fetch_attempt() {
        // The spec requires the probe to gate the fetch, not merely to
        // exist ("session health check before any LinkedIn fetch"). Order
        // is the whole contract: probing afterwards would still report a
        // dead session, but only after burning a ~$0.40 / ~9s claude -p
        // MCP round-trip per URL across a nightly batch.
        let body = fn_span(
            include_str!("knowledge_pipeline.rs"),
            "fn fetch_linkedin_content",
        );
        let probe = body
            .find("check_linkedin_session")
            .expect("fetch_linkedin_content must probe session health");
        let fetch = body
            .find("call_claude_json_with_mcp")
            .expect("fetch_linkedin_content must perform the MCP fetch");
        assert!(
            probe < fetch,
            "session health must be checked BEFORE the claude -p MCP shell-out"
        );
    }

    #[test]
    fn session_health_error_surfaces_probe_output() {
        // The operator needs the probe's own words to distinguish "logged
        // out" from "binary is broken".
        let err = resolve_session_health(false, "playwright: browser not found")
            .expect_err("must be an error");
        assert!(
            err.to_string().contains("playwright: browser not found"),
            "the probe's output must not be swallowed — got: {err}"
        );
    }

    /// Source span of a function: its signature through to the next
    /// top-level `fn`/`pub fn`. Backs the lock-discipline tripwire below.
    fn fn_span<'a>(src: &'a str, signature: &str) -> &'a str {
        let start = src
            .find(signature)
            .unwrap_or_else(|| panic!("{signature} must exist in the source"));
        let after = start + signature.len();
        let end = src[after..]
            .find("\nfn ")
            .into_iter()
            .chain(src[after..].find("\npub fn "))
            .min()
            .map(|i| after + i)
            .unwrap_or(src.len());
        &src[start..end]
    }

    #[test]
    fn linkedin_fetch_call_graph_never_acquires_pipeline_lock() {
        // ADR-070 §Lock discipline. fetch_url_content is shared with
        // t-1144's planned in-pipeline use, which calls it from inside
        // process_core's already-locked call graph. lock_pipeline is
        // non-reentrant, so an acquire anywhere below deadlocks. The
        // brana-cli tripwire (test_lock_discipline_source_tripwires) scans
        // only knowledge.rs and cannot see any of these functions.
        let src = include_str!("knowledge_pipeline.rs");
        for signature in [
            "pub fn fetch_url_content",
            "fn fetch_linkedin_content",
            "fn resolve_linkedin_fetch",
            "fn check_linkedin_session",
            "fn resolve_session_health",
            "fn fetch_public_url",
            "fn call_claude_json_with_mcp",
            "fn write_scoped_linkedin_mcp_config",
            "fn find_matching_post",
        ] {
            assert!(
                !fn_span(src, signature).contains("lock_pipeline"),
                "{signature} must never acquire the pipeline lock — non-reentrant, \
                 deadlocks when called from inside process_core (t-1144)"
            );
        }
    }

    // ── resolve_linkedin_scraper_binary / write_scoped_linkedin_mcp_config ─

    #[test]
    fn resolve_linkedin_scraper_binary_does_not_panic() {
        // None is acceptable in environments without the tool installed —
        // the important contract is no panic, matching the sibling
        // resolvers' test convention (resolve_ruflo_binary, resolve_claude_binary).
        let _ = resolve_linkedin_scraper_binary();
    }

    #[test]
    fn write_scoped_linkedin_mcp_config_writes_expected_json() {
        let fake_binary = PathBuf::from("/fake/path/linkedin-scraper-mcp");
        let config = write_scoped_linkedin_mcp_config(&fake_binary).unwrap();
        let written = std::fs::read_to_string(&config.path).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&written).unwrap();
        assert_eq!(
            parsed["mcpServers"]["linkedin-scraper"]["command"],
            "/fake/path/linkedin-scraper-mcp"
        );
    }

    #[test]
    fn scoped_mcp_config_two_calls_same_process_get_distinct_paths() {
        // Boundary: batch mode calls this once per URL from the same
        // process — PID-only naming would collide (regression guard).
        let fake_binary = PathBuf::from("/fake/path/linkedin-scraper-mcp");
        let a = write_scoped_linkedin_mcp_config(&fake_binary).unwrap();
        let b = write_scoped_linkedin_mcp_config(&fake_binary).unwrap();
        assert_ne!(a.path, b.path);
        assert!(a.path.exists());
        assert!(b.path.exists());
    }

    #[test]
    fn scoped_mcp_config_removed_on_drop() {
        let fake_binary = PathBuf::from("/fake/path/linkedin-scraper-mcp");
        let config = write_scoped_linkedin_mcp_config(&fake_binary).unwrap();
        let path = config.path.clone();
        assert!(path.exists());
        drop(config);
        assert!(!path.exists(), "temp mcp-config file must be cleaned up on drop");
    }

    // ── resolve_extraction (agy → claude-p → raw fallback) ─────────────

    fn valid_response(summary: &str, topic: &str) -> serde_json::Value {
        serde_json::json!({"summary": summary, "topic": topic})
    }

    #[test]
    fn resolve_extraction_agy_success_never_calls_claude() {
        let claude_called = std::cell::Cell::new(false);
        let insight = resolve_extraction(
            Ok(valid_response("agy summary", "rust")),
            || {
                claude_called.set(true);
                bail!("should not be called")
            },
            "raw content",
            "other",
        );
        assert_eq!(insight.summary, "agy summary");
        assert_eq!(insight.topic, "rust");
        assert!(!insight.extraction_skipped);
        assert!(!claude_called.get(), "agy succeeded — claude -p must not be invoked");
    }

    #[test]
    fn resolve_extraction_agy_fails_falls_back_to_claude() {
        let insight = resolve_extraction(
            Err(anyhow::anyhow!("agy quota exhausted")),
            || Ok(valid_response("claude summary", "ai")),
            "raw content",
            "other",
        );
        assert_eq!(insight.summary, "claude summary");
        assert_eq!(insight.topic, "ai");
        assert!(!insight.extraction_skipped);
    }

    #[test]
    fn resolve_extraction_agy_malformed_falls_back_to_claude() {
        // Boundary: agy returns Ok but the JSON doesn't have a "summary" key.
        let insight = resolve_extraction(
            Ok(serde_json::json!({"unexpected": "shape"})),
            || Ok(valid_response("claude summary", "ai")),
            "raw content",
            "other",
        );
        assert_eq!(insight.summary, "claude summary");
        assert!(!insight.extraction_skipped);
    }

    #[test]
    fn resolve_extraction_both_fail_falls_back_to_raw_truncated() {
        let insight = resolve_extraction(
            Err(anyhow::anyhow!("agy down")),
            || Err(anyhow::anyhow!("claude down")),
            "the raw fetched content",
            "linkedin",
        );
        assert_eq!(insight.summary, "the raw fetched content");
        assert_eq!(insight.topic, "linkedin", "topic falls back to platform when both fail");
        assert!(insight.extraction_skipped);
    }

    #[test]
    fn resolve_extraction_raw_fallback_truncates_long_content() {
        let long_content = "x".repeat(EXTRACTION_RAW_TRUNCATE_CHARS + 500);
        let insight = resolve_extraction(
            Err(anyhow::anyhow!("agy down")),
            || Err(anyhow::anyhow!("claude down")),
            &long_content,
            "other",
        );
        assert_eq!(insight.summary.chars().count(), EXTRACTION_RAW_TRUNCATE_CHARS);
    }

    #[test]
    fn resolve_extraction_raw_fallback_short_content_not_padded() {
        let insight = resolve_extraction(
            Err(anyhow::anyhow!("agy down")),
            || Err(anyhow::anyhow!("claude down")),
            "short",
            "other",
        );
        assert_eq!(insight.summary, "short");
    }

    #[test]
    fn parse_extraction_response_missing_topic_defaults_to_platform() {
        let v = serde_json::json!({"summary": "hi"});
        let insight = parse_extraction_response(&v, "github").unwrap();
        assert_eq!(insight.topic, "github");
    }

    #[test]
    fn parse_extraction_response_missing_summary_returns_none() {
        let v = serde_json::json!({"topic": "rust"});
        assert!(parse_extraction_response(&v, "other").is_none());
    }

    // ── build_claude_args ─────────────────────────────────────────────

    #[test]
    fn test_build_claude_args_with_model_includes_model_flag() {
        let args = build_claude_args("test prompt", Some("claude-haiku-4-5-20251001"));
        assert!(args.contains(&"--model"), "expected --model in args: {:?}", args);
        assert!(
            args.contains(&"claude-haiku-4-5-20251001"),
            "expected model name in args: {:?}",
            args
        );
    }

    #[test]
    fn test_build_claude_args_without_model_omits_model_flag() {
        let args = build_claude_args("test prompt", None);
        assert!(!args.contains(&"--model"), "expected no --model in args: {:?}", args);
    }

    #[test]
    fn test_build_claude_args_prompt_is_last() {
        let prompt = "my prompt";
        let args = build_claude_args(prompt, Some("claude-haiku-4-5-20251001"));
        assert_eq!(*args.last().unwrap(), prompt);
    }

    // ── parse_linkedin_url ────────────────────────────────────────────

    #[test]
    fn test_parse_standard_share_url() {
        let url = "https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-7437448165403852801-F5RX";
        let (author, title) = parse_linkedin_url(url).expect("should parse");
        assert_eq!(author, "walid-boulanouar");
        assert_eq!(title, "everyone using claude code is paying for");
    }

    #[test]
    fn test_parse_ugcpost_url() {
        let url = "https://www.linkedin.com/posts/prateekkarnal_a-self-improving-system-in-one-repo-is-impressive-ugcPost-7437898224763375616-Abzi";
        let (author, title) = parse_linkedin_url(url).expect("should parse");
        assert_eq!(author, "prateekkarnal");
        assert_eq!(title, "a self improving system in one repo is impressive");
    }

    #[test]
    fn test_parse_url_with_query_string() {
        let url = "https://www.linkedin.com/posts/foo_bar-baz-share-123-XY?tracking=true";
        let (author, title) = parse_linkedin_url(url).expect("should parse");
        assert_eq!(author, "foo");
        assert_eq!(title, "bar baz");
    }

    #[test]
    fn test_parse_non_linkedin_url_returns_none() {
        assert!(parse_linkedin_url("https://github.com/foo/bar").is_none());
        assert!(parse_linkedin_url("https://www.linkedin.com/in/martinrios").is_none());
    }

    #[test]
    fn test_parse_linkedin_pulse_url() {
        let url = "https://www.linkedin.com/posts/unmeshgundecha_harness-engineering-domain2-pulse-7437241299629481985-Nig0";
        let (author, title) = parse_linkedin_url(url).expect("should parse");
        assert_eq!(author, "unmeshgundecha");
        assert_eq!(title, "harness engineering domain2");
    }

    // ── extract_tags_from_line ────────────────────────────────────────

    #[test]
    fn test_extract_single_tag() {
        let tags = extract_tags_from_line("- 21:14 — https://... #claude-code");
        assert_eq!(tags, vec!["claude-code"]);
    }

    #[test]
    fn test_extract_multiple_tags() {
        let tags = extract_tags_from_line("- 09:00 — https://... #agents #memory #knowledge");
        assert_eq!(tags, vec!["agents", "memory", "knowledge"]);
    }

    #[test]
    fn test_extract_no_tags() {
        let tags = extract_tags_from_line("- 09:00 — https://...");
        assert!(tags.is_empty());
    }

    #[test]
    fn test_extract_tags_lowercased() {
        let tags = extract_tags_from_line("line #Claude-Code #AI");
        assert_eq!(tags, vec!["claude-code", "ai"]);
    }

    // ── parse_event_log ───────────────────────────────────────────────

    #[test]
    fn test_parse_event_log_basic() {
        let content = r#"
## 2026-04-08

- 21:14 — https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-7437448165403852801-F5RX #claude-code #cost
- 22:51 — https://www.linkedin.com/posts/elirangeffen_opensource-claudecode-ai-share-7437542416074727424-DFJh #open-source
"#;
        let known = HashSet::new();
        let entries = parse_event_log(content, &known);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].author, "walid-boulanouar");
        assert_eq!(entries[0].logged_date, "2026-04-08");
        assert_eq!(entries[0].tags, vec!["claude-code", "cost"]);
        assert_eq!(entries[1].author, "elirangeffen");
    }

    #[test]
    fn test_parse_event_log_skips_known_urls() {
        let content = r#"
## 2026-04-08
- 21:14 — https://www.linkedin.com/posts/foo_bar-baz-share-123-XX #tag
"#;
        let mut known = HashSet::new();
        known.insert("https://www.linkedin.com/posts/foo_bar-baz-share-123-XX".to_string());
        let entries = parse_event_log(content, &known);
        assert!(entries.is_empty());
    }

    #[test]
    fn test_parse_event_log_accepts_non_linkedin() {
        // Both URLs must be accepted — no platform filter.
        let content = r#"
## 2026-04-08
- 09:00 — https://github.com/anthropics/claude-code #tools
- 10:00 — https://www.linkedin.com/posts/foo_bar-share-999-XX #agents
"#;
        let known = HashSet::new();
        let entries = parse_event_log(content, &known);
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[1].author, "foo"); // LinkedIn entry still parsed correctly
    }

    #[test]
    fn test_parse_event_log_non_linkedin_fallback() {
        // Non-LinkedIn URL gets domain as author, path slug as title_signal.
        let content = r#"
## 2026-05-24
- 09:00 — https://arxiv.org/abs/2501.12345 #research
- 10:00 — https://github.com/anthropics/claude-code #tools
"#;
        let known = HashSet::new();
        let entries = parse_event_log(content, &known);
        assert_eq!(entries.len(), 2);
        // author should be non-empty (domain or "unknown")
        assert!(!entries[0].author.is_empty());
        // title_signal should be non-empty
        assert!(!entries[0].title_signal.is_empty());
        assert_eq!(entries[0].logged_date, "2026-05-24");
        assert_eq!(entries[0].tags, vec!["research"]);
    }

    #[test]
    fn test_parse_event_log_date_carried_forward() {
        let content = r#"
## 2026-03-15

- 08:00 — https://www.linkedin.com/posts/alice_topic-a-share-1-XA #a

## 2026-03-16

- 09:00 — https://www.linkedin.com/posts/bob_topic-b-share-2-XB #b
"#;
        let known = HashSet::new();
        let entries = parse_event_log(content, &known);
        assert_eq!(entries[0].logged_date, "2026-03-15");
        assert_eq!(entries[1].logged_date, "2026-03-16");
    }

    // ── state R/W ─────────────────────────────────────────────────────

    #[test]
    fn test_state_roundtrip() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("state.json");
        let mut state = PipelineState::default();
        state.urls.insert(
            "https://www.linkedin.com/posts/foo_bar-share-1-XX".to_string(),
            UrlEntry::new_unprocessed(Some("2026-04-08".to_string())),
        );
        save_state(&path, &state).expect("save should succeed");
        let loaded = load_state(&path).expect("load should succeed");
        assert_eq!(loaded.urls.len(), 1);
        assert!(loaded
            .urls
            .contains_key("https://www.linkedin.com/posts/foo_bar-share-1-XX"));
    }

    #[test]
    fn test_load_state_missing_file_returns_default() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("nonexistent.json");
        let state = load_state(&path).expect("should return default");
        assert!(state.urls.is_empty());
        assert!(!state.draft_cap_acknowledged);
    }

    #[test]
    fn test_save_state_creates_parent_dirs() {
        let dir = TempDir::new().unwrap();
        let path = dir.path().join("deep/nested/state.json");
        let state = PipelineState::default();
        save_state(&path, &state).expect("should create dirs and save");
        assert!(path.exists());
    }

    // ── pipeline lock + candidate sourcing (t-2247) ───────────────────

    #[test]
    fn test_lock_pipeline_serializes_concurrent_writers() {
        use std::sync::Arc;
        let dir = TempDir::new().unwrap();
        let lock_path = Arc::new(dir.path().join("pipeline.lock"));
        let state_path = Arc::new(dir.path().join("state.json"));
        save_state(&state_path, &PipelineState::default()).unwrap();

        const N: usize = 8;
        let mut handles = Vec::new();
        for i in 0..N {
            let lock_path = Arc::clone(&lock_path);
            let state_path = Arc::clone(&state_path);
            handles.push(std::thread::spawn(move || {
                let _guard = lock_pipeline_at(&lock_path).expect("acquire pipeline lock");
                let mut state = load_state(&state_path).unwrap();
                state.urls.insert(
                    format!("https://example.com/post-{i}"),
                    UrlEntry::new_unprocessed(None),
                );
                // widen the load→save window so unserialized writers interleave
                std::thread::sleep(std::time::Duration::from_millis(10));
                save_state(&state_path, &state).unwrap();
            }));
        }
        for h in handles {
            h.join().unwrap();
        }
        let final_state = load_state(&state_path).unwrap();
        assert_eq!(
            final_state.urls.len(),
            N,
            "every writer's update must survive — a lost update means the lock failed to serialize load→modify→save"
        );
    }

    #[test]
    fn test_lock_pipeline_excludes_second_writer_until_released() {
        use std::sync::atomic::{AtomicBool, Ordering};
        use std::sync::Arc;
        use std::time::Duration;

        let dir = TempDir::new().unwrap();
        let lock_path = Arc::new(dir.path().join("pipeline.lock"));

        let first = lock_pipeline_at(&lock_path).expect("first writer acquires");
        let acquired = Arc::new(AtomicBool::new(false));
        let handle = {
            let lock_path = Arc::clone(&lock_path);
            let acquired = Arc::clone(&acquired);
            std::thread::spawn(move || {
                let _second =
                    lock_pipeline_at(&lock_path).expect("second writer eventually acquires");
                acquired.store(true, Ordering::SeqCst);
            })
        };
        std::thread::sleep(Duration::from_millis(100));
        assert!(
            !acquired.load(Ordering::SeqCst),
            "second writer must block while the first holds the lock"
        );
        drop(first);
        handle.join().unwrap();
        assert!(
            acquired.load(Ordering::SeqCst),
            "second writer must acquire the lock once it is released"
        );
    }

    #[test]
    fn test_lock_pipeline_creates_missing_parent_dirs() {
        let dir = TempDir::new().unwrap();
        let lock_path = dir.path().join("no/such/dir/pipeline.lock");
        let _guard = lock_pipeline_at(&lock_path).expect("must create parents and lock");
        assert!(lock_path.exists());
    }

    #[test]
    fn test_extract_unprocessed_nonexistent_projects_dir_yields_state_only() {
        let dir = TempDir::new().unwrap();
        let mut state = PipelineState::default();
        state
            .urls
            .insert("https://example.com/only".into(), UrlEntry::new_unprocessed(None));
        let out = extract_unprocessed_urls_in(&state, &dir.path().join("missing"))
            .expect("missing projects dir is not an error");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].url, "https://example.com/only");
    }

    #[test]
    fn test_extract_unprocessed_includes_state_queued() {
        let dir = TempDir::new().unwrap();
        let projects = dir.path().join("projects"); // empty — no event logs
        std::fs::create_dir_all(&projects).unwrap();

        let mut state = PipelineState::default();
        state.urls.insert(
            "https://example.com/b".into(),
            UrlEntry::new_unprocessed(Some("2026-07-02".into())),
        );
        state
            .urls
            .insert("https://example.com/a".into(), UrlEntry::new_unprocessed(None));
        let mut scored = UrlEntry::new_unprocessed(None);
        scored.status = UrlStatus::Tier1Passed;
        state.urls.insert("https://example.com/done".into(), scored);

        let out = extract_unprocessed_urls_in(&state, &projects).expect("extract");
        let urls: Vec<&str> = out.iter().map(|e| e.url.as_str()).collect();
        assert_eq!(
            urls,
            vec!["https://example.com/a", "https://example.com/b"],
            "state-queued Unprocessed entries must be tier1 candidates (sorted), already-scored excluded"
        );
    }

    #[test]
    fn test_extract_unprocessed_unions_event_log_and_state() {
        let dir = TempDir::new().unwrap();
        let projects = dir.path().join("projects");
        let mem = projects.join("-home-user-proj/memory");
        std::fs::create_dir_all(&mem).unwrap();
        std::fs::write(
            mem.join("event-log.md"),
            "## 2026-07-02\n- 10:00 — https://www.linkedin.com/posts/someone_topic-share-42-XY\n",
        )
        .unwrap();

        let mut state = PipelineState::default();
        state
            .urls
            .insert("https://example.com/queued".into(), UrlEntry::new_unprocessed(None));

        let out = extract_unprocessed_urls_in(&state, &projects).expect("extract");
        let urls: Vec<&str> = out.iter().map(|e| e.url.as_str()).collect();
        assert!(
            urls.contains(&"https://example.com/queued"),
            "state-queued entry missing from candidates"
        );
        assert!(
            urls.iter().any(|u| u.contains("linkedin.com/posts/someone")),
            "event-log sourcing regressed"
        );
        assert_eq!(out.len(), 2, "no duplicates expected in the union");
    }

    // ── is_allowed_write_path ─────────────────────────────────────────

    #[test]
    fn test_allow_list_permits_drafts_dir() {
        let dir = TempDir::new().unwrap();
        let root = dir.path().to_path_buf();
        let draft = root.join("drafts/2026-04-12-agent-memory.md");
        assert!(is_allowed_write_path(&draft, &root));
    }

    #[test]
    fn test_allow_list_permits_drafts_archive() {
        let dir = TempDir::new().unwrap();
        let root = dir.path().to_path_buf();
        let archived = root.join("drafts-archive/2026-04-12/old-draft.md");
        assert!(is_allowed_write_path(&archived, &root));
    }

    #[test]
    fn test_allow_list_rejects_layer1_paths() {
        let dir = TempDir::new().unwrap();
        let root = dir.path().to_path_buf();
        let bad_paths = [
            PathBuf::from("/home/martineserios/.claude/CLAUDE.md"),
            PathBuf::from("/home/martineserios/.claude/rules/git-discipline.md"),
            root.join("dimensions/21-memory-patterns.md"),
        ];
        for p in &bad_paths {
            assert!(
                !is_allowed_write_path(p, &root),
                "should be rejected: {}",
                p.display()
            );
        }
    }

    #[test]
    fn test_assert_allowed_write_err_mentions_layer1() {
        let dir = TempDir::new().unwrap();
        let root = dir.path().to_path_buf();
        let layer1 = PathBuf::from("/home/martineserios/.claude/CLAUDE.md");
        let err = assert_allowed_write(&layer1, &root).unwrap_err().to_string();
        assert!(err.contains("Layer-1 protection"));
    }

    // ── find_event_log_files_in ───────────────────────────────────────

    #[test]
    fn test_find_event_log_files_finds_logs() {
        let dir = TempDir::new().unwrap();
        for proj in &["proj-a", "proj-b"] {
            let mem = dir.path().join(proj).join("memory");
            std::fs::create_dir_all(&mem).unwrap();
            std::fs::write(mem.join("event-log.md"), "## 2026-04-01\n").unwrap();
        }
        std::fs::create_dir_all(dir.path().join("proj-c/memory")).unwrap();
        let logs = find_event_log_files_in(dir.path());
        assert_eq!(logs.len(), 2);
    }

    #[test]
    fn test_find_event_log_files_missing_dir_returns_empty() {
        let logs = find_event_log_files_in(Path::new("/tmp/nonexistent-projects-xyz"));
        assert!(logs.is_empty());
    }

    // ── count_drafts ──────────────────────────────────────────────────

    #[test]
    fn test_count_drafts_empty_dir() {
        let dir = TempDir::new().unwrap();
        std::fs::create_dir(dir.path().join("drafts")).unwrap();
        assert_eq!(count_drafts(dir.path()), 0);
    }

    #[test]
    fn test_count_drafts_counts_md_files_only() {
        let dir = TempDir::new().unwrap();
        let drafts = dir.path().join("drafts");
        std::fs::create_dir(&drafts).unwrap();
        std::fs::write(drafts.join("draft-a.md"), "# A").unwrap();
        std::fs::write(drafts.join("draft-b.md"), "# B").unwrap();
        std::fs::write(drafts.join(".gitkeep"), "").unwrap();
        assert_eq!(count_drafts(dir.path()), 2);
    }

    #[test]
    fn test_count_drafts_missing_dir_returns_zero() {
        let dir = TempDir::new().unwrap();
        assert_eq!(count_drafts(dir.path()), 0);
    }

    // ── resolve_agy_binary / call_gemini_json ────────────────────────

    #[test]
    fn test_resolve_agy_binary_does_not_panic() {
        // Just verify it doesn't panic — None is ok in CI without agy installed
        let _ = resolve_agy_binary();
    }

    // ── check_agy_version_with_bin ────────────────────────────────────

    #[cfg(unix)]
    fn write_fake_agy(script_body: &str, label: &str) -> std::path::PathBuf {
        let path = std::path::PathBuf::from(format!(
            "/tmp/fake-agy-kp-{label}-{}.sh",
            std::process::id()
        ));
        std::fs::write(&path, format!("#!/bin/sh\n{script_body}\n")).unwrap();
        std::process::Command::new("chmod")
            .args(["+x", path.to_str().unwrap()])
            .output()
            .unwrap();
        path
    }

    #[cfg(unix)]
    #[test]
    fn test_check_agy_version_accepts_floor() {
        let bin = write_fake_agy(&format!("echo '{AGY_CLI_MIN_VERSION}'"), "ver-ok");
        let result = check_agy_version_with_bin(bin.to_str().unwrap());
        let _ = std::fs::remove_file(&bin);
        assert!(result.is_ok(), "floor version should pass: {:?}", result.err());
    }

    #[cfg(unix)]
    #[test]
    fn test_check_agy_version_accepts_above_floor() {
        // A future agy release must not break the loop — anything >= floor passes.
        let bin = write_fake_agy("echo '1.99.0'", "ver-newer");
        let result = check_agy_version_with_bin(bin.to_str().unwrap());
        let _ = std::fs::remove_file(&bin);
        assert!(result.is_ok(), "above-floor version should pass: {:?}", result.err());
    }

    #[cfg(unix)]
    #[test]
    fn test_check_agy_version_rejects_below_floor() {
        let bin = write_fake_agy("echo '0.0.0'", "ver-bad");
        let result = check_agy_version_with_bin(bin.to_str().unwrap());
        let _ = std::fs::remove_file(&bin);
        let err = result.unwrap_err().to_string();
        assert!(err.contains("too old"), "should report too old: {err}");
        assert!(err.contains(AGY_CLI_MIN_VERSION), "should name floor: {err}");
        assert!(err.contains("0.0.0"), "should name actual: {err}");
    }

    #[cfg(unix)]
    #[test]
    fn test_check_agy_version_rejects_nonzero_exit() {
        let bin = write_fake_agy("exit 1", "ver-nonzero");
        let result = check_agy_version_with_bin(bin.to_str().unwrap());
        let _ = std::fs::remove_file(&bin);
        assert!(result.is_err(), "non-zero exit should fail version check");
    }

    // ── append_event_log_entry_at ─────────────────────────────────────

    #[test]
    fn test_append_entry_correct_format() {
        // TDD: appends `- HH:MM — <url> #tag1 #tag2` under today's date header
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("event-log.md");
        let date = "2026-05-31";
        let time = "14:30";
        let url = "https://example.com/article";
        let tags = vec!["ai", "learning"];
        append_event_log_entry_at(&log_path, date, time, url, &tags).unwrap();
        let content = std::fs::read_to_string(&log_path).unwrap();
        assert!(content.contains(&format!("## {date}")), "missing date header");
        assert!(
            content.contains(&format!("- {time} \u{2014} {url} #ai #learning")),
            "missing entry line: {content}"
        );
    }

    #[test]
    fn test_append_creates_date_header_if_missing() {
        // TDD: creates `## YYYY-MM-DD` section when log has no entry for today
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("event-log.md");
        std::fs::write(
            &log_path,
            "# Event Log\n\n## 2026-01-01\n\n- 09:00 \u{2014} https://old.example.com\n",
        ).unwrap();
        let date = "2026-05-31";
        let time = "10:00";
        let url = "https://new.example.com";
        append_event_log_entry_at(&log_path, date, time, url, &[]).unwrap();
        let content = std::fs::read_to_string(&log_path).unwrap();
        assert!(content.contains(&format!("## {date}")), "new date header missing");
        assert!(content.contains(&format!("- {time} \u{2014} {url}")), "entry line missing");
        // Old section must still be present
        assert!(content.contains("## 2026-01-01"), "old date header lost");
    }

    #[test]
    fn test_append_no_duplicate_date_header() {
        // TDD: when today's date header already exists, appends without duplicating
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("event-log.md");
        let date = "2026-05-31";
        std::fs::write(
            &log_path,
            &format!("# Event Log\n\n## {date}\n\n- 09:00 \u{2014} https://first.example.com\n"),
        ).unwrap();
        let time = "10:00";
        let url = "https://second.example.com";
        append_event_log_entry_at(&log_path, date, time, url, &[]).unwrap();
        let content = std::fs::read_to_string(&log_path).unwrap();
        let header = format!("## {date}");
        let count = content.matches(&header).count();
        assert_eq!(count, 1, "date header duplicated: {content}");
        assert!(content.contains("https://first.example.com"), "first entry lost");
        assert!(content.contains("https://second.example.com"), "second entry missing");
    }

    #[test]
    fn test_append_creates_log_file_if_absent() {
        // TDD: creates event-log.md with a title header when file does not exist
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("event-log.md");
        let date = "2026-05-31";
        let time = "08:00";
        let url = "https://brand-new.example.com";
        append_event_log_entry_at(&log_path, date, time, url, &["fresh"]).unwrap();
        let content = std::fs::read_to_string(&log_path).unwrap();
        assert!(content.contains("# Event Log"), "title header missing");
        assert!(content.contains(&format!("## {date}")), "date header missing");
        assert!(
            content.contains(&format!("- {time} \u{2014} {url} #fresh")),
            "entry missing: {content}"
        );
    }

    #[test]
    fn test_append_no_tags_omits_hash_suffix() {
        // TDD: entry line has no trailing space or hash when tags is empty
        let dir = TempDir::new().unwrap();
        let log_path = dir.path().join("event-log.md");
        let date = "2026-05-31";
        let time = "09:15";
        let url = "https://notags.example.com";
        append_event_log_entry_at(&log_path, date, time, url, &[]).unwrap();
        let content = std::fs::read_to_string(&log_path).unwrap();
        let expected_line = format!("- {time} \u{2014} {url}");
        assert!(
            content.contains(&expected_line),
            "expected bare line, got: {content}"
        );
        for line in content.lines() {
            if line.contains(url) {
                assert!(!line.ends_with(' '), "trailing space: {line:?}");
                assert!(!line.ends_with('#'), "trailing hash: {line:?}");
            }
        }
    }

    #[test]
    fn test_call_gemini_json_returns_value_shape() {
        // Test the parsing logic only (not the actual agy call).
        // Simulate what call_gemini_json does with valid JSON output from agy.
        let fake_output = r#"{"score": 4, "reason": "highly relevant"}"#;
        let cleaned = strip_code_fences(fake_output.trim());
        let parsed: serde_json::Value = serde_json::from_str(cleaned).unwrap();
        assert_eq!(parsed["score"], 4);
        assert!(parsed["reason"].as_str().unwrap().contains("relevant"));
    }

    // ── resolve_claude_binary ─────────────────────────────────────────

    #[test]
    fn test_resolve_claude_binary_does_not_panic() {
        if let Some(path) = resolve_claude_binary() {
            assert!(path.is_absolute());
        }
        // None is acceptable in CI environments without claude installed
    }

    // ── strip_code_fences ────────────────────────────────────────────

    #[test]
    fn test_strip_code_fences_json_fence() {
        let input = "```json\n{\"score\": 3}\n```";
        assert_eq!(strip_code_fences(input), "{\"score\": 3}");
    }

    #[test]
    fn test_strip_code_fences_plain_fence() {
        let input = "```\n{\"score\": 3}\n```";
        assert_eq!(strip_code_fences(input), "{\"score\": 3}");
    }

    #[test]
    fn test_strip_code_fences_no_fence_passthrough() {
        let input = "{\"score\": 3}";
        assert_eq!(strip_code_fences(input), "{\"score\": 3}");
    }

    #[test]
    fn test_strip_code_fences_trims_whitespace() {
        let input = "```json\n  {\"score\": 3}  \n```";
        assert_eq!(strip_code_fences(input), "{\"score\": 3}");
    }

    #[test]
    fn test_strip_code_fences_parses_to_valid_json() {
        let input = "```json\n{\"score\": 4, \"reason\": \"relevant\"}\n```";
        let cleaned = strip_code_fences(input);
        let parsed: serde_json::Value = serde_json::from_str(cleaned).unwrap();
        assert_eq!(parsed["score"], 4);
    }

    // ── call_claude_text envelope parsing ─────────────────────────────

    /// call_claude_text must extract the `result` field from the CLI envelope
    /// and return it as a plain String — without attempting JSON parsing of the body.
    #[test]
    fn test_call_claude_text_envelope_extraction() {
        // Simulate what call_claude_text does with a CLI envelope containing prose.
        let envelope = "{\"type\":\"result\",\"result\":\"## Harness Engineering\\n\\nThis is markdown prose.\",\"cost_usd\":0.001}";
        let raw: serde_json::Value = serde_json::from_str(envelope).unwrap();
        let result = raw
            .get("result")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_default();
        assert_eq!(result, "## Harness Engineering\n\nThis is markdown prose.");
        // Crucially: serde_json::from_str on this result would fail (it's not JSON),
        // but call_claude_text never attempts that parse.
        assert!(serde_json::from_str::<serde_json::Value>(&result).is_err());
    }

    #[test]
    fn test_call_claude_text_envelope_missing_result_falls_back_to_stdout() {
        // If the envelope has no `result` field, fall back to raw stdout.
        let envelope = r#"{"type":"error","error":"something went wrong"}"#;
        let raw: serde_json::Value = serde_json::from_str(envelope).unwrap();
        let result = raw
            .get("result")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .unwrap_or_else(|| envelope.trim().to_string());
        assert_eq!(result, envelope.trim());
    }

    // ── extract_result_from_envelope ─────────────────────────────────

    #[test]
    fn test_extract_envelope_legacy_single_object() {
        let env = serde_json::json!({
            "type": "result",
            "result": "hello from model",
            "cost_usd": 0.001
        });
        assert_eq!(
            extract_result_from_envelope(&env),
            Some("hello from model".to_string())
        );
    }

    #[test]
    fn test_extract_envelope_array_stream() {
        let env = serde_json::json!([
            {"type": "system", "subtype": "init"},
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "thinking..."}]}},
            {"type": "result", "result": "array stream result", "cost_usd": 0.002}
        ]);
        assert_eq!(
            extract_result_from_envelope(&env),
            Some("array stream result".to_string())
        );
    }

    #[test]
    fn test_extract_envelope_array_stream_result_not_first() {
        let env = serde_json::json!([
            {"type": "system"},
            {"type": "result", "result": "found it"}
        ]);
        assert_eq!(
            extract_result_from_envelope(&env),
            Some("found it".to_string())
        );
    }

    #[test]
    fn test_extract_envelope_no_result_returns_none() {
        let env = serde_json::json!({"type": "error", "error": "something went wrong"});
        assert_eq!(extract_result_from_envelope(&env), None);
    }

    #[test]
    fn test_extract_envelope_empty_array_returns_none() {
        let env = serde_json::json!([]);
        assert_eq!(extract_result_from_envelope(&env), None);
    }

    #[test]
    fn test_extract_envelope_array_without_result_type_returns_none() {
        let env = serde_json::json!([
            {"type": "system"},
            {"type": "assistant", "message": {}}
        ]);
        assert_eq!(extract_result_from_envelope(&env), None);
    }

    // ── extract_urls_from_text ────────────────────────────────────────────

    #[test]
    fn test_extract_urls_basic() {
        let text = "check this out https://example.com and also http://other.org/path";
        let urls = extract_urls_from_text(text);
        assert_eq!(urls, vec!["https://example.com", "http://other.org/path"]);
    }

    #[test]
    fn test_extract_urls_deduplicates() {
        let text = "https://example.com foo https://example.com bar";
        let urls = extract_urls_from_text(text);
        assert_eq!(urls.len(), 1);
        assert_eq!(urls[0], "https://example.com");
    }

    #[test]
    fn test_extract_urls_strips_trailing_punctuation() {
        let text = "see https://example.com, and https://other.org.";
        let urls = extract_urls_from_text(text);
        assert_eq!(urls[0], "https://example.com");
        assert_eq!(urls[1], "https://other.org");
    }

    #[test]
    fn test_extract_urls_wa_dump_format() {
        let text = "[2026-05-24, 10:31] User: interesting https://github.com/foo/bar #agents\n[2026-05-24, 10:32] User: also https://arxiv.org/abs/1234";
        let urls = extract_urls_from_text(text);
        assert_eq!(urls, vec!["https://github.com/foo/bar", "https://arxiv.org/abs/1234"]);
    }

    #[test]
    fn test_extract_urls_empty_text() {
        assert_eq!(extract_urls_from_text("no urls here"), vec![] as Vec<String>);
    }

    #[test]
    fn test_extract_urls_preserves_query_string() {
        let text = "https://example.com/path?q=1&foo=bar rest";
        let urls = extract_urls_from_text(text);
        assert_eq!(urls[0], "https://example.com/path?q=1&foo=bar");
    }

    // ── classify_platform ─────────────────────────────────────────────────

    #[test]
    fn test_classify_platform_linkedin() {
        assert_eq!(classify_platform("https://www.linkedin.com/posts/foo"), "linkedin");
    }

    #[test]
    fn test_classify_platform_github() {
        assert_eq!(classify_platform("https://github.com/foo/bar"), "github");
    }

    #[test]
    fn test_classify_platform_substack() {
        assert_eq!(classify_platform("https://foo.substack.com/p/article"), "substack");
    }

    #[test]
    fn test_classify_platform_arxiv() {
        assert_eq!(classify_platform("https://arxiv.org/abs/2401.1234"), "arxiv");
    }

    #[test]
    fn test_classify_platform_other() {
        assert_eq!(classify_platform("https://example.com/article"), "other");
    }

    // ── ingest_urls ───────────────────────────────────────────────────────

    #[test]
    fn test_ingest_urls_adds_to_state() {
        let mut state = PipelineState::default();
        let urls = vec!["https://github.com/foo/bar".to_string()];
        let result = ingest_urls(&urls, None, &mut state);
        assert_eq!(result.queued, 1);
        assert_eq!(result.duplicates, 0);
        assert!(state.urls.contains_key("https://github.com/foo/bar"));
        assert_eq!(state.urls["https://github.com/foo/bar"].status, UrlStatus::Unprocessed);
    }

    #[test]
    fn test_ingest_urls_skips_duplicates() {
        let mut state = PipelineState::default();
        let urls = vec!["https://github.com/foo/bar".to_string()];
        ingest_urls(&urls, None, &mut state);
        let result = ingest_urls(&urls, None, &mut state);
        assert_eq!(result.queued, 0);
        assert_eq!(result.duplicates, 1);
        assert_eq!(state.urls.len(), 1);
    }

    #[test]
    fn test_ingest_urls_platform_tagged() {
        let mut state = PipelineState::default();
        let urls = vec![
            "https://github.com/foo".to_string(),
            "https://arxiv.org/abs/123".to_string(),
            "https://randomsite.io/article".to_string(),
        ];
        ingest_urls(&urls, None, &mut state);
        assert_eq!(state.urls["https://github.com/foo"].platform.as_deref(), Some("github"));
        assert_eq!(state.urls["https://arxiv.org/abs/123"].platform.as_deref(), Some("arxiv"));
        assert_eq!(state.urls["https://randomsite.io/article"].platform.as_deref(), Some("other"));
    }

    #[test]
    fn test_ingest_urls_linkedin_author_extracted() {
        let mut state = PipelineState::default();
        let url = "https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-share-7437448165403852801-F5RX";
        ingest_urls(&[url.to_string()], None, &mut state);
        let entry = &state.urls[url];
        assert_eq!(entry.author.as_deref(), Some("walid-boulanouar"));
        assert_eq!(entry.platform.as_deref(), Some("linkedin"));
    }

    #[test]
    fn test_ingest_urls_non_linkedin_fallback_signals() {
        let mut state = PipelineState::default();
        let url = "https://github.com/anthropics/claude-code";
        ingest_urls(&[url.to_string()], None, &mut state);
        let entry = &state.urls[url];
        assert_eq!(entry.author.as_deref(), Some("github"));
        assert!(entry.title_signal.is_some());
    }

    #[test]
    fn test_ingest_urls_source_tag_stored() {
        let mut state = PipelineState::default();
        let urls = vec!["https://example.com".to_string()];
        ingest_urls(&urls, Some("telegram"), &mut state);
        assert_eq!(state.urls["https://example.com"].source.as_deref(), Some("telegram"));
    }

    #[test]
    fn test_ingest_urls_skips_already_processed() {
        let mut state = PipelineState::default();
        let url = "https://example.com".to_string();
        // Pre-populate as Tier1Passed (already through pipeline)
        state.urls.insert(url.clone(), UrlEntry {
            status: UrlStatus::Tier1Passed,
            tier1_score: Some(4),
            ..UrlEntry::new_unprocessed(None)
        });
        let result = ingest_urls(&[url], None, &mut state);
        assert_eq!(result.queued, 0);
        assert_eq!(result.duplicates, 1);
    }

    // ── append_event_log_entry_at ─────────────────────────────────────────

    #[test]
    fn append_event_log_creates_new_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("event-log.md");
        append_event_log_entry_at(&path, "2026-05-31", "14:00", "https://example.com", &[]).unwrap();
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("# Event Log"));
        assert!(content.contains("## 2026-05-31"));
        assert!(content.contains("- 14:00 \u{2014} https://example.com"));
    }

    #[test]
    fn append_event_log_adds_tags() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("event-log.md");
        append_event_log_entry_at(&path, "2026-05-31", "14:00", "https://example.com", &["ai", "rust"]).unwrap();
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("#ai #rust"), "tags should appear as #tag format");
    }

    #[test]
    fn append_event_log_appends_to_existing_date_section() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("event-log.md");
        // Write initial entry
        append_event_log_entry_at(&path, "2026-05-31", "10:00", "https://first.com", &[]).unwrap();
        // Append second entry on same date
        append_event_log_entry_at(&path, "2026-05-31", "11:00", "https://second.com", &[]).unwrap();
        let content = std::fs::read_to_string(&path).unwrap();
        // Date header appears exactly once
        assert_eq!(content.matches("## 2026-05-31").count(), 1);
        assert!(content.contains("https://first.com"));
        assert!(content.contains("https://second.com"));
        // Second entry appears after first
        let first_pos = content.find("https://first.com").unwrap();
        let second_pos = content.find("https://second.com").unwrap();
        assert!(second_pos > first_pos);
    }

    #[test]
    fn append_event_log_adds_new_date_section() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("event-log.md");
        append_event_log_entry_at(&path, "2026-05-30", "10:00", "https://yesterday.com", &[]).unwrap();
        append_event_log_entry_at(&path, "2026-05-31", "10:00", "https://today.com", &[]).unwrap();
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("## 2026-05-30"));
        assert!(content.contains("## 2026-05-31"));
        assert!(content.contains("https://yesterday.com"));
        assert!(content.contains("https://today.com"));
    }

    // ── semantic dedup output parsing (t-1668) ───────────────────────

    #[test]
    fn test_parse_semantic_dedup_found_results_returns_true() {
        let output = "[INFO] Searching: \"MCP tutorial\" (semantic)\n\n  Search time: 758ms\n\n+---+-------+\n| Key | Score |\n+---+-------+\n| k1 |  0.91 |\n+---+-------+\n\n[INFO] Found 1 results\n";
        assert!(parse_semantic_dedup_output(output));
    }

    #[test]
    fn test_parse_semantic_dedup_found_zero_returns_false() {
        let output = "[INFO] Searching: \"novel topic\" (semantic)\n\n  Search time: 123ms\n\n[INFO] Found 0 results\n";
        assert!(!parse_semantic_dedup_output(output));
    }

    #[test]
    fn test_parse_semantic_dedup_empty_output_returns_false() {
        assert!(!parse_semantic_dedup_output(""));
    }

    #[test]
    fn test_parse_semantic_dedup_error_output_returns_false() {
        assert!(!parse_semantic_dedup_output("Error: connection refused\n"));
    }

    #[test]
    fn test_resolve_ruflo_binary_does_not_panic() {
        // None is acceptable in environments where ruflo is not installed.
        let _ = crate::ruflo::resolve_ruflo_binary();
    }

}