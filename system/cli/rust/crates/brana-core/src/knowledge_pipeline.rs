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
    let mut cmd = std::process::Command::new("git");
    crate::util::scrub_git_env(&mut cmd);
    if let Ok(out) = cmd.args(["rev-parse", "--show-toplevel"]).output() {
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
/// Returns one of: `"linkedin"`, `"github"`, `"substack"`, `"arxiv"`,
/// `"youtube"`, `"other"`.
pub fn classify_platform(url: &str) -> &'static str {
    if url.contains("linkedin.com") {
        "linkedin"
    } else if url.contains("github.com") {
        "github"
    } else if url.contains("substack.com") {
        "substack"
    } else if url.contains("arxiv.org") {
        "arxiv"
    } else if url.contains("youtube.com") || url.contains("youtu.be") {
        "youtube"
    } else {
        "other"
    }
}

/// Result of a URL content fetch (ADR-070 three-tier fetch mechanism).
///
/// `caption_source` is `Some("manual"|"auto")` only for `platform ==
/// "youtube"` (feature spec §3's `caption_source` tag) — `None` for every
/// other platform.
#[derive(Debug, Clone, PartialEq)]
pub struct FetchedContent {
    pub text: String,
    pub platform: &'static str,
    pub caption_source: Option<YoutubeCaptionSource>,
    /// The post's image URL (ld+json `image.url`), LinkedIn-only,
    /// best-effort metadata (t-3187). The image itself is never fetched or
    /// OCR'd. `None` for every other platform, and for LinkedIn posts whose
    /// ld+json carried no image.
    pub image_url: Option<String>,
}

/// Fetch a URL's content via the tier appropriate to its platform: `ureq`
/// for public URLs, a headless `claude -p --mcp-config` shell-out to
/// `linkedin-scraper-mcp` for LinkedIn, `yt-dlp` for YouTube.
///
/// Returns `Ok(None)` — distinct from `Err` — when a LinkedIn post could
/// not be found in the author's fetched feed (ADR-070 §Tier-2 correction:
/// `linkedin-scraper-mcp` has no arbitrary-URL fetch tool, only a fuzzy
/// author-feed match), or when a YouTube video has no captions in the
/// requested language (feature spec §2's no-captions contract). Public
/// URLs never produce `Ok(None)`: they either fetch or error.
///
/// Never acquires [`lock_pipeline`] — this function is shared with a future
/// t-1144 for populating `UrlEntry.fetched_content` inside the pipeline's
/// locked `process_core` call graph, so it must stay lock-free itself
/// (ADR-070 §Lock discipline; see `test_lock_discipline_source_tripwires`
/// in `brana-cli/src/commands/knowledge.rs` and its brana-core companion
/// below).
pub fn fetch_url_content(url: &str) -> Result<Option<FetchedContent>> {
    fetch_url_content_with(url, &YtDlpCookies::None)
}

/// [`fetch_url_content`] with an explicit yt-dlp cookie/auth choice
/// (t-3033, feature spec §7). Only the youtube tier reads `cookies`;
/// every other platform ignores it. Same lock-free contract.
pub fn fetch_url_content_with(url: &str, cookies: &YtDlpCookies) -> Result<Option<FetchedContent>> {
    // /safety/go wrappers unwrap BEFORE platform routing — the wrapped
    // target is often not LinkedIn at all (t-2589).
    let unwrapped = unwrap_linkedin_safety_url(url);
    let url = unwrapped.as_str();
    let platform = classify_platform(url);
    if platform == "linkedin" {
        return Ok(fetch_linkedin_content(url)?.map(|(text, image_url)| FetchedContent {
            text,
            platform,
            caption_source: None,
            image_url,
        }));
    }
    if platform == "youtube" {
        return Ok(fetch_youtube_content(url, cookies)?.map(|(text, source)| FetchedContent {
            text,
            platform,
            caption_source: Some(source),
            image_url: None,
        }));
    }
    let text = fetch_public_url(url)?;
    Ok(Some(FetchedContent { text, platform, caption_source: None, image_url: None }))
}

/// Timeout for one LinkedIn MCP `tools/call`, measured rather than guessed:
/// a real `get_person_profile(sections="posts")` took **28.8s** end to end
/// on 2026-07-31 (t-2568, unsandboxed), against a server-side tool timeout
/// of 90s (`linkedin_mcp_server` `TOOL_TIMEOUT_SECONDS`). 120s leaves room
/// for a slow scrape and still bounds a genuine hang at a fifth of the old
/// budget.
///
/// The previous 240s was set for a `claude -p` shell-out that no longer
/// exists (ADR-070 §Amendment). That figure was never a latency
/// measurement — every fetch hit it exactly, because the parent deadlocked
/// on an undrained pipe rather than because anything took four minutes.
const LINKEDIN_MCP_TIMEOUT_SECS: u64 = 120;

/// Per-stream cap on child output quoted into a timeout error. A hung MCP
/// server can emit megabytes; an unbounded error is unreadable in a log and
/// useless in a scheduler notification.
const TIMEOUT_TAIL_CHARS: usize = 800;

/// Build the error text for a child killed before it finished, preserving
/// whatever it managed to write.
///
/// Pure so the truncation and the empty case are testable without spawning
/// anything. The empty case is reported explicitly: a child that wrote
/// *nothing* before the kill indicates a different fault than one that
/// errored loudly, and a blank tail would read as the latter.
///
/// `headline` is the whole first line, caller-owned. A deadline and a
/// server that closed its output early both end in "no response", but they
/// are different faults and must not be described in the same words.
fn subprocess_diagnostic(headline: &str, stdout: &str, stderr: &str) -> String {
    fn tail(s: &str) -> Option<String> {
        let t = s.trim();
        if t.is_empty() {
            return None;
        }
        let chars: Vec<char> = t.chars().collect();
        if chars.len() <= TIMEOUT_TAIL_CHARS {
            return Some(t.to_string());
        }
        let start = chars.len() - TIMEOUT_TAIL_CHARS;
        Some(format!(
            "…(truncated, showing last {TIMEOUT_TAIL_CHARS} of {} chars) {}",
            chars.len(),
            chars[start..].iter().collect::<String>()
        ))
    }

    let mut msg = headline.to_string();
    match (tail(stdout), tail(stderr)) {
        (None, None) => msg.push_str(" — child produced no output before it was killed"),
        (out, err) => {
            if let Some(e) = err {
                msg.push_str(&format!("\n  child stderr: {e}"));
            }
            if let Some(o) = out {
                msg.push_str(&format!("\n  child stdout: {o}"));
            }
        }
    }
    msg
}

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

/// JSON-RPC ids for the two requests this client makes, in order. Fixed
/// rather than generated: one `initialize`, then one `tools/call`, per
/// server process.
const MCP_INIT_ID: u64 = 1;
const MCP_CALL_ID: u64 = 2;

/// How long to let an MCP server exit on its own after stdin closes before
/// killing it. Measured at 0.4s (t-2568); 5s is generous headroom for a
/// server tearing down a headless browser.
const MCP_SHUTDOWN_GRACE_SECS: u64 = 5;

/// Interpret one line of an MCP server's stdout while waiting for the
/// response to `want_id`.
///
/// Pure, so the framing rules are testable without spawning a server:
/// - `Ok(Some(result))` — this line is the awaited response; here is its
///   `result` object.
/// - `Ok(None)` — not the awaited response: a notification, a reply to an
///   earlier id, a log banner, a blank line. Keep reading.
/// - `Err` — a JSON-RPC error object *for the awaited id*. Fail now rather
///   than block until the deadline waiting for a reply that will never come.
fn parse_jsonrpc_message(line: &str, want_id: u64) -> Result<Option<serde_json::Value>> {
    let Ok(msg) = serde_json::from_str::<serde_json::Value>(line.trim()) else {
        return Ok(None);
    };
    if msg.get("id").and_then(|v| v.as_u64()) != Some(want_id) {
        return Ok(None);
    }
    if let Some(err) = msg.get("error") {
        let code = err.get("code").and_then(|v| v.as_i64()).unwrap_or(0);
        let message = err
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("no message");
        bail!("MCP server returned error {code}: {message}");
    }
    Ok(Some(
        msg.get("result").cloned().unwrap_or(serde_json::Value::Null),
    ))
}

/// Pull the `posts` section out of a `get_person_profile` tool result.
///
/// Three outcomes, deliberately distinct — they are what feed the
/// `Ok(None)`-vs-`Err` split that [`resolve_linkedin_fetch`] documents:
/// - `sections.posts` present → the raw feed text.
/// - `sections` present, `posts` absent → an **empty feed**, not an error.
///   The tool documents that a section "may be absent if extraction yielded
///   no content for that page" — an author with no visible posts.
/// - anything else — no `structuredContent`/`sections`, a non-string
///   `posts`, or `isError` — → `Err`. A changed or failed tool output is a
///   failure, never evidence that the post is absent.
fn extract_posts_section(result: &serde_json::Value) -> Result<String> {
    if result.get("isError").and_then(|v| v.as_bool()) == Some(true) {
        // The server reports tool-level failure in band, on an otherwise
        // well-formed response. Reading past it would turn a failed scrape
        // into "this author has no posts".
        let detail = result
            .get("content")
            .and_then(|c| c.as_array())
            .and_then(|a| a.first())
            .and_then(|c| c.get("text"))
            .and_then(|t| t.as_str())
            .unwrap_or("no detail");
        bail!("linkedin-scraper-mcp reported a tool error: {detail}");
    }

    let sections = result
        .get("structuredContent")
        .and_then(|s| s.get("sections"))
        .and_then(|s| s.as_object())
        .ok_or_else(|| {
            anyhow::anyhow!(
                "unexpected get_person_profile result shape — \
                 no structuredContent.sections: {result}"
            )
        })?;

    match sections.get("posts") {
        None => Ok(String::new()),
        Some(v) => v
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| anyhow::anyhow!("structuredContent.sections.posts is not a string: {v}")),
    }
}

/// Process-wide counter disambiguating temp stderr-log filenames. PID alone
/// is not enough: batch mode calls [`mcp_call_tool`] once per URL from
/// within the *same* process, so two calls sharing a PID would collide on
/// one path — and one call's `Drop` could delete another's still-open log.
static MCP_STDERR_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// RAII guard for an MCP server's stderr log — removed on drop, including
/// on early `?` returns, so an erroring call never leaves the file behind.
///
/// A plain temp file rather than the `tempfile` crate: `tempfile` is a
/// dev-dependency across this workspace, and a stderr sink is not worth
/// promoting it to a runtime one.
struct ScopedStderrLog {
    path: PathBuf,
}

impl Drop for ScopedStderrLog {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

impl ScopedStderrLog {
    /// Returns the guard alongside an open handle to hand to `Stdio::from`.
    fn create() -> Result<(Self, std::fs::File)> {
        let n = MCP_STDERR_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("brana-mcp-stderr-{}-{n}.log", std::process::id()));
        let file = std::fs::File::create(&path)
            .with_context(|| format!("creating MCP stderr log at {}", path.display()))?;
        Ok((Self { path }, file))
    }
}

/// Write one JSON-RPC message, newline-delimited, to a server's stdin.
fn mcp_send(stdin: &mut std::process::ChildStdin, msg: &serde_json::Value) -> Result<()> {
    use std::io::Write as _;
    stdin.write_all(msg.to_string().as_bytes())?;
    stdin.write_all(b"\n")?;
    stdin.flush()?;
    Ok(())
}

/// Read lines until the response to `want_id` arrives or `deadline` passes.
///
/// `Ok(None)` means the deadline was hit — the caller owns that diagnosis,
/// because only it can kill the child and quote its stderr.
fn mcp_await(
    rx: &std::sync::mpsc::Receiver<String>,
    want_id: u64,
    deadline: std::time::Instant,
) -> Result<Option<serde_json::Value>> {
    loop {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        if remaining.is_zero() {
            return Ok(None);
        }
        match rx.recv_timeout(remaining) {
            Ok(line) => {
                if let Some(result) = parse_jsonrpc_message(&line, want_id)? {
                    return Ok(Some(result));
                }
                // Not ours — a notification, the initialize reply, or a log
                // line. Keep reading.
            }
            // Timeout, or the reader thread ended because the server closed
            // stdout without answering. Both are "no response in budget".
            Err(_) => return Ok(None),
        }
    }
}

/// Call one tool on a stdio MCP server, speaking JSON-RPC 2.0 directly.
///
/// `linkedin-scraper-mcp` is a local stdio MCP server, so being its client
/// is three writes and one read. Routing that through `claude -p` instead
/// cost a model round-trip (98s against a measured 28.8s here), a
/// per-invocation API charge, and — fatally — pushed a ~50 KB tool result
/// through a context window too small to hold it, so the payload came back
/// as prose *about* the data rather than the data (ADR-070 §Amendment,
/// t-2568).
///
/// Never acquires [`lock_pipeline`] — see [`fetch_url_content`]'s note.
fn mcp_call_tool(
    binary: &std::path::Path,
    tool: &str,
    arguments: serde_json::Value,
    timeout: std::time::Duration,
) -> Result<serde_json::Value> {
    use std::io::BufRead as _;

    // stderr goes to a file, not a pipe. The server logs banners and status
    // lines there, and an unread pipe that fills would block it forever —
    // precisely the deadlock that made this path look like a 240s hang
    // (t-2568). A file has no such limit and needs no drain thread.
    let (stderr_log, stderr_file) = ScopedStderrLog::create()?;

    let mut child = std::process::Command::new(binary)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::from(stderr_file))
        .spawn()
        .with_context(|| format!("spawning MCP server {}", binary.display()))?;

    let mut stdin = child.stdin.take().context("MCP server stdin not piped")?;
    let stdout = child.stdout.take().context("MCP server stdout not piped")?;

    // Read on a thread and hand lines over a channel: `recv_timeout` is what
    // bounds this call. On timeout the child is killed and we walk away
    // WITHOUT joining — a grandchild (the server's headless Chromium) can
    // hold the pipe's write end open long after its parent dies, so a join
    // would block for as long as that grandchild lives. That mistake turned
    // a 2s timeout into a 60s stall once already (t-2568).
    let (tx, rx) = std::sync::mpsc::channel::<String>();
    std::thread::spawn(move || {
        for line in std::io::BufReader::new(stdout).lines().map_while(Result::ok) {
            if tx.send(line).is_err() {
                break;
            }
        }
    });

    let started = std::time::Instant::now();
    let deadline = started + timeout;
    let exchange = (|| -> Result<Option<serde_json::Value>> {
        mcp_send(
            &mut stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": MCP_INIT_ID,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "brana", "version": env!("CARGO_PKG_VERSION")}
                }
            }),
        )?;
        if mcp_await(&rx, MCP_INIT_ID, deadline)?.is_none() {
            return Ok(None);
        }
        mcp_send(
            &mut stdin,
            &serde_json::json!({"jsonrpc": "2.0", "method": "notifications/initialized"}),
        )?;
        mcp_send(
            &mut stdin,
            &serde_json::json!({
                "jsonrpc": "2.0",
                "id": MCP_CALL_ID,
                "method": "tools/call",
                "params": {"name": tool, "arguments": arguments}
            }),
        )?;
        mcp_await(&rx, MCP_CALL_ID, deadline)
    })();

    let stderr_tail = || std::fs::read_to_string(&stderr_log.path).unwrap_or_default();

    match exchange {
        Ok(Some(result)) => {
            // Closing stdin is the server's shutdown signal; it exits on EOF
            // (measured rc=0 in 0.4s). Poll for that rather than killing
            // outright, so the server gets to close its browser session.
            drop(stdin);
            let grace = std::time::Instant::now()
                + std::time::Duration::from_secs(MCP_SHUTDOWN_GRACE_SECS);
            loop {
                match child.try_wait() {
                    Ok(Some(_)) | Err(_) => break,
                    Ok(None) if std::time::Instant::now() >= grace => {
                        let _ = child.kill();
                        let _ = child.wait();
                        break;
                    }
                    Ok(None) => std::thread::sleep(std::time::Duration::from_millis(50)),
                }
            }
            Ok(result)
        }
        Ok(None) => {
            let _ = child.kill();
            let _ = child.wait();
            // Distinguish a real deadline from a server that closed stdout
            // without answering. Both leave us with no response, but they
            // are different faults, and reporting "timed out after 120s"
            // one second in would be exactly the kind of lying diagnostic
            // that made this bug take four attempts to find (t-2568).
            let elapsed = started.elapsed();
            if elapsed >= timeout {
                bail!(
                    "{}",
                    subprocess_diagnostic(
                        &format!("linkedin MCP {tool} timed out after {}s", timeout.as_secs()),
                        "",
                        &stderr_tail(),
                    )
                );
            }
            bail!(
                "{}",
                subprocess_diagnostic(
                    &format!(
                        "linkedin MCP {tool}: server closed its output after {}s without \
                         answering",
                        elapsed.as_secs()
                    ),
                    "",
                    &stderr_tail(),
                )
            );
        }
        Err(e) => {
            let _ = child.kill();
            let _ = child.wait();
            Err(e)
        }
    }
}

/// Minimum public-extract length (chars) considered a usable post body.
/// Calibrated from the t-2589 spike: 14/15 pending links returned ≥200
/// chars publicly; the single sub-200 result was a genuinely thin post.
const LINKEDIN_PUBLIC_MIN_CHARS: usize = 200;

/// User-Agent for the public LinkedIn GET. The t-2589 spike (14/15 usable,
/// 0 blocks over 12 rapid requests) was measured with curl's default UA —
/// keep parity with what was validated rather than introducing an
/// unmeasured identity.
const LINKEDIN_PUBLIC_UA: &str = "curl/8.5.0";

/// Hard bounds on every public HTTP fetch. The fetch target can be
/// attacker-influenced (unwrapped /safety/go params, user-logged URLs), so
/// an unbounded request is a resource-exhaustion primitive against the
/// unattended pipeline (t-2589 challenger finding). 30s covers slow public
/// pages (the LinkedIn extract measures ~1s); 10 MB covers heavyweight
/// article pages while bounding a hostile endless stream.
const PUBLIC_FETCH_TIMEOUT_SECS: u64 = 30;
const PUBLIC_FETCH_MAX_BYTES: u64 = 10 * 1024 * 1024;

/// LinkedIn fetch — public extract primary, authenticated scrape fallback
/// (ADR-070 second §Amendment, t-2589).
///
/// Every post URL serves its body unauthenticated, above the authwall, in
/// `application/ld+json` `articleBody` + `og:description` (LinkedIn must
/// serve link previews). One HTTP GET at ~0.8s replaces a ~30-60s
/// authenticated feed scrape for the common case; the tier-2 MCP client
/// (t-2568) runs only when the public extract is below
/// [`LINKEDIN_PUBLIC_MIN_CHARS`].
///
/// Returns `(text, image_url)` — `image_url` is best-effort metadata from
/// the public extract's ld+json `image.url` (t-3187), carried alongside
/// whichever text source (public or tier-2) the tiered decision below
/// picked; tier-2 (the MCP scrape) never supplies an image URL. The tiered
/// decision itself is untouched — `image_url` rides beside it, it does not
/// participate in it.
fn fetch_linkedin_content(url: &str) -> Result<Option<(String, Option<String>)>> {
    let public = fetch_linkedin_public_extract(url);
    let (public_text, image_url): (Result<Option<String>>, Option<String>) = match public {
        Ok(Some((text, image_url))) => (Ok(Some(text)), image_url),
        Ok(None) => (Ok(None), None),
        Err(e) => (Err(e), None),
    };

    let text = resolve_tiered_linkedin_fetch(public_text, || {
        let (author, title_signal) =
            parse_linkedin_url(url).unwrap_or_else(|| url_fallback_signals(url));

        let binary = resolve_linkedin_scraper_binary().ok_or_else(|| {
            anyhow::anyhow!(
                "linkedin-scraper-mcp binary not found — install with: uv tool install linkedin-scraper-mcp"
            )
        })?;
        check_linkedin_session(&binary)?;

        let feed = mcp_call_tool(
            &binary,
            "get_person_profile",
            serde_json::json!({"linkedin_username": author, "sections": "posts"}),
            std::time::Duration::from_secs(LINKEDIN_MCP_TIMEOUT_SECS),
        )
        .and_then(|result| extract_posts_section(&result));

        resolve_linkedin_fetch(feed, &title_signal)
    })?;

    Ok(text.map(|t| (t, image_url)))
}

/// Decide the tiered LinkedIn fetch outcome from the public-extract result,
/// invoking `tier2` only when the public path is insufficient.
///
/// Injectable core (same convention as [`resolve_linkedin_fetch`] and
/// `resolve_extraction`): the laziness of `tier2` is the tested contract —
/// a sufficient public extract must never spawn the MCP client.
///
/// Outcome table (public × tier-2):
/// - public ≥ threshold → returned; tier-2 not invoked.
/// - thin/absent public → tier-2 runs; the **longer** non-empty text wins
///   (each source is individually incomplete — og beat articleBody on 2 of
///   15 spiked posts, and a thin public beat a tier-2 miss on 1).
/// - both empty/miss → `Ok(None)` (a real miss).
/// - tier-2 error with a non-empty thin public → the thin public is
///   salvaged (real content beats a broken enrichment path).
/// - nothing salvageable and either path broke → `Err` (never degraded to
///   a miss).
fn resolve_tiered_linkedin_fetch(
    public: Result<Option<String>>,
    tier2: impl FnOnce() -> Result<Option<String>>,
) -> Result<Option<String>> {
    let (thin, public_err) = match public {
        Ok(Some(text)) => {
            if text.chars().count() >= LINKEDIN_PUBLIC_MIN_CHARS {
                return Ok(Some(text));
            }
            if text.trim().is_empty() { (None, None) } else { (Some(text), None) }
        }
        Ok(None) => (None, None),
        Err(e) => (None, Some(e)),
    };

    match tier2() {
        Ok(Some(t2)) => Ok(Some(match thin {
            Some(p) if p.chars().count() > t2.chars().count() => p,
            _ => t2,
        })),
        Ok(None) => match (thin, public_err) {
            (Some(p), _) => Ok(Some(p)),
            (None, Some(e)) => {
                Err(e.context("public LinkedIn extract failed and tier-2 found no match"))
            }
            (None, None) => Ok(None),
        },
        Err(t2_err) => match thin {
            Some(p) => {
                // Salvage real content, but keep tier-2 failures loud —
                // a dying session must stay visible in the run log even
                // when the public path papers over it (t-2589 challenger
                // finding; ADR-070 fail-loud-on-expired-session rule).
                eprintln!(
                    "  tier-2 LinkedIn fetch failed ({t2_err:#}); salvaging thin public \
                     extract ({} chars)",
                    p.chars().count()
                );
                Ok(Some(p))
            }
            None => Err(t2_err),
        },
    }
}

/// GET the post URL and extract its public preview text plus, best-effort,
/// its ld+json `image.url` (t-3187 — the image itself is never fetched or
/// OCR'd).
///
/// - `Ok(Some((text, image_url)))` — extracted (any length; the caller
///   applies the usability threshold). `image_url` is `None` when the
///   ld+json carried no image.
/// - `Ok(None)` — the page answered but carries no post body (deleted post,
///   authwall-only markup, or an HTTP status error such as 404/999 — status
///   errors are "no public content", not transport failures, so the tier-2
///   fallback still gets its chance).
/// - `Err` — transport failure (DNS, connect, read).
fn fetch_linkedin_public_extract(url: &str) -> Result<Option<(String, Option<String>)>> {
    let response = match ureq::get(url)
        .config()
        .timeout_global(Some(std::time::Duration::from_secs(PUBLIC_FETCH_TIMEOUT_SECS)))
        .build()
        .header("User-Agent", LINKEDIN_PUBLIC_UA)
        .call()
    {
        Ok(r) => r,
        Err(ureq::Error::StatusCode(_)) => return Ok(None),
        Err(e) => {
            return Err(anyhow::Error::from(e))
                .with_context(|| format!("public LinkedIn fetch failed: {url}"));
        }
    };
    let html = response
        .into_body()
        .with_config()
        .limit(PUBLIC_FETCH_MAX_BYTES)
        .read_to_string()
        .with_context(|| format!("failed to read public LinkedIn response body: {url}"))?;
    Ok(extract_linkedin_public_text(&html)
        .map(|text| (text, extract_linkedin_public_image_url(&html))))
}

/// Extract the post body from public LinkedIn HTML:
/// `max(ld+json articleBody, og:description)` by char count — never
/// `articleBody` alone (t-2589 spike: og wins outright on 2 of 15 posts;
/// each source is individually incomplete) — with ld+json `comment[]` text
/// appended, attributed by author name, post-author comments ordered first
/// (t-3187: surfaces the classic "link in first comment" pattern). Comments
/// are best-effort enrichment: absent/empty `comment[]`, or no ld+json at
/// all (LinkedIn's bot-shell), leaves the base text unchanged — never an
/// error, never a change to the underlying tiered-fetch decision.
fn extract_linkedin_public_text(html: &str) -> Option<String> {
    let mut candidates: Vec<String> = Vec::new();
    let mut comments: Vec<LinkedInComment> = Vec::new();
    for block in ld_json_blocks(html) {
        if let Ok(value) = serde_json::from_str::<serde_json::Value>(block) {
            collect_article_bodies(&value, &mut candidates);
            collect_linkedin_comments(&value, &mut comments);
        }
    }
    if let Some(og) = extract_meta_content(html, "og:description") {
        candidates.push(decode_html_entities(&og));
    }
    let base = candidates
        .into_iter()
        .filter(|c| !c.trim().is_empty())
        .max_by_key(|c| c.chars().count())?;
    Some(match format_linkedin_comments(comments) {
        Some(block) => format!("{base}{block}"),
        None => base,
    })
}

/// One ld+json `comment[]` entry, attributed by author name when present.
/// `is_post_author` marks a comment whose author name matches the `author`
/// at the same JSON nesting level as the `comment` array — the post's own
/// author — so callers can surface the classic "link in first comment"
/// pattern first (t-3187).
#[derive(Debug, Clone, PartialEq)]
struct LinkedInComment {
    author: Option<String>,
    text: String,
    is_post_author: bool,
}

/// Collect every `comment[]` entry found anywhere in a JSON-LD value.
/// Mirrors [`collect_article_bodies`]'s `@graph` tolerance — LinkedIn nests
/// `comment` directly on the post object or under `@graph` depending on
/// post type. A comment missing `text`, or with blank `text`, is dropped;
/// a missing/unnamed `author` is kept with `author: None` (rendered
/// "(unknown)" by [`format_linkedin_comments`]) rather than dropped.
fn collect_linkedin_comments(value: &serde_json::Value, out: &mut Vec<LinkedInComment>) {
    match value {
        serde_json::Value::Object(map) => {
            if let Some(serde_json::Value::Array(items)) = map.get("comment") {
                let post_author = map.get("author").and_then(linkedin_json_author_name);
                for item in items {
                    let Some(text) = item.get("text").and_then(|v| v.as_str()) else { continue };
                    if text.trim().is_empty() {
                        continue;
                    }
                    let author = item.get("author").and_then(linkedin_json_author_name);
                    let is_post_author = matches!(
                        (&author, &post_author),
                        (Some(a), Some(p)) if a == p
                    );
                    out.push(LinkedInComment { author, text: text.to_string(), is_post_author });
                }
            }
            for val in map.values() {
                collect_linkedin_comments(val, out);
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_linkedin_comments(item, out);
            }
        }
        _ => {}
    }
}

/// The `name` of an author value — LinkedIn's ld+json represents an author
/// either as a bare string or as a `Person`/`Organization` object carrying
/// a `name` field.
fn linkedin_json_author_name(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::String(s) => Some(s.clone()),
        serde_json::Value::Object(map) => {
            map.get("name").and_then(|n| n.as_str()).map(str::to_string)
        }
        _ => None,
    }
}

/// Render collected comments into the block appended after the post body:
/// post-author comments first (their original relative order preserved via
/// a stable sort; same for the rest), each line `"{author}: {text}"` with
/// `"(unknown)"` standing in for a missing author name. `None` when there
/// is nothing to append — the caller must leave the base text untouched.
fn format_linkedin_comments(mut comments: Vec<LinkedInComment>) -> Option<String> {
    if comments.is_empty() {
        return None;
    }
    comments.sort_by_key(|c| !c.is_post_author);
    let mut block = String::from("\n\nComments:");
    for c in &comments {
        let author = c.author.as_deref().unwrap_or("(unknown)");
        block.push('\n');
        block.push_str(author);
        block.push_str(": ");
        block.push_str(&c.text);
    }
    Some(block)
}

/// The public post's `image.url` from ld+json, when present — best-effort
/// metadata surfaced alongside the body text (t-3187). The image itself is
/// never fetched or OCR'd; that is out of scope. `None` for a bot-shell
/// page with no ld+json, or ld+json carrying no `image` field.
fn extract_linkedin_public_image_url(html: &str) -> Option<String> {
    let mut urls = Vec::new();
    for block in ld_json_blocks(html) {
        if let Ok(value) = serde_json::from_str::<serde_json::Value>(block) {
            collect_linkedin_image_urls(&value, &mut urls);
        }
    }
    urls.into_iter().find(|u| !u.trim().is_empty())
}

/// Collect every `image.url` (or bare-string `image`) anywhere in a JSON-LD
/// value. Mirrors [`collect_article_bodies`]'s `@graph` tolerance.
fn collect_linkedin_image_urls(value: &serde_json::Value, out: &mut Vec<String>) {
    match value {
        serde_json::Value::Object(map) => {
            for (key, val) in map {
                if key == "image" {
                    match val {
                        serde_json::Value::Object(img) => {
                            if let Some(url) = img.get("url").and_then(|u| u.as_str()) {
                                out.push(url.to_string());
                            }
                        }
                        serde_json::Value::String(s) => out.push(s.clone()),
                        _ => {}
                    }
                } else {
                    collect_linkedin_image_urls(val, out);
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_linkedin_image_urls(item, out);
            }
        }
        _ => {}
    }
}

/// The raw contents of every `<script type="application/ld+json">` block.
/// Manual scan (regex-lite has no lazy quantifiers); a malformed block
/// without a closing `</script` is skipped rather than looping.
fn ld_json_blocks(html: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut rest = html;
    while let Some(marker) = rest.find("application/ld+json") {
        let after_marker = &rest[marker..];
        let Some(gt) = after_marker.find('>') else { break };
        let body = &after_marker[gt + 1..];
        match body.find("</script") {
            Some(end) => {
                out.push(&body[..end]);
                rest = &body[end..];
            }
            None => break,
        }
    }
    out
}

/// Collect every string-valued `articleBody` anywhere in a JSON-LD value —
/// LinkedIn nests it directly or under `@graph` depending on post type.
fn collect_article_bodies(value: &serde_json::Value, out: &mut Vec<String>) {
    match value {
        serde_json::Value::Object(map) => {
            for (key, val) in map {
                if key == "articleBody" {
                    if let Some(s) = val.as_str() {
                        out.push(s.to_string());
                    }
                } else {
                    collect_article_bodies(val, out);
                }
            }
        }
        serde_json::Value::Array(items) => {
            for item in items {
                collect_article_bodies(item, out);
            }
        }
        _ => {}
    }
}

/// The `content` attribute of the `<meta>` tag carrying `property_name`.
/// Attribute order is not assumed; both quote styles are accepted.
fn extract_meta_content(html: &str, property_name: &str) -> Option<String> {
    let mut rest = html;
    while let Some(pos) = rest.find("<meta") {
        let after = &rest[pos..];
        let tag_end = after.find('>').map(|i| i + 1).unwrap_or(after.len());
        let tag = &after[..tag_end];
        if tag.contains(property_name) {
            for quote in ['"', '\''] {
                let needle = format!("content={quote}");
                if let Some(start) = tag.find(&needle) {
                    let value_start = start + needle.len();
                    if let Some(len) = tag[value_start..].find(quote) {
                        return Some(tag[value_start..value_start + len].to_string());
                    }
                }
            }
        }
        rest = &after[tag_end.max(1)..];
    }
    None
}

/// Minimal HTML entity decode for meta-attribute text: the five named
/// entities plus `&nbsp;` and numeric (`&#39;` / `&#x27;`) forms. Unknown
/// entities pass through literally.
fn decode_html_entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let tail = &rest[amp..];
        let decoded = tail
            .find(';')
            .filter(|&i| i > 1 && i <= 10)
            .and_then(|semi| {
                let entity = &tail[1..semi];
                let ch = match entity {
                    "amp" => Some('&'),
                    "lt" => Some('<'),
                    "gt" => Some('>'),
                    "quot" => Some('"'),
                    "apos" => Some('\''),
                    "nbsp" => Some(' '),
                    _ => entity
                        .strip_prefix("#x")
                        .or_else(|| entity.strip_prefix("#X"))
                        .and_then(|hex| u32::from_str_radix(hex, 16).ok())
                        .or_else(|| {
                            entity.strip_prefix('#').and_then(|dec| dec.parse::<u32>().ok())
                        })
                        .and_then(char::from_u32),
                };
                ch.map(|c| (c, semi))
            });
        match decoded {
            Some((c, semi)) => {
                out.push(c);
                rest = &tail[semi + 1..];
            }
            None => {
                out.push('&');
                rest = &tail[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// Unwrap a LinkedIn `/safety/go` redirect wrapper to its percent-decoded
/// `url` parameter, so wrapped external links route to their real platform
/// (t-2589). Non-wrapper URLs, and wrappers without a decodable `http…`
/// target, pass through unchanged.
pub fn unwrap_linkedin_safety_url(url: &str) -> String {
    if !url.contains("linkedin.com/safety/go") {
        return url.to_string();
    }
    let Some(param) = url.find("url=") else {
        return url.to_string();
    };
    let raw = url[param + 4..].split('&').next().unwrap_or("");
    let decoded = percent_decode(raw);
    // The url= param is attacker-authorable (any post author controls it)
    // and becomes the pipeline's raw fetch target — only unwrap to public
    // http(s) hosts, never loopback/private/link-local (cloud metadata)
    // targets (t-2589 challenger finding).
    if is_public_http_target(&decoded) { decoded } else { url.to_string() }
}

/// Tracking query params stripped by [`canonicalize_url`]. A denylist, not an
/// allowlist — some queries are load-bearing (`youtube.com/watch?v=`), so only
/// known tracking keys are removed (t-2583).
const TRACKING_PARAMS: [&str; 7] = ["rcm", "fbclid", "gclid", "si", "igshid", "ref", "ref_src"];

/// Canonical form of a captured URL for keying and dedup (t-2583, t-2590):
/// unwrap the LinkedIn `/safety/go` wrapper, drop the fragment, then strip
/// tracking params (`utm_*` prefix plus [`TRACKING_PARAMS`]). Mobile share
/// sheets append `utm_*`/`rcm` to effectively every captured link, so without
/// this pass the same page stores under two `knowledge:url:` keys and
/// exact-key idempotency never fires.
pub fn canonicalize_url(url: &str) -> String {
    let unwrapped = unwrap_linkedin_safety_url(url.trim());
    let no_fragment = unwrapped.split('#').next().unwrap_or("");
    let Some((base, query)) = no_fragment.split_once('?') else {
        return no_fragment.to_string();
    };
    let kept: Vec<&str> = query
        .split('&')
        .filter(|pair| {
            let key = pair.split('=').next().unwrap_or("").to_ascii_lowercase();
            !key.starts_with("utm_") && !TRACKING_PARAMS.contains(&key.as_str())
        })
        .collect();
    if kept.is_empty() {
        base.to_string()
    } else {
        format!("{base}?{}", kept.join("&"))
    }
}

/// True when `url` is `http(s)` on a host that is not loopback, private,
/// link-local, unique-local, or unspecified. Hostnames pass (DNS answers
/// are not resolved here); IP literals — including bracketed IPv6 and
/// userinfo-prefixed forms (`user@127.0.0.1`) — are range-checked.
/// Accepted residual risk (not addressed by this check, same as prior art
/// in this file's redirect handling): DNS rebinding (a hostname that
/// resolves to a private IP at connect time — this is a string-level
/// check, not a resolver), 3xx redirect chains to a private target
/// (neither `ureq::get` call site restricts redirects), and exotic
/// non-dotted-quad IPv4 literal encodings (decimal/octal/hex — Rust's
/// `Ipv4Addr` parser rejects them, so they fall through to the
/// "unresolved hostname" `true` case below). Closing those is a
/// dedicated-SSRF-guard scope, not a narrow redirect-unwrap fix.
fn is_public_http_target(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    let rest = if let Some(r) = lower.strip_prefix("https://") {
        r
    } else if let Some(r) = lower.strip_prefix("http://") {
        r
    } else {
        return false;
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host_port = authority.rsplit('@').next().unwrap_or(authority);
    let host = if let Some(bracketed) = host_port.strip_prefix('[') {
        bracketed.split(']').next().unwrap_or("")
    } else if host_port.parse::<std::net::Ipv6Addr>().is_ok() {
        // Unbracketed IPv6 literal (invalid URL syntax, but cheap to
        // range-check rather than misread its first group as a hostname).
        host_port
    } else {
        host_port.split(':').next().unwrap_or("")
    };
    if host.is_empty() || host == "localhost" || host.ends_with(".localhost") {
        return false;
    }
    if let Ok(v4) = host.parse::<std::net::Ipv4Addr>() {
        return is_public_v4(v4);
    }
    if let Ok(v6) = host.parse::<std::net::Ipv6Addr>() {
        // IPv4-mapped (`::ffff:a.b.c.d`, RFC 4291 §2.5.5.2) resolves to the
        // embedded IPv4 address at the socket layer on every mainstream
        // OS — `Ipv6Addr::is_loopback`/`is_unspecified` do NOT recognize
        // this form, so it must be unwrapped and range-checked as IPv4
        // rather than falling through to the native-v6 checks below.
        if let Some(mapped) = v6.to_ipv4_mapped() {
            return is_public_v4(mapped);
        }
        let seg0 = v6.segments()[0];
        return !(v6.is_loopback()
            || v6.is_unspecified()
            || (seg0 & 0xfe00) == 0xfc00    // unique-local fc00::/7
            || (seg0 & 0xffc0) == 0xfe80); // link-local fe80::/10
    }
    true
}

fn is_public_v4(v4: std::net::Ipv4Addr) -> bool {
    !(v4.is_loopback() || v4.is_private() || v4.is_link_local() || v4.is_unspecified() || v4.is_broadcast())
}

/// Minimal percent-decoding (RFC 3986 `%XX`). Invalid escapes pass through
/// literally; invalid UTF-8 is replaced rather than erroring.
fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Some(hex) = std::str::from_utf8(&bytes[i + 1..i + 3])
                .ok()
                .and_then(|h| u8::from_str_radix(h, 16).ok())
            {
                out.push(hex);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Decide a Tier-2 fetch's outcome from the fetched author feed.
///
/// Split out of [`fetch_linkedin_content`] so the three-way contract is
/// testable without spawning an MCP server — the same injectable-core
/// convention as [`resolve_extraction`], which takes its upstream call
/// results as parameters for exactly this reason.
///
/// - `Err` in → `Err` out: the fetch itself broke (spawn failure, timeout,
///   MCP error, unparseable tool result). Never degraded to a miss.
/// - Feed fetched, post not in it → `Ok(None)`: a real miss.
///
/// Shape validation lives upstream in [`extract_posts_section`], which is
/// what turns a changed tool output into the `Err` this function then
/// propagates.
fn resolve_linkedin_fetch(feed: Result<String>, title_signal: &str) -> Result<Option<String>> {
    Ok(find_matching_post(&feed?, title_signal))
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

// ── YouTube caption fetch (ADR-070 §Amendment) ──────────────────────────
// Tests only as of t-2947 (TDD-red, pre-impl); the bodies below land in the
// follow-up implementation task per
// docs/architecture/features/youtube-knowledge-extraction.md §2, §Follow-up.

/// Which yt-dlp caption track a subtitle file came from — human-authored
/// (`"manual"`, `--write-sub`) or auto-generated (`"auto"`,
/// `--write-auto-sub`). Feeds the `caption_source` tag on the stored entry.
pub type YoutubeCaptionSource = &'static str;

/// Resolve yt-dlp's caption output for one video into deduped plain text.
///
/// Pure — no I/O, no subprocess. `manual_vtt`/`auto_vtt` are the raw file
/// contents yt-dlp would have written for `--write-sub`/`--write-auto-sub`
/// respectively (`None` when that file wasn't written). This is the
/// fixture-testable boundary for [`fetch_youtube_content`]'s subprocess
/// wrapper (feature spec §2 "Tests"): tests exercise it directly against
/// fixture VTT text instead of spawning `yt-dlp` or hitting the network —
/// same discipline as `find_matching_post` relative to `mcp_call_tool`
/// above.
///
/// - Both `None` — yt-dlp exited 0 with zero subtitle files written. This
///   is the no-captions contract (spec §2): `Ok(None)`, never an error,
///   never `Completed` downstream.
/// - `manual_vtt` present — the human-authored track wins.
/// - Otherwise `auto_vtt` — auto-generated fallback.
pub fn resolve_youtube_captions(
    manual_vtt: Option<&str>,
    auto_vtt: Option<&str>,
) -> Result<Option<(String, YoutubeCaptionSource)>> {
    if let Some(vtt) = manual_vtt {
        return Ok(Some((dedupe_vtt_cues(vtt), "manual")));
    }
    if let Some(vtt) = auto_vtt {
        return Ok(Some((dedupe_vtt_cues(vtt), "auto")));
    }
    Ok(None)
}

/// Extract each cue's text from a VTT document, in order. Pure text
/// parsing — no timestamp arithmetic needed, only "does this block have a
/// `-->` line" to distinguish a cue block from the `WEBVTT` header or a
/// bare cue identifier line.
fn parse_vtt_cue_texts(vtt: &str) -> Vec<String> {
    let mut cues = Vec::new();
    for block in vtt.split("\n\n") {
        let mut text_lines: Vec<&str> = Vec::new();
        let mut seen_timing_line = false;
        for line in block.lines() {
            if line.contains("-->") {
                seen_timing_line = true;
                continue;
            }
            if seen_timing_line {
                text_lines.push(line);
            }
        }
        if seen_timing_line {
            let text = text_lines.join(" ").trim().to_string();
            if !text.is_empty() {
                cues.push(text);
            }
        }
    }
    cues
}

/// Whether `cue` is `prefix` plus zero or more additional whole words —
/// i.e. `prefix` is a growing run's earlier, shorter cue and `cue` is its
/// next incremental reveal. Word-boundary-checked so `"the quick"` does not
/// falsely match `"the quickest"`.
fn extends_cue(cue: &str, prefix: &str) -> bool {
    cue.strip_prefix(prefix).is_some_and(|rest| rest.is_empty() || rest.starts_with(' '))
}

/// Remove `yt-dlp` auto-caption's word-level cue duplication, producing
/// plain text. Auto-generated VTT re-emits each line multiple times with
/// incrementally revealed words (a live-caption rendering artifact) — this
/// collapses each growing run down to its final, longest cue. Pure, no I/O;
/// never store raw VTT (feature spec §2).
pub fn dedupe_vtt_cues(vtt: &str) -> String {
    let mut runs: Vec<String> = Vec::new();
    for cue in parse_vtt_cue_texts(vtt) {
        match runs.last() {
            Some(prev) if extends_cue(&cue, prev) => {
                let last = runs.last_mut().expect("checked Some above");
                *last = cue;
            }
            _ => runs.push(cue),
        }
    }
    runs.join(" ")
}

/// Fixed basename for yt-dlp's output template — deterministic regardless
/// of the video's title/id, so the written caption file's path is always
/// predictable (`{work_dir}/video.en.vtt`).
const YT_DLP_CAPTION_BASENAME: &str = "video";

/// Build the exact argv for the yt-dlp caption-fetch invocation (ADR-070
/// §Amendment). Pure — no I/O, no subprocess — so the `--` separator and
/// `--socket-timeout` are fixture-testable without spawning `yt-dlp`
/// (regression guard, t-2950, per t-2947's Challenger finding that this
/// argv construction had no test pinning either flag).
///
/// `--dump-json` prints video metadata (including `requested_subtitles`/
/// `automatic_captions`, used by [`determine_youtube_caption_source`]) to
/// stdout in the SAME invocation that writes the subtitle files — one
/// subprocess call, not two, per the spec's "no new dependency, one
/// subprocess call" constraint.
///
/// **`--no-simulate` is required** — `-j`/`--dump-json` implies
/// `--simulate` on its own (yt-dlp's documented behavior for its
/// info-only flags), which suppresses every disk write including
/// `--write-sub`/`--write-auto-sub`. Without this flag every real
/// invocation would silently resolve as "no captions" regardless of
/// ground truth (Challenger finding, t-2950 iteration 1) — exactly the
/// class of bug ("fetch appears to succeed, content never lands") this
/// whole feature exists to fix, arriving through a different mechanism.
///
/// Cookie/auth passthrough (t-3033, feature spec §7): `cookies` args are
/// inserted **before** the `--` separator so the URL stays the sole
/// positional after it — the injection guard above is unchanged.
/// `YtDlpCookies::None` yields the pre-t-3033 argv byte-for-byte
/// (regression-pinned in this file's tests).
fn build_yt_dlp_caption_args(url: &str, cookies: &YtDlpCookies) -> Vec<String> {
    let mut args = vec![
        "--dump-json".to_string(),
        "--no-simulate".to_string(),
        "--skip-download".to_string(),
        "--write-sub".to_string(),
        "--write-auto-sub".to_string(),
        "--sub-langs".to_string(),
        "en".to_string(),
        "--sub-format".to_string(),
        "vtt".to_string(),
        "--socket-timeout".to_string(),
        "30".to_string(),
        "-o".to_string(),
        format!("{YT_DLP_CAPTION_BASENAME}.%(ext)s"),
    ];
    args.extend(cookies.to_args());
    args.push("--".to_string());
    args.push(url.to_string());
    args
}

/// How yt-dlp authenticates to YouTube (t-3033, feature spec §7).
/// YouTube's bot-check ("Sign in to confirm you're not a bot", live
/// 2026-08-23) blocks unauthenticated caption fetches even on a current
/// yt-dlp with a JS runtime; an authenticated session is what works.
///
/// `None` is today's behaviour and the default everywhere. The browser
/// value is passed verbatim — yt-dlp owns `browser[+keyring][:profile]`
/// parsing. A `File` path must already be absolute and UTF-8 (the CLI
/// resolver in `brana-cli` guarantees both before constructing it).
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum YtDlpCookies {
    #[default]
    None,
    /// `--cookies-from-browser <browser[+keyring][:profile]>`
    FromBrowser(String),
    /// `--cookies <path>` — a Netscape-format cookie jar.
    File(PathBuf),
}

impl YtDlpCookies {
    /// The yt-dlp flag pair for this value — the whole of the flag
    /// knowledge lives here. Pure.
    pub fn to_args(&self) -> Vec<String> {
        match self {
            YtDlpCookies::None => Vec::new(),
            YtDlpCookies::FromBrowser(b) => vec!["--cookies-from-browser".to_string(), b.clone()],
            YtDlpCookies::File(p) => {
                vec!["--cookies".to_string(), p.to_string_lossy().into_owned()]
            }
        }
    }
}

/// Basename of the staged cookie-jar copy inside a yt-dlp work dir.
const YT_DLP_STAGED_JAR: &str = "cookies.txt";

/// Stage `cookies` for one yt-dlp invocation in `work_dir`. yt-dlp's
/// `--cookies FILE` both reads *and rewrites* the jar on exit, so handing
/// it the operator's exported file would (a) race between overlapping
/// lock-free runs (`fetch_url_content` holds no lock — ADR-070 §Lock
/// discipline) and (b) let the kill-timeout in [`run_yt_dlp_captions`]
/// SIGKILL yt-dlp mid-write and truncate a credential. So a `File` jar is
/// copied to `{work_dir}/cookies.txt` (0600 on unix) and the copy — which
/// dies with the [`ScopedYtDlpWorkDir`] guard — is what yt-dlp sees.
/// `None`/`FromBrowser` pass through untouched; nothing is written.
fn stage_cookie_jar(cookies: &YtDlpCookies, work_dir: &std::path::Path) -> Result<YtDlpCookies> {
    let YtDlpCookies::File(src) = cookies else {
        return Ok(cookies.clone());
    };
    let dst = work_dir.join(YT_DLP_STAGED_JAR);
    let bytes = std::fs::read(src)
        .with_context(|| format!("reading cookie jar {}", src.display()))?;
    // Create at 0600 in the open() itself — a create-then-chmod sequence
    // leaves a umask-mode window with the credential on disk (rung-2
    // panel finding, TOCTOU). create_new: the scratch dir is ours, so an
    // existing file here is a bug, not something to truncate over.
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        opts.mode(0o600);
    }
    let mut f = opts
        .open(&dst)
        .with_context(|| format!("staging cookie jar at {}", dst.display()))?;
    {
        use std::io::Write as _;
        f.write_all(&bytes)
            .with_context(|| format!("writing staged cookie jar {}", dst.display()))?;
    }
    Ok(YtDlpCookies::File(dst))
}

/// Resolve the `yt-dlp` binary via `PATH`. Unlike `linkedin-scraper-mcp`
/// (a project-managed `uv tool install` with an env-var override and a
/// well-known install dir), yt-dlp is an ambient system tool this project
/// doesn't manage — `which` on PATH is the only resolution this needs.
fn resolve_yt_dlp_binary() -> Option<PathBuf> {
    let out = std::process::Command::new("which").arg("yt-dlp").output().ok()?;
    if !out.status.success() {
        return None;
    }
    let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (!path.is_empty()).then(|| PathBuf::from(path))
}

/// Process-wide counter disambiguating scratch work-dir names for
/// concurrent yt-dlp calls within the same process (batch mode calls
/// [`fetch_youtube_content`] once per URL) — same shape as
/// `MCP_STDERR_COUNTER` above.
static YT_DLP_WORKDIR_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// RAII guard for a yt-dlp scratch directory — removed (recursively) on
/// drop, including on early `?` returns, so a failed fetch never leaves
/// downloaded subtitle files behind. `tempfile` is a dev-only workspace
/// dependency (brana-core's `[dev-dependencies]`), so this hand-rolls the
/// same disposable-directory shape `ScopedStderrLog` already uses above.
struct ScopedYtDlpWorkDir {
    path: PathBuf,
}

impl Drop for ScopedYtDlpWorkDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

impl ScopedYtDlpWorkDir {
    fn create() -> Result<Self> {
        let n = YT_DLP_WORKDIR_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!("brana-yt-dlp-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&path)
            .with_context(|| format!("creating yt-dlp work dir at {}", path.display()))?;
        // 0700: since t-3033 this dir can hold a staged cookie jar, so no
        // other local account may list it (rung-2 panel finding).
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700))
                .with_context(|| format!("restricting yt-dlp work dir {}", path.display()))?;
        }
        Ok(Self { path })
    }
}

/// Outer kill-timeout for one yt-dlp invocation — generous against the
/// 2-6s typical case measured live 2026-08-17 (feature spec §2), bounding
/// the pathological hang yt-dlp's own default-10-retries can leave open.
const YT_DLP_TIMEOUT_SECS: u64 = 60;

/// Run one yt-dlp caption-fetch invocation in `work_dir`, bounded by
/// [`YT_DLP_TIMEOUT_SECS`]. Returns `(exit status, stdout, stderr)` — the
/// caller distinguishes "no captions" (exit 0, no subtitle file written)
/// from a real failure, and classifies stderr via [`is_youtube_rate_limited`].
///
/// stdout/stderr are drained on their own threads while polling for exit —
/// `--dump-json` output can be tens of KB, large enough to fill an unread
/// pipe and deadlock a bare `try_wait` loop (same class `mcp_call_tool`'s
/// stdout-reader thread above already guards against). On timeout the
/// child is killed WITHOUT joining the reader threads — a hung yt-dlp
/// process (or a grandchild) can hold a pipe open past the kill, and this
/// call must not block on that (t-2568's original 240s-hang lesson).
///
/// The spawn itself stays untested here (verified live instead, same
/// discipline as `mcp_call_tool` above) — [`build_yt_dlp_caption_args`]
/// covers the argv construction.
fn run_yt_dlp_captions(
    binary: &std::path::Path,
    url: &str,
    cookies: &YtDlpCookies,
    work_dir: &std::path::Path,
) -> Result<(std::process::ExitStatus, String, String)> {
    let staged = stage_cookie_jar(cookies, work_dir)?;
    let mut child = std::process::Command::new(binary)
        .current_dir(work_dir)
        .args(build_yt_dlp_caption_args(url, &staged))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning {}", binary.display()))?;

    let mut stdout_pipe = child.stdout.take().context("yt-dlp stdout not piped")?;
    let mut stderr_pipe = child.stderr.take().context("yt-dlp stderr not piped")?;
    let stdout_handle = std::thread::spawn(move || {
        use std::io::Read as _;
        let mut buf = String::new();
        let _ = stdout_pipe.read_to_string(&mut buf);
        buf
    });
    let stderr_handle = std::thread::spawn(move || {
        use std::io::Read as _;
        let mut buf = String::new();
        let _ = stderr_pipe.read_to_string(&mut buf);
        buf
    });

    let timeout = std::time::Duration::from_secs(YT_DLP_TIMEOUT_SECS);
    let started = std::time::Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {
                if started.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("yt-dlp timed out after {YT_DLP_TIMEOUT_SECS}s");
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Err(e) => bail!("yt-dlp wait error: {e}"),
        }
    };

    let stdout = stdout_handle.join().unwrap_or_default();
    let stderr = stderr_handle.join().unwrap_or_default();
    Ok((status, stdout, stderr))
}

/// Determine which caption track (manual vs auto) a fetch actually
/// captured, from yt-dlp's `--dump-json` metadata (feature spec §2: "use
/// `requested_subtitles` vs `automatic_captions`, not filename parsing").
/// `None` when neither map contains the requested language — the
/// no-captions case, or a `--dump-json` payload that failed to parse.
///
/// Precedence: `requested_subtitles` is checked first, so a video with
/// both a manual and an auto-generated English track resolves as
/// `"manual"`. This matches yt-dlp's documented field semantics —
/// `requested_subtitles` is only populated when a subtitle yt-dlp
/// actually wrote is present in it, and manual tracks are preferred over
/// auto ones during writing — but it has **not** been live-verified
/// against a real yt-dlp invocation in this sandbox (no network/yt-dlp
/// access here; Challenger finding, t-2950 iteration 1). Verify against a
/// real dual-track video once a task with live yt-dlp access runs
/// (tracked for t-2953).
fn determine_youtube_caption_source(info: &serde_json::Value) -> Option<YoutubeCaptionSource> {
    let has = |key: &str| {
        info.get(key).and_then(|v| v.as_object()).is_some_and(|o| o.contains_key("en"))
    };
    if has("requested_subtitles") {
        Some("manual")
    } else if has("automatic_captions") {
        Some("auto")
    } else {
        None
    }
}

/// One yt-dlp caption-fetch attempt — everything [`run_with_youtube_backoff`]
/// retries on a rate-limit response.
fn fetch_youtube_content_attempt(
    binary: &std::path::Path,
    url: &str,
    cookies: &YtDlpCookies,
) -> Result<Option<(String, YoutubeCaptionSource)>> {
    let work_dir = ScopedYtDlpWorkDir::create()?;
    let (status, stdout, stderr) = run_yt_dlp_captions(binary, url, cookies, &work_dir.path)?;

    if !status.success() {
        bail!("{}", subprocess_diagnostic(&format!("yt-dlp exited with {status}"), &stdout, &stderr));
    }

    let info: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap_or(serde_json::Value::Null);
    let source = determine_youtube_caption_source(&info);

    let vtt_path = work_dir.path.join(format!("{YT_DLP_CAPTION_BASENAME}.en.vtt"));
    let vtt = std::fs::read_to_string(&vtt_path).ok();

    let (manual_vtt, auto_vtt) = match (source, &vtt) {
        (Some("manual"), Some(text)) => (Some(text.as_str()), None),
        (Some("auto"), Some(text)) => (None, Some(text.as_str())),
        // No-captions contract (feature spec §2): a written file yt-dlp's
        // JSON doesn't attribute to either track, or no file at all, both
        // resolve through the same Ok(None) path below.
        _ => (None, None),
    };

    resolve_youtube_captions(manual_vtt, auto_vtt)
}

/// Fetch a YouTube video's captions via `yt-dlp` (ADR-070 §Amendment,
/// docs/architecture/features/youtube-knowledge-extraction.md §2). Shells
/// out once, never a Rust YouTube client library — same shape as the
/// LinkedIn MCP client and `call_gemini_json` subprocess calls in this file.
///
/// `Ok(None)` — distinct from `Err` — when `yt-dlp` exits 0 with zero
/// subtitle files written (no captions available for this video). Never
/// acquires [`lock_pipeline`] (see [`fetch_url_content`]'s note — this
/// function is subject to the same lock-discipline tripwire).
///
/// Retries through `HTTP 429` via [`run_with_youtube_backoff`]; any other
/// failure (malformed URL, network down, `yt-dlp` missing) surfaces
/// immediately.
///
/// The subprocess spawn itself stays untested here (verified live instead,
/// same discipline as `mcp_call_tool` above) — the fixture-testable logic
/// (dedup, manual/auto precedence, no-captions contract) lives in
/// [`resolve_youtube_captions`], and the argv construction is covered by
/// [`build_yt_dlp_caption_args`]'s own tests.
pub fn fetch_youtube_content(
    url: &str,
    cookies: &YtDlpCookies,
) -> Result<Option<(String, YoutubeCaptionSource)>> {
    let binary = resolve_yt_dlp_binary()
        .ok_or_else(|| anyhow::anyhow!("yt-dlp not found on PATH — install it to fetch youtube captions"))?;
    run_with_youtube_backoff(|_attempt| {
        fetch_youtube_content_attempt(&binary, url, cookies).map_err(|e| e.to_string())
    })
    .map_err(|e| anyhow::anyhow!(e))
}

// ── YouTube channel ingestion, Tier A (t-2997 tests, TDD-red pre-impl) ──
// Tests only as of t-2997; bodies land in t-2999 per
// docs/architecture/features/youtube-channel-ingestion.md §1, §Tests.
// Spike source: t-2994 (live-probed against a real channel — position
// range + duration match-filter confirmed cheap and correct under
// `--flat-playlist`; date filters confirmed to silently no-op, hence
// out of scope here — see ADR-070 §Amendment).

/// Which channel tab to enumerate — caller picks explicitly, never
/// inferred from the URL (feature spec §1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelTab {
    Videos,
    Shorts,
}

/// How to narrow a channel tab's video listing before mapping to URLs.
/// Each variant maps to a distinct `yt-dlp --flat-playlist` flag —
/// see [`build_channel_selection_args`] (feature spec §1).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChannelSelection {
    /// `--playlist-start`/`--playlist-end` (1-indexed, either bound optional).
    Range { start: Option<u32>, end: Option<u32> },
    /// `--playlist-items "3,7,10"`.
    Items(Vec<u32>),
    /// `--match-filter "duration<N"` — **`Videos` tab only**. The spike
    /// (t-2994) confirmed `duration` is unset on `Shorts`-tab flat
    /// entries, so pairing this with `tab: Shorts` is a caller error,
    /// not a silently-empty result (see [`build_channel_selection_args`]).
    MaxDuration(u32),
}

/// Pure argv builder for `yt-dlp --flat-playlist` selection flags —
/// no subprocess, no I/O (feature spec §1 "Tests": "pure
/// argv-construction tests, no subprocess").
///
/// # Errors
///
/// Returns `Err` immediately for `ChannelSelection::MaxDuration` paired
/// with `tab: ChannelTab::Shorts` — the spike (t-2994) confirmed
/// `duration` is unset for Shorts-tab flat entries, so this combination
/// can never be evaluated meaningfully. Callers (and this function's
/// tests) must never reach a subprocess call for this case.
pub fn build_channel_selection_args(tab: ChannelTab, selection: &ChannelSelection) -> Result<Vec<String>> {
    match selection {
        ChannelSelection::Range { start, end } => {
            let mut args = Vec::new();
            if let Some(s) = start {
                args.push("--playlist-start".to_string());
                args.push(s.to_string());
            }
            if let Some(e) = end {
                args.push("--playlist-end".to_string());
                args.push(e.to_string());
            }
            Ok(args)
        }
        ChannelSelection::Items(items) => {
            let joined = items.iter().map(u32::to_string).collect::<Vec<_>>().join(",");
            Ok(vec!["--playlist-items".to_string(), joined])
        }
        ChannelSelection::MaxDuration(max_secs) => {
            if tab == ChannelTab::Shorts {
                bail!(
                    "MaxDuration selection is not supported on the Shorts tab — \
                     yt-dlp's flat-playlist entries carry no duration field for Shorts"
                );
            }
            Ok(vec!["--match-filter".to_string(), format!("duration<{max_secs}")])
        }
    }
}

/// Pure parser for `yt-dlp --flat-playlist --print "%(id)s"` stdout —
/// one video ID per line, blank lines skipped. No subprocess, no I/O
/// (feature spec §1 "Tests": "fixture-based flat-listing parse").
///
/// An empty or all-blank `output` returns an empty `Vec`, never an
/// error — the empty-channel / zero-results fixture case (feature spec
/// §1 "Tests") is a legitimate `Ok(vec![])`, not a failure.
pub fn parse_flat_playlist_ids(output: &str) -> Vec<String> {
    output
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect()
}

/// Pure mapping: a bare video ID -> its full `youtube.com/watch` URL.
/// No subprocess, no I/O (feature spec §1 "Tests": "unit tested
/// independently of the subprocess call").
pub fn youtube_video_id_to_url(id: &str) -> String {
    format!("https://www.youtube.com/watch?v={id}")
}

/// [`fetch_youtube_channel_videos`]'s testable core — takes an injected
/// `run` closure in place of the real `yt-dlp` subprocess spawn, same
/// seam shape as [`run_with_youtube_backoff`]'s injected `attempt`
/// closure above. Tests substitute a fixture-returning or
/// invocation-asserting stub here instead of shelling out (feature spec
/// §1 "Tests": "tested against a recorded/fixture `--flat-playlist`
/// invocation, not live network", and "assert via a test double that
/// fails the test if the subprocess mock is invoked" for the
/// Shorts+MaxDuration caller-error case).
///
/// `run` receives the **full** yt-dlp argv built by
/// [`build_channel_listing_args`] (cookies, selection flags, `--print`,
/// `--`, listing URL) and returns `yt-dlp`'s stdout on success. Never
/// called at all when [`build_channel_selection_args`] itself returns
/// `Err` — the error path must short-circuit before `run` is invoked.
/// Handing the whole argv to `run` (t-3035) is what lets the fixture
/// tests observe the cookie args rather than leaving them "verified live".
pub fn fetch_youtube_channel_videos_with_runner(
    channel_url: &str,
    tab: ChannelTab,
    selection: ChannelSelection,
    cookies: &YtDlpCookies,
    run: impl FnOnce(&[String]) -> Result<String, String>,
) -> Result<Vec<String>> {
    let selection_args = build_channel_selection_args(tab, &selection)?;
    let listing_url = channel_listing_url(channel_url, tab);
    let args = build_channel_listing_args(cookies, &selection_args, &listing_url);
    let output = run(&args).map_err(|e| anyhow::anyhow!(e))?;
    Ok(parse_flat_playlist_ids(&output)
        .iter()
        .map(|id| youtube_video_id_to_url(id))
        .collect())
}

/// `{channel_url}/{videos|shorts}` — the tab listing yt-dlp enumerates.
fn channel_listing_url(channel_url: &str, tab: ChannelTab) -> String {
    let tab_path = match tab {
        ChannelTab::Videos => "videos",
        ChannelTab::Shorts => "shorts",
    };
    format!("{}/{tab_path}", channel_url.trim_end_matches('/'))
}

/// Build the exact argv for the channel-listing yt-dlp invocation
/// (feature spec §7). Pure. Cookie args precede the selection flags; the
/// `--` separator before the listing URL applies §2's injection guard to
/// the channel URL too — a gap the pre-t-3035 wrapper left open.
pub fn build_channel_listing_args(
    cookies: &YtDlpCookies,
    selection_args: &[String],
    listing_url: &str,
) -> Vec<String> {
    let mut args = vec!["--flat-playlist".to_string(), "--skip-download".to_string()];
    args.extend(cookies.to_args());
    args.extend(selection_args.iter().cloned());
    args.push("--print".to_string());
    args.push("%(id)s".to_string());
    args.push("--".to_string());
    args.push(listing_url.to_string());
    args
}

/// Enumerate a YouTube channel tab's video URLs via `yt-dlp
/// --flat-playlist`, narrowed by `selection`. Shells out once, same
/// subprocess discipline as [`fetch_youtube_content`] — never acquires
/// [`lock_pipeline`] (feature spec §1). `cookies` is staged into a
/// scoped scratch dir exactly as the caption fetch does (§7) — the
/// operator's jar is never handed to yt-dlp.
///
/// The subprocess spawn itself stays untested here (verified live
/// instead, same discipline as `fetch_youtube_content` above) — the
/// fixture-testable logic (argv construction, listing parse,
/// ID-to-URL mapping, the Shorts+MaxDuration caller error) lives in
/// [`build_channel_selection_args`], [`build_channel_listing_args`],
/// [`parse_flat_playlist_ids`], [`youtube_video_id_to_url`], and
/// [`fetch_youtube_channel_videos_with_runner`], which this delegates to.
pub fn fetch_youtube_channel_videos(
    channel_url: &str,
    tab: ChannelTab,
    selection: ChannelSelection,
    cookies: &YtDlpCookies,
) -> Result<Vec<String>> {
    let work_dir = ScopedYtDlpWorkDir::create()?;
    let staged = stage_cookie_jar(cookies, &work_dir.path)?;
    let listing_url = channel_listing_url(channel_url, tab);

    fetch_youtube_channel_videos_with_runner(channel_url, tab, selection, &staged, |args| {
        let out = std::process::Command::new("yt-dlp")
            .current_dir(&work_dir.path)
            .args(args)
            .output()
            .map_err(|e| format!("spawning yt-dlp for {listing_url}: {e}"))?;
        if !out.status.success() {
            let stderr = String::from_utf8_lossy(&out.stderr);
            return Err(format!("yt-dlp failed for {listing_url}: {stderr}"));
        }
        String::from_utf8(out.stdout).map_err(|e| format!("yt-dlp stdout not valid UTF-8: {e}"))
    })
}

// ── YouTube rate-limit backoff/retry (t-2955 tests, TDD-red pre-impl) ───
// Tests only as of t-2955; bodies land in t-2956 per
// docs/architecture/features/youtube-knowledge-extraction.md §2, §5.
// Rate limiting is confirmed real (HTTP 429 observed live 2026-08-17 on a
// single video, 2 languages back-to-back) — this is not a hypothetical case.

/// Whether a `yt-dlp` subprocess's stderr indicates HTTP 429 rate limiting —
/// the ONLY failure class [`run_with_youtube_backoff`] should mask behind a
/// retry. Any other failure (malformed URL, network down, no captions) must
/// surface immediately, never be silently retried.
///
/// Matched on `yt-dlp`'s own error line shape (`HTTP Error <code>: <reason>`,
/// observed live 2026-08-17), not a bare `"429"` substring — a URL or video
/// ID containing the digits "429" must not false-positive into a retry.
pub fn is_youtube_rate_limited(stderr: &str) -> bool {
    stderr.contains("HTTP Error 429")
}

/// Maximum retry attempts for a rate-limited `yt-dlp` call before giving up.
/// Bounded deliberately — this repo's other rate-limit retry precedent,
/// `gh_create_issue` (`brana-cli/src/sync.rs:413-419`), has NO cap at all
/// (unbounded recursion on every 429), which is a real defect class, not a
/// hypothetical one (Challenger finding, t-2955 iteration 1).
const YOUTUBE_BACKOFF_MAX_RETRIES: u32 = 5;

/// Backoff delay before retry attempt `attempt` (0-indexed) of a
/// rate-limited `yt-dlp` call. `None` once the retry budget
/// ([`YOUTUBE_BACKOFF_MAX_RETRIES`]) is exhausted — [`run_with_youtube_backoff`]
/// gives up rather than retrying forever.
///
/// Pure and deterministic — no sleep, no I/O — so pacing itself is
/// fixture-testable without a real (and, under an unbounded or
/// zero-abstraction design, potentially minutes-long) wait. This is the
/// seam the feature spec's own Tests section asks for ("Backoff/retry
/// unit — simulated HTTP 429, verifies pacing without a live network
/// call") that the first draft of this function omitted.
///
/// Exponential, capped at 5 attempts: 1s, 2s, 4s, 8s, 16s — generous
/// against a 429 that clears within seconds in practice (live-measured
/// 2026-08-17), while keeping the *backoff/sleep* portion of a
/// fully-exhausted retry budget (1+2+4+8+16 = 31s) well under a minute
/// rather than open-ended.
///
/// This bounds only the sleeps this function contributes — it is NOT the
/// worst-case latency of a full [`run_with_youtube_backoff`] call. Each
/// retry attempt can also block for up to [`YT_DLP_TIMEOUT_SECS`] (60s)
/// inside `run_yt_dlp_captions` before backoff even runs, so a call that
/// exhausts the whole retry budget can take up to
/// `6 * YT_DLP_TIMEOUT_SECS + 31s ≈ 391s` (~6.5 minutes) end to end
/// (Challenger finding, t-2950 iteration 1: the "well under a minute"
/// framing read as a claim about total latency, not just this function's
/// own sleep contribution).
pub fn backoff_delay(attempt: u32) -> Option<std::time::Duration> {
    if attempt >= YOUTUBE_BACKOFF_MAX_RETRIES {
        return None;
    }
    Some(std::time::Duration::from_secs(1u64 << attempt))
}

/// Actually wait out a computed backoff delay. A private seam so tests can
/// exercise [`run_with_youtube_backoff`]'s retry/give-up control flow
/// without incurring [`backoff_delay`]'s real multi-second-to-31-second
/// exponential schedule — pacing itself is already verified deterministically
/// by `backoff_delay`'s own tests; re-sleeping the full schedule here would
/// only slow the suite (t-2955 Challenger iteration 2 finding 1: the
/// pacing-call commitment needed to be more than doc-comment-only, but
/// "more than doc-comment-only" means gated, not literally executed, in
/// test builds).
#[cfg(not(test))]
fn youtube_backoff_wait(delay: std::time::Duration) {
    std::thread::sleep(delay);
}
#[cfg(test)]
fn youtube_backoff_wait(_delay: std::time::Duration) {}

/// Run `attempt` (given its 0-indexed attempt number) until it succeeds or
/// [`backoff_delay`]'s retry budget is exhausted, retrying only when the
/// error looks rate-limited per [`is_youtube_rate_limited`], sleeping
/// [`backoff_delay`] between retries. A non-rate-limited failure returns
/// immediately on the first attempt — never masked behind a retry loop.
pub fn run_with_youtube_backoff<T>(
    mut attempt: impl FnMut(u32) -> Result<T, String>,
) -> Result<T, String> {
    let mut n = 0u32;
    loop {
        match attempt(n) {
            Ok(v) => return Ok(v),
            Err(e) if is_youtube_rate_limited(&e) => match backoff_delay(n) {
                Some(delay) => {
                    youtube_backoff_wait(delay);
                    n += 1;
                }
                None => return Err(e),
            },
            Err(e) => return Err(e),
        }
    }
}

/// Tier 1: plain HTTP GET + HTML-to-text, for public (non-LinkedIn) URLs.
/// Uses `ureq` (already a workspace dependency, ADR-024 convention) — no
/// new HTTP client dependency.
fn fetch_public_url(url: &str) -> Result<String> {
    let response = ureq::get(url)
        .config()
        .timeout_global(Some(std::time::Duration::from_secs(PUBLIC_FETCH_TIMEOUT_SECS)))
        .build()
        .header("User-Agent", "brana-knowledge-process-url/1.0")
        .call()
        .with_context(|| format!("fetch failed: {url}"))?;
    let body = response
        .into_body()
        .with_config()
        .limit(PUBLIC_FETCH_MAX_BYTES)
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
        assert_eq!(content.image_url, None, "image_url is LinkedIn-only metadata (t-3187)");
    }

    // Companion to knowledge.rs's test_lock_discipline_source_tripwires
    // (t-2950 AC): that test scans brana-cli's knowledge.rs via
    // include_str! and cannot see fetch_url_content/fetch_youtube_content,
    // which live here in brana-core. Structural guarantee: neither ever
    // acquires the pipeline lock (ADR-070 §Lock discipline) — a lock held
    // across fetch_youtube_content's yt-dlp subprocess call would stall
    // every other pipeline writer for the duration of a network fetch.
    #[test]
    fn test_lock_discipline_source_tripwires_youtube_fetch() {
        let src = include_str!("knowledge_pipeline.rs");

        let fuc_start = src.find("pub fn fetch_url_content").expect("fetch_url_content exists");
        let fuc_end = src[fuc_start..]
            .find("\nconst LINKEDIN_MCP_TIMEOUT_SECS")
            .map(|i| fuc_start + i)
            .expect("LINKEDIN_MCP_TIMEOUT_SECS follows fetch_url_content");
        assert!(
            !src[fuc_start..fuc_end].contains("lock_pipeline("),
            "fetch_url_content must never acquire the pipeline lock (ADR-070 §Lock discipline)"
        );

        // Covers the whole youtube-fetch helper chain, not just the public
        // fetch_youtube_content entry point — build_yt_dlp_caption_args,
        // resolve_yt_dlp_binary, ScopedYtDlpWorkDir, run_yt_dlp_captions,
        // and determine_youtube_caption_source all live BEFORE
        // fetch_youtube_content in source order, so a narrower scan
        // anchored only on the pub fn would miss them.
        let fyc_start =
            src.find("const YT_DLP_CAPTION_BASENAME").expect("youtube fetch helper block exists");
        let fyc_end = src[fyc_start..]
            .find("\n// ── YouTube rate-limit backoff/retry (t-2955 tests")
            .map(|i| fyc_start + i)
            .expect("the backoff/retry section follows the youtube fetch helper block");
        assert!(
            !src[fyc_start..fyc_end].contains("lock_pipeline("),
            "fetch_youtube_content and its helpers must never acquire the pipeline lock — \
             it spawns a yt-dlp subprocess and must not stall other pipeline writers"
        );
    }

    // ── YouTube caption fetch (t-2947, TDD-red pre-impl) ────────────────
    // dedupe_vtt_cues / resolve_youtube_captions are pure — no subprocess,
    // no network — so they're exercised directly against fixture VTT text,
    // per feature spec §2 "Tests". fetch_youtube_content's actual yt-dlp
    // spawn stays untested here, same discipline as mcp_call_tool above.

    /// A fixture auto-caption VTT with the real word-level cue-duplication
    /// artifact: each cue repeats the prior cue's words plus one more,
    /// reset once for a second run. Modeled on the shape observed
    /// live 2026-08-17 against https://www.youtube.com/watch?v=jNQXAC9IVRw.
    const FIXTURE_VTT_WORD_LEVEL_DUPLICATION: &str = "\
WEBVTT

00:00:00.000 --> 00:00:02.000
the quick

00:00:01.000 --> 00:00:03.000
the quick brown

00:00:02.000 --> 00:00:04.000
the quick brown fox

00:00:04.000 --> 00:00:06.000
jumps over

00:00:05.000 --> 00:00:07.000
jumps over the lazy dog
";

    #[test]
    fn test_dedupe_vtt_cues_collapses_word_level_duplication() {
        assert_eq!(
            dedupe_vtt_cues(FIXTURE_VTT_WORD_LEVEL_DUPLICATION),
            "the quick brown fox jumps over the lazy dog"
        );
    }

    #[test]
    fn test_dedupe_vtt_cues_empty_input_is_empty() {
        assert_eq!(dedupe_vtt_cues("WEBVTT\n"), "");
    }

    #[test]
    fn test_resolve_youtube_captions_prefers_manual_over_auto() {
        let manual = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nmanual track text\n";
        let auto = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nauto track text\n";
        let (text, source) = resolve_youtube_captions(Some(manual), Some(auto)).unwrap().unwrap();
        assert_eq!(text, "manual track text");
        assert_eq!(source, "manual");
    }

    #[test]
    fn test_resolve_youtube_captions_falls_back_to_auto_when_no_manual_track() {
        let auto = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nauto track text\n";
        let (text, source) = resolve_youtube_captions(None, Some(auto)).unwrap().unwrap();
        assert_eq!(text, "auto track text");
        assert_eq!(source, "auto");
    }

    // AC (t-2947): yt-dlp exit 0 with zero subtitle files written must
    // produce Ok(None), not an error and not (downstream) Completed —
    // reproduces the original t-1349 bug shape one layer deeper if
    // unhandled. Asserted directly here, not just documented as a case.
    #[test]
    fn test_resolve_youtube_captions_no_captions_returns_ok_none() {
        assert_eq!(resolve_youtube_captions(None, None).unwrap(), None);
    }

    // ── YouTube channel ingestion, Tier A (t-2997, TDD-red pre-impl) ────
    // build_channel_selection_args / parse_flat_playlist_ids /
    // youtube_video_id_to_url are pure — no subprocess, no network — per
    // feature spec §1 "Tests". fetch_youtube_channel_videos_with_runner
    // exercises the subprocess-shaped seam against an injected closure
    // instead of a real `yt-dlp` spawn (same discipline as
    // run_with_youtube_backoff's injected `attempt` closure above).

    #[test]
    fn test_build_channel_selection_args_range_both_bounds() {
        let args =
            build_channel_selection_args(ChannelTab::Videos, &ChannelSelection::Range { start: Some(1), end: Some(20) })
                .unwrap();
        assert_eq!(
            args,
            vec!["--playlist-start", "1", "--playlist-end", "20"]
        );
    }

    // Boundary (Challenger, t-2997 build gate): Range with neither bound
    // set is a legitimate "no restriction" selection, not a caller
    // error — must produce an empty argv, not a spurious flag.
    #[test]
    fn test_build_channel_selection_args_range_no_bounds_is_empty_args() {
        let args =
            build_channel_selection_args(ChannelTab::Videos, &ChannelSelection::Range { start: None, end: None })
                .unwrap();
        let empty: Vec<String> = Vec::new();
        assert_eq!(args, empty);
    }

    #[test]
    fn test_build_channel_selection_args_range_start_only() {
        let args =
            build_channel_selection_args(ChannelTab::Videos, &ChannelSelection::Range { start: Some(5), end: None })
                .unwrap();
        assert_eq!(args, vec!["--playlist-start", "5"]);
    }

    #[test]
    fn test_build_channel_selection_args_range_end_only() {
        let args =
            build_channel_selection_args(ChannelTab::Videos, &ChannelSelection::Range { start: None, end: Some(10) })
                .unwrap();
        assert_eq!(args, vec!["--playlist-end", "10"]);
    }

    #[test]
    fn test_build_channel_selection_args_items() {
        let args =
            build_channel_selection_args(ChannelTab::Videos, &ChannelSelection::Items(vec![3, 7, 10])).unwrap();
        assert_eq!(args, vec!["--playlist-items", "3,7,10"]);
    }

    #[test]
    fn test_build_channel_selection_args_max_duration_on_videos_tab() {
        let args =
            build_channel_selection_args(ChannelTab::Videos, &ChannelSelection::MaxDuration(600)).unwrap();
        assert_eq!(args, vec!["--match-filter", "duration<600"]);
    }

    // AC (t-2994 spike / feature spec §1): Shorts-tab flat entries carry
    // no duration field — MaxDuration paired with Shorts must fail before
    // any argv is used to spawn a subprocess, not silently produce an
    // unfiltered or nonsensical filter.
    #[test]
    fn test_build_channel_selection_args_max_duration_on_shorts_tab_errs() {
        let result = build_channel_selection_args(ChannelTab::Shorts, &ChannelSelection::MaxDuration(60));
        assert!(result.is_err(), "MaxDuration on Shorts must be a caller error, not silently accepted");
    }

    #[test]
    fn test_parse_flat_playlist_ids_multiple_lines() {
        assert_eq!(
            parse_flat_playlist_ids("abc123
def456
ghi789
"),
            vec!["abc123", "def456", "ghi789"]
        );
    }

    #[test]
    fn test_parse_flat_playlist_ids_skips_blank_lines() {
        assert_eq!(parse_flat_playlist_ids("abc123


def456
"), vec!["abc123", "def456"]);
    }

    // AC (feature spec §1 "Tests"): empty-channel / zero-results is a
    // legitimate Ok(vec![]), never an error.
    #[test]
    fn test_parse_flat_playlist_ids_empty_output_is_empty_vec() {
        let empty: Vec<String> = Vec::new();
        assert_eq!(parse_flat_playlist_ids(""), empty);
    }

    #[test]
    fn test_parse_flat_playlist_ids_whitespace_only_output_is_empty_vec() {
        let empty: Vec<String> = Vec::new();
        assert_eq!(parse_flat_playlist_ids("   

  
"), empty);
    }

    #[test]
    fn test_youtube_video_id_to_url_maps_bare_id() {
        assert_eq!(
            youtube_video_id_to_url("dQw4w9WgXcQ"),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        );
    }

    // AC (feature spec §1 "Tests"): "tested against a recorded/fixture
    // --flat-playlist invocation, not live network" — the injected `run`
    // closure stands in for the subprocess spawn.
    #[test]
    fn test_fetch_youtube_channel_videos_with_runner_maps_fixture_listing_to_urls() {
        let result = fetch_youtube_channel_videos_with_runner(
            "https://www.youtube.com/@example",
            ChannelTab::Videos,
            ChannelSelection::Range { start: Some(1), end: Some(3) },
            &YtDlpCookies::None,
            |_argv| Ok::<String, String>("id1
id2
id3
".to_string()),
        );
        assert_eq!(
            result.unwrap(),
            vec![
                "https://www.youtube.com/watch?v=id1",
                "https://www.youtube.com/watch?v=id2",
                "https://www.youtube.com/watch?v=id3",
            ]
        );
    }

    // AC (feature spec §1 "Tests"): empty-channel / zero-results fixture
    // returns Ok(vec![]), not an error.
    #[test]
    fn test_fetch_youtube_channel_videos_with_runner_empty_channel_returns_ok_empty() {
        let result = fetch_youtube_channel_videos_with_runner(
            "https://www.youtube.com/@empty-channel",
            ChannelTab::Videos,
            ChannelSelection::Range { start: None, end: None },
            &YtDlpCookies::None,
            |_argv| Ok::<String, String>(String::new()),
        );
        let empty: Vec<String> = Vec::new();
        assert_eq!(result.unwrap(), empty);
    }

    // AC (feature spec §1 "Tests"): "MaxDuration on tab:Shorts returns Err
    // immediately with no subprocess call made (assert via a test double
    // that fails if invoked)" — the closure panics if it is ever called,
    // which fails this test rather than silently passing.
    #[test]
    fn test_fetch_youtube_channel_videos_with_runner_max_duration_on_shorts_never_invokes_runner() {
        let result = fetch_youtube_channel_videos_with_runner(
            "https://www.youtube.com/@example",
            ChannelTab::Shorts,
            ChannelSelection::MaxDuration(60),
            &YtDlpCookies::None,
            |_argv| -> Result<String, String> {
                panic!("subprocess runner must not be invoked for MaxDuration on Shorts")
            },
        );
        assert!(result.is_err(), "MaxDuration on Shorts must fail before reaching the runner");
    }

    // Regression (t-2950, Challenger finding carried from t-2947 iteration 1):
    // fetch_youtube_content's yt-dlp argv construction had no test pinning the
    // `--` separator or --socket-timeout, so a future edit could silently drop
    // either. build_yt_dlp_caption_args is pure — no subprocess — so this
    // asserts the exact argv without spawning yt-dlp.
    #[test]
    fn test_build_yt_dlp_caption_args_includes_required_flags_and_separator() {
        let args = build_yt_dlp_caption_args("https://www.youtube.com/watch?v=jNQXAC9IVRw", &YtDlpCookies::None);
        assert!(args.contains(&"--write-sub".to_string()));
        assert!(args.contains(&"--write-auto-sub".to_string()));
        let langs_idx = args.iter().position(|a| a == "--sub-langs").expect("--sub-langs present");
        assert_eq!(args[langs_idx + 1], "en");
        let timeout_idx =
            args.iter().position(|a| a == "--socket-timeout").expect("--socket-timeout present");
        assert_eq!(args[timeout_idx + 1], "30");
        // -- separator must be the second-to-last arg, URL last — argv-injection
        // guard (t-2947 Challenger finding): attacker-influenced URL input must
        // never be parsed as a yt-dlp flag.
        let sep_idx = args.iter().position(|a| a == "--").expect("-- separator present");
        assert_eq!(sep_idx, args.len() - 2);
        assert_eq!(args[sep_idx + 1], "https://www.youtube.com/watch?v=jNQXAC9IVRw");
    }

    // Regression (Challenger, t-2950 iteration 1, severity 5): --dump-json
    // implies --simulate on its own, which suppresses every disk write —
    // including --write-sub/--write-auto-sub. Without --no-simulate,
    // fetch_youtube_content would silently resolve every video as
    // "no captions" regardless of ground truth. This pins the flag so a
    // future edit can't drop it the way its absence went unnoticed here.
    #[test]
    fn test_build_yt_dlp_caption_args_includes_no_simulate_alongside_dump_json() {
        let args = build_yt_dlp_caption_args("https://www.youtube.com/watch?v=jNQXAC9IVRw", &YtDlpCookies::None);
        assert!(
            args.contains(&"--dump-json".to_string()),
            "sanity: --dump-json must still be present"
        );
        assert!(
            args.contains(&"--no-simulate".to_string()),
            "--dump-json implies --simulate on its own — without --no-simulate, \
             --write-sub/--write-auto-sub silently write nothing to disk"
        );
    }

    // determine_youtube_caption_source (Challenger, t-2950 iteration 1,
    // severity 3): pins the assumed manual-over-auto precedence contract
    // as an executable spec, since it can't be live-verified against real
    // yt-dlp output in this sandbox — see the function's own doc comment.
    #[test]
    fn test_determine_youtube_caption_source_manual_only() {
        let info = serde_json::json!({"requested_subtitles": {"en": {}}});
        assert_eq!(determine_youtube_caption_source(&info), Some("manual"));
    }

    #[test]
    fn test_determine_youtube_caption_source_auto_only() {
        let info = serde_json::json!({"automatic_captions": {"en": {}}});
        assert_eq!(determine_youtube_caption_source(&info), Some("auto"));
    }

    #[test]
    fn test_determine_youtube_caption_source_manual_takes_precedence_over_auto() {
        let info = serde_json::json!({
            "requested_subtitles": {"en": {}},
            "automatic_captions": {"en": {}},
        });
        assert_eq!(
            determine_youtube_caption_source(&info),
            Some("manual"),
            "a video with both tracks must resolve as manual, not auto"
        );
    }

    #[test]
    fn test_determine_youtube_caption_source_neither_track_is_none() {
        let info = serde_json::json!({"requested_subtitles": {}, "automatic_captions": {}});
        assert_eq!(determine_youtube_caption_source(&info), None);
    }

    #[test]
    fn test_determine_youtube_caption_source_wrong_language_is_none() {
        let info = serde_json::json!({
            "requested_subtitles": {"es": {}},
            "automatic_captions": {"fr": {}},
        });
        assert_eq!(
            determine_youtube_caption_source(&info),
            None,
            "only the requested language (en) counts as a captured track"
        );
    }

    #[test]
    fn test_determine_youtube_caption_source_malformed_json_is_none() {
        assert_eq!(determine_youtube_caption_source(&serde_json::Value::Null), None);
    }

    // Boundary (t-2950): a URL-shaped string starting with "-" (attacker
    // influenced, per t-2589's LinkedIn precedent for the same class of bug)
    // must land strictly after the -- separator, never before it where yt-dlp
    // would parse it as a flag (e.g. yt-dlp's own --exec <cmd>).
    #[test]
    fn test_build_yt_dlp_caption_args_dash_prefixed_url_never_precedes_separator() {
        let args = build_yt_dlp_caption_args("-exec=rm -rf /", &YtDlpCookies::None);
        let sep_idx = args.iter().position(|a| a == "--").expect("-- separator present");
        assert_eq!(args[sep_idx + 1], "-exec=rm -rf /");
        assert!(args[..sep_idx].iter().all(|a| a != "-exec=rm -rf /"));
    }

    // ── channel listing argv + cookies (t-3035, feature spec §7) ────────

    #[test]
    fn test_build_channel_listing_args_no_cookies_has_separator_before_url() {
        let sel = vec!["--playlist-end".to_string(), "3".to_string()];
        let args = build_channel_listing_args(&YtDlpCookies::None, &sel, "https://www.youtube.com/@x/videos");
        let expected: Vec<String> = [
            "--flat-playlist", "--skip-download", "--playlist-end", "3", "--print", "%(id)s",
            "--", "https://www.youtube.com/@x/videos",
        ].iter().map(|s| s.to_string()).collect();
        assert_eq!(args, expected);
    }

    #[test]
    fn test_build_channel_listing_args_cookies_precede_selection_args() {
        let sel = vec!["--playlist-items".to_string(), "1,2".to_string()];
        let args = build_channel_listing_args(
            &YtDlpCookies::File(PathBuf::from("/tmp/jar.txt")),
            &sel,
            "https://www.youtube.com/@x/videos",
        );
        let c = args.iter().position(|a| a == "--cookies").expect("--cookies present");
        assert_eq!(args[c + 1], "/tmp/jar.txt");
        let p = args.iter().position(|a| a == "--playlist-items").unwrap();
        assert!(c < p, "cookie args must precede selection args");
        let sep = args.iter().position(|a| a == "--").unwrap();
        assert_eq!(sep, args.len() - 2);
    }

    // Injection guard (§2 applied to the listing URL — pre-existing gap
    // closed by t-3035): a dash-prefixed listing URL lands after `--`.
    #[test]
    fn test_build_channel_listing_args_dash_prefixed_url_never_precedes_separator() {
        let args = build_channel_listing_args(&YtDlpCookies::None, &[], "-exec=rm -rf /");
        let sep = args.iter().position(|a| a == "--").unwrap();
        assert_eq!(args[sep + 1], "-exec=rm -rf /");
        assert!(args[..sep].iter().all(|a| a != "-exec=rm -rf /"));
    }

    // The injected runner must observe the cookie args — otherwise the
    // cookie insertion is covered only "verified live" (challenger §7 #2).
    #[test]
    fn test_fetch_youtube_channel_videos_with_runner_passes_cookie_args_to_runner() {
        let seen = std::cell::RefCell::new(Vec::new());
        let result = fetch_youtube_channel_videos_with_runner(
            "https://www.youtube.com/@example",
            ChannelTab::Videos,
            ChannelSelection::Range { start: None, end: Some(2) },
            &YtDlpCookies::FromBrowser("chrome".to_string()),
            |argv| {
                seen.borrow_mut().extend(argv.iter().cloned());
                Ok::<String, String>("id1\n".to_string())
            },
        );
        assert_eq!(result.unwrap(), vec!["https://www.youtube.com/watch?v=id1"]);
        let argv = seen.into_inner();
        let c = argv.iter().position(|a| a == "--cookies-from-browser").expect("cookie flag reached runner");
        assert_eq!(argv[c + 1], "chrome");
        assert!(argv.contains(&"--playlist-end".to_string()));
        assert_eq!(argv.last().unwrap(), "https://www.youtube.com/@example/videos");
    }

    // ── yt-dlp cookie/auth passthrough (t-3033, feature spec §7) ────────
    // YtDlpCookies::to_args and build_yt_dlp_caption_args are pure; the
    // jar staging touches only a scratch dir — no yt-dlp, no network.

    #[test]
    fn test_yt_dlp_cookies_to_args_none_is_empty() {
        assert!(YtDlpCookies::None.to_args().is_empty());
    }

    #[test]
    fn test_yt_dlp_cookies_to_args_from_browser() {
        assert_eq!(
            YtDlpCookies::FromBrowser("chrome".to_string()).to_args(),
            vec!["--cookies-from-browser".to_string(), "chrome".to_string()]
        );
    }

    #[test]
    fn test_yt_dlp_cookies_to_args_file() {
        assert_eq!(
            YtDlpCookies::File(PathBuf::from("/p/c.txt")).to_args(),
            vec!["--cookies".to_string(), "/p/c.txt".to_string()]
        );
    }

    // Regression pin: the no-cookie argv must be exactly the pre-t-3033
    // argv — backward compatibility is a frozen decision in spec §7.
    #[test]
    fn test_build_yt_dlp_caption_args_no_cookies_is_unchanged_argv() {
        let url = "https://www.youtube.com/watch?v=jNQXAC9IVRw";
        let args = build_yt_dlp_caption_args(url, &YtDlpCookies::None);
        let expected: Vec<String> = [
            "--dump-json", "--no-simulate", "--skip-download", "--write-sub", "--write-auto-sub",
            "--sub-langs", "en", "--sub-format", "vtt", "--socket-timeout", "30",
            "-o", "video.%(ext)s", "--", url,
        ].iter().map(|s| s.to_string()).collect();
        assert_eq!(args, expected);
    }

    #[test]
    fn test_build_yt_dlp_caption_args_cookie_pair_precedes_separator_url_still_last() {
        let url = "https://www.youtube.com/watch?v=jNQXAC9IVRw";
        for cookies in [
            YtDlpCookies::FromBrowser("firefox".to_string()),
            YtDlpCookies::File(PathBuf::from("/tmp/jar.txt")),
        ] {
            let args = build_yt_dlp_caption_args(url, &cookies);
            let pair = cookies.to_args();
            let flag_idx = args.iter().position(|a| a == &pair[0]).expect("cookie flag present");
            assert_eq!(args[flag_idx + 1], pair[1]);
            let sep_idx = args.iter().position(|a| a == "--").expect("-- separator present");
            assert!(flag_idx < sep_idx, "cookie flag must precede --");
            assert_eq!(sep_idx, args.len() - 2);
            assert_eq!(args[sep_idx + 1], url);
        }
    }

    // Injection guard holds with cookies in play: a dash-prefixed URL
    // still lands strictly after `--`.
    #[test]
    fn test_build_yt_dlp_caption_args_with_cookies_dash_url_never_precedes_separator() {
        let args = build_yt_dlp_caption_args("-exec=rm -rf /", &YtDlpCookies::FromBrowser("chrome".into()));
        let sep_idx = args.iter().position(|a| a == "--").expect("-- separator present");
        assert_eq!(args[sep_idx + 1], "-exec=rm -rf /");
        assert!(args[..sep_idx].iter().all(|a| a != "-exec=rm -rf /"));
    }

    // Spec §7: yt-dlp rewrites the `--cookies` jar on exit, so the
    // operator's file must never be handed to yt-dlp — stage a copy in
    // the scratch dir instead.
    #[test]
    fn test_stage_cookie_jar_copies_file_into_work_dir_and_leaves_original_untouched() {
        let work = ScopedYtDlpWorkDir::create().unwrap();
        let original = work.path.join("operator-jar.txt");
        std::fs::write(&original, "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc\n").unwrap();
        let staged = stage_cookie_jar(&YtDlpCookies::File(original.clone()), &work.path).unwrap();
        let YtDlpCookies::File(staged_path) = &staged else { panic!("expected File, got {staged:?}") };
        assert_ne!(staged_path, &original, "must not reuse the operator's path");
        assert!(staged_path.starts_with(&work.path), "staged copy must live in work_dir");
        assert_eq!(std::fs::read(staged_path).unwrap(), std::fs::read(&original).unwrap());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            assert_eq!(std::fs::metadata(staged_path).unwrap().permissions().mode() & 0o777, 0o600);
        }
    }

    // Panel finding (t-3033 rung-2 concurrency-lock): the scratch dir holds a
    // credential now, so it must be 0700 — not the umask default 0755.
    #[cfg(unix)]
    #[test]
    fn test_scoped_yt_dlp_work_dir_is_private() {
        use std::os::unix::fs::PermissionsExt as _;
        let work = ScopedYtDlpWorkDir::create().unwrap();
        assert_eq!(std::fs::metadata(&work.path).unwrap().permissions().mode() & 0o777, 0o700);
    }

    #[test]
    fn test_stage_cookie_jar_passes_none_and_browser_through_without_writing() {
        let work = ScopedYtDlpWorkDir::create().unwrap();
        assert!(matches!(stage_cookie_jar(&YtDlpCookies::None, &work.path).unwrap(), YtDlpCookies::None));
        let b = stage_cookie_jar(&YtDlpCookies::FromBrowser("chrome".into()), &work.path).unwrap();
        assert!(matches!(b, YtDlpCookies::FromBrowser(ref x) if x == "chrome"));
        assert_eq!(std::fs::read_dir(&work.path).unwrap().count(), 0, "nothing written for non-File");
    }

    // Boundary: a File jar that vanished between resolve and stage is an
    // Err naming the path, not a silent fallback to unauthenticated.
    #[test]
    fn test_stage_cookie_jar_missing_file_errs_naming_path() {
        let work = ScopedYtDlpWorkDir::create().unwrap();
        let gone = work.path.join("nope.txt");
        let err = stage_cookie_jar(&YtDlpCookies::File(gone.clone()), &work.path).unwrap_err();
        assert!(err.to_string().contains("nope.txt"), "{err}");
    }

    // ── YouTube rate-limit backoff/retry (t-2955, TDD-red pre-impl) ─────
    // is_youtube_rate_limited / run_with_youtube_backoff are pure and take
    // no subprocess, no network — a simulated HTTP 429 is a plain string,
    // per feature spec §2/§5's "not a live network call" discipline.

    /// A yt-dlp stderr fixture as observed live 2026-08-17 against a real
    /// video hit twice in quick succession (2 caption languages).
    const FIXTURE_STDERR_HTTP_429: &str =
        "ERROR: unable to download video subtitles for en: HTTP Error 429: Too Many Requests";

    #[test]
    fn test_is_youtube_rate_limited_matches_http_429() {
        assert!(is_youtube_rate_limited(FIXTURE_STDERR_HTTP_429));
    }

    #[test]
    fn test_is_youtube_rate_limited_false_for_unrelated_failure() {
        assert!(!is_youtube_rate_limited("ERROR: Unsupported URL: not-a-real-url"));
    }

    // Boundary (t-2956): a bare "429" substring — e.g. incidentally present
    // in a video length or id — must not false-positive into a retry. Only
    // yt-dlp's actual HTTP-error line shape counts.
    #[test]
    fn test_is_youtube_rate_limited_false_for_bare_429_substring() {
        assert!(!is_youtube_rate_limited("video is 429 seconds long"));
    }

    #[test]
    fn test_is_youtube_rate_limited_empty_input_is_false() {
        assert!(!is_youtube_rate_limited(""));
    }

    // Boundary (t-2956): success on the very first attempt must not enter
    // the retry loop at all — no backoff, no sleep, one call.
    #[test]
    fn test_youtube_backoff_succeeds_immediately_without_retry() {
        let mut calls = 0u32;
        let result = run_with_youtube_backoff(|_attempt| {
            calls += 1;
            Ok::<u32, String>(42)
        });
        assert_eq!(result, Ok(42));
        assert_eq!(calls, 1);
    }

    // Regression (Challenger, t-2956 implementation gate): a non-429 error
    // on a LATER retry attempt (after at least one genuine 429) must still
    // return immediately, not get masked by the retry loop continuing on
    // the strength of the earlier 429. Guards the `Err(e) if
    // is_youtube_rate_limited(&e) => ... / Err(e) => return Err(e)` control
    // flow against a future refactor silently reordering those arms.
    #[test]
    fn test_youtube_backoff_non_429_after_retry_still_returns_immediately() {
        let mut calls = 0u32;
        let result: Result<u32, String> = run_with_youtube_backoff(|attempt| {
            calls += 1;
            if attempt == 0 {
                Err(FIXTURE_STDERR_HTTP_429.to_string())
            } else {
                Err("ERROR: Unsupported URL".to_string())
            }
        });
        assert!(result.is_err());
        assert_eq!(calls, 2, "must stop at the first non-429 failure, not keep retrying past it");
    }

    // AC (t-2955): a simulated HTTP 429 must trigger backoff/retry, not an
    // immediate error — asserted via call count, not just documented.
    #[test]
    fn test_youtube_backoff_retries_on_simulated_429() {
        let mut calls = 0u32;
        let result = run_with_youtube_backoff(|attempt| {
            calls += 1;
            if attempt < 2 {
                Err(FIXTURE_STDERR_HTTP_429.to_string())
            } else {
                Ok(calls)
            }
        });
        assert_eq!(result, Ok(3));
        assert_eq!(calls, 3, "must retry through the 429s rather than erroring immediately");
    }

    #[test]
    fn test_youtube_backoff_does_not_retry_non_429_failures() {
        let mut calls = 0u32;
        let result: Result<u32, String> = run_with_youtube_backoff(|_attempt| {
            calls += 1;
            Err("ERROR: Unsupported URL".to_string())
        });
        assert!(result.is_err());
        assert_eq!(calls, 1, "a non-429 failure must surface immediately, not be masked by retries");
    }

    #[test]
    fn test_youtube_backoff_gives_up_after_bounded_retries_on_persistent_429() {
        let mut calls = 0u32;
        let result: Result<u32, String> = run_with_youtube_backoff(|_attempt| {
            calls += 1;
            Err(FIXTURE_STDERR_HTTP_429.to_string())
        });
        assert!(result.is_err(), "must eventually give up, not retry forever");
        assert!(calls <= 10, "retry count must be bounded, not unbounded");
    }

    // Pacing itself, fixture-tested without sleeping (Challenger finding,
    // t-2955 iteration 1: the spec's Tests section requires verifying
    // pacing, not just call count — these are fast and deterministic
    // because backoff_delay is pure).

    #[test]
    fn test_backoff_delay_grows_monotonically() {
        let d0 = backoff_delay(0).expect("attempt 0 is within budget");
        let d1 = backoff_delay(1).expect("attempt 1 is within budget");
        let d2 = backoff_delay(2).expect("attempt 2 is within budget");
        assert!(d0 < d1, "delay must grow between retries, not stay flat");
        assert!(d1 < d2, "delay must grow between retries, not stay flat");
    }

    #[test]
    fn test_backoff_delay_none_once_retry_budget_exhausted() {
        assert_eq!(
            backoff_delay(YOUTUBE_BACKOFF_MAX_RETRIES),
            None,
            "must give up at the retry budget, not retry forever"
        );
    }

    #[test]
    fn test_backoff_delay_bounded_total_wait() {
        // Bounds only the backoff/sleep portion of a fully-exhausted retry
        // budget — NOT the full run_with_youtube_backoff worst case, which
        // also includes up to YT_DLP_TIMEOUT_SECS per attempt and can run
        // to several minutes (see backoff_delay's doc comment; Challenger
        // finding, t-2950 iteration 1).
        let total: std::time::Duration = (0..YOUTUBE_BACKOFF_MAX_RETRIES)
            .filter_map(backoff_delay)
            .sum();
        assert!(
            total < std::time::Duration::from_secs(60),
            "backoff-only wait across the whole retry budget must stay well under a minute, got {total:?}"
        );
    }

    // ── LinkedIn Tier 2: find_matching_post (fuzzy fallback, ADR-070) ───
    // The process spawn in mcp_call_tool stays untested here (verified live
    // instead — see ADR-070 §Empirical validation and §Amendment).
    // Everything around it is covered: extract_posts_section takes the tool
    // result, parse_jsonrpc_message takes one wire line, and
    // resolve_linkedin_fetch takes the fetch's Result — so the framing,
    // response-shape, and Ok(None)/Err decisions are all reachable without
    // a server. The novel pure logic — fuzzy matching — is tested here.

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
        let feed = "A post about gardening.\n\nA post about coffee brewing.".to_string();
        let result = resolve_linkedin_fetch(Ok(feed), "quantum computing breakthroughs");
        assert!(
            matches!(&result, Ok(None)),
            "a clean fetch that lacks the post is a miss, not a failure — got {result:?}"
        );
    }

    #[test]
    fn linkedin_fetch_post_present_returns_ok_some() {
        let feed = "Unrelated gardening post.\n\n\
                    Excited to announce our new semantic layer for BigQuery."
            .to_string();
        let found = resolve_linkedin_fetch(Ok(feed), "bigquerys native semantic layer")
            .expect("a well-formed feed must not error")
            .expect("the post is present in this feed");
        assert!(found.contains("semantic layer for BigQuery"));
    }

    #[test]
    fn linkedin_fetch_transport_error_propagates_as_err() {
        // Boundary: the fetch itself failed (spawn failure, timeout, MCP
        // error). Must stay Err — never degrade to a quiet miss.
        let result = resolve_linkedin_fetch(
            Err(anyhow::anyhow!("linkedin MCP tools/call timed out after 120s")),
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
        let result = resolve_linkedin_fetch(Ok(String::new()), "some title signal");
        assert!(
            matches!(&result, Ok(None)),
            "an empty feed is a miss, not a failure — got {result:?}"
        );
    }

    // ── LinkedIn Tier 2: MCP tool-result shape (t-2568) ─────────────────
    // The transport is a direct JSON-RPC client as of ADR-070 §Amendment,
    // so what gets parsed is the MCP tool result itself rather than
    // whatever prose `claude -p` decided to emit around it. These cover the
    // parse; the spawn stays untested here, same convention as the rest of
    // this file.

    #[test]
    fn mcp_result_extracts_posts_section() {
        let result = serde_json::json!({
            "structuredContent": {
                "url": "https://www.linkedin.com/in/someone",
                "sections": {
                    "main_profile": "Name, headline, etc.",
                    "posts": "Excited to announce our new semantic layer for BigQuery."
                }
            },
            "isError": false
        });
        let posts = extract_posts_section(&result).expect("a well-formed result must parse");
        assert!(posts.contains("semantic layer for BigQuery"));
    }

    #[test]
    fn mcp_result_absent_posts_section_is_an_empty_feed_not_an_error() {
        // get_person_profile documents that a section "may be absent if
        // extraction yielded no content for that page" — that is an author
        // with no visible posts, a miss rather than a broken tool. The
        // presence of `sections` is what separates this from a shape change.
        let result = serde_json::json!({
            "structuredContent": {"sections": {"main_profile": "Name, headline."}},
            "isError": false
        });
        let posts =
            extract_posts_section(&result).expect("an absent posts section is not an error");
        assert!(posts.is_empty(), "expected an empty feed, got {posts:?}");
        assert_eq!(find_matching_post(&posts, "anything at all"), None);
    }

    #[test]
    fn mcp_result_missing_structured_content_is_err() {
        // A changed or failed tool output is a failure, not evidence that
        // the post is absent. If this degrades to Ok(None), every LinkedIn
        // URL silently reports "not found" the day the tool changes shape.
        let result = serde_json::json!({"content": [{"type": "text", "text": "..."}]});
        assert!(
            extract_posts_section(&result).is_err(),
            "missing structuredContent must be Err"
        );
    }

    #[test]
    fn mcp_result_is_error_flag_is_err() {
        // The server reports tool-level failure in band, on an otherwise
        // well-formed response. Ignoring isError would read a failed scrape
        // as an empty feed and mark the post permanently missing.
        let result = serde_json::json!({
            "content": [{"type": "text", "text": "Session expired"}],
            "structuredContent": {"sections": {"posts": ""}},
            "isError": true
        });
        let err = extract_posts_section(&result).expect_err("isError must surface as Err");
        assert!(
            err.to_string().contains("Session expired"),
            "the server's message must not be swallowed — got {err}"
        );
    }

    #[test]
    fn mcp_result_posts_section_wrong_type_is_err() {
        // Boundary: key present, but not a string.
        let result = serde_json::json!({
            "structuredContent": {"sections": {"posts": 42}}
        });
        assert!(
            extract_posts_section(&result).is_err(),
            "a non-string posts section must be Err"
        );
    }

    #[test]
    fn mcp_stderr_log_is_removed_on_drop() {
        // Inherited from the scoped-mcp-config guard this replaced: an
        // unattended batch that leaked one temp file per URL would quietly
        // fill /tmp.
        let (guard, _file) = ScopedStderrLog::create().unwrap();
        let path = guard.path.clone();
        assert!(path.exists());
        drop(guard);
        assert!(!path.exists(), "temp stderr log must be cleaned up on drop");
    }

    #[test]
    fn mcp_stderr_logs_two_calls_same_process_get_distinct_paths() {
        // Boundary: batch mode calls mcp_call_tool once per URL from the
        // same process — PID-only naming would collide, and one call's Drop
        // would delete another's still-open log (regression guard).
        let (a, _fa) = ScopedStderrLog::create().unwrap();
        let (b, _fb) = ScopedStderrLog::create().unwrap();
        assert_ne!(a.path, b.path);
        assert!(a.path.exists() && b.path.exists());
    }

    #[test]
    fn mcp_call_tool_server_that_closes_output_fails_fast_and_says_why() {
        // A server that closes stdout without answering leaves us with no
        // response — same end state as a deadline, different fault. Claiming
        // "timed out after 120s" a moment in would be exactly the lying
        // diagnostic that made this bug take four attempts to find (t-2568).
        //
        // The stand-in closes stdout but keeps draining stdin, so the writes
        // succeed and the failure is specifically "no response", not EPIPE.
        let script = std::env::temp_dir().join(format!("brana-fake-mcp-{}.sh", std::process::id()));
        std::fs::write(&script, "#!/bin/sh\nexec 1>&-\ncat > /dev/null\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt as _;
            std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
        }

        let started = std::time::Instant::now();
        let err = mcp_call_tool(
            &script,
            "get_person_profile",
            serde_json::json!({}),
            std::time::Duration::from_secs(120),
        )
        .expect_err("a server that never answers must be an error");
        let elapsed = started.elapsed();
        let _ = std::fs::remove_file(&script);

        assert!(
            elapsed < std::time::Duration::from_secs(20),
            "must not wait out a 120s deadline it never hit: took {elapsed:?}"
        );
        let msg = err.to_string();
        assert!(
            msg.contains("closed its output"),
            "must name the actual fault: {msg}"
        );
        assert!(
            !msg.contains("timed out"),
            "must not report a timeout that did not happen: {msg}"
        );
    }

    // ── JSON-RPC framing (t-2568) ───────────────────────────────────────

    #[test]
    fn jsonrpc_skips_messages_that_are_not_the_awaited_response() {
        // FastMCP can interleave progress notifications with responses, and
        // the initialize reply precedes the tools/call reply on the same
        // stream. A client that took the first line it read would parse the
        // wrong message as its tool result.
        let notification =
            r#"{"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":0.5}}"#;
        assert!(
            matches!(parse_jsonrpc_message(notification, 2), Ok(None)),
            "a notification must not satisfy the wait for id 2"
        );
        let other_id = r#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}"#;
        assert!(
            matches!(parse_jsonrpc_message(other_id, 2), Ok(None)),
            "a response to another id must not satisfy the wait for id 2"
        );
    }

    #[test]
    fn jsonrpc_matching_id_returns_the_result() {
        let line = r#"{"jsonrpc":"2.0","id":2,"result":{"isError":false}}"#;
        let got = parse_jsonrpc_message(line, 2)
            .expect("a well-formed response must not error")
            .expect("id 2 must satisfy the wait");
        assert_eq!(got["isError"], serde_json::json!(false));
    }

    #[test]
    fn jsonrpc_error_object_surfaces_as_err() {
        // A protocol-level error (unknown tool, bad params) must not be
        // mistaken for "no result yet" and waited on until the timeout.
        let line =
            r#"{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"Unknown tool: nope"}}"#;
        let err = parse_jsonrpc_message(line, 2).expect_err("an error object must surface as Err");
        assert!(
            err.to_string().contains("Unknown tool: nope"),
            "the server's message must not be swallowed — got {err}"
        );
    }

    #[test]
    fn jsonrpc_non_json_line_is_skipped_not_fatal() {
        // Servers print banners and log lines. FastMCP's own update notice
        // goes to stderr, but a stray non-JSON line on stdout must not abort
        // a fetch that is otherwise fine.
        assert!(matches!(parse_jsonrpc_message("Starting MCP server", 2), Ok(None)));
        assert!(matches!(parse_jsonrpc_message("", 2), Ok(None)));
    }

    // ── Subprocess timeout diagnostics ──────────────────────────────────
    // Shared by every path that kills a child on a deadline. A killed
    // child's output used to be dropped on the floor, which is why t-2568
    // could not be diagnosed from its own error message.

    #[test]
    fn subprocess_diagnostic_includes_what_the_child_wrote() {
        // t-2557 AC-3. A killed child's piped output used to be dropped on
        // the floor: the caller got "timed out after 240s" and nothing else,
        // which is why t-2568 could not be diagnosed from its own error.
        let msg = subprocess_diagnostic(
            "claude CLI (MCP) timed out after 240s",
            "partial stdout here",
            "Chromium launch failed",
        );
        assert!(msg.contains("240s"));
        assert!(msg.contains("Chromium launch failed"), "child stderr must survive: {msg}");
        assert!(msg.contains("partial stdout here"), "child stdout must survive: {msg}");
    }

    #[test]
    fn subprocess_diagnostic_says_so_when_the_child_wrote_nothing() {
        // Silence is itself the diagnosis — a child that produced nothing
        // before the kill points at a different fault than one that errored.
        let msg = subprocess_diagnostic("linkedin MCP get_person_profile timed out after 240s", "", "   ");
        assert!(msg.contains("240s"));
        assert!(
            msg.contains("no output"),
            "an empty child must be reported as empty, not as a blank tail: {msg}"
        );
    }

    #[test]
    fn subprocess_diagnostic_truncates_a_flood() {
        // A hung MCP server can emit megabytes; the error must stay readable
        // and must say it truncated rather than silently cutting.
        let flood = "x".repeat(10_000);
        let msg = subprocess_diagnostic("linkedin MCP get_person_profile timed out after 240s", "", &flood);
        assert!(msg.len() < 3_000, "diagnostic must stay bounded: {} bytes", msg.len());
        assert!(msg.contains("truncated"));
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
        // dead session, but only after spawning the server and launching a
        // headless browser for a ~29s scrape that cannot succeed — once per
        // URL across an unattended batch.
        let body = fn_span(
            include_str!("knowledge_pipeline.rs"),
            "fn fetch_linkedin_content",
        );
        let probe = body
            .find("check_linkedin_session")
            .expect("fetch_linkedin_content must probe session health");
        let fetch = body
            .find("mcp_call_tool")
            .expect("fetch_linkedin_content must perform the MCP fetch");
        assert!(
            probe < fetch,
            "session health must be checked BEFORE the MCP tools/call"
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
            "fn resolve_tiered_linkedin_fetch",
            "fn fetch_linkedin_public_extract",
            "fn extract_linkedin_public_text",
            "fn collect_linkedin_comments",
            "fn linkedin_json_author_name",
            "fn format_linkedin_comments",
            "fn extract_linkedin_public_image_url",
            "fn collect_linkedin_image_urls",
            "fn ld_json_blocks",
            "fn collect_article_bodies",
            "fn extract_meta_content",
            "fn decode_html_entities",
            "pub fn unwrap_linkedin_safety_url",
            "fn is_public_http_target",
            "fn percent_decode",
            "fn check_linkedin_session",
            "fn resolve_session_health",
            "fn fetch_public_url",
            "fn mcp_call_tool",
            "fn extract_posts_section",
            "fn find_matching_post",
        ] {
            assert!(
                !fn_span(src, signature).contains("lock_pipeline"),
                "{signature} must never acquire the pipeline lock — non-reentrant, \
                 deadlocks when called from inside process_core (t-1144)"
            );
        }
    }

    // ── resolve_linkedin_scraper_binary ─────────────────────────────────

    #[test]
    fn resolve_linkedin_scraper_binary_does_not_panic() {
        // None is acceptable in environments without the tool installed —
        // the important contract is no panic, matching the sibling
        // resolvers' test convention (resolve_ruflo_binary, resolve_claude_binary).
        let _ = resolve_linkedin_scraper_binary();
    }

    // ── unwrap_linkedin_safety_url (t-2589) ────────────────────────────

    #[test]
    fn unwrap_safety_url_decodes_wrapped_target() {
        let wrapped = "https://www.linkedin.com/safety/go?url=https%3A%2F%2Fexample.com%2Fpost%3Fa%3D1";
        assert_eq!(unwrap_linkedin_safety_url(wrapped), "https://example.com/post?a=1");
    }

    #[test]
    fn unwrap_safety_url_cuts_trailing_params() {
        let wrapped = "https://www.linkedin.com/safety/go?url=https%3A%2F%2Fexample.com%2Fx&trk=feed";
        assert_eq!(unwrap_linkedin_safety_url(wrapped), "https://example.com/x");
    }

    #[test]
    fn unwrap_safety_url_rejects_non_public_targets() {
        // Challenger finding (t-2589, sev 4): the url= param is
        // attacker-authorable (any post author controls it), and the
        // decoded value becomes the pipeline's raw fetch target. Private,
        // loopback, link-local (cloud metadata), and non-http targets must
        // not be unwrapped — the wrapper URL passes through unchanged.
        for target in [
            "http%3A%2F%2Flocalhost%2Fadmin",
            "http%3A%2F%2F127.0.0.1%3A8080%2F",
            "http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data%2F",
            "https%3A%2F%2F10.0.0.7%2Finternal",
            "https%3A%2F%2F192.168.1.1%2F",
            "http%3A%2F%2F%5B%3A%3A1%5D%2F",
            "http%3A%2F%2Ffd00%3A%3A1%2F",
            "http%3A%2F%2Fuser%40127.0.0.1%2F",
            "ftp%3A%2F%2Fexample.com%2F",
            // Challenger iteration 2 (t-2589): IPv4-mapped IPv6 resolves to
            // the embedded IPv4 address at the socket layer on every
            // mainstream OS, bypassing native-v6-only range checks.
            "http%3A%2F%2F%5B%3A%3Affff%3A169.254.169.254%5D%2Flatest%2Fmeta-data%2F",
            "http%3A%2F%2F%5B%3A%3Affff%3A127.0.0.1%5D%2F",
        ] {
            let wrapped = format!("https://www.linkedin.com/safety/go?url={target}");
            assert_eq!(
                unwrap_linkedin_safety_url(&wrapped),
                wrapped,
                "must not unwrap to non-public target: {target}"
            );
        }
    }

    #[test]
    fn unwrap_safety_url_scheme_check_is_case_insensitive() {
        // Challenger iteration 2 (t-2589): an uppercase scheme must not
        // slip past strip_prefix and be treated as "not http", which would
        // fall back to fetching the ORIGINAL wrapped URL directly.
        let wrapped = "https://www.linkedin.com/safety/go?url=HTTP%3A%2F%2F169.254.169.254%2F";
        assert_eq!(unwrap_linkedin_safety_url(wrapped), wrapped);

        let ok = "https://www.linkedin.com/safety/go?url=HTTPS%3A%2F%2Fexample.com%2Fpost";
        assert_eq!(unwrap_linkedin_safety_url(ok), "HTTPS://example.com/post");
    }

    #[test]
    fn unwrap_safety_url_leaves_plain_urls_alone() {
        let plain = "https://www.linkedin.com/posts/someone_slug-activity-123-xy";
        assert_eq!(unwrap_linkedin_safety_url(plain), plain);
        let no_param = "https://www.linkedin.com/safety/go?trk=feed";
        assert_eq!(unwrap_linkedin_safety_url(no_param), no_param);
    }

    // ── canonicalize_url (t-2583, t-2590) ──────────────────────────────

    #[test]
    fn canonicalize_strips_tracking_params() {
        // The real observed shape (t-2583): the same LinkedIn post captured
        // clean and via a mobile share sheet carrying utm_*/rcm.
        let clean = "https://www.linkedin.com/posts/adrien-taravant-aa11bb_some-post-activity-h9dx";
        let tracked = "https://www.linkedin.com/posts/adrien-taravant-aa11bb_some-post-activity-h9dx?utm_source=share&utm_medium=member_android&rcm=ACoAAARwJLkBJqr70A1PJbG5r3-PHzY3QMybYwc";
        assert_eq!(canonicalize_url(tracked), clean);
        assert_eq!(canonicalize_url(clean), clean);
    }

    #[test]
    fn canonicalize_keeps_load_bearing_query_params() {
        // youtube.com/watch is meaningless without ?v= — strip only the
        // tracking keys (si is YouTube's share-tracking param), keep v.
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=AbCdEf123";
        assert_eq!(
            canonicalize_url(url),
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        );
    }

    #[test]
    fn canonicalize_strips_fragment() {
        assert_eq!(
            canonicalize_url("https://example.com/page?x=1#section-2"),
            "https://example.com/page?x=1"
        );
    }

    #[test]
    fn canonicalize_unwraps_safety_wrapper_then_strips_tracking() {
        // t-2590 residual: the same content shared via different /safety/go
        // wrappers must canonicalize to one URL.
        let wrapped =
            "https://www.linkedin.com/safety/go?url=https%3A%2F%2Fexample.com%2Fpost%3Futm_source%3Dshare&trk=feed";
        assert_eq!(canonicalize_url(wrapped), "https://example.com/post");
    }

    #[test]
    fn canonicalize_leaves_plain_urls_alone() {
        let plain = "https://example.com/a/b?page=2";
        assert_eq!(canonicalize_url(plain), plain);
    }

    // ── extract_linkedin_public_text (t-2589) ──────────────────────────

    fn post_html(article_body: Option<&str>, og_description: Option<&str>) -> String {
        let ld = article_body
            .map(|b| {
                format!(
                    r#"<script type="application/ld+json">{{"@type":"SocialMediaPosting","articleBody":{}}}</script>"#,
                    serde_json::json!(b)
                )
            })
            .unwrap_or_default();
        let og = og_description
            .map(|d| format!(r#"<meta property="og:description" content="{d}"/>"#))
            .unwrap_or_default();
        format!("<html><head>{og}{ld}</head><body>authwall</body></html>")
    }

    #[test]
    fn public_extract_prefers_longer_article_body() {
        let html = post_html(Some("the full post body, considerably longer"), Some("short og"));
        assert_eq!(
            extract_linkedin_public_text(&html).as_deref(),
            Some("the full post body, considerably longer")
        );
    }

    #[test]
    fn public_extract_og_wins_when_longer() {
        // AC (t-2589): max(articleBody, og:description) — og wins outright
        // on 2 of 15 spiked posts (one had ld=0/og=896, another ld=257/og=283).
        let html = post_html(Some("thin ld"), Some("a much longer og description carrying the real body"));
        assert_eq!(
            extract_linkedin_public_text(&html).as_deref(),
            Some("a much longer og description carrying the real body")
        );
    }

    #[test]
    fn public_extract_og_only_page_extracts() {
        let html = post_html(None, Some("og only body"));
        assert_eq!(extract_linkedin_public_text(&html).as_deref(), Some("og only body"));
    }

    #[test]
    fn public_extract_none_when_no_signals() {
        assert_eq!(extract_linkedin_public_text("<html><body>authwall</body></html>"), None);
    }

    #[test]
    fn public_extract_decodes_og_entities() {
        let html = r#"<meta property="og:description" content="A &amp; B &#39;quoted&#39; &lt;tag&gt;"/>"#;
        assert_eq!(
            extract_linkedin_public_text(html).as_deref(),
            Some("A & B 'quoted' <tag>")
        );
    }

    #[test]
    fn public_extract_takes_longest_article_body_across_blocks() {
        let html = format!(
            "{}{}",
            r#"<script type="application/ld+json">{"articleBody":"short"}</script>"#,
            r#"<script type="application/ld+json">{"@graph":[{"articleBody":"the nested and much longer article body"}]}</script>"#
        );
        assert_eq!(
            extract_linkedin_public_text(&html).as_deref(),
            Some("the nested and much longer article body")
        );
    }

    // ── extract_linkedin_public_text comment/image extraction (t-3187) ──
    //
    // Probe-validated 2026-08-24 (t-3151 session): the public post HTML
    // embeds ld+json `comment[]` (top ~10 comments, full text + author.name
    // — including the post author's own "link in first comment") and
    // `image.url`. See pattern_linkedin-public-ldjson-carries-comments-and-image.

    fn ldjson_html(value: &serde_json::Value) -> String {
        format!(
            r#"<html><head><script type="application/ld+json">{value}</script></head><body>authwall</body></html>"#
        )
    }

    #[test]
    fn public_extract_appends_comments_post_author_first() {
        let value = serde_json::json!({
            "@type": "SocialMediaPosting",
            "articleBody": "Sharing my new open source project.",
            "author": {"@type": "Person", "name": "Jane Doe"},
            "comment": [
                {"@type": "Comment", "text": "Great post!", "author": {"@type": "Person", "name": "Random Reader"}},
                {"@type": "Comment", "text": "Link: https://github.com/example-org/patterns-repo", "author": {"@type": "Person", "name": "Jane Doe"}},
                {"@type": "Comment", "text": "Nice work.", "author": {"@type": "Person", "name": "Another Reader"}}
            ]
        });
        let html = ldjson_html(&value);
        let expected = "Sharing my new open source project.\n\nComments:\n\
                         Jane Doe: Link: https://github.com/example-org/patterns-repo\n\
                         Random Reader: Great post!\n\
                         Another Reader: Nice work.";
        assert_eq!(extract_linkedin_public_text(&html).as_deref(), Some(expected));
    }

    #[test]
    fn public_extract_no_ldjson_bot_shell_succeeds_without_comments() {
        // AC boundary (a): bot-shell HTML with no ld+json at all must still
        // succeed with base (og:description) behavior — no comments
        // appended, no error.
        let html = r#"<meta property="og:description" content="Post preview text"/>"#;
        assert_eq!(extract_linkedin_public_text(html).as_deref(), Some("Post preview text"));
    }

    #[test]
    fn public_extract_ldjson_present_comment_key_absent_no_block() {
        // AC boundary (b): ld+json present but no `comment` key at all.
        let value = serde_json::json!({"articleBody": "Body text only, no comment key at all."});
        let html = ldjson_html(&value);
        assert_eq!(
            extract_linkedin_public_text(&html).as_deref(),
            Some("Body text only, no comment key at all.")
        );
    }

    #[test]
    fn public_extract_ldjson_present_comment_array_empty_no_block() {
        // AC boundary (b): ld+json present, `comment` key present but empty.
        let value = serde_json::json!({"articleBody": "Body text.", "comment": []});
        let html = ldjson_html(&value);
        assert_eq!(extract_linkedin_public_text(&html).as_deref(), Some("Body text."));
    }

    #[test]
    fn public_extract_comment_missing_author_name_falls_back_gracefully() {
        // AC: a comment with a missing author name must not panic and must
        // still be appended, attributed as "(unknown)".
        let value = serde_json::json!({
            "articleBody": "Body text.",
            "comment": [
                {"text": "Anonymous comment with no author object at all."},
                {"text": "Comment with an author object but no name field.", "author": {"@type": "Person"}}
            ]
        });
        let html = ldjson_html(&value);
        let expected = "Body text.\n\nComments:\n\
                         (unknown): Anonymous comment with no author object at all.\n\
                         (unknown): Comment with an author object but no name field.";
        assert_eq!(extract_linkedin_public_text(&html).as_deref(), Some(expected));
    }

    #[test]
    fn public_extract_realistic_fixture_link_in_first_comment() {
        // Realistic captured shape (t-3151 probe, 2026-08-24): headline,
        // author, articleBody, image.url, commentCount, and top comment[]
        // entries — including the post author's own "link in first
        // comment" (the classic LinkedIn pattern for sharing an external
        // link without the algorithm's outbound-link penalty).
        let html = r#"<html><head>
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SocialMediaPosting",
  "headline": "Sharing a new open-source pattern library",
  "articleBody": "Just published a set of reusable engineering patterns. Link is in the first comment below — LinkedIn buries posts with outbound links.",
  "commentCount": 42,
  "author": {"@type": "Person", "name": "Priya Shah"},
  "image": {"@type": "ImageObject", "url": "https://media.licdn.com/dms/image/D4E22AQ_example/feedshare-shrink/0"},
  "comment": [
    {"@type": "Comment", "text": "Link in first comment: https://github.com/example-org/patterns-repo", "author": {"@type": "Person", "name": "Priya Shah"}},
    {"@type": "Comment", "text": "This is incredibly useful, thank you for sharing!", "author": {"@type": "Person", "name": "Marcus Lee"}},
    {"@type": "Comment", "text": "Bookmarking this for the team.", "author": {"@type": "Person", "name": "Grace Kim"}},
    {"@type": "Comment", "text": "Do you have a Rust example too?", "author": {"@type": "Person", "name": "Marcus Lee"}}
  ]
}
</script>
</head><body>authwall</body></html>"#;

        let extracted = extract_linkedin_public_text(html).expect("realistic fixture must extract");
        assert!(
            extracted.starts_with(
                "Just published a set of reusable engineering patterns. Link is in the first \
                 comment below \u{2014} LinkedIn buries posts with outbound links."
            ),
            "base article body must lead: {extracted}"
        );
        let comment_block = extracted
            .split("\n\nComments:\n")
            .nth(1)
            .expect("a Comments: block must be appended");
        let lines: Vec<&str> = comment_block.lines().collect();
        assert_eq!(
            lines[0],
            "Priya Shah: Link in first comment: https://github.com/example-org/patterns-repo",
            "the post author's link-in-comment must be ordered first"
        );
        assert_eq!(lines.len(), 4, "all four comments must be appended: {lines:?}");
        assert!(
            lines[1..].iter().any(|l| l.contains("Marcus Lee") && l.contains("incredibly useful")),
            "non-author comments must still be present"
        );

        assert_eq!(
            extract_linkedin_public_image_url(html),
            Some("https://media.licdn.com/dms/image/D4E22AQ_example/feedshare-shrink/0".to_string())
        );
    }

    // ── extract_linkedin_public_image_url (t-3187) ──────────────────────

    #[test]
    fn public_extract_image_url_present() {
        let value = serde_json::json!({
            "articleBody": "Body",
            "image": {"@type": "ImageObject", "url": "https://media.licdn.com/dms/image/abc123"}
        });
        let html = ldjson_html(&value);
        assert_eq!(
            extract_linkedin_public_image_url(&html),
            Some("https://media.licdn.com/dms/image/abc123".to_string())
        );
    }

    #[test]
    fn public_extract_image_url_absent_is_none() {
        let value = serde_json::json!({"articleBody": "Body, no image field."});
        let html = ldjson_html(&value);
        assert_eq!(extract_linkedin_public_image_url(&html), None);
    }

    #[test]
    fn public_extract_image_url_no_ldjson_bot_shell_is_none() {
        assert_eq!(
            extract_linkedin_public_image_url("<html><body>authwall</body></html>"),
            None
        );
    }

    #[test]
    fn public_extract_image_url_nested_under_graph() {
        // LinkedIn nests directly or under @graph depending on post type
        // (same tolerance as collect_article_bodies).
        let html =
            r#"<script type="application/ld+json">{"@graph":[{"image":{"url":"https://media.licdn.com/nested.jpg"}}]}</script>"#;
        assert_eq!(
            extract_linkedin_public_image_url(html),
            Some("https://media.licdn.com/nested.jpg".to_string())
        );
    }

    // ── resolve_tiered_linkedin_fetch (t-2589 tier inversion) ──────────

    fn long_public(n: usize) -> String {
        "x".repeat(n)
    }

    #[test]
    fn tiered_fetch_sufficient_public_never_calls_tier2() {
        // AC (t-2589): tier-2 runs only when the public extract is below
        // the threshold.
        let tier2_called = std::cell::Cell::new(false);
        let text = long_public(LINKEDIN_PUBLIC_MIN_CHARS);
        let got = resolve_tiered_linkedin_fetch(Ok(Some(text.clone())), || {
            tier2_called.set(true);
            bail!("tier-2 must not run")
        })
        .unwrap();
        assert_eq!(got, Some(text));
        assert!(!tier2_called.get(), "tier-2 invoked despite sufficient public extract");
    }

    #[test]
    fn tiered_fetch_thin_public_enriched_by_longer_tier2() {
        let got = resolve_tiered_linkedin_fetch(Ok(Some("thin".into())), || {
            Ok(Some("a longer tier-2 feed match".into()))
        })
        .unwrap();
        assert_eq!(got.as_deref(), Some("a longer tier-2 feed match"));
    }

    #[test]
    fn tiered_fetch_thin_public_beats_shorter_tier2() {
        let got = resolve_tiered_linkedin_fetch(Ok(Some("thin but longer than t2".into())), || {
            Ok(Some("t2".into()))
        })
        .unwrap();
        assert_eq!(got.as_deref(), Some("thin but longer than t2"));
    }

    #[test]
    fn tiered_fetch_thin_public_survives_tier2_miss_and_error() {
        let got = resolve_tiered_linkedin_fetch(Ok(Some("thin".into())), || Ok(None)).unwrap();
        assert_eq!(got.as_deref(), Some("thin"));
        let got = resolve_tiered_linkedin_fetch(Ok(Some("thin".into())), || bail!("session dead")).unwrap();
        assert_eq!(got.as_deref(), Some("thin"));
    }

    #[test]
    fn tiered_fetch_absent_public_falls_through_to_tier2() {
        // AC (t-2589): a post tier-2 CAN find still stores when the public
        // path has nothing; a genuine double miss stays Ok(None).
        let got = resolve_tiered_linkedin_fetch(Ok(None), || Ok(Some("t2 body".into()))).unwrap();
        assert_eq!(got.as_deref(), Some("t2 body"));
        let got = resolve_tiered_linkedin_fetch(Ok(None), || Ok(None)).unwrap();
        assert_eq!(got, None);
    }

    #[test]
    fn tiered_fetch_propagates_errors_when_nothing_salvageable() {
        // Transport failure is still Err — never degraded to a miss.
        assert!(resolve_tiered_linkedin_fetch(Ok(None), || bail!("t2 broke")).is_err());
        assert!(resolve_tiered_linkedin_fetch(Err(anyhow::anyhow!("dns")), || Ok(None)).is_err());
        let got = resolve_tiered_linkedin_fetch(Err(anyhow::anyhow!("dns")), || {
            Ok(Some("t2 saves the day".into()))
        })
        .unwrap();
        assert_eq!(got.as_deref(), Some("t2 saves the day"));
    }

    #[test]
    #[ignore = "live network probe — run manually: cargo test -p brana-core live_public_extract -- --ignored"]
    fn live_public_extract_real_post() {
        // Revalidates the t-2589 spike against LinkedIn's live markup: a
        // real post must yield a usable public extract, fast, with no auth.
        // If this starts failing, LinkedIn changed its preview metadata and
        // the tier inversion needs re-verification.
        let url = "https://www.linkedin.com/posts/ghiles-moussaoui-b36218250_loop-to-graph-engineering-ugcPost-7486019288294817792-Sr9I/";
        let started = std::time::Instant::now();
        let got = fetch_linkedin_public_extract(url).expect("transport must not fail");
        let elapsed = started.elapsed();
        let (text, image_url) = got.expect("a live post must have public preview text");
        println!(
            "live extract: {} chars in {:?}, image_url={image_url:?}",
            text.chars().count(),
            elapsed
        );
        assert!(
            text.chars().count() >= LINKEDIN_PUBLIC_MIN_CHARS,
            "live post extract under threshold: {} chars",
            text.chars().count()
        );
        assert!(elapsed.as_secs() < 10, "public extract took {elapsed:?} — should be ~1s");
    }

    // ── fetch_linkedin_public_extract text+image tuple wiring (t-3187) ──

    #[test]
    fn fetch_linkedin_public_extract_returns_text_and_image_tuple() {
        let body = r#"<html><head><script type="application/ld+json">{"articleBody":"hi there","image":{"url":"https://media.licdn.com/x.jpg"}}</script></head><body>authwall</body></html>"#;
        let (addr, handle) = serve_once("HTTP/1.1 200 OK", body);
        let result = fetch_linkedin_public_extract(&format!("http://{addr}/"));
        handle.join().unwrap();
        let (text, image_url) = result.unwrap().expect("must extract from mock server");
        assert_eq!(text, "hi there");
        assert_eq!(image_url.as_deref(), Some("https://media.licdn.com/x.jpg"));
    }

    #[test]
    fn fetch_linkedin_public_extract_no_image_is_none() {
        let body = r#"<html><head><script type="application/ld+json">{"articleBody":"hi there, no image"}</script></head><body>authwall</body></html>"#;
        let (addr, handle) = serve_once("HTTP/1.1 200 OK", body);
        let result = fetch_linkedin_public_extract(&format!("http://{addr}/"));
        handle.join().unwrap();
        let (text, image_url) = result.unwrap().expect("must extract from mock server");
        assert_eq!(text, "hi there, no image");
        assert_eq!(image_url, None);
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

    // TDD-red as of t-2947 (pre-impl): classify_platform has no youtube
    // case yet, so this fails today. Implementation lands in the follow-up
    // task per docs/architecture/features/youtube-knowledge-extraction.md §1.
    #[test]
    fn test_classify_platform_youtube() {
        assert_eq!(classify_platform("https://www.youtube.com/watch?v=jNQXAC9IVRw"), "youtube");
        assert_eq!(classify_platform("https://www.youtube.com/shorts/abc123"), "youtube");
        assert_eq!(classify_platform("https://youtu.be/jNQXAC9IVRw"), "youtube");
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