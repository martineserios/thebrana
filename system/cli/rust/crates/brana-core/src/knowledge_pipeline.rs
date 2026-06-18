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

/// agy version this CLI layer is tested against.
/// Must match AGY_PINNED_VERSION in brana-mcp/src/tools/agy_delegate.rs.
/// Upgrade procedure: bump → re-run adversarial spike → confirm JSON contract → commit.
pub const AGY_CLI_PINNED_VERSION: &str = "1.0.9";

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
    /// Not yet consumed by tier1 scoring — see t-1144 (LinkedIn pre-pass implementation).
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
    let known: std::collections::HashSet<String> = state.urls.keys().cloned().collect();
    let mut all = Vec::new();
    for log_path in find_event_log_files() {
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

// ── Gemini CLI shell-out (call_gemini_json — ADR-040 Tier1/Tier2 routing) ────

/// Check that the installed agy binary matches [`AGY_CLI_PINNED_VERSION`].
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
            "agy --version unavailable — cannot verify version pin {AGY_CLI_PINNED_VERSION}. \
             Binary exists but --version flag failed."
        );
    }

    let version = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if version != AGY_CLI_PINNED_VERSION {
        bail!(
            "agy version mismatch: expected {AGY_CLI_PINNED_VERSION}, got {version} — \
             update AGY_CLI_PINNED_VERSION in knowledge_pipeline.rs after re-running adversarial spike"
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
    fn test_check_agy_version_accepts_pinned() {
        let bin = write_fake_agy(&format!("echo '{AGY_CLI_PINNED_VERSION}'"), "ver-ok");
        let result = check_agy_version_with_bin(bin.to_str().unwrap());
        let _ = std::fs::remove_file(&bin);
        assert!(result.is_ok(), "pinned version should pass: {:?}", result.err());
    }

    #[cfg(unix)]
    #[test]
    fn test_check_agy_version_rejects_mismatch() {
        let bin = write_fake_agy("echo '0.0.0'", "ver-bad");
        let result = check_agy_version_with_bin(bin.to_str().unwrap());
        let _ = std::fs::remove_file(&bin);
        let err = result.unwrap_err().to_string();
        assert!(err.contains("version mismatch"), "should report mismatch: {err}");
        assert!(err.contains(AGY_CLI_PINNED_VERSION), "should name expected: {err}");
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