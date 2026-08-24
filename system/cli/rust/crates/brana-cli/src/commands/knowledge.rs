//! Knowledge subcommand handlers

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use brana_core::knowledge_pipeline::{
    self as kp, DRAFT_CAP, UrlStatus,
};
use brana_core::ruflo::{ruflo_memory_get, ruflo_memory_store};
use brana_core::tasks;
use std::io::IsTerminal as _;

use crate::util::{find_project_root, home};

/// Ruflo namespace `process-url` stores into. Independent of the tier1/2/3
/// pipeline's own state file (ADR-070 §Scope split) — this command does not
/// share or mutate `~/.swarm/knowledge-pipeline-state.json`.
const PROCESS_URL_NAMESPACE: &str = "knowledge";

/// Below this many non-whitespace characters, fetched content is treated as
/// empty and stored nothing. A JS-only page or an auth wall strips down to a
/// handful of characters; storing that yields a namespace entry that looks
/// real to search and carries no information.
const MIN_STORABLE_CHARS: usize = 40;

/// Storage key for a processed URL: `knowledge:url:{slug}`.
///
/// Idempotency depends on this being a pure function of the URL — the second
/// run recognises the first run's entry only if it derives the same key.
/// Keyed on the canonical URL (safety-wrapper unwrapped, tracking params
/// stripped — t-2583/t-2590), so share-sheet variants of the same page
/// resolve to one entry.
fn url_storage_key(url: &str) -> String {
    let canonical = brana_core::knowledge_pipeline::canonicalize_url(url);
    let trimmed = canonical
        .trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_end_matches('/');

    let mut slug = String::with_capacity(trimmed.len());
    let mut last_was_dash = false;
    for ch in trimmed.chars() {
        if ch.is_ascii_alphanumeric() {
            slug.push(ch.to_ascii_lowercase());
            last_was_dash = false;
        } else if !last_was_dash {
            slug.push('-');
            last_was_dash = true;
        }
    }
    format!("knowledge:url:{}", slug.trim_matches('-'))
}

/// What one `process-url` invocation decided to do with a URL.
#[derive(Debug, PartialEq, Eq)]
enum ProcessUrlOutcome {
    /// Key already present — nothing fetched, nothing stored.
    AlreadyStored,
    /// Fetch returned `Ok(None)`: the LinkedIn post was not in the author's
    /// feed. A miss, not a failure (ADR-070 §Tier-2 correction).
    NotFound,
    /// Fetched, but the content was empty/near-empty — stored nothing.
    EmptyContent,
    /// Fetched substantive content; extract and store it.
    Store,
}

/// Decide a URL's outcome from the idempotency probe and the fetch result.
///
/// Pure so the four branches are testable without ruflo or the network;
/// the handler below owns the I/O and the printing.
fn resolve_process_url_outcome(
    already_stored: bool,
    fetched: Option<&kp::FetchedContent>,
) -> ProcessUrlOutcome {
    if already_stored {
        return ProcessUrlOutcome::AlreadyStored;
    }
    match fetched {
        None => ProcessUrlOutcome::NotFound,
        Some(c) if c.text.trim().chars().count() < MIN_STORABLE_CHARS => {
            ProcessUrlOutcome::EmptyContent
        }
        Some(_) => ProcessUrlOutcome::Store,
    }
}

/// Compute the value to store and its tags for a `Store` outcome. Pure —
/// takes the already-extracted insight rather than calling
/// `kp::extract_insight` itself, so it's testable without that function's
/// real agy/`claude -p` subprocess calls (same "test the decision, not the
/// I/O" discipline as `resolve_process_url_outcome` above).
///
/// youtube skips summarization entirely and stores `content.text`
/// unmodified, tagged `[platform, "transcript", caption_source]` — a short
/// summary of a long transcript is only marginally less shallow than the
/// HTML-shell bug this whole command exists to fix (feature spec §3,
/// t-2950). Every other platform keeps the existing summarized-storage
/// behavior, unchanged. `insight` must be `Some` for every non-youtube
/// platform — the caller (`process_one_url`) only skips computing it for
/// youtube.
fn resolve_store_value(
    content: &kp::FetchedContent,
    insight: Option<&kp::ExtractedInsight>,
) -> (String, Vec<String>) {
    if content.platform == "youtube" {
        let source = content.caption_source.unwrap_or("auto");
        return (
            content.text.clone(),
            vec![content.platform.to_string(), "transcript".to_string(), source.to_string()],
        );
    }
    let insight = insight.expect("non-youtube Store always has an extracted insight");
    (insight.summary.clone(), vec![content.platform.to_string(), insight.topic.clone()])
}

/// One `{id, url}` record from a batch file.
#[derive(Debug, Deserialize)]
struct BatchEntry {
    id: String,
    url: String,
}

/// Parse a batch JSONL body into records, ignoring blank lines.
///
/// Errors name the 1-based line number: a batch runs unattended, and
/// "invalid json" alone would mean bisecting the file by hand.
fn parse_batch_file(body: &str) -> Result<Vec<BatchEntry>> {
    let mut entries = Vec::new();
    for (i, line) in body.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        let entry: BatchEntry = serde_json::from_str(line)
            .with_context(|| format!("line {}: expected {{\"id\":…,\"url\":…}}", i + 1))?;
        entries.push(entry);
    }
    Ok(entries)
}

/// Whether an outcome means the URL's tracking task is safe to cancel.
///
/// Only outcomes where the content actually reached the knowledge base
/// qualify. A miss or an empty fetch leaves the link genuinely unread, so
/// cancelling its stub would silently drop the work (spec §Edge Cases).
fn is_cancellable(outcome: &ProcessUrlOutcome) -> bool {
    match outcome {
        ProcessUrlOutcome::Store | ProcessUrlOutcome::AlreadyStored => true,
        ProcessUrlOutcome::NotFound | ProcessUrlOutcome::EmptyContent => false,
    }
}

/// Batch exit code: non-zero only when a URL genuinely failed.
///
/// NotFound and EmptyContent are expected outcomes the spec calls "not
/// itself an error", so they deliberately do not count — otherwise a
/// nightly cron would alert on every batch containing one old post.
fn batch_exit_code(failures: usize) -> i32 {
    if failures > 0 { 1 } else { 0 }
}

/// Pull the captured URL out of a link task's `context` field.
///
/// `process-link-queue.sh` writes `... URL: {url}` into the context, so the
/// marker — not position — is what identifies it.
///
/// The trailing-quote trim is a regression guard, not defensiveness:
/// `backlog get --field` emits a *JSON-quoted* string, so a URL sitting at
/// the end of the context absorbed the closing `"` and every fetch ran
/// against a malformed URL (personal-repo t-1365). Trimming here means the
/// extractor is correct whether the caller hands us a decoded value or a
/// raw one.
fn extract_capture_url(context: &str) -> Option<String> {
    let rest = context.split("URL: ").nth(1)?;
    let token = rest.split_whitespace().next()?;
    let cleaned = token.trim_end_matches(['"', '\\', ',']);
    if cleaned.is_empty() {
        return None;
    }
    Some(cleaned.to_string())
}

/// Take at most `cap` link IDs for this run, leaving the rest pending.
///
/// Per-run cap rather than a watermark (pattern_per-run-cap-backlog-draining,
/// t-2076): `process_one_url` short-circuits on an already-stored key, so a
/// later run re-scanning what this one skipped costs a cheap idempotency
/// probe per link and nothing else. Nothing to advance, nothing to corrupt.
fn select_drain_batch(ids: &[String], cap: usize) -> Vec<String> {
    ids.iter().take(cap).cloned().collect()
}

/// Whether a drain-links candidate URL belongs in this run's batch, given
/// an optional `--platform` filter (feature spec §5, t-2955 tests /
/// t-2956 impl). `platform: None` is the existing shared job — excludes
/// youtube (it runs its own separate job, its own cap, its own
/// backoff/retry) so a stuck youtube fetch can never starve
/// LinkedIn/GitHub/Substack/arxiv slots in the same batch. `platform:
/// Some("youtube")` is the new youtube-only job.
///
/// This is the split point — `select_drain_batch` itself stays a bare
/// `.take(cap)`, unmodified; the platform split lives entirely in the
/// candidate filter that runs before it.
///
/// Reconciled onto `kp::classify_platform` (t-2950) — it inlined its own
/// `youtube.com`/`youtu.be` match while classify_platform's youtube case
/// was still a separate pending task (t-2956 Challenger finding: two
/// places independently deciding what counts as a youtube URL). No
/// behavior change; same URL patterns, single source of truth now.
fn candidate_passes_platform_filter(url: &str, platform: Option<&str>) -> bool {
    let is_youtube = kp::classify_platform(url) == "youtube";
    match platform {
        None => !is_youtube,
        Some("youtube") => is_youtube,
        // Fail closed: no other platform-specific job exists yet, so an
        // unrecognized --platform value selects nothing rather than
        // silently reusing the default job's set (which would include
        // URLs the caller didn't ask for).
        Some(_) => false,
    }
}

/// Whether a drained link's tracking task may be marked completed.
///
/// Delegates to [`is_cancellable`] deliberately — "the content reached the
/// knowledge base" is ONE predicate, and a drain that answered it separately
/// could drift from the batch advisory that reports it. The same
/// two-copies-of-one-query shape is what let the capture pipeline's staleness
/// watchdog fail in exactly the mode it was built to detect (t-1364).
///
/// This is the defect this whole command exists to kill: the bash it replaces
/// marked a task completed whenever `claude -p` exited 0, including when it
/// persisted nothing (personal-repo t-1366, P0). Completion follows the
/// artifact, never the exit status.
fn should_complete_link(outcome: &ProcessUrlOutcome) -> bool {
    is_cancellable(outcome)
}

/// `brana knowledge process-url --file <jsonl>` — process each `{id,url}`
/// record in sequence, then print an advisory list of task IDs whose
/// content is now in the knowledge base.
///
/// Advisory only: this never calls `backlog set` (spec §Assumptions) — the
/// operator decides what to cancel.
pub fn cmd_process_url_batch(path: &std::path::Path, cookies: &kp::YtDlpCookies) -> Result<()> {
    let body = std::fs::read_to_string(path)
        .with_context(|| format!("reading batch file {}", path.display()))?;
    let entries = parse_batch_file(&body)?;

    let mut cancellable: Vec<String> = Vec::new();
    let mut failures = 0usize;

    for entry in &entries {
        match process_one_url(&entry.url, cookies) {
            Ok(outcome) => {
                if is_cancellable(&outcome) {
                    cancellable.push(entry.id.clone());
                }
            }
            Err(e) => {
                // Keep going: one dead link must not strand the rest of a
                // nightly batch. The exit code still reports the failure.
                failures += 1;
                eprintln!("{}: FAILED — {e:#}", entry.url);
            }
        }
    }

    println!("\nProcessed {} URL(s), {failures} failed.", entries.len());
    if cancellable.is_empty() {
        println!("No task IDs are safe to cancel from this batch.");
    } else {
        println!("Task IDs safe to cancel (advisory — not applied):");
        for id in &cancellable {
            println!("  {id}");
        }
    }

    let code = batch_exit_code(failures);
    if code != 0 {
        bail!("{failures} URL(s) failed in this batch");
    }
    Ok(())
}

/// A pending link task selected for this drain run.
struct DrainCandidate {
    id: String,
    url: String,
}

/// `brana knowledge drain-links` — drain pending `link`-tagged tasks from a
/// project's backlog through `process-url`, completing only those whose
/// content actually reached the knowledge base.
///
/// Replaces `personal/deploy/research-extraction.sh`. Three things differ
/// from the bash, each a defect it shipped:
///
/// 1. **Completion follows the artifact.** The bash ran
///    `claude -p ... >/dev/null 2>&1` and marked the task completed on exit
///    0 — `/brana:research` exits 0 without persisting anything for a bare
///    link, so 33 links drained into `completed` with nothing captured
///    (personal-repo t-1366, P0). Here the outcome comes from the ruflo
///    idempotency probe and the fetch, via [`should_complete_link`].
/// 2. **The batch cannot truncate.** The bash looped `while read` over ids
///    and called `claude` inside it; the child drained the shared stdin, so
///    a cap of 3 processed 1 (t-1367). A `for` over an owned Vec has no
///    stdin to share.
/// 3. **Output is not discarded.** Every per-link outcome is printed.
///
/// The tasks lock is taken twice and never held across the network: a batch
/// of 27 links takes minutes, and holding the sidecar lock through it would
/// stall every other writer of that backlog.
pub fn cmd_drain_links(
    file: Option<PathBuf>,
    cap: usize,
    dry_run: bool,
    platform: Option<&str>,
    cookies: &kp::YtDlpCookies,
) -> Result<()> {
    let tf = match file {
        Some(f) => f,
        None => brana_core::util::find_tasks_file().context("tasks.json not found")?,
    };

    // --- Phase 1: select (locked, no I/O beyond the read) ---------------
    let candidates: Vec<DrainCandidate> = {
        let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
        let val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
        let empty: Vec<serde_json::Value> = Vec::new();
        let all = val["tasks"].as_array().unwrap_or(&empty);

        let filter = tasks::TaskFilter {
            tag: Some("link"),
            status: Some("pending"),
            ..Default::default()
        };
        let pending = tasks::filter_tasks_by(all, all, &filter);

        // Skip-with-reason, never silently: a link whose context carries no
        // URL is a capture bug, and dropping it quietly is how this pipeline
        // lost work before.
        let mut with_urls: Vec<DrainCandidate> = Vec::new();
        for t in pending {
            let Some(id) = t["id"].as_str() else { continue };
            let ctx = t["context"].as_str().unwrap_or("");
            match extract_capture_url(ctx) {
                Some(url) => with_urls.push(DrainCandidate { id: id.to_string(), url }),
                None => println!("skip {id}: no 'URL:' marker in context"),
            }
        }

        // Platform split (feature spec §5) — runs before select_drain_batch,
        // which stays a bare .take(cap) unmodified. `platform: None` (the
        // existing shared job) excludes youtube; `--platform youtube`
        // selects only youtube.
        with_urls.retain(|c| candidate_passes_platform_filter(&c.url, platform));

        let ids: Vec<String> = with_urls.iter().map(|c| c.id.clone()).collect();
        let selected = select_drain_batch(&ids, cap);
        with_urls.retain(|c| selected.contains(&c.id));
        with_urls
    };

    if candidates.is_empty() {
        // An unrecognized --platform value fails closed (selects nothing,
        // candidate_passes_platform_filter's `Some(_) => false` arm) —
        // distinguish that from a legitimately empty batch rather than
        // printing the same message either way (Challenger finding,
        // t-2956 implementation gate).
        match platform {
            Some(p) if p != "youtube" => {
                println!(
                    "No candidates selected — \"{p}\" is not a recognized --platform value \
                     (only \"youtube\" is supported today). Nothing was drained."
                );
            }
            _ => println!("No pending link tasks with a URL — nothing to drain."),
        }
        return Ok(());
    }

    if dry_run {
        println!("Would drain {} link(s) (cap {cap}):", candidates.len());
        for c in &candidates {
            println!("  {} {}", c.id, c.url);
        }
        return Ok(());
    }

    // --- Phase 2: process (unlocked — this is the slow, networked part) --
    let mut completable: Vec<String> = Vec::new();
    let mut failures = 0usize;
    for c in &candidates {
        println!("\ndraining {}: {}", c.id, c.url);
        match process_one_url(&c.url, cookies) {
            Ok(outcome) => {
                if should_complete_link(&outcome) {
                    completable.push(c.id.clone());
                } else {
                    // Left pending deliberately — the link is still unread.
                    println!("  {} left pending ({outcome:?} — nothing stored)", c.id);
                }
            }
            Err(e) => {
                failures += 1;
                eprintln!("  {} FAILED — {e:#}", c.id);
            }
        }
    }

    // --- Phase 3: complete (locked again, re-reading current state) ------
    let mut completed = 0usize;
    if !completable.is_empty() {
        let _lock = tasks::lock_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
        let mut val = tasks::load_raw(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
        for id in &completable {
            let idx = val["tasks"]
                .as_array()
                .and_then(|arr| arr.iter().position(|t| t["id"].as_str() == Some(id.as_str())));
            let Some(idx) = idx else {
                eprintln!("  {id} vanished from the backlog before completion — skipped");
                continue;
            };
            let task = &mut val["tasks"][idx];
            if let Err(e) = tasks::set_field(task, "status", "completed", false) {
                eprintln!("  {id} could not be completed: {e}");
                continue;
            }
            completed += 1;
        }
        tasks::save_tasks(&tf, &val).map_err(|e| anyhow::anyhow!("{e}"))?;
    }

    println!(
        "\nDrained {} link(s): {completed} completed, {} left pending, {failures} failed.",
        candidates.len(),
        candidates.len() - completed - failures
    );

    if failures > 0 {
        bail!("{failures} link(s) failed in this drain");
    }
    Ok(())
}

/// `brana knowledge process-url <url>` — fetch one URL, extract an insight,
/// store it in the ruflo `knowledge` namespace keyed by slugified URL.
///
/// Idempotent: an existing key short-circuits before the fetch, so re-running
/// a nightly batch costs nothing per already-processed URL.
///
/// Never acquires the pipeline lock — this command's storage is independent
/// of the tier1/2/3 pipeline (ADR-070 §Lock discipline).
pub fn cmd_process_url(url: &str, cookies: &kp::YtDlpCookies) -> Result<()> {
    process_one_url(url, cookies).map(|_| ())
}

/// Map the `--cookies-from-browser` / `--cookies` flags to
/// [`kp::YtDlpCookies`] (t-3033, feature spec §7) — the single place the
/// CLI surface meets the core type. Fails early, before any yt-dlp call,
/// with an error naming the path when a `--cookies` file is missing,
/// unreadable by this process (cron user ≠ exporting user), or not UTF-8.
/// The path is canonicalized because the yt-dlp child runs with
/// `current_dir(<scratch work dir>)`, where a relative path would resolve
/// against the wrong directory. clap makes the two flags mutually
/// exclusive; both `None` is today's unauthenticated default.
pub fn resolve_yt_dlp_cookies(
    from_browser: Option<String>,
    file: Option<PathBuf>,
) -> Result<kp::YtDlpCookies> {
    resolve_yt_dlp_cookies_with(from_browser, file, default_yt_dlp_cookie_jar().as_deref())
}

/// The persisted cookie jar (feature spec §8, t-3038): consulted only when
/// neither flag is given, so a scheduled `drain-links --platform youtube`
/// needs no per-run flag. Lives outside every git repo and the synced
/// `~/.claude/` tree, next to `linear.env`. `None` when `$HOME` is unset
/// or not absolute — see `default_yt_dlp_cookie_jar_in`.
pub fn default_yt_dlp_cookie_jar() -> Option<PathBuf> {
    default_yt_dlp_cookie_jar_in(&home())
}

/// `default_yt_dlp_cookie_jar` for an explicit home. A non-absolute home
/// (notably the empty string `util::home()` yields when `$HOME` is unset)
/// returns `None` rather than a cwd-relative `.config/brana/yt-cookies.txt`
/// — in a stripped scheduler environment that relative path would let a
/// planted file in the working directory pose as the trusted credential
/// (t-3038 rung-2 panel finding).
pub fn default_yt_dlp_cookie_jar_in(home: &std::path::Path) -> Option<PathBuf> {
    if !home.is_absolute() {
        return None;
    }
    Some(home.join(".config").join("brana").join("yt-cookies.txt"))
}

/// `resolve_yt_dlp_cookies` with the default-jar location injected, so tests
/// never touch the real `$HOME`. Precedence: explicit flag > default jar
/// (if present) > `None`.
///
/// The implicit jar must be private: any group/other permission bit is a
/// hard error naming `chmod 600` (a warning would leave the requirement
/// unenforced — same stance as ssh on a loose private key). An explicit
/// `--cookies` keeps §7's contract and is not mode-checked. A default jar
/// that exists but cannot be read is also an error: the operator placed a
/// file there, so failing loud beats silently draining unauthenticated.
pub fn resolve_yt_dlp_cookies_with(
    from_browser: Option<String>,
    file: Option<PathBuf>,
    default_jar: Option<&std::path::Path>,
) -> Result<kp::YtDlpCookies> {
    match (from_browser, file) {
        (Some(browser), None) => Ok(kp::YtDlpCookies::FromBrowser(browser)),
        (_, Some(path)) => checked_jar(&path, "--cookies"),
        (None, None) => match default_jar {
            Some(jar) if jar.exists() => {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt as _;
                    let mode = std::fs::metadata(jar)
                        .with_context(|| format!("persisted cookie jar {}: cannot stat", jar.display()))?
                        .permissions()
                        .mode()
                        & 0o777;
                    if mode & 0o077 != 0 {
                        bail!(
                            "persisted cookie jar {}: mode {:04o} is readable by others — run `chmod 600 {}` (it is a Google bearer credential)",
                            jar.display(),
                            mode,
                            jar.display()
                        );
                    }
                }
                checked_jar(jar, "persisted cookie jar")
            }
            _ => Ok(kp::YtDlpCookies::None),
        },
    }
}

/// §7's checks shared by both jar sources: canonicalize (the child runs
/// with `current_dir(work_dir)`), open-for-read (existence alone misses the
/// cron-user-can't-read case), and UTF-8 (so `to_args` never mangles).
fn checked_jar(path: &std::path::Path, label: &str) -> Result<kp::YtDlpCookies> {
    let abs = path
        .canonicalize()
        .with_context(|| format!("{label} {}: file not found", path.display()))?;
    std::fs::File::open(&abs)
        .with_context(|| format!("{label} {}: not readable by this process", abs.display()))?;
    if abs.to_str().is_none() {
        bail!("{label} {}: path is not valid UTF-8", abs.display());
    }
    Ok(kp::YtDlpCookies::File(abs))
}

/// Process a single URL and report which branch it took. Shared by the
/// single-URL command and the batch loop, so batch mode cannot drift from
/// the semantics the single-URL tests pin down.
fn process_one_url(url: &str, cookies: &kp::YtDlpCookies) -> Result<ProcessUrlOutcome> {
    let key = url_storage_key(url);

    let existing = ruflo_memory_get(&key, PROCESS_URL_NAMESPACE)
        .with_context(|| format!("checking whether {key} is already stored"))?;

    // Only fetch when the idempotency probe came back empty.
    let fetched = match existing {
        Some(_) => None,
        None => kp::fetch_url_content_with(url, cookies).with_context(|| format!("fetching {url}"))?,
    };

    let outcome = resolve_process_url_outcome(existing.is_some(), fetched.as_ref());
    match outcome {
        ProcessUrlOutcome::AlreadyStored => println!("already stored: {key}"),
        ProcessUrlOutcome::NotFound => {
            println!("post not found in the author's recent feed: {url}");
        }
        ProcessUrlOutcome::EmptyContent => {
            eprintln!("warning: content fetched from {url} is empty or too short — nothing stored");
        }
        ProcessUrlOutcome::Store => {
            let content = fetched.expect("Store outcome is only reachable with fetched content");
            // youtube skips extract_insight entirely (feature spec §3) —
            // don't pay for the LLM call at all when its result is discarded.
            let insight = (content.platform != "youtube")
                .then(|| kp::extract_insight(&content.text, content.platform));
            let (value, tags) = resolve_store_value(&content, insight.as_ref());
            let tag_refs: Vec<&str> = tags.iter().map(String::as_str).collect();
            // t-3097: fetched content (not agent-authored memory) is exempt from
            // the MemPoison write-scan (t-2755) — it false-positives on legitimate
            // transcripts that discuss prompting, e.g. "system prompt", "jailbreak".
            ruflo_memory_store(&key, &value, PROCESS_URL_NAMESPACE, &tag_refs, false)
                .with_context(|| format!("storing {key}"))?;
            println!("Stored: {key}");
            if content.platform == "youtube" {
                // A transcript can be hundreds of KB — printing it in full
                // would flood the terminal on every drain-links run.
                println!("{} chars of transcript stored (not printed in full)", value.chars().count());
            } else {
                println!("{value}");
            }
        }
    }
    Ok(outcome)
}

/// Warn if the installed binary predates source changes in system/cli/rust/crates/.
/// No-ops silently when the source tree can't be located (non-dev environments).
const STALE_BINARY_SENTINELS: &[&str] = &[
    "brana-core/src/knowledge_pipeline.rs",
    "brana-cli/src/commands/knowledge.rs",
    "brana-core/src/tasks.rs",
];

/// Returns true when any sentinel source file in `crates_root` is newer than `binary_mtime`.
fn stale_binary_check(crates_root: &std::path::Path, binary_mtime: SystemTime) -> bool {
    let newest_src: Option<SystemTime> = STALE_BINARY_SENTINELS.iter()
        .filter_map(|rel| std::fs::metadata(crates_root.join(rel)).ok())
        .filter_map(|m| m.modified().ok())
        .max();
    newest_src.is_some_and(|src| binary_mtime < src)
}

fn warn_if_stale_binary() {
    let binary_mtime = std::env::current_exe()
        .ok()
        .and_then(|p| std::fs::metadata(p).ok())
        .and_then(|m| m.modified().ok());
    let Some(binary_mtime) = binary_mtime else { return };

    let crates_root = std::env::var("BRANA_SRC_ROOT")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            let h = home();
            let p = h.join("enter_thebrana/thebrana/system/cli/rust/crates");
            p.exists().then_some(p)
        });
    let Some(crates_root) = crates_root else { return };

    if stale_binary_check(&crates_root, binary_mtime) {
        eprintln!("⚠  brana: installed binary is stale — source changed after last build.");
        eprintln!("   Rebuild: cd {}/.. && cargo build -p brana-cli && cp target/debug/brana ~/.local/bin/brana",
            crates_root.display());
    }
}

pub fn cmd_reindex(changed: bool, files: Vec<PathBuf>) -> Result<()> {
    use anyhow::anyhow;
    let root = find_project_root().ok_or_else(|| anyhow!("Not in git repo"))?;
    let script = root.join("system/scripts/index-knowledge.sh");
    if !script.exists() {
        return Err(anyhow!("index-knowledge.sh not found at {}", script.display()));
    }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).current_dir(&root);

    if changed {
        cmd.arg("--changed");
    } else {
        for f in &files {
            cmd.arg(f);
        }
    }

    println!("\n  Running index-knowledge.sh...");
    let status = cmd.status().context("running index-knowledge.sh")?;
    if !status.success() {
        return Err(anyhow!(
            "index-knowledge.sh failed (exit {})",
            status.code().unwrap_or(-1)
        ));
    }
    println!("  \x1b[32mDone.\x1b[0m\n");
    Ok(())
}

pub fn cmd_reindex_patterns(files: Vec<PathBuf>) -> Result<()> {
    use anyhow::anyhow;
    let root = find_project_root().ok_or_else(|| anyhow!("Not in git repo"))?;
    let script = root.join("system/scripts/index-patterns.sh");
    if !script.exists() {
        return Err(anyhow!("index-patterns.sh not found at {}", script.display()));
    }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).current_dir(&root);

    for f in &files {
        cmd.arg(f);
    }

    println!("\n  Running index-patterns.sh...");
    let status = cmd.status().context("running index-patterns.sh")?;
    if !status.success() {
        return Err(anyhow!(
            "index-patterns.sh failed (exit {})",
            status.code().unwrap_or(-1)
        ));
    }
    println!("  \x1b[32mDone.\x1b[0m\n");
    Ok(())
}

// ── knowledge search ─────────────────────────────────────────────────

/// A single result entry returned by ruflo memory search.
#[derive(Debug, Deserialize, Serialize)]
pub struct SearchResult {
    pub key: String,
    pub value: String,
    #[serde(default)]
    pub score: f64,
    /// Which store produced this hit: "vector" (brana-owned store, full keys,
    /// authoritative) or "ruflo" (live store — fresh-writes window; table
    /// output may truncate keys). Default keeps old JSON deserializable.
    #[serde(default = "default_source")]
    pub source: String,
}

fn default_source() -> String {
    "ruflo".to_string()
}

/// Parse ruflo memory search output into `SearchResult` entries.
///
/// Handles two formats emitted by different ruflo versions:
/// - **JSON array** (old): `[{"key":"...","value":"...","score":0.8}]`
/// - **Table** (current): ASCII table with columns Key | Score | Namespace | Preview
///
/// Both formats may be preceded by ONNX loading preamble lines on stdout — these
/// are skipped. Table keys are truncated by ruflo (e.g. `knowledge:feed:re...`);
/// acceptable for display but unsuitable for exact-key lookups.
pub fn parse_search_results(text: &str) -> Result<Vec<SearchResult>> {
    // Table format: look for +--- separator lines
    if text.lines().any(|l| l.starts_with("+---")) {
        return parse_table_results(text);
    }

    // No matches: ruflo emits neither a table nor a JSON array, just a warning.
    // An empty result set is a valid answer, not a malformed response — returning
    // an error here made a zero-result search look like a parser bug (t-2729).
    if text.contains("No results found") {
        return Ok(Vec::new());
    }

    // JSON format: skip ONNX preamble and [INFO] log lines.
    // Find a [ that's followed (ignoring whitespace) by { or ] — a real JSON array.
    // This correctly skips [INFO] markers where [ is followed by a letter.
    let json_start = find_json_array_start(text)
        .ok_or_else(|| anyhow::anyhow!("unrecognized ruflo output format (no table or JSON array found)"))?;

    let json_text = &text[json_start..];
    let results: Vec<SearchResult> = serde_json::from_str(json_text)?;
    Ok(results)
}

/// Find the byte offset of the first `[` that opens a JSON array.
///
/// Skips `[INFO]`, `[WARN]`, and similar log markers where `[` is followed
/// by a letter. Handles both compact (`[{`) and pretty-printed (`[\n  {`) formats.
fn find_json_array_start(text: &str) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'[' {
            let mut j = i + 1;
            while j < bytes.len()
                && matches!(bytes[j], b' ' | b'\n' | b'\r' | b'\t')
            {
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

/// Parse ASCII table output from ruflo memory search.
///
/// Row format: `| key (possibly truncated) | score | namespace | preview |`
/// Skips separator rows, preamble lines, and the header row.
fn parse_table_results(text: &str) -> Result<Vec<SearchResult>> {
    let mut results = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if !line.starts_with('|') {
            continue;
        }
        let parts: Vec<&str> = line
            .split('|')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();
        if parts.len() < 4 {
            continue;
        }
        if parts[0] == "Key" {
            continue; // header row
        }
        let key = parts[0].to_string();
        let score: f64 = parts[1].parse().unwrap_or(0.0);
        let value = parts.get(3).copied().unwrap_or("").to_string();
        results.push(SearchResult { key, value, score, source: default_source() });
    }
    Ok(results)
}

/// Truncate `text` to at most `max_chars` characters, appending "..." when clipped.
pub fn truncate(text: &str, max_chars: usize) -> String {
    let text = text.trim();
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    let clipped: String = text.chars().take(max_chars).collect();
    format!("{clipped}...")
}

/// Format search results for human-readable display.
///
/// Example output:
/// ```text
/// 1. [0.82] pattern:thebrana:hooks-cant-enforce-ordering
///    Hooks are stateless — can't enforce workflow ordering...
/// ```
pub fn format_results(results: &[SearchResult]) -> String {
    if results.is_empty() {
        return "  No results found.".to_string();
    }
    let mut lines = Vec::new();
    for (i, r) in results.iter().enumerate() {
        lines.push(format!(
            "{}. [{:.2}] {}",
            i + 1,
            r.score,
            r.key
        ));
        lines.push(format!("   {}", truncate(&r.value, 100)));
    }
    lines.join("\n")
}

/// Resolve the similarity threshold for a search — an explicit `--threshold`
/// wins, otherwise the calibrated default. Never falls through to ruflo's 0.7;
/// see `brana_core::ruflo::DEFAULT_SEARCH_THRESHOLD` for the calibration data.
fn resolve_threshold(explicit: Option<f64>) -> f64 {
    explicit.unwrap_or(brana_core::ruflo::DEFAULT_SEARCH_THRESHOLD)
}

/// Call ruflo memory search and return raw output.
/// Uses a 15-second timeout. Always passes an explicit threshold: the
/// ruflo-cli.sh wrapper only injects one for namespaceless calls, and this call
/// is always namespaced, so omitting it silently selected ruflo's 0.7 default.
fn call_ruflo_search(
    query: &str,
    namespace: &str,
    limit: usize,
    threshold: Option<f64>,
) -> Result<String> {
    brana_core::ruflo::ruflo_memory_search_raw(
        query,
        namespace,
        limit,
        Some(resolve_threshold(threshold)),
        false,
    )
    .ok_or_else(|| anyhow::anyhow!("ruflo not found or timed out — run `brana knowledge reindex` first"))
}

/// Merge the two search legs (t-2734): vector-store hits (authoritative,
/// full keys) first, then live-ruflo extras that are not already covered.
///
/// Dedup is truncation-aware: ruflo's table output truncates keys
/// (`knowledge:feed:re...`), so a ruflo key ending in `...` is considered
/// covered when its stem prefixes any vector key.
fn merge_search_legs(vector: Vec<SearchResult>, ruflo: Vec<SearchResult>) -> Vec<SearchResult> {
    let covered = |rk: &str| -> bool {
        if let Some(stem) = rk.strip_suffix("...") {
            vector.iter().any(|v| v.key.starts_with(stem))
        } else {
            vector.iter().any(|v| v.key == rk)
        }
    };
    let extras: Vec<SearchResult> = ruflo.into_iter().filter(|r| !covered(&r.key)).collect();
    let mut merged = vector;
    merged.extend(extras);
    merged
}

/// `brana knowledge search <query> [--limit N] [--namespace NS] [--threshold T] [--json]`
///
/// Backing stores (t-2734 decision, recorded): the brana-owned vector store
/// (`~/.claude/memory/knowledge.db`, the surviving record — same stack recall
/// uses) is the **authoritative** semantic leg. Live ruflo is **demoted to a
/// best-effort second leg** covering the fresh-writes window not yet
/// vector-synced — one provider in a merge, never the sole backing store
/// again. `--namespace` other than `knowledge` stays ruflo-only: the vector
/// store holds only `knowledge:` entries.
pub fn cmd_search(
    query: &str,
    limit: usize,
    namespace: &str,
    threshold: Option<f64>,
    json_output: bool,
) -> Result<()> {
    // Non-knowledge namespaces exist only in live ruflo — unchanged path.
    if namespace != "knowledge" {
        let raw = call_ruflo_search(query, namespace, limit, threshold)?;
        let results = parse_search_results(&raw)?;
        return print_search_output(query, namespace, &results, None, json_output);
    }

    // Leg 1 — authoritative: brana vector store (full keys, verified by
    // retrieval). Same construction as recall.rs; 0.25 is the f32 cosine
    // threshold, a different knob from ruflo's DEFAULT_SEARCH_THRESHOLD.
    use brana_core::search::{DocRef, SearchProvider};
    use brana_core::vector::{RufloEmbedder, VectorProvider};
    let provider = VectorProvider::new(
        brana_core::vector::knowledge_db_path(),
        std::sync::Arc::new(RufloEmbedder),
    )
    .with_threshold(0.25);
    let vector_hits: Vec<SearchResult> = provider
        .query(query, limit)
        .into_iter()
        .map(|h| SearchResult {
            key: match h.doc {
                DocRef::KnowledgeEntry { key, .. } => key,
                DocRef::MemoryFile { slug, .. } => slug,
            },
            value: h.snippet,
            score: h.rrf_score,
            source: "vector".to_string(),
        })
        .collect();

    // Leg 2 — best-effort: live ruflo (fresh-writes window). Fail-open: a
    // missing/timed-out ruflo must not hide the authoritative leg.
    let ruflo_hits: Vec<SearchResult> = call_ruflo_search(query, namespace, limit, threshold)
        .ok()
        .and_then(|raw| parse_search_results(&raw).ok())
        .unwrap_or_default();

    let (n_vector, n_ruflo) = (vector_hits.len(), ruflo_hits.len());
    let results = merge_search_legs(vector_hits, ruflo_hits);
    print_search_output(
        query,
        namespace,
        &results,
        Some((n_vector, n_ruflo)),
        json_output,
    )
}

/// Render search results. `leg_counts` (vector, ruflo) drives the coverage
/// line — the AC-mandated signal that both stores were consulted, so a
/// 4%-window regression can never again be silent.
fn print_search_output(
    query: &str,
    namespace: &str,
    results: &[SearchResult],
    leg_counts: Option<(usize, usize)>,
    json_output: bool,
) -> Result<()> {
    if json_output {
        let out = serde_json::to_string_pretty(results)?;
        println!("{out}");
        if let Some((v, r)) = leg_counts {
            eprintln!("coverage: vector store {v} hit(s), live ruflo {r} hit(s)");
        }
        return Ok(());
    }
    println!("\n  \x1b[1mKnowledge Search\x1b[0m — \"{query}\" (namespace: {namespace})\n");
    println!("{}", format_results(results));
    if let Some((v, r)) = leg_counts {
        println!("\n  coverage: vector store {v} hit(s) · live ruflo {r} hit(s)");
    }
    println!();
    Ok(())
}

pub fn cmd_status() {
    let db_path = home().join(".swarm/memory.db");

    if !db_path.exists() {
        println!("  Knowledge DB not found at {}", db_path.display());
        println!("  Run `brana knowledge reindex` to create it.");
        return;
    }

    // Query entry count and last modified via sqlite3
    let output = Command::new("sqlite3")
        .arg(&db_path)
        .arg("SELECT COUNT(*), datetime(MAX(COALESCE(updated_at, created_at)) / 1000, 'unixepoch', 'localtime') FROM memory_entries WHERE namespace = 'knowledge' AND status = 'active';")
        .output();

    match output {
        Ok(out) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            let parts: Vec<&str> = text.trim().split('|').collect();
            let count = parts.first().unwrap_or(&"?");
            let last = parts.get(1).unwrap_or(&"?");
            println!("\n  \x1b[1mKnowledge Index Status\x1b[0m");
            println!("  Entries:      {count}");
            println!("  Last indexed: {last}");
            println!("  DB path:      {}\n", db_path.display());
        }
        Ok(out) => {
            let err = String::from_utf8_lossy(&out.stderr);
            eprintln!("  sqlite3 error: {err}");
            // Fallback: just show file stats
            if let Ok(meta) = std::fs::metadata(&db_path) {
                println!("  DB size: {} bytes", meta.len());
            }
        }
        Err(_) => {
            // sqlite3 not available — show file info
            println!("\n  \x1b[1mKnowledge Index Status\x1b[0m");
            println!("  DB path: {}", db_path.display());
            if let Ok(meta) = std::fs::metadata(&db_path) {
                println!("  DB size: {} bytes", meta.len());
                if let Ok(modified) = meta.modified() {
                    let elapsed = modified.elapsed().unwrap_or_default();
                    let hours = elapsed.as_secs() / 3600;
                    println!("  Last modified: ~{hours}h ago");
                }
            }
            println!("  (install sqlite3 for detailed stats)\n");
        }
    }
}

// ── brana knowledge process ───────────────────────────────────────────────

#[allow(clippy::too_many_arguments)]
/// Unlocked pipeline core: draft-cap gate + tier1/tier2/draft dispatch.
///
/// t-2247: this function must never acquire the pipeline lock — callers
/// (`cmd_process`, `cmd_run`) hold it for the whole invocation, and
/// `File::lock()` is not reentrant (same-thread re-acquisition deadlocks).
#[allow(clippy::too_many_arguments)]
pub(crate) fn process_core(
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    tier1: bool,
    tier2: bool,
    draft: Option<String>,
    dry_run: bool,
    limit: usize,
) -> Result<()> {
    // ── draft cap gate (blocks --tier1 and --tier2) ───────────────────
    if tier1 || tier2 {
        let draft_count = kp::count_drafts(knowledge_root);
        if draft_count >= DRAFT_CAP && !state.draft_cap_acknowledged {
            bail!(
                "Draft cap hit ({draft_count}/{DRAFT_CAP} drafts in brana-knowledge/drafts/). Review and promote/reject drafts, then run `brana knowledge process --status` to acknowledge."
            );
        }
    }

    // ── --tier1 ───────────────────────────────────────────────────────
    if tier1 {
        run_tier1(knowledge_root, state_path, state, dry_run)?;
    }

    // ── --tier2 ───────────────────────────────────────────────────────
    if tier2 {
        run_tier2(knowledge_root, state_path, state, dry_run)?;
    }

    // ── --draft [topic] ──────────────────────────────────────────────
    if let Some(topic) = draft {
        if topic.is_empty() {
            // Auto-select mode: draft up to `limit` undrafted clusters
            let undrafted = list_undrafted_clusters(state);
            if undrafted.is_empty() {
                println!("  No undrafted clusters found. Run --tier2 first.");
            } else {
                let to_draft: Vec<_> = undrafted.into_iter().take(limit).collect();
                println!("\n  \x1b[1mAuto-drafting {} cluster(s)\x1b[0m", to_draft.len());
                for t in &to_draft {
                    run_tier3(t, knowledge_root, state_path, state, dry_run)?;
                }
            }
        } else {
            run_tier3(&topic, knowledge_root, state_path, state, dry_run)?;
        }
    }

    Ok(())
}

pub fn cmd_process(
    tier1: bool,
    tier2: bool,
    draft: Option<String>,
    report: bool,
    status: bool,
    reset_url: Option<String>,
    dry_run: bool,
    limit: usize,
) -> Result<()> {
    warn_if_stale_binary();
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!(
            "brana-knowledge repo not found. Checked: $BRANA_KNOWLEDGE_ROOT, \
             sibling of git root, ~/enter_thebrana/brana-knowledge/"
        ))?;
    let state_path = kp::pipeline_state_path();

    // ── --status ──────────────────────────────────────────────────────
    // Display reads an unlocked snapshot (atomic rename keeps it consistent);
    // only the cap-ack write takes the lock — so interactive status never
    // blocks behind a multi-minute tier1/tier2 batch (t-2247).
    if status {
        let state = kp::load_state(&state_path)?;
        let counts = count_by_tier(&state);
        let draft_count = kp::count_drafts(&knowledge_root);
        let cap_hit = draft_count >= DRAFT_CAP && !state.draft_cap_acknowledged;
        println!("\n  \x1b[1mKnowledge Pipeline Status\x1b[0m");
        println!("  Unprocessed:     {}", counts.unprocessed);
        println!("  Irrelevant:      {}", counts.irrelevant);
        println!("  Tier 1 passed:   {}", counts.tier1_passed);
        println!("  Tier 2 clustered:{}", counts.tier2_clustered);
        println!("  Tier 3 drafted:  {}", counts.tier3_drafted);
        println!("  Drafts on disk:  {}/{DRAFT_CAP}", draft_count);
        if cap_hit {
            println!("  \x1b[33m⚠ Draft cap hit — review drafts before pipeline runs again.\x1b[0m");
            println!("  \x1b[33m  Run `brana knowledge process --status` again after reviewing to acknowledge.\x1b[0m");
            // Acknowledge on explicit --status invocation — reload under the
            // lock so the ack can't clobber a concurrent run's results.
            if !dry_run {
                let _lock = kp::lock_pipeline()?;
                let mut fresh = kp::load_state(&state_path)?;
                fresh.draft_cap_acknowledged = true;
                kp::save_state(&state_path, &fresh)?;
            }
        }
        if let Some(last) = &state.last_tier1_run {
            println!("  Last Tier 1 run: {last}");
        }
        if let Some(last) = &state.last_tier2_run {
            println!("  Last Tier 2 run: {last}");
        }
        println!();
        return Ok(());
    }

    // ── --reset-url ───────────────────────────────────────────────────
    // Short-lived lock: just this load→modify→save (t-2247).
    if let Some(url) = reset_url {
        let _lock = kp::lock_pipeline()?;
        let mut state = kp::load_state(&state_path)?;
        if state.urls.remove(&url).is_some() {
            println!("  Removed '{}' from pipeline state — will reprocess on next run.", url);
            if !dry_run {
                kp::save_state(&state_path, &url_reset_state(state, &url))?;
            } else {
                println!("  [dry-run] state not written.");
            }
        } else {
            println!("  URL not found in pipeline state: {url}");
        }
        return Ok(());
    }

    // ── --report ──────────────────────────────────────────────────────
    if report {
        let report_path = home().join(".claude/knowledge-pipeline-report.md");
        if report_path.exists() {
            let content = std::fs::read_to_string(&report_path)?;
            println!("{content}");
        } else {
            println!("  No cluster report found. Run `brana knowledge process --tier2` first.");
        }
        return Ok(());
    }

    // ── mutating pipeline ops — whole-invocation lock (t-2247) ────────
    // Batch selection reads state, so the lock must span load→LLM→save;
    // a write-only lock would still double-score across concurrent runs.
    let _lock = kp::lock_pipeline()?;
    let mut state = kp::load_state(&state_path)?;
    process_core(
        &knowledge_root,
        &state_path,
        &mut state,
        tier1,
        tier2,
        draft,
        dry_run,
        limit,
    )
}

// ── Tier 1 ────────────────────────────────────────────────────────────────

const TIER1_BATCH: usize = 50;
const TIER1_CONCURRENCY: usize = 5;

/// Article + content-kind label for platform-aware prompt wording
/// (t-3178, ADR-087 Context #2). The catch-all keeps neutral wording.
fn platform_content_label(platform: &str) -> &'static str {
    match platform {
        "linkedin" => "a LinkedIn post",
        "github" => "a GitHub repository",
        "substack" => "a Substack article",
        "arxiv" => "an arXiv paper",
        _ => "a shared link",
    }
}

fn build_tier1_prompt(entry: &kp::UrlEventEntry, dim_list: &str) -> String {
    let label = platform_content_label(kp::classify_platform(&entry.url));
    format!(
        "You are classifying {label} for relevance to a personal knowledge base \
about AI systems, agent design, developer tooling, and knowledge management.\n\n\
Author: {}\nTitle signal: {}\nTags: {}\n\n\
Score the relevance 1-5 where:\n\
1 = personal update, marketing, unrelated\n\
2 = tangentially related, low signal\n\
3 = relevant, worth reading\n\
4 = directly relevant to known topics (memory, agents, CLI tooling, CC patterns)\n\
5 = high-signal, likely new dimension content\n\n\
Known dimension topics: {}\n\n\
Respond with JSON only: {{\"score\": N, \"reason\": \"one sentence\"}}",
        entry.author,
        entry.title_signal,
        entry.tags.join(" "),
        dim_list,
    )
}

fn run_tier1(
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    dry_run: bool,
) -> Result<()> {
    let dimension_slugs = kp::list_dimension_slugs(knowledge_root);
    let dim_list = dimension_slugs.join(", ");

    let candidates = kp::extract_unprocessed_urls(state)?;
    let batch: Vec<_> = candidates.into_iter().take(TIER1_BATCH).collect();

    if batch.is_empty() {
        println!("  Tier 1: no unprocessed URLs found.");
        return Ok(());
    }

    // n_workers computed after dedup — see below
    println!(
        "\n  \x1b[1mTier 1 — Relevance filter\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!(
        "  Candidates: {} URL(s) (batch cap: {TIER1_BATCH})\n",
        batch.len()
    );

    if dry_run {
        for entry in &batch {
            println!(
                "  [dry-run] would score: {} (author: {}, tags: {})",
                entry.url, entry.author, entry.tags.join(" "),
            );
        }
        return Ok(());
    }

    kp::check_agy_version()?;

    // ── Semantic dedup pre-filter (t-1668) ────────────────────────────────────
    // Before paying for LLM scoring, reject URLs whose topic is already well-
    // represented in the knowledge base (similarity ≥ 0.85 at ruflo threshold).
    const DEDUP_THRESHOLD: f64 = 0.85; // calibrated from t-1589
    let mut dedup_filtered = 0usize;
    let mut llm_batch: Vec<kp::UrlEventEntry> = Vec::with_capacity(batch.len());

    for entry in batch {
        if kp::check_semantic_dedup(&entry.title_signal, DEDUP_THRESHOLD) {
            println!("  ⟳ [dedup] {} — topic already in knowledge base", entry.author);
            state.urls.insert(entry.url.clone(), kp::UrlEntry {
                status: UrlStatus::Irrelevant,
                tier1_score: Some(0),
                tier1_reason: Some("semantic dedup: topic already in brana-knowledge".to_string()),
                logged_date: Some(entry.logged_date.clone()),
                author: Some(entry.author.clone()),
                title_signal: Some(entry.title_signal.clone()),
                tags: entry.tags.clone(),
                platform: Some(kp::classify_platform(&entry.url).to_string()),
                ..kp::UrlEntry::new_unprocessed(None)
            });
            dedup_filtered += 1;
        } else {
            llm_batch.push(entry);
        }
    }
    if dedup_filtered > 0 {
        kp::save_state(state_path, state)?;
        println!("  Dedup: {} URL(s) skipped (topic already in knowledge base)", dedup_filtered);
    }
    if llm_batch.is_empty() {
        println!("  Tier 1: all URLs filtered by semantic dedup.");
        return Ok(());
    }
    // ─────────────────────────────────────────────────────────────────────────

    let n_workers = TIER1_CONCURRENCY.min(llm_batch.len());
    println!("  LLM scoring: {} URL(s), workers: {n_workers}\n", llm_batch.len());

    // Build work queue: (entry, prompt) pairs
    let tasks: Vec<(kp::UrlEventEntry, String)> = llm_batch
        .iter()
        .map(|e| (e.clone(), build_tier1_prompt(e, &dim_list)))
        .collect();

    let queue = Arc::new(Mutex::new(VecDeque::from(tasks)));
    let (tx, rx) = std::sync::mpsc::channel::<(kp::UrlEventEntry, Result<serde_json::Value>)>();

    let handles: Vec<_> = (0..n_workers)
        .map(|_| {
            let queue = Arc::clone(&queue);
            let tx = tx.clone();
            std::thread::spawn(move || loop {
                let work = { queue.lock().unwrap().pop_front() };
                let Some((entry, prompt)) = work else { break };
                let result = kp::call_gemini_json(&prompt);
                let _ = tx.send((entry, result));
            })
        })
        .collect();
    drop(tx);

    let mut passed = 0usize;
    let mut filtered = 0usize;

    for (entry, result) in rx {
        match result {
            Ok(json) => {
                let score = json.get("score").and_then(|v| v.as_u64()).unwrap_or(0) as u8;
                let reason = json
                    .get("reason")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let status = if score >= 3 {
                    passed += 1;
                    UrlStatus::Tier1Passed
                } else {
                    filtered += 1;
                    UrlStatus::Irrelevant
                };

                let icon = if score >= 3 { "✓" } else { "✗" };
                println!("  {icon} [{score}] {} — {reason}", entry.author);

                // Preserve ingest provenance for state-sourced candidates (t-2247).
                let source = state.urls.get(&entry.url).and_then(|e| e.source.clone());
                state.urls.insert(entry.url.clone(), kp::UrlEntry {
                    status,
                    tier1_score: Some(score),
                    tier1_reason: Some(reason),
                    logged_date: Some(entry.logged_date.clone()),
                    author: Some(entry.author.clone()),
                    title_signal: Some(entry.title_signal.clone()),
                    tags: entry.tags.clone(),
                    platform: Some(kp::classify_platform(&entry.url).to_string()),
                    source,
                    ..kp::UrlEntry::new_unprocessed(None)
                });
                // Checkpoint: survive mid-batch crashes
                kp::save_state(state_path, state)?;
            }
            Err(e) => {
                eprintln!("  \x1b[33m  ⚠ LLM call failed for {}: {e:#}\x1b[0m", entry.url);
            }
        }
    }

    for h in handles {
        let _ = h.join();
    }

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    state.last_tier1_run = Some(now);
    kp::save_state(state_path, state)?;
    println!("\n  Tier 1 done — {} passed, {} filtered. State saved.", passed, filtered);

    Ok(())
}

// ── Tier 2 ────────────────────────────────────────────────────────────────

const TIER2_CONCURRENCY: usize = 3;

/// Build the cluster-assignment prompt for a single URL.
fn build_tier2_prompt(
    platform: &str,
    author: &str,
    title_signal: &str,
    tags: &[String],
    dim_list: &str,
) -> String {
    let label = platform_content_label(platform);
    format!(
        "You are assigning {label} to the nearest topic in a knowledge base.\n\n\
Author: {author}\nTitle signal: {title_signal}\nTags: {}\n\n\
Existing dimension topics:\n{dim_list}\n\n\
Assign this post to the best-matching dimension, or flag as \"new-topic\" \
if it doesn't fit any existing dimension.\n\n\
Respond with JSON only:\n\
{{\"dimension_target\": \"slug or new-topic\", \"cluster_topic\": \"short label\", \"reason\": \"one sentence\"}}",
        tags.join(" "),
    )
}

/// Extract (dim_target, cluster_topic, reason) from a Gemini cluster-assignment response.
fn parse_tier2_json(json: &serde_json::Value) -> (String, String, String) {
    let dim_target = json
        .get("dimension_target")
        .and_then(|v| v.as_str())
        .unwrap_or("new-topic")
        .to_string();
    let cluster_topic = json
        .get("cluster_topic")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown")
        .to_string();
    let reason = json
        .get("reason")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    (dim_target, cluster_topic, reason)
}

fn backfill_linkedin_fields(state: &mut kp::PipelineState) -> usize {
    let mut backfilled = 0usize;
    for (url, entry) in state.urls.iter_mut() {
        if entry.author.is_none() || entry.title_signal.is_none() {
            if let Some((author, title_signal)) = kp::parse_linkedin_url(url) {
                if entry.author.is_none() { entry.author = Some(author); }
                if entry.title_signal.is_none() { entry.title_signal = Some(title_signal); }
                backfilled += 1;
            }
        }
    }
    backfilled
}

fn run_tier2(
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    dry_run: bool,
) -> Result<()> {
    let backfilled = backfill_linkedin_fields(state);
    if backfilled > 0 {
        println!("  Backfilled author/title_signal for {backfilled} pre-field URL record(s)");
    }

    let dimension_slugs = kp::list_dimension_slugs(knowledge_root);
    let dim_list: Vec<String> = dimension_slugs
        .iter()
        .map(|s| format!("- {s}"))
        .collect();
    let dim_list_str = dim_list.join("\n");

    let candidates: Vec<_> = state
        .urls
        .iter()
        .filter(|(_, e)| e.status == UrlStatus::Tier1Passed)
        .map(|(url, e)| (
            url.clone(),
            e.author.clone().unwrap_or_default(),
            e.title_signal.clone().unwrap_or_default(),
            e.tags.clone(),
        ))
        .collect();

    if candidates.is_empty() {
        println!("  Tier 2: no tier1-passed URLs found. Run --tier1 first.");
        return Ok(());
    }

    println!(
        "\n  \x1b[1mTier 2 — Cluster assignment\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!("  Processing {} URL(s)\n", candidates.len());

    if dry_run {
        for (url, _, _, _) in &candidates {
            println!("  [dry-run] would cluster: {url}");
        }
        return Ok(());
    }

    // Cluster assignments: topic_slug → list of URLs
    let mut clusters: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    let mut dim_targets: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();

    // Build work queue: (url, author, prompt) triples
    let tasks: Vec<(String, String, String)> = candidates
        .iter()
        .map(|(url, author, title_signal, tags)| {
            let prompt =
                build_tier2_prompt(kp::classify_platform(url), author, title_signal, tags, &dim_list_str);
            (url.clone(), author.clone(), prompt)
        })
        .collect();

    let n_workers = TIER2_CONCURRENCY.min(tasks.len());
    println!("  Workers: {n_workers}\n");

    let queue = Arc::new(Mutex::new(VecDeque::from(tasks)));
    let (tx, rx) = std::sync::mpsc::channel::<(String, String, Result<serde_json::Value>)>();

    let handles: Vec<_> = (0..n_workers)
        .map(|_| {
            let queue = Arc::clone(&queue);
            let tx = tx.clone();
            std::thread::spawn(move || loop {
                let work = { queue.lock().unwrap().pop_front() };
                let Some((url, author, prompt)) = work else { break };
                let result = kp::call_gemini_json(&prompt);
                let _ = tx.send((url, author, result));
            })
        })
        .collect();
    drop(tx);

    for (url, author, result) in rx {
        match result {
            Ok(json) => {
                let (dim_target, cluster_topic, reason) = parse_tier2_json(&json);

                println!("  → [{cluster_topic}] {author} — {reason}");

                clusters
                    .entry(cluster_topic.clone())
                    .or_default()
                    .push(url.clone());
                dim_targets.insert(cluster_topic.clone(), dim_target.clone());

                if let Some(entry) = state.urls.get_mut(&url) {
                    entry.status = UrlStatus::Tier2Clustered;
                    entry.cluster_topic = Some(cluster_topic);
                    entry.dimension_target = Some(dim_target);
                }
                // Checkpoint: survive mid-batch crashes
                kp::save_state(state_path, state)?;
            }
            Err(e) => {
                eprintln!("  \x1b[33m  ⚠ LLM call failed for {url}: {e:#}\x1b[0m");
            }
        }
    }

    for h in handles {
        let _ = h.join();
    }

    // Write cluster report
    let report_path = home().join(".claude/knowledge-pipeline-report.md");
    let report = build_cluster_report(&clusters, &dim_targets);
    kp::assert_allowed_write(&report_path, knowledge_root)
        .unwrap_or(()); // report path is in allowed exact list
    std::fs::write(&report_path, &report)
        .with_context(|| format!("writing cluster report to {}", report_path.display()))?;

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    state.last_tier2_run = Some(now);
    kp::save_state(state_path, state)?;

    println!(
        "\n  Tier 2 done — {} cluster(s). Report: {}",
        clusters.len(),
        report_path.display()
    );
    println!("  To draft a cluster: brana knowledge process --draft <topic-slug>");

    Ok(())
}

fn build_cluster_report(
    clusters: &std::collections::HashMap<String, Vec<String>>,
    dim_targets: &std::collections::HashMap<String, String>,
) -> String {
    use std::fmt::Write as _;
    let now = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let mut out = format!("# Knowledge Pipeline — Cluster Report\n\nGenerated: {now}\n\n");
    let mut topics: Vec<_> = clusters.keys().collect();
    topics.sort();
    for topic in topics {
        let urls = &clusters[topic];
        let dim = dim_targets.get(topic).map(|s| s.as_str()).unwrap_or("new-topic");
        let _ = writeln!(out, "## {topic}\n\n**Target dimension:** `{dim}`  \n**Sources ({}):**\n", urls.len());
        for url in urls {
            let _ = writeln!(out, "- {url}");
        }
        let _ = writeln!(
            out,
            "\nTo draft: `brana knowledge process --draft {topic}`\n"
        );
    }
    out
}

// ── Tier 3 ────────────────────────────────────────────────────────────────

fn run_tier3(
    topic: &str,
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    dry_run: bool,
) -> Result<()> {
    // Draft cap
    let draft_count = kp::count_drafts(knowledge_root);
    if draft_count >= DRAFT_CAP {
        bail!(
            "Draft cap hit ({draft_count}/{DRAFT_CAP}). Review and promote/reject drafts first, \
             then run `brana knowledge process --status` to acknowledge."
        );
    }

    // Collect URLs for this cluster
    let cluster_urls: Vec<_> = state
        .urls
        .iter()
        .filter(|(_, e)| {
            e.status == UrlStatus::Tier2Clustered
                && e.cluster_topic.as_deref() == Some(topic)
        })
        .map(|(url, e)| (
            url.clone(),
            e.author.clone().unwrap_or_default(),
            e.title_signal.clone().unwrap_or_default(),
            e.tags.clone(),
            e.dimension_target.clone().unwrap_or_default(),
        ))
        .collect();

    if cluster_urls.is_empty() {
        bail!("No tier2-clustered URLs found for topic '{topic}'. Run --tier2 first.");
    }

    let dim_target = cluster_urls[0].4.clone();

    // Read existing dimension summary if available
    let dim_summary = {
        let dim_path = knowledge_root.join("dimensions").join(format!("{dim_target}.md"));
        if dim_path.exists() {
            let content = std::fs::read_to_string(&dim_path).unwrap_or_default();
            content.chars().take(500).collect::<String>()
        } else {
            String::from("(new dimension — no existing content)")
        }
    };

    let sources_block: String = cluster_urls
        .iter()
        .map(|(url, author, title_signal, tags, _)| {
            format!("- Author: {author}, Title: {title_signal}, Tags: {}, URL: {url}", tags.join(" "))
        })
        .collect::<Vec<_>>()
        .join("\n");

    let prompt = format!(
        "You are writing an addition to a knowledge base dimension document.\n\n\
Dimension: {dim_target}\nExisting content summary:\n{dim_summary}\n\n\
Source posts ({n} posts, approved cluster: {topic}):\n{sources_block}\n\n\
Write a new section to add to this dimension. Use markdown. \
Cite each source post inline as [author, date]. \
Do not repeat content already in the dimension. Focus on new insights only.\n\n\
Output: markdown section only (no frontmatter, no preamble).",
        n = cluster_urls.len(),
    );

    if dry_run {
        println!("  [dry-run] would draft '{topic}' → dimensions/{dim_target}.md");
        println!("  Sources: {} URL(s)", cluster_urls.len());
        return Ok(());
    }

    println!("\n  \x1b[1mTier 3 — Draft synthesis\x1b[0m");
    println!("  Topic: {topic} ({} sources) → {dim_target}", cluster_urls.len());

    let body_text = kp::call_claude_text(&prompt)?;

    let now_date = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let review_due = {
        let d = chrono::Utc::now() + chrono::Duration::days(7);
        d.format("%Y-%m-%d").to_string()
    };

    let sources_yaml: String = cluster_urls
        .iter()
        .map(|(url, _, _, _, _)| format!("  - url: {url}\n    logged: unknown"))
        .collect::<Vec<_>>()
        .join("\n");

    let draft_content = build_draft_content(&now_date, &sources_yaml, topic, &dim_target, &review_due, &body_text);

    let topic_slug = sanitize_topic_slug(topic);
    let draft_filename = format!("{now_date}-{topic_slug}.md");
    let draft_path = knowledge_root.join("drafts").join(&draft_filename);

    kp::assert_allowed_write(&draft_path, knowledge_root)?;
    std::fs::create_dir_all(draft_path.parent().unwrap())?;
    std::fs::write(&draft_path, &draft_content)?;

    // Update state
    for (url, _, _, _, _) in &cluster_urls {
        if let Some(entry) = state.urls.get_mut(url) {
            entry.status = UrlStatus::Tier3Drafted;
            entry.draft_path = Some(draft_path.to_string_lossy().to_string());
        }
    }
    kp::save_state(state_path, state)?;

    println!("  ✓ Draft written: {}", draft_path.display());
    println!("  To promote: brana knowledge promote {}", draft_path.display());

    Ok(())
}

// ── brana knowledge promote ───────────────────────────────────────────────

pub fn cmd_promote(draft_path: PathBuf, dry_run: bool) -> Result<()> {
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!("brana-knowledge repo not found"))?;

    // Resolve draft path (may be relative to knowledge_root or absolute)
    let abs_draft = if draft_path.is_absolute() {
        draft_path.clone()
    } else {
        knowledge_root.join(&draft_path)
    };

    if !abs_draft.exists() {
        bail!("Draft file not found: {}", abs_draft.display());
    }

    kp::assert_allowed_write(&abs_draft, &knowledge_root)?;

    let content = std::fs::read_to_string(&abs_draft)?;

    // Parse promotion_target from frontmatter
    let promotion_target = parse_frontmatter_field(&content, "promotion_target")
        .ok_or_else(|| anyhow::anyhow!("Draft missing 'promotion_target' in frontmatter"))?;

    let target_path = knowledge_root.join(&promotion_target);

    println!("\n  \x1b[1mPromote draft\x1b[0m{}", if dry_run { " [dry-run]" } else { "" });
    println!("  Draft:  {}", abs_draft.display());
    println!("  Target: {}", target_path.display());

    if dry_run {
        return Ok(());
    }

    // Strip draft frontmatter, update status to accepted
    let new_content = set_frontmatter_status(&content, "accepted");

    if target_path.exists() {
        // Append to existing dimension file
        let existing = std::fs::read_to_string(&target_path)?;
        let appended = format!("{existing}\n\n---\n\n<!-- promoted from draft: {} -->\n\n{}", abs_draft.file_name().unwrap_or_default().to_string_lossy(), strip_frontmatter(&new_content));
        std::fs::write(&target_path, appended)?;
        println!("  ✓ Appended to existing dimension: {}", target_path.display());
    } else {
        std::fs::create_dir_all(target_path.parent().unwrap_or(&target_path))?;
        std::fs::write(&target_path, new_content)?;
        println!("  ✓ Created new dimension: {}", target_path.display());
    }

    // Archive the draft
    let archive_dir = knowledge_root
        .join("drafts-archive")
        .join(chrono::Utc::now().format("%Y-%m-%d").to_string());
    std::fs::create_dir_all(&archive_dir)?;
    let archive_dest = archive_dir.join(abs_draft.file_name().unwrap());
    std::fs::rename(&abs_draft, &archive_dest)?;
    println!("  ✓ Draft archived to: {}", archive_dest.display());

    Ok(())
}

// ── helpers ───────────────────────────────────────────────────────────────

#[derive(Default)]
struct TierCounts {
    unprocessed: usize,
    irrelevant: usize,
    tier1_passed: usize,
    tier2_clustered: usize,
    tier3_drafted: usize,
}

fn count_by_tier(state: &kp::PipelineState) -> TierCounts {
    let mut c = TierCounts::default();
    for entry in state.urls.values() {
        match entry.status {
            UrlStatus::Unprocessed => c.unprocessed += 1,
            UrlStatus::Irrelevant => c.irrelevant += 1,
            UrlStatus::Tier1Passed => c.tier1_passed += 1,
            UrlStatus::Tier2Clustered => c.tier2_clustered += 1,
            UrlStatus::Tier3Drafted => c.tier3_drafted += 1,
        }
    }
    c
}

fn url_reset_state(mut state: kp::PipelineState, url: &str) -> kp::PipelineState {
    state.urls.remove(url);
    state
}

/// Build a Tier 3 draft file's content: frontmatter + body. `type: claim` per
/// ADR-057 §2 — a drafted dimension addition is a sourced, falsifiable
/// synthesis awaiting human review, exactly what `claim` models (t-2437).
fn build_draft_content(
    now_date: &str,
    sources_yaml: &str,
    topic: &str,
    dim_target: &str,
    review_due: &str,
    body_text: &str,
) -> String {
    format!(
        "---\ntype: claim\nstatus: draft\ncreated: {now_date}\nsources:\n{sources_yaml}\ncluster_topic: {topic}\ndraft_author: llm\nreview_due: {review_due}\npromotion_target: dimensions/{dim_target}.md\n---\n\n{body_text}\n"
    )
}

fn parse_frontmatter_field(content: &str, field: &str) -> Option<String> {
    let prefix = format!("{field}: ");
    for line in content.lines() {
        if let Some(val) = line.strip_prefix(&prefix) {
            return Some(val.trim().to_string());
        }
    }
    None
}

fn set_frontmatter_status(content: &str, new_status: &str) -> String {
    content
        .lines()
        .map(|line| {
            if line.starts_with("status: ") {
                format!("status: {new_status}")
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn strip_frontmatter(content: &str) -> String {
    let mut lines = content.lines();
    // Skip opening ---
    if lines.next().map(|l| l.trim()) == Some("---") {
        let rest: Vec<_> = lines.collect();
        if let Some(pos) = rest.iter().position(|l| l.trim() == "---") {
            return rest[pos + 1..].join("\n").trim_start().to_string();
        }
    }
    content.to_string()
}

// ── brana knowledge run ───────────────────────────────────────────────────────

/// Determine if a directive requires a human gate before execution.
///
/// Returns `Some(gate_message)` when the directive is a decision point that
/// requires human review before proceeding. Returns `None` when the pipeline
/// can auto-advance (tier1 or tier2 processing).
pub fn run_gate_message(directive: &str) -> Option<String> {
    if directive.contains("--report") || directive.starts_with("brana knowledge process --report") {
        return Some(format!(
            "Pipeline stopped — human decision required.\n\
             Review the cluster report:\n\
             \n\
               brana knowledge process --report\n\
             \n\
             Then draft a topic:\n\
             \n\
               brana knowledge process --draft <topic>"
        ));
    }
    if directive.contains("knowledge promote") {
        return Some(format!(
            "Pipeline stopped — human decision required.\n\
             Draft ready for review. To promote:\n\
             \n\
               {directive}"
        ));
    }
    if directive.contains("knowledge ingest") {
        return Some(format!(
            "Pipeline stopped — pipeline is current.\n\
             Ingest new URLs to continue:\n\
             \n\
               {directive}"
        ));
    }
    None
}

/// `brana knowledge run` — auto-advance tier1→tier2, stop at human gates.
///
/// Logic:
/// 1. Check current state via `next_directive`.
/// 2. If tier1 needed: run tier1, reload, check again. If tier2 now needed: run tier2.
/// 3. If tier2 needed: run tier2 only.
/// 4. After any automated step completes: reload state, compute next directive,
///    emit gate message and stop.
/// 5. If current state is already a gate (--report, promote, ingest): print gate and stop.
pub fn cmd_run() -> Result<()> {
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!(
            "brana-knowledge repo not found. Checked: $BRANA_KNOWLEDGE_ROOT, \
             sibling of git root, ~/enter_thebrana/brana-knowledge/"
        ))?;
    let state_path = kp::pipeline_state_path();

    // t-2247: lock once for the whole auto-advance; the composed tier1/tier2
    // steps run through the lock-free process_core (calling cmd_process here
    // would re-acquire and self-deadlock — File::lock() is not reentrant).
    let _lock = kp::lock_pipeline()?;
    let state = kp::load_state(&state_path)?;

    let directive = next_directive(&state, &knowledge_root);

    // If already at a human gate, print and stop.
    if let Some(gate) = run_gate_message(&directive) {
        println!("\n{gate}\n");
        return Ok(());
    }

    // Auto-advance: tier1
    if directive.contains("--tier1") {
        println!("  \x1b[1mbrana knowledge run\x1b[0m — auto-advancing tier1...\n");
        let mut s = kp::load_state(&state_path)?;
        process_core(&knowledge_root, &state_path, &mut s, true, false, None, false, 1)?;

        // Reload and check again
        let state2 = kp::load_state(&state_path)?;
        let directive2 = next_directive(&state2, &knowledge_root);

        if directive2.contains("--tier2") {
            println!("\n  Auto-advancing tier2...\n");
            let mut s = kp::load_state(&state_path)?;
            process_core(&knowledge_root, &state_path, &mut s, false, true, None, false, 1)?;

            // Reload after tier2 and emit gate
            let state3 = kp::load_state(&state_path)?;
            let directive3 = next_directive(&state3, &knowledge_root);
            let gate = run_gate_message(&directive3).unwrap_or_else(|| {
                format!("Pipeline stopped. Next: {directive3}")
            });
            println!("\n{gate}\n");
        } else {
            // tier1 ran but tier2 not ready yet (or already at gate)
            let gate = run_gate_message(&directive2).unwrap_or_else(|| {
                format!("Pipeline stopped. Next: {directive2}")
            });
            println!("\n{gate}\n");
        }
        return Ok(());
    }

    // Auto-advance: tier2 only
    if directive.contains("--tier2") {
        println!("  \x1b[1mbrana knowledge run\x1b[0m — auto-advancing tier2...\n");
        let mut s = kp::load_state(&state_path)?;
        process_core(&knowledge_root, &state_path, &mut s, false, true, None, false, 1)?;

        // Reload after tier2 and emit gate
        let state2 = kp::load_state(&state_path)?;
        let directive2 = next_directive(&state2, &knowledge_root);
        let gate = run_gate_message(&directive2).unwrap_or_else(|| {
            format!("Pipeline stopped. Next: {directive2}")
        });
        println!("\n{gate}\n");
        return Ok(());
    }

    // Fallback: unknown directive, just print it
    println!("  Pipeline state: {directive}");
    Ok(())
}

// ── brana knowledge next ──────────────────────────────────────────────────────

/// Determine the single next pipeline action given current state.
///
/// Priority order (first match wins):
/// 1. `unprocessed > 0`                         → `process --tier1`
/// 2. `tier1_passed > 0`                         → `process --tier2`
/// 3. `drafts_on_disk > 0`                       → `promote <first-draft>`
/// 4. `tier2_clustered > 0` (no drafts on disk)  → `process --report`
/// 5. all current                                 → `ingest <url>`
pub fn next_directive(state: &kp::PipelineState, knowledge_root: &std::path::Path) -> String {
    let counts = count_by_tier(state);

    if counts.unprocessed > 0 {
        return "brana knowledge process --tier1".to_string();
    }
    if counts.tier1_passed > 0 {
        return "brana knowledge process --tier2".to_string();
    }
    let draft_count = kp::count_drafts(knowledge_root);
    if draft_count > 0 {
        let drafts_dir = knowledge_root.join("drafts");
        if let Ok(dir) = std::fs::read_dir(&drafts_dir) {
            let mut paths: Vec<_> = dir
                .flatten()
                .filter(|e| {
                    e.path().extension().and_then(|x| x.to_str()) == Some("md")
                })
                .map(|e| e.path())
                .collect();
            paths.sort();
            if let Some(first) = paths.first() {
                return format!("brana knowledge promote {}", first.display());
            }
        }
        return "brana knowledge promote <draft-path>".to_string();
    }
    if counts.tier2_clustered > 0 {
        return "brana knowledge process --report".to_string();
    }
    "brana knowledge ingest <url>".to_string()
}

/// `brana knowledge next` — emit the single next pipeline command to run.
pub fn cmd_next() -> Result<()> {
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!(
            "brana-knowledge repo not found. Checked: $BRANA_KNOWLEDGE_ROOT, \
             sibling of git root, ~/enter_thebrana/brana-knowledge/"
        ))?;
    let state_path = kp::pipeline_state_path();
    let state = kp::load_state(&state_path)?;
    let directive = next_directive(&state, &knowledge_root);
    println!("{directive}");
    Ok(())
}

// ── brana knowledge ingest ────────────────────────────────────────────────────

/// `brana knowledge ingest [sources...] [--source <tag>] [--dry-run]`
///
/// Sources may be:
/// - Direct `https://` URLs (passed through unchanged)
/// - File paths (content read; URLs extracted via regex)
/// - Absent (stdin read if piped; error if terminal)
pub fn cmd_ingest(
    sources: Vec<String>,
    source_tag: Option<String>,
    from_ruflo: Option<String>,
    dry_run: bool,
) -> Result<()> {
    let mut raw_text = String::new();
    let mut direct_urls: Vec<String> = Vec::new();

    if sources.is_empty() {
        if std::io::stdin().is_terminal() {
            anyhow::bail!(
                "No input. Provide file paths or URLs, or pipe text: cat urls.txt | brana knowledge ingest"
            );
        }
        use std::io::Read as _;
        std::io::stdin()
            .read_to_string(&mut raw_text)
            .context("reading from stdin")?;
    } else {
        for src in &sources {
            if src.starts_with("https://") || src.starts_with("http://") {
                direct_urls.push(src.clone());
            } else {
                let path = std::path::Path::new(src);
                if path.exists() {
                    let content = std::fs::read_to_string(path)
                        .with_context(|| format!("reading {}", path.display()))?;
                    raw_text.push_str(&content);
                    raw_text.push('\n');
                } else {
                    raw_text.push_str(src);
                    raw_text.push('\n');
                }
            }
        }
    }

    let mut extracted = kp::extract_urls_from_text(&raw_text);
    for url in &direct_urls {
        if !extracted.contains(url) {
            extracted.push(url.clone());
        }
    }

    if extracted.is_empty() {
        println!("  No URLs found in input.");
        return Ok(());
    }

    println!(
        "\n  \x1b[1mbrana knowledge ingest\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!("  {} URL(s) extracted\n", extracted.len());

    if from_ruflo.is_some() && extracted.len() != 1 {
        bail!(
            "--from-ruflo names one stored entry, so it takes exactly one URL (got {})",
            extracted.len()
        );
    }

    let state_path = kp::pipeline_state_path();
    // t-2247: dedup-against-state + queue is a load→modify→save — lock it.
    let _lock = kp::lock_pipeline()?;
    let mut state = kp::load_state(&state_path)?;
    let result = kp::ingest_urls(&extracted, source_tag.as_deref(), &mut state);

    println!("  ✓ {} new URL(s) queued", result.queued);
    if result.duplicates > 0 {
        println!("  · {} duplicate(s) skipped", result.duplicates);
    }

    // t-3177: attach already-drained ruflo content at ingest time — ingest
    // stays the sole PipelineState writer (ADR-042 §1). Explicit key first;
    // otherwise best-effort probe, LongForm URLs only (short-signal tiers
    // never read fetched_content, and a ruflo round-trip per URL would
    // drag on big WA-dump batches).
    let mut populated = 0usize;
    if !dry_run {
        if let Some(key) = &from_ruflo {
            let content = ruflo_memory_get(key, PROCESS_URL_NAMESPACE)
                .with_context(|| format!("reading {key}"))?
                .ok_or_else(|| anyhow::anyhow!("no ruflo entry stored at {key}"))?;
            kp::populate_fetched_content(&mut state, &extracted[0], &content);
            populated += 1;
        } else {
            for url in &extracted {
                let adapter = kp::PlatformAdapter::for_platform(kp::classify_platform(url));
                if adapter != kp::PlatformAdapter::LongForm {
                    continue;
                }
                match ruflo_memory_get(&url_storage_key(url), PROCESS_URL_NAMESPACE) {
                    Ok(Some(content)) => {
                        kp::populate_fetched_content(&mut state, url, &content);
                        populated += 1;
                    }
                    Ok(None) => {}
                    // Best-effort enrichment: a ruflo outage must not block
                    // queueing — the entry just stays content-less.
                    Err(e) => eprintln!("  warning: ruflo probe failed for {url}: {e}"),
                }
            }
        }
        if populated > 0 {
            println!("  ✓ {populated} entr(ies) enriched with drained content");
        }
    }

    if dry_run {
        println!("  [dry-run] state not written.");
    } else if result.queued > 0 || populated > 0 {
        kp::save_state(&state_path, &state)?;
        println!("\n  Next: brana knowledge process --status");
    }

    Ok(())
}

/// One-time key migration (t-3182): rewrite `state.urls` keys through
/// `canonicalize_url()` so pre-t-3173 raw-keyed entries share ingest's
/// canonical identity. Backs up the pre-migration state file next to it
/// before writing; a no-op run writes nothing.
pub fn cmd_migrate_keys(dry_run: bool) -> Result<()> {
    let state_path = kp::pipeline_state_path();
    println!(
        "\n  \x1b[1mbrana knowledge migrate-keys\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );

    // Load→modify→save on the shared state file — lock it (t-2247).
    let _lock = kp::lock_pipeline()?;
    let mut state = kp::load_state(&state_path)?;
    let before = state.urls.len();
    let result = kp::migrate_urls_to_canonical_keys(&mut state);

    println!("  {} entr(ies) scanned", before);
    println!("  ✓ {} key(s) rewritten to canonical form", result.rewritten);
    println!("  ✓ {} collision(s) merged (more-advanced status kept)", result.merged);

    if dry_run {
        println!("  [dry-run] state not written.");
    } else if result.rewritten + result.merged > 0 {
        let backup = state_path.with_extension("json.pre-migrate-keys.bak");
        std::fs::copy(&state_path, &backup)
            .with_context(|| format!("backing up {} to {}", state_path.display(), backup.display()))?;
        kp::save_state(&state_path, &state)?;
        println!("  Backup: {}", backup.display());
    } else {
        println!("  Already canonical — nothing to write.");
    }

    Ok(())
}

/// Parse the `--tab` flag into [`kp::ChannelTab`]. Pure, no I/O.
fn resolve_channel_tab(tab: &str) -> Result<kp::ChannelTab> {
    match tab {
        "videos" => Ok(kp::ChannelTab::Videos),
        "shorts" => Ok(kp::ChannelTab::Shorts),
        other => bail!("unknown --tab value \"{other}\" — expected \"videos\" or \"shorts\""),
    }
}

/// Build the `brana backlog add --json` payload for one channel-backfilled
/// video URL. Pure, no I/O — mirrors the `link`-tag / `"URL: {url}"`
/// contract [`extract_capture_url`] parses on the drain side (feature spec
/// §2: "queues each one as a `link`-tagged backlog task exactly the way any
/// other link enters the queue today").
fn build_channel_link_task_json(channel_url: &str, video_url: &str) -> serde_json::Value {
    serde_json::json!({
        "subject": format!("[channel-backfill] {channel_url} — {video_url}"),
        "type": "task",
        "tags": ["link", "channel-backfill"],
        "context": format!("URL: {video_url}"),
    })
}

/// `brana knowledge channel-backfill <channel_url> --tab videos --max N` —
/// enumerate a channel tab via [`kp::fetch_youtube_channel_videos`] and
/// queue each returned URL as a `link`-tagged backlog task (feature spec
/// §1, §2). No new fetch/dedupe/store code: every queued URL drains
/// through the existing `drain-links --platform youtube` path unchanged.
///
/// The `--max` flag's own default (50) is the sanity cap the feature spec
/// §3 calls for — mapped directly to `ChannelSelection::Range { end }`, so
/// a caller who wants more must say so explicitly via `--max`.
pub fn cmd_channel_backfill(
    channel_url: &str,
    tab: &str,
    max: u32,
    dry_run: bool,
    cookies: &kp::YtDlpCookies,
) -> Result<()> {
    let channel_tab = resolve_channel_tab(tab)?;
    let selection = kp::ChannelSelection::Range { start: None, end: Some(max) };
    let urls = kp::fetch_youtube_channel_videos(channel_url, channel_tab, selection, cookies)
        .with_context(|| format!("enumerating channel {channel_url}"))?;

    if urls.is_empty() {
        println!("No videos found for {channel_url} ({tab} tab).");
        return Ok(());
    }

    println!(
        "\n  \x1b[1mbrana knowledge channel-backfill\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!("  {} video(s) found on {channel_url} ({tab} tab)\n", urls.len());

    let mut queued = 0usize;
    for url in &urls {
        let payload = build_channel_link_task_json(channel_url, url);
        if dry_run {
            println!("  [dry-run] would queue: {url}");
        } else {
            let status = Command::new("brana")
                .args(["backlog", "add", "--json", &payload.to_string()])
                .status()
                .context("spawning brana backlog add")?;
            if status.success() {
                queued += 1;
            } else {
                eprintln!("  ⚠ failed to queue {url} (brana backlog add exited {status})");
            }
        }
    }

    if dry_run {
        println!("\n  [dry-run] nothing queued.");
    } else {
        println!("\n  ✓ {queued} video(s) queued");
        println!("  Next: brana knowledge drain-links --platform youtube");
    }

    Ok(())
}

/// Return cluster topics that have Tier2Clustered URLs but no Tier3Drafted URLs,
/// sorted by source count descending (highest-signal clusters first).
fn list_undrafted_clusters(state: &kp::PipelineState) -> Vec<String> {
    use std::collections::HashMap;
    let mut counts: HashMap<String, usize> = HashMap::new();
    for entry in state.urls.values() {
        if entry.status == kp::UrlStatus::Tier2Clustered {
            if let Some(topic) = &entry.cluster_topic {
                *counts.entry(topic.clone()).or_insert(0) += 1;
            }
        }
    }
    let mut topics: Vec<(String, usize)> = counts.into_iter().collect();
    topics.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    topics.into_iter().map(|(t, _)| t).collect()
}

pub(crate) fn sanitize_topic_slug(topic: &str) -> String {
    topic
        .replace(" / ", "-")
        .replace('/', "-")
        .replace(' ', "-")
        .to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── process_core composition guard (t-2247) ───────────────────────

    #[test]
    fn test_process_core_completes_while_lock_held() {
        let dir = tempfile::TempDir::new().unwrap();
        let lock_path = dir.path().join("pipeline.lock");
        let state_path = dir.path().join("state.json");
        let knowledge_root = dir.path().join("bk");
        std::fs::create_dir_all(knowledge_root.join("drafts")).unwrap();
        kp::save_state(&state_path, &kp::PipelineState::default()).unwrap();

        // Hold the lock the way cmd_run does, then drive the core: it must
        // complete without trying to re-acquire (the self-deadlock the
        // challenger flagged — run → process composition).
        let _guard = kp::lock_pipeline_at(&lock_path).expect("outer lock");
        let (tx, rx) = std::sync::mpsc::channel();
        let sp = state_path.clone();
        let kr = knowledge_root.clone();
        std::thread::spawn(move || {
            let mut state = kp::load_state(&sp).unwrap();
            let r = process_core(&kr, &sp, &mut state, true, false, None, true, 1);
            let _ = tx.send(r.is_ok());
        });
        let ok = rx
            .recv_timeout(std::time::Duration::from_secs(10))
            .expect("process_core hung while the caller held the pipeline lock");
        assert!(ok, "process_core (tier1, dry-run) must succeed");
    }

    #[test]
    fn test_lock_discipline_source_tripwires() {
        // Structural guarantees File::lock() can't express: the core must be
        // lock-free, and cmd_run must compose via the core, not cmd_process
        // (which acquires). A regression here reintroduces the deadlock.
        let src = include_str!("knowledge.rs");

        let core_start = src.find("fn process_core").expect("process_core exists");
        let core_end = src[core_start..]
            .find("\npub fn cmd_process")
            .map(|i| core_start + i)
            .expect("cmd_process follows process_core");
        assert!(
            !src[core_start..core_end].contains("lock_pipeline"),
            "process_core must never acquire the pipeline lock (non-reentrant — deadlocks under run→process composition)"
        );

        // process-url stores independently of the pipeline (ADR-070
        // §Lock discipline). Acquiring here would serialise an unrelated
        // command behind a long tier1/2/3 run — and would deadlock outright
        // if t-1144 ever composes the two.
        let pu_start = src.find("pub fn cmd_process_url").expect("cmd_process_url exists");
        let pu_end = src[pu_start..]
            .find("\n/// Warn if the installed binary")
            .map(|i| pu_start + i)
            .unwrap_or(src.len());
        assert!(
            !src[pu_start..pu_end].contains("lock_pipeline"),
            "cmd_process_url must never acquire the pipeline lock — its storage is independent of the tier1/2/3 pipeline"
        );

        let run_start = src.find("pub fn cmd_run").expect("cmd_run exists");
        let run_end = src[run_start..]
            .find("\npub fn ")
            .map(|i| run_start + i)
            .unwrap_or(src.len());
        assert!(
            !src[run_start..run_end].contains("cmd_process("),
            "cmd_run must call process_core, not cmd_process — cmd_process acquires the lock cmd_run already holds"
        );
    }

    #[test]
    fn test_adr042_ingest_sole_pipeline_state_writer_tripwire() {
        // ADR-042 §1: ingest is the sole ingestion write path into
        // PipelineState. drain-links and process-url store into ruflo only —
        // neither may save pipeline state nor queue entries into it
        // (t-3174: the ruflo→fetched_content bridge lives in ingest, not in
        // a second drain-links-writes-both-stores path).
        let src = include_str!("knowledge.rs");

        for (fn_start, fn_name) in [
            ("pub fn cmd_drain_links", "cmd_drain_links"),
            ("pub fn cmd_process_url", "cmd_process_url"),
        ] {
            let start = src.find(fn_start).unwrap_or_else(|| panic!("{fn_name} exists"));
            let end = src[start + 10..]
                .find("\npub fn ")
                .map(|i| start + 10 + i)
                .unwrap_or(src.len());
            let body = &src[start..end];
            assert!(
                !body.contains("save_state") && !body.contains("ingest_urls(")
                    && !body.contains("populate_fetched_content"),
                "{fn_name} must not write into PipelineState (ADR-042 §1 — ingest is the sole writer)"
            );
        }
    }

    // ── process-url: key derivation + outcome decision (t-2450) ──────

    #[test]
    fn process_url_key_is_namespaced_and_slugified() {
        let key = url_storage_key("https://www.Example.com/Posts/Some-Thing?utm=x");
        assert!(key.starts_with("knowledge:url:"), "got {key}");
        assert!(!key.contains("://"), "scheme must not survive into the key: {key}");
        assert!(
            !key.trim_start_matches("knowledge:url:").contains('/'),
            "path separators must be slugified: {key}"
        );
        assert_eq!(key, key.to_lowercase(), "key must be case-stable: {key}");
    }

    #[test]
    fn process_url_key_is_stable_for_the_same_url() {
        // Idempotency rests entirely on this: the second run must derive
        // the identical key or it re-fetches and re-stores every time.
        let a = url_storage_key("https://www.linkedin.com/posts/someone_a-title-abc123");
        let b = url_storage_key("https://www.linkedin.com/posts/someone_a-title-abc123");
        assert_eq!(a, b);
    }

    #[test]
    fn process_url_key_ignores_tracking_params() {
        // t-2583: mobile share sheets append utm_*/rcm to effectively every
        // captured link — with and without them must be ONE key or exact-key
        // idempotency never fires.
        let clean = url_storage_key(
            "https://www.linkedin.com/posts/adrien-taravant-aa11bb_some-post-activity-h9dx",
        );
        let tracked = url_storage_key(
            "https://www.linkedin.com/posts/adrien-taravant-aa11bb_some-post-activity-h9dx?utm_source=share&utm_medium=member_android&rcm=ACoAAARwJLkBJqr70A1PJbG5r3-PHzY3QMybYwc",
        );
        assert_eq!(clean, tracked);
    }

    #[test]
    fn process_url_key_keeps_load_bearing_query() {
        // Two different videos must not collapse to one key.
        let a = url_storage_key("https://www.youtube.com/watch?v=aaaa1111");
        let b = url_storage_key("https://www.youtube.com/watch?v=bbbb2222");
        assert_ne!(a, b);
    }

    #[test]
    fn process_url_key_unwraps_safety_wrapper() {
        // t-2590 residual: different /safety/go wrappers around the same
        // target must store under the target's key.
        let wrapped = url_storage_key(
            "https://www.linkedin.com/safety/go?url=https%3A%2F%2Fexample.com%2Fpost&trk=feed",
        );
        let direct = url_storage_key("https://example.com/post");
        assert_eq!(wrapped, direct);
    }

    #[test]
    fn process_url_distinct_urls_get_distinct_keys() {
        // Boundary: slug collapsing must not merge two different posts.
        let a = url_storage_key("https://example.com/one");
        let b = url_storage_key("https://example.com/two");
        assert_ne!(a, b);
    }

    #[test]
    fn process_url_already_stored_short_circuits_before_fetch() {
        // The idempotency contract: a stored key means no fetch at all —
        // re-running a nightly batch must not re-pay for every URL.
        let outcome = resolve_process_url_outcome(true, None);
        assert_eq!(outcome, ProcessUrlOutcome::AlreadyStored);
    }

    #[test]
    fn process_url_not_found_is_a_miss_not_a_failure() {
        // fetch_url_content returned Ok(None): the LinkedIn post wasn't in
        // the author's feed. Spec: print, store nothing, and do NOT add the
        // id to the cancellation list — but this is not an error.
        let outcome = resolve_process_url_outcome(false, None);
        assert_eq!(outcome, ProcessUrlOutcome::NotFound);
    }

    #[test]
    fn process_url_empty_content_stores_nothing() {
        let fetched = kp::FetchedContent { text: String::new(), platform: "other", caption_source: None };
        assert_eq!(
            resolve_process_url_outcome(false, Some(&fetched)),
            ProcessUrlOutcome::EmptyContent
        );
    }

    #[test]
    fn process_url_whitespace_only_content_counts_as_empty() {
        // Boundary: strip_html_to_text on a JS-only page yields whitespace,
        // not an empty string. Storing that would poison the namespace with
        // an entry that looks real to search and contains nothing.
        let fetched =
            kp::FetchedContent { text: "   \n\t  ".into(), platform: "other", caption_source: None };
        assert_eq!(
            resolve_process_url_outcome(false, Some(&fetched)),
            ProcessUrlOutcome::EmptyContent
        );
    }

    #[test]
    fn process_url_substantive_content_is_stored() {
        let fetched = kp::FetchedContent {
            text: "A genuine paragraph of fetched content worth keeping around.".into(),
            platform: "other",
            caption_source: None,
        };
        assert_eq!(
            resolve_process_url_outcome(false, Some(&fetched)),
            ProcessUrlOutcome::Store
        );
    }

    // ── process-url Store arm: youtube bypasses extract_insight (t-2950) ──
    // resolve_store_value takes the already-extracted insight as a parameter
    // rather than calling kp::extract_insight itself, so these tests exercise
    // the storage decision without extract_insight's real agy/claude -p
    // subprocess calls (same "test the decision, not the I/O" discipline as
    // resolve_process_url_outcome above).

    #[test]
    fn test_resolve_store_value_youtube_stores_text_unmodified_with_transcript_tags() {
        let fetched = kp::FetchedContent {
            text: "the full transcript text, unsummarized".into(),
            platform: "youtube",
            caption_source: Some("manual"),
        };
        let (value, tags) = resolve_store_value(&fetched, None);
        assert_eq!(value, "the full transcript text, unsummarized");
        assert_eq!(tags, vec!["youtube", "transcript", "manual"]);
    }

    #[test]
    fn test_resolve_store_value_youtube_auto_caption_source_tag() {
        let fetched = kp::FetchedContent {
            text: "auto-captioned transcript".into(),
            platform: "youtube",
            caption_source: Some("auto"),
        };
        let (_, tags) = resolve_store_value(&fetched, None);
        assert_eq!(tags, vec!["youtube", "transcript", "auto"]);
    }

    #[test]
    fn test_resolve_store_value_non_youtube_uses_insight_summary_and_topic() {
        // Regression guard (t-2950 AC): every non-youtube tier's existing
        // extract_insight summarization behavior must stay unchanged.
        let fetched = kp::FetchedContent {
            text: "raw fetched content, never stored directly for this platform".into(),
            platform: "github",
            caption_source: None,
        };
        let insight = kp::ExtractedInsight {
            summary: "a short summary".into(),
            topic: "software".into(),
            extraction_skipped: false,
        };
        let (value, tags) = resolve_store_value(&fetched, Some(&insight));
        assert_eq!(value, "a short summary");
        assert_eq!(tags, vec!["github", "software"]);
    }

    // Boundary (t-2950): caption_source should always be Some for a
    // Store-reachable youtube FetchedContent (fetch_youtube_content only
    // returns Some(FetchedContent) when it found captions), but the
    // storage decision must not panic if that invariant is ever violated —
    // fail safe to "auto" rather than crash the drain.
    #[test]
    fn test_resolve_store_value_youtube_missing_caption_source_defaults_to_auto() {
        let fetched =
            kp::FetchedContent { text: "transcript".into(), platform: "youtube", caption_source: None };
        let (_, tags) = resolve_store_value(&fetched, None);
        assert_eq!(tags, vec!["youtube", "transcript", "auto"]);
    }

    // ── process-url batch mode (t-2451) ──────────────────────────────

    #[test]
    fn process_url_batch_parses_id_and_url_pairs() {
        let entries = parse_batch_file(
            "{\"id\":\"t-100\",\"url\":\"https://example.com/a\"}\n\
             {\"id\":\"t-101\",\"url\":\"https://example.com/b\"}\n",
        )
        .expect("well-formed jsonl must parse");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].id, "t-100");
        assert_eq!(entries[1].url, "https://example.com/b");
    }

    #[test]
    fn process_url_batch_ignores_blank_lines() {
        // Boundary: trailing newline / blank separators are common in
        // generated jsonl and must not read as a malformed record.
        let entries = parse_batch_file(
            "{\"id\":\"t-100\",\"url\":\"https://example.com/a\"}\n\n   \n",
        )
        .expect("blank lines are not records");
        assert_eq!(entries.len(), 1);
    }

    #[test]
    fn process_url_batch_malformed_line_reports_line_number() {
        // A batch is unattended; "parse error" without a line number means
        // hand-bisecting the file.
        let err = parse_batch_file(
            "{\"id\":\"t-100\",\"url\":\"https://example.com/a\"}\n\
             not json at all\n",
        )
        .expect_err("malformed jsonl must be an error");
        assert!(err.to_string().contains('2'), "must name the line: {err}");
    }

    #[test]
    fn process_url_batch_cancellable_when_stored_or_already_stored() {
        // Both mean the URL's content is in the knowledge base, so the
        // research stub that tracked it can be closed.
        assert!(is_cancellable(&ProcessUrlOutcome::Store));
        assert!(is_cancellable(&ProcessUrlOutcome::AlreadyStored));
    }

    #[test]
    fn process_url_batch_cancellable_excludes_empty_content() {
        // Spec Edge Cases, explicit: empty/near-empty content is NOT
        // grounds to cancel — nothing was captured, so the stub still has
        // work behind it.
        assert!(!is_cancellable(&ProcessUrlOutcome::EmptyContent));
    }

    #[test]
    fn process_url_batch_cancellable_excludes_not_found() {
        // The post wasn't in the author's feed; the link is still unread.
        assert!(!is_cancellable(&ProcessUrlOutcome::NotFound));
    }

    #[test]
    fn process_url_batch_exit_code_nonzero_only_on_real_failure() {
        // NotFound and EmptyContent are expected outcomes, not failures
        // (spec: a miss "is not itself an error"), so they must not make a
        // nightly cron alert. A fetch/store error must.
        assert_eq!(batch_exit_code(0), 0);
        assert_eq!(batch_exit_code(2), 1);
    }

    // --- drain-links (t-2557) ---------------------------------------------
    //
    // These replace personal/deploy/research-extraction.sh, whose own suite
    // passed 8/8 while the live path was broken. Each test below pins a
    // defect that suite could not see.

    #[test]
    fn drain_extracts_url_from_capture_context() {
        // process-link-queue.sh writes "... URL: {url}" into the context.
        let ctx = "Captured via telegram link-capture. \
                   queued_at: 2026-07-22T19:00:40-03:00. \
                   URL: https://example.com/post";
        assert_eq!(
            extract_capture_url(ctx),
            Some("https://example.com/post".to_string())
        );
    }

    #[test]
    fn drain_url_extraction_strips_json_quoting() {
        // REGRESSION t-1365: `backlog get --field` emits a JSON-quoted
        // string, so a URL at the end of context absorbed the closing quote
        // and every fetch was made against a malformed URL. The bash fix
        // decoded the JSON; here the extractor must not include the quote
        // regardless of how the value arrives.
        let ctx = "\"Captured via telegram. URL: https://example.com/post\"";
        assert_eq!(
            extract_capture_url(ctx),
            Some("https://example.com/post".to_string())
        );
    }

    #[test]
    fn drain_url_extraction_returns_none_without_a_url() {
        // A context with no URL: marker must be skipped, not guessed at.
        assert_eq!(extract_capture_url("Captured via telegram. no link here"), None);
        assert_eq!(extract_capture_url(""), None);
    }

    #[test]
    fn drain_cap_takes_all_items_up_to_the_cap() {
        // REGRESSION t-1367: the bash loop piped ids into `while read` and
        // called `claude -p` inside it; the real binary drained the shared
        // stdin, so a cap of 3 processed exactly 1 and the swallowed ids
        // leaked into the prompt. Its test passed anyway, because the stub
        // never read stdin. Selection here is pure — assert the full cap.
        let ids = vec!["t-1".to_string(), "t-2".to_string(), "t-3".to_string()];
        assert_eq!(select_drain_batch(&ids, 3).len(), 3);
    }

    #[test]
    fn drain_cap_truncates_a_longer_backlog() {
        // Per-run cap (pattern_per-run-cap-backlog-draining, t-2076): take
        // `cap` now and leave the rest pending. Idempotency makes the next
        // run's re-scan cheap, so nothing needs a watermark.
        let ids: Vec<String> = (0..27).map(|i| format!("t-{i}")).collect();
        let batch = select_drain_batch(&ids, 3);
        assert_eq!(batch.len(), 3);
        assert_eq!(batch[0], "t-0");
        assert_eq!(batch[2], "t-2");
    }

    #[test]
    fn drain_cap_of_zero_selects_nothing() {
        let ids = vec!["t-1".to_string()];
        assert!(select_drain_batch(&ids, 0).is_empty());
    }

    #[test]
    fn drain_extracts_url_from_real_backlog_output_verbatim() {
        // Fixture copied byte-for-byte from `brana backlog get t-1336
        // --field context` in the personal repo — NOT hand-written.
        //
        // The suite this command replaces passed 8/8 against a hand-written
        // stub that returned a tidier shape than the real CLI, which is
        // precisely how t-1365 survived (pattern_test-double-must-match-
        // real-output-shape). Note the real shape: JSON-quoted, URL last, so
        // the closing quote abuts the URL with no whitespace to separate it.
        let real = "\"Captured via telegram link-capture. \
                    queued_at: 2026-07-23T21:14:29.722965-03:00. \
                    URL: https://www.linkedin.com/posts/adrien-taravant_if-youre-building-a-company-brain-gbrain-share-7486017239981375488-H9Dx/?utm_source=share&utm_medium=member_android&rcm=ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc\"";
        let url = extract_capture_url(real).expect("real context must yield a URL");
        assert!(
            !url.ends_with('"'),
            "trailing JSON quote leaked into the URL — t-1365 regression: {url}"
        );
        assert!(url.ends_with("ACoAAARWJLkBjqr70A1PjBg5r3-pHzy3QmyBYwc"));
        assert!(url.starts_with("https://www.linkedin.com/posts/adrien-taravant_"));
    }

    #[test]
    fn drain_url_extraction_takes_the_first_marker_only() {
        // Boundary: a context appended to twice must not concatenate or
        // silently prefer the later link.
        let ctx = "URL: https://a.example/one and later URL: https://b.example/two";
        assert_eq!(
            extract_capture_url(ctx),
            Some("https://a.example/one".to_string())
        );
    }

    #[test]
    fn drain_url_extraction_handles_a_dangling_marker() {
        // Boundary: "URL: " with nothing after it must be None, not an
        // empty-string URL that would then be fetched.
        assert_eq!(extract_capture_url("Captured. URL: "), None);
        assert_eq!(extract_capture_url("Captured. URL: \""), None);
    }

    #[test]
    fn drain_cap_larger_than_backlog_returns_everything() {
        // Boundary: the common steady-state once the backlog is drained.
        let ids = vec!["t-1".to_string(), "t-2".to_string()];
        assert_eq!(select_drain_batch(&ids, 99).len(), 2);
        assert!(select_drain_batch(&[], 3).is_empty());
    }

    // ── drain-links platform filter (t-2955, TDD-red pre-impl) ──────────
    // AC: the split lives in cmd_drain_links's candidate filter, NOT
    // select_drain_batch (which stays a bare .take(cap), asserted above
    // unchanged by these three new tests existing alongside it).

    #[test]
    fn test_candidate_filter_excludes_youtube_from_default_batch() {
        assert!(!candidate_passes_platform_filter(
            "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            None
        ));
    }

    #[test]
    fn test_candidate_filter_includes_non_youtube_in_default_batch() {
        assert!(candidate_passes_platform_filter("https://github.com/foo/bar", None));
    }

    #[test]
    fn test_candidate_filter_platform_youtube_selects_only_youtube() {
        assert!(candidate_passes_platform_filter(
            "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            Some("youtube")
        ));
        assert!(!candidate_passes_platform_filter("https://github.com/foo/bar", Some("youtube")));
    }

    // Boundary (t-2956): youtu.be short links must match too — not just
    // youtube.com/watch — and an unrecognized --platform value must select
    // nothing rather than silently falling back to the default job's set.
    #[test]
    fn test_candidate_filter_matches_youtu_be_short_links() {
        assert!(!candidate_passes_platform_filter("https://youtu.be/jNQXAC9IVRw", None));
        assert!(candidate_passes_platform_filter("https://youtu.be/jNQXAC9IVRw", Some("youtube")));
    }

    #[test]
    fn test_candidate_filter_unknown_platform_selects_nothing() {
        assert!(!candidate_passes_platform_filter("https://github.com/foo/bar", Some("linkedin")));
        assert!(!candidate_passes_platform_filter(
            "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            Some("linkedin")
        ));
    }

    #[test]
    fn drain_completes_only_links_whose_content_reached_the_store() {
        // THE POINT OF THIS TASK (personal t-1366, P0). The bash script
        // marked a task completed whenever `claude -p` exited 0 — including
        // when it persisted nothing — draining 33 links into `completed`
        // with zero knowledge captured. Completion must follow the artifact.
        assert!(should_complete_link(&ProcessUrlOutcome::Store));
        assert!(should_complete_link(&ProcessUrlOutcome::AlreadyStored));
        assert!(!should_complete_link(&ProcessUrlOutcome::EmptyContent));
        assert!(!should_complete_link(&ProcessUrlOutcome::NotFound));
    }

    // ── parse_search_results ─────────────────────────────────────────

    #[test]
    fn test_parse_valid_results() {
        let json = r#"[
            {"key": "knowledge:docs/reflections/31-assurance.md:testing", "value": "Testing and assurance framework overview", "score": 0.82},
            {"key": "pattern:thebrana:hooks-cant-enforce-ordering", "value": "Hooks are stateless — can't enforce workflow ordering", "score": 0.75}
        ]"#;
        let results = parse_search_results(json).expect("should parse");
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].key, "knowledge:docs/reflections/31-assurance.md:testing");
        assert!((results[0].score - 0.82).abs() < 1e-9);
        assert_eq!(results[1].key, "pattern:thebrana:hooks-cant-enforce-ordering");
    }

    #[test]
    fn test_parse_empty_array() {
        let results = parse_search_results("[]").expect("should parse");
        assert!(results.is_empty());
    }

    #[test]
    fn test_parse_missing_score_defaults_to_zero() {
        let json = r#"[{"key": "knowledge:some:key", "value": "content here"}]"#;
        let results = parse_search_results(json).expect("should parse");
        assert_eq!(results.len(), 1);
        assert!((results[0].score - 0.0).abs() < 1e-9);
    }

    #[test]
    fn test_parse_invalid_json_returns_error() {
        assert!(parse_search_results("not json").is_err());
        assert!(parse_search_results("{\"key\":\"v\"}").is_err()); // object, not array
    }

    #[test]
    fn test_parse_json_with_onnx_preamble() {
        // ruflo prepends ONNX loading messages before JSON on stdout
        let text = concat!(
            "Loading ONNX model: all-MiniLM-L6-v2...\n",
            "  Disk cache hit: all-MiniLM-L6-v2\n",
            "ONNX embedder ready: 384d, SIMD: true\n",
            "[INFO] Searching: \"test\" (semantic)\n\n",
            "  Search time: 76ms\n\n",
            "[{\"key\":\"k1\",\"value\":\"v1\",\"score\":0.7}]"
        );
        let results = parse_search_results(text).expect("should parse preamble + json");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].key, "k1");
        assert!((results[0].score - 0.7).abs() < 1e-9);
    }

    #[test]
    fn test_parse_table_format() {
        let table = concat!(
            "Loading ONNX model: all-MiniLM-L6-v2...\n",
            "ONNX embedder ready: 384d, SIMD: true\n",
            "[INFO] Searching: \"hook\" (semantic)\n\n",
            "+----------------------+-------+-----------+-------------------------------------+\n",
            "| Key                  | Score | Namespace | Preview                             |\n",
            "+----------------------+-------+-----------+-------------------------------------+\n",
            "| knowledge:feed:re... |  0.65 | knowledge | 2026-04-30 — TDD and Rules Enfor... |\n",
            "| field-note:hooks:... |  0.42 | knowledge | Two hooks in sequence reliably c... |\n",
            "+----------------------+-------+-----------+-------------------------------------+\n",
            "\n[INFO] Found 2 results\n"
        );
        let results = parse_search_results(table).expect("should parse table format");
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].key, "knowledge:feed:re...");
        assert!((results[0].score - 0.65).abs() < 0.001);
        assert_eq!(results[0].value, "2026-04-30 — TDD and Rules Enfor...");
        assert_eq!(results[1].key, "field-note:hooks:...");
        assert!((results[1].score - 0.42).abs() < 0.001);
    }

    #[test]
    fn test_parse_empty_table_returns_empty() {
        let table = concat!(
            "+-----+-------+-----------+---------+\n",
            "| Key | Score | Namespace | Preview |\n",
            "+-----+-------+-----------+---------+\n",
            "+-----+-------+-----------+---------+\n"
        );
        let results = parse_search_results(table).expect("should parse empty table");
        assert!(results.is_empty());
    }

    #[test]
    fn test_parse_no_results_returns_empty_not_error() {
        // ruflo emits neither a table nor a JSON array when nothing matches.
        // This is a legitimate empty result, not a malformed response (t-2729).
        let text = concat!(
            "[INFO] Searching: \"orca\" (semantic)\n\n",
            "  Search time: 313ms\n\n",
            "[WARN] No results found\n",
            "Try: claude-flow memory store -k \"key\" --value \"data\"\n"
        );
        let results = parse_search_results(text).expect("no-results output should parse as empty");
        assert!(results.is_empty());
    }

    #[test]
    fn test_parse_garbage_still_errors() {
        // Guard: the no-results carve-out must not swallow genuinely broken output.
        assert!(parse_search_results("not json").is_err());
        assert!(parse_search_results("").is_err());
    }

    // ── search threshold calibration ─────────────────────────────────

    #[test]
    fn test_default_threshold_below_corpus_ceiling() {
        // ruflo's own default is 0.7. Measured top scores in the `knowledge`
        // namespace across 5 diverse queries: 0.69, 0.43, 0.40, 0.39, 0.37.
        // A 0.7 default therefore filters out every result for every query.
        const OBSERVED_TOP_SCORES: [f64; 5] = [0.69, 0.43, 0.40, 0.39, 0.37];
        for top in OBSERVED_TOP_SCORES {
            assert!(
                resolve_threshold(None) < top,
                "default threshold {} would return zero results for a query whose best match scores {top}",
                resolve_threshold(None)
            );
        }
    }

    #[test]
    fn test_explicit_threshold_overrides_default() {
        assert!((resolve_threshold(Some(0.6)) - 0.6).abs() < 1e-9);
        assert!((resolve_threshold(Some(0.0)) - 0.0).abs() < 1e-9);
    }

    // ── truncate ─────────────────────────────────────────────────────

    #[test]
    fn test_truncate_short_string_unchanged() {
        assert_eq!(truncate("hello world", 50), "hello world");
    }

    #[test]
    fn test_truncate_exact_length_unchanged() {
        let s = "abcde";
        assert_eq!(truncate(s, 5), "abcde");
    }

    #[test]
    fn test_truncate_long_string_clipped() {
        let s = "abcdefghij";
        let result = truncate(s, 5);
        assert_eq!(result, "abcde...");
    }

    #[test]
    fn test_truncate_trims_whitespace() {
        assert_eq!(truncate("  hi  ", 50), "hi");
    }

    // ── format_results ───────────────────────────────────────────────

    #[test]
    fn test_format_empty_results() {
        let out = format_results(&[]);
        assert!(out.contains("No results found"));
    }

    #[test]
    fn test_format_single_result() {
        let results = vec![SearchResult {
            key: "knowledge:docs/reflections/31-assurance.md:testing".into(),
            value: "Testing and assurance framework overview".into(),
            score: 0.82, source: default_source(),
        }];
        let out = format_results(&results);
        assert!(out.contains("1."), "should contain rank number");
        assert!(out.contains("[0.82]"), "should contain formatted score");
        assert!(out.contains("knowledge:docs/reflections/31-assurance.md:testing"), "should contain key");
        assert!(out.contains("Testing and assurance framework"), "should contain value preview");
    }

    #[test]
    fn test_format_multiple_results_numbered_sequentially() {
        let results = vec![
            SearchResult { key: "k:a".into(), value: "first".into(), score: 0.9, source: default_source() },
            SearchResult { key: "k:b".into(), value: "second".into(), score: 0.7, source: default_source() },
            SearchResult { key: "k:c".into(), value: "third".into(), score: 0.5, source: default_source() },
        ];
        let out = format_results(&results);
        assert!(out.contains("1."));
        assert!(out.contains("2."));
        assert!(out.contains("3."));
        // Verify ordering: first result should appear before second
        let pos_first = out.find("k:a").unwrap();
        let pos_second = out.find("k:b").unwrap();
        assert!(pos_first < pos_second);
    }

    #[test]
    fn test_format_long_value_is_truncated() {
        let long_value = "x".repeat(200);
        let results = vec![SearchResult {
            key: "k:long".into(),
            value: long_value,
            score: 0.5, source: default_source(),
        }];
        let out = format_results(&results);
        // Value preview line should end with "..." due to truncation
        assert!(out.contains("..."), "long value should be truncated with ...");
    }

    #[test]
    fn test_format_score_precision() {
        let results = vec![SearchResult {
            key: "k:precise".into(),
            value: "some content".into(),
            score: 0.123456, source: default_source(),
        }];
        let out = format_results(&results);
        // Score should be formatted with 2 decimal places
        assert!(out.contains("[0.12]"), "score should be 2 decimal places, got: {out}");
    }

    // ── merge_search_legs (t-2734) ───────────────────────────────────────

    fn sr(key: &str, score: f64, source: &str) -> SearchResult {
        SearchResult {
            key: key.into(),
            value: format!("value for {key}"),
            score,
            source: source.into(),
        }
    }

    #[test]
    fn test_merge_vector_first_then_ruflo_extras() {
        // AC (t-2734): an entry present only in the vector store must be
        // findable; ruflo extras (fresh-writes window) follow, source-tagged.
        let vector = vec![sr("knowledge:feature:only-in-vector", 0.9, "vector")];
        let ruflo = vec![sr("knowledge:feed:fresh-write", 0.8, "ruflo")];
        let merged = merge_search_legs(vector, ruflo);
        assert_eq!(merged.len(), 2);
        assert_eq!(merged[0].key, "knowledge:feature:only-in-vector");
        assert_eq!(merged[0].source, "vector");
        assert_eq!(merged[1].key, "knowledge:feed:fresh-write");
        assert_eq!(merged[1].source, "ruflo");
    }

    #[test]
    fn test_merge_dedups_exact_key() {
        let vector = vec![sr("knowledge:feed:same", 0.9, "vector")];
        let ruflo = vec![sr("knowledge:feed:same", 0.7, "ruflo")];
        let merged = merge_search_legs(vector, ruflo);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].source, "vector");
    }

    #[test]
    fn test_merge_dedups_truncated_ruflo_key() {
        // ruflo table output truncates keys — a `...` stem that prefixes a
        // vector key is the same entry, not an extra.
        let vector = vec![sr("knowledge:feed:release-notes-2026", 0.9, "vector")];
        let ruflo = vec![sr("knowledge:feed:re...", 0.7, "ruflo")];
        let merged = merge_search_legs(vector, ruflo);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].key, "knowledge:feed:release-notes-2026");
    }

    #[test]
    fn test_merge_keeps_unrelated_truncated_key() {
        // A truncated stem that matches NO vector key is a genuine extra —
        // keep it (display-grade identity is better than silence).
        let vector = vec![sr("knowledge:feature:x", 0.9, "vector")];
        let ruflo = vec![sr("knowledge:url:someth...", 0.7, "ruflo")];
        let merged = merge_search_legs(vector, ruflo);
        assert_eq!(merged.len(), 2);
    }

    // ── build_draft_content ──────────────────────────────────────────────

    #[test]
    fn test_build_draft_content_stamps_type_claim() {
        let content = build_draft_content(
            "2026-07-24",
            "  - url: https://example.com\n    logged: unknown",
            "agent-memory",
            "21-memory",
            "2026-07-31",
            "body text",
        );
        assert_eq!(
            parse_frontmatter_field(&content, "type"),
            Some("claim".to_string()),
            "Tier 3 draft output must carry type: claim per ADR-057 (t-2437): got {content}"
        );
    }

    #[test]
    fn test_build_draft_content_preserves_existing_fields() {
        let content = build_draft_content(
            "2026-07-24",
            "  - url: https://example.com\n    logged: unknown",
            "agent-memory",
            "21-memory",
            "2026-07-31",
            "body text",
        );
        assert_eq!(parse_frontmatter_field(&content, "status"), Some("draft".to_string()));
        assert_eq!(parse_frontmatter_field(&content, "cluster_topic"), Some("agent-memory".to_string()));
        assert_eq!(
            parse_frontmatter_field(&content, "promotion_target"),
            Some("dimensions/21-memory.md".to_string())
        );
        assert!(content.ends_with("body text\n"), "got: {content}");
    }

    // ── parse_frontmatter_field ──────────────────────────────────────────

    #[test]
    fn test_parse_frontmatter_field_present() {
        let content = "---\nstatus: draft\ncluster_topic: agent-memory\n---\nbody";
        assert_eq!(
            parse_frontmatter_field(content, "cluster_topic"),
            Some("agent-memory".to_string())
        );
    }

    #[test]
    fn test_parse_frontmatter_field_missing_returns_none() {
        let content = "---\nstatus: draft\n---\nbody";
        assert_eq!(parse_frontmatter_field(content, "promotion_target"), None);
    }

    #[test]
    fn test_parse_frontmatter_field_trims_whitespace() {
        let content = "promotion_target:   dimensions/21-memory.md  ";
        assert_eq!(
            parse_frontmatter_field(content, "promotion_target"),
            Some("dimensions/21-memory.md".to_string())
        );
    }

    // ── set_frontmatter_status ───────────────────────────────────────────

    #[test]
    fn test_set_frontmatter_status_replaces_status_line() {
        let content = "---\nstatus: draft\ncreated: 2026-04-12\n---\nbody";
        let result = set_frontmatter_status(content, "accepted");
        assert!(result.contains("status: accepted"));
        assert!(!result.contains("status: draft"));
    }

    #[test]
    fn test_set_frontmatter_status_leaves_other_lines_unchanged() {
        let content = "---\nstatus: draft\ncreated: 2026-04-12\n---\nbody";
        let result = set_frontmatter_status(content, "accepted");
        assert!(result.contains("created: 2026-04-12"));
        assert!(result.contains("body"));
    }

    #[test]
    fn test_set_frontmatter_status_no_status_line_unchanged() {
        let content = "---\ncreated: 2026-04-12\n---\nbody";
        let result = set_frontmatter_status(content, "accepted");
        assert!(!result.contains("status:"));
        assert!(result.contains("created: 2026-04-12"));
    }

    // ── strip_frontmatter ────────────────────────────────────────────────

    #[test]
    fn test_strip_frontmatter_removes_yaml_block() {
        let content = "---\nstatus: draft\n---\n\n# Body\n\ncontent here";
        assert_eq!(strip_frontmatter(content), "# Body\n\ncontent here");
    }

    #[test]
    fn test_strip_frontmatter_no_frontmatter_returns_unchanged() {
        let content = "# Just a doc\n\nno frontmatter";
        assert_eq!(strip_frontmatter(content), "# Just a doc\n\nno frontmatter");
    }

    #[test]
    fn test_strip_frontmatter_unclosed_returns_unchanged() {
        let content = "---\nstatus: draft\n\n# Body";
        // no closing ---, returns original
        assert_eq!(strip_frontmatter(content), "---\nstatus: draft\n\n# Body");
    }

    // ── count_by_tier ────────────────────────────────────────────────────

    fn make_entry(status: UrlStatus) -> kp::UrlEntry {
        let mut e = kp::UrlEntry::new_unprocessed(None);
        e.status = status;
        e
    }

    #[test]
    fn test_count_by_tier_empty_state() {
        let state = kp::PipelineState::default();
        let counts = count_by_tier(&state);
        assert_eq!(counts.unprocessed, 0);
        assert_eq!(counts.tier1_passed, 0);
    }

    #[test]
    fn test_count_by_tier_mixed_statuses() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("u1".into(), make_entry(UrlStatus::Unprocessed));
        state.urls.insert("u2".into(), make_entry(UrlStatus::Unprocessed));
        state.urls.insert("u3".into(), make_entry(UrlStatus::Tier1Passed));
        state.urls.insert("u4".into(), make_entry(UrlStatus::Irrelevant));
        state.urls.insert("u5".into(), make_entry(UrlStatus::Tier2Clustered));
        state.urls.insert("u6".into(), make_entry(UrlStatus::Tier3Drafted));
        let counts = count_by_tier(&state);
        assert_eq!(counts.unprocessed, 2);
        assert_eq!(counts.irrelevant, 1);
        assert_eq!(counts.tier1_passed, 1);
        assert_eq!(counts.tier2_clustered, 1);
        assert_eq!(counts.tier3_drafted, 1);
    }

    // ── url_reset_state ──────────────────────────────────────────────────

    #[test]
    fn test_url_reset_state_removes_url() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(UrlStatus::Tier1Passed));
        let new_state = url_reset_state(state, "https://example.com");
        assert!(!new_state.urls.contains_key("https://example.com"));
    }

    #[test]
    fn test_url_reset_state_missing_url_is_noop() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://kept.com".into(), make_entry(UrlStatus::Tier1Passed));
        let new_state = url_reset_state(state, "https://gone.com");
        assert!(new_state.urls.contains_key("https://kept.com"));
        assert_eq!(new_state.urls.len(), 1);
    }

    // ── build_cluster_report ─────────────────────────────────────────────

    #[test]
    fn test_build_cluster_report_contains_topic_and_target() {
        let mut clusters = std::collections::HashMap::new();
        clusters.insert("agent-memory".to_string(), vec!["https://linkedin.com/u1".to_string()]);
        let mut dim_targets = std::collections::HashMap::new();
        dim_targets.insert("agent-memory".to_string(), "21-memory-patterns".to_string());
        let report = build_cluster_report(&clusters, &dim_targets);
        assert!(report.contains("## agent-memory"));
        assert!(report.contains("21-memory-patterns"));
        assert!(report.contains("https://linkedin.com/u1"));
    }

    #[test]
    fn test_build_cluster_report_empty_returns_header() {
        let clusters = std::collections::HashMap::new();
        let dim_targets = std::collections::HashMap::new();
        let report = build_cluster_report(&clusters, &dim_targets);
        assert!(report.contains("# Knowledge Pipeline"));
    }

    #[test]
    fn test_build_cluster_report_includes_draft_command() {
        let mut clusters = std::collections::HashMap::new();
        clusters.insert("cli-tooling".to_string(), vec!["https://linkedin.com/u2".to_string()]);
        let dim_targets = std::collections::HashMap::new();
        let report = build_cluster_report(&clusters, &dim_targets);
        assert!(report.contains("brana knowledge process --draft cli-tooling"));
    }

    // ── backfill_linkedin_fields ─────────────────────────────────────────

    #[test]
    fn test_backfill_linkedin_fields_populates_missing_author_and_title() {
        let url = "https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-7437448165403852801-F5RX";
        let mut state = kp::PipelineState::default();
        state.urls.insert(url.to_string(), make_entry(kp::UrlStatus::Unprocessed));
        let count = backfill_linkedin_fields(&mut state);
        assert_eq!(count, 1);
        let entry = &state.urls[url];
        assert_eq!(entry.author.as_deref(), Some("walid-boulanouar"));
        assert!(entry.title_signal.is_some());
    }

    #[test]
    fn test_backfill_linkedin_fields_skips_non_linkedin_urls() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://github.com/foo/bar".to_string(), make_entry(kp::UrlStatus::Unprocessed));
        let count = backfill_linkedin_fields(&mut state);
        assert_eq!(count, 0);
        let entry = state.urls.values().next().unwrap();
        assert!(entry.author.is_none());
    }

    #[test]
    fn test_backfill_linkedin_fields_skips_fully_populated_entries() {
        let url = "https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-7437448165403852801-F5RX";
        let mut state = kp::PipelineState::default();
        let mut entry = make_entry(kp::UrlStatus::Unprocessed);
        entry.author = Some("already-set".to_string());
        entry.title_signal = Some("already-set-title".to_string());
        state.urls.insert(url.to_string(), entry);
        let count = backfill_linkedin_fields(&mut state);
        assert_eq!(count, 0);
        assert_eq!(state.urls[url].author.as_deref(), Some("already-set"));
    }

    // ── next_directive ───────────────────────────────────────────────────

    #[test]
    fn test_next_directive_empty_state_ingest() {
        let dir = tempfile::TempDir::new().unwrap();
        let state = kp::PipelineState::default();
        let d = next_directive(&state, dir.path());
        assert!(d.starts_with("brana knowledge ingest"), "got: {d}");
    }

    #[test]
    fn test_next_directive_unprocessed_tier1() {
        let dir = tempfile::TempDir::new().unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Unprocessed));
        let d = next_directive(&state, dir.path());
        assert_eq!(d, "brana knowledge process --tier1");
    }

    #[test]
    fn test_next_directive_tier1_passed_tier2() {
        let dir = tempfile::TempDir::new().unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Tier1Passed));
        let d = next_directive(&state, dir.path());
        assert_eq!(d, "brana knowledge process --tier2");
    }

    #[test]
    fn test_next_directive_clusters_no_drafts_report() {
        let dir = tempfile::TempDir::new().unwrap();
        std::fs::create_dir(dir.path().join("drafts")).unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Tier2Clustered));
        let d = next_directive(&state, dir.path());
        assert_eq!(d, "brana knowledge process --report");
    }

    #[test]
    fn test_next_directive_drafts_on_disk_promote() {
        let dir = tempfile::TempDir::new().unwrap();
        let drafts = dir.path().join("drafts");
        std::fs::create_dir(&drafts).unwrap();
        std::fs::write(drafts.join("2026-05-24-agents.md"), "# draft").unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Tier2Clustered));
        let d = next_directive(&state, dir.path());
        assert!(d.starts_with("brana knowledge promote"), "got: {d}");
        assert!(d.contains("2026-05-24-agents.md"), "got: {d}");
    }

    #[test]
    fn test_next_directive_drafts_only_no_clusters_promote() {
        let dir = tempfile::TempDir::new().unwrap();
        let drafts = dir.path().join("drafts");
        std::fs::create_dir(&drafts).unwrap();
        std::fs::write(drafts.join("2026-05-01-topic.md"), "# draft").unwrap();
        let state = kp::PipelineState::default();
        let d = next_directive(&state, dir.path());
        assert!(d.starts_with("brana knowledge promote"), "got: {d}");
    }

    // ── run_gate_message ─────────────────────────────────────────────────

    #[test]
    fn test_run_gate_report_directive_returns_gate_message() {
        let msg = run_gate_message("brana knowledge process --report");
        assert!(msg.is_some(), "expected a gate message for --report directive");
        let msg = msg.unwrap();
        assert!(msg.contains("--report"), "gate message should reference --report, got: {msg}");
    }

    #[test]
    fn test_run_gate_promote_directive_returns_gate_message() {
        let msg = run_gate_message("brana knowledge promote /path/to/draft.md");
        assert!(msg.is_some(), "expected a gate message for promote directive");
        let msg = msg.unwrap();
        assert!(msg.contains("promote"), "gate message should reference promote, got: {msg}");
    }

    #[test]
    fn test_run_gate_ingest_directive_returns_gate_message() {
        let msg = run_gate_message("brana knowledge ingest <url>");
        assert!(msg.is_some(), "expected a gate message for ingest directive");
        let msg = msg.unwrap();
        assert!(msg.contains("ingest"), "gate message should reference ingest, got: {msg}");
    }

    #[test]
    fn test_run_gate_tier1_directive_returns_none() {
        let msg = run_gate_message("brana knowledge process --tier1");
        assert!(msg.is_none(), "tier1 should auto-advance (no gate), got: {msg:?}");
    }

    #[test]
    fn test_run_gate_tier2_directive_returns_none() {
        let msg = run_gate_message("brana knowledge process --tier2");
        assert!(msg.is_none(), "tier2 should auto-advance (no gate), got: {msg:?}");
    }

    // ── warn_if_stale_binary ─────────────────────────────────────────────

    #[test]
    fn test_stale_binary_no_panic_when_source_absent() {
        // Should silently no-op when crates root doesn't exist.
        // BRANA_SRC_ROOT points to a nonexistent path.
        unsafe { std::env::set_var("BRANA_SRC_ROOT", "/nonexistent/path/crates"); }
        warn_if_stale_binary(); // must not panic
        unsafe { std::env::remove_var("BRANA_SRC_ROOT"); }
    }

    #[test]
    fn test_stale_binary_detects_newer_source() {
        use std::time::{Duration, SystemTime};
        // Build a temp crates_root with one sentinel file.
        let tmp = std::env::temp_dir()
            .join(format!("brana-stale-test-{}", std::process::id()));
        let sentinel_dir = tmp.join("brana-core/src");
        std::fs::create_dir_all(&sentinel_dir).unwrap();
        std::fs::write(sentinel_dir.join("knowledge_pipeline.rs"), "// sentinel").unwrap();

        // A binary_mtime at epoch is older than any real file — must be detected as stale.
        let ancient = SystemTime::UNIX_EPOCH + Duration::from_secs(1);
        assert!(
            stale_binary_check(&tmp, ancient),
            "should report stale when source is newer than binary"
        );

        // A binary_mtime far in the future must NOT be detected as stale.
        let future = SystemTime::now() + Duration::from_secs(3600);
        assert!(
            !stale_binary_check(&tmp, future),
            "should not report stale when binary is newer than source"
        );

        let _ = std::fs::remove_dir_all(&tmp);
    }

    // ── sanitize_topic_slug ──────────────────────────────────────────────

    #[test]
    fn test_sanitize_slug_spaces() {
        assert_eq!(sanitize_topic_slug("AI agents"), "ai-agents");
    }

    #[test]
    fn test_sanitize_slug_slash_with_spaces() {
        // "SPDD / software process design" must not produce a path-separator slash
        let slug = sanitize_topic_slug("SPDD / software process design");
        assert!(!slug.contains('/'), "slug must not contain '/' — got: {slug}");
        assert_eq!(slug, "spdd-software-process-design");
    }

    #[test]
    fn test_sanitize_slug_bare_slash() {
        let slug = sanitize_topic_slug("context/window");
        assert!(!slug.contains('/'), "slug must not contain '/'");
        assert_eq!(slug, "context-window");
    }

    #[test]
    fn test_sanitize_slug_second_brain_pkm() {
        let slug = sanitize_topic_slug("second brain / PKM architecture");
        assert!(!slug.contains('/'), "slug must not contain '/'");
        assert_eq!(slug, "second-brain-pkm-architecture");
    }

    // ── list_undrafted_clusters ──────────────────────────────────────────

    fn clustered(topic: &str, suffix: &str) -> (String, kp::UrlEntry) {
        let url = format!("https://li.com/{suffix}");
        let mut e = kp::UrlEntry::new_unprocessed(None);
        e.status = kp::UrlStatus::Tier2Clustered;
        e.cluster_topic = Some(topic.into());
        (url, e)
    }

    fn drafted(topic: &str, suffix: &str) -> (String, kp::UrlEntry) {
        let url = format!("https://li.com/{suffix}");
        let mut e = kp::UrlEntry::new_unprocessed(None);
        e.status = kp::UrlStatus::Tier3Drafted;
        e.cluster_topic = Some(topic.into());
        e.draft_path = Some("/drafts/x.md".into());
        (url, e)
    }

    #[test]
    fn test_list_undrafted_empty() {
        assert!(list_undrafted_clusters(&kp::PipelineState::default()).is_empty());
    }

    #[test]
    fn test_list_undrafted_returns_clustered() {
        let mut state = kp::PipelineState::default();
        let (url, entry) = clustered("ai-agents", "p1");
        state.urls.insert(url, entry);
        assert_eq!(list_undrafted_clusters(&state), vec!["ai-agents"]);
    }

    #[test]
    fn test_list_undrafted_excludes_drafted() {
        let mut state = kp::PipelineState::default();
        let (url, entry) = drafted("context-engineering", "p2");
        state.urls.insert(url, entry);
        assert!(list_undrafted_clusters(&state).is_empty());
    }

    #[test]
    fn test_list_undrafted_sorted_by_count() {
        let mut state = kp::PipelineState::default();
        for i in 0..3usize {
            let (url, entry) = clustered("popular", &format!("pop/{i}"));
            state.urls.insert(url, entry);
        }
        let (url, entry) = clustered("rare", "rare/1");
        state.urls.insert(url, entry);
        let result = list_undrafted_clusters(&state);
        assert_eq!(result[0], "popular");
        assert_eq!(result[1], "rare");
    }

    // ── tier2 parallel helpers ───────────────────────────────────────

    #[test]
    fn test_tier2_concurrency_is_3() {
        assert_eq!(TIER2_CONCURRENCY, 3);
    }

    #[test]
    fn test_parse_tier2_json_complete_response() {
        let json = serde_json::json!({
            "dimension_target": "agent-memory",
            "cluster_topic": "memory-systems",
            "reason": "Post discusses vector storage and retrieval."
        });
        let (dim, topic, reason) = parse_tier2_json(&json);
        assert_eq!(dim, "agent-memory");
        assert_eq!(topic, "memory-systems");
        assert_eq!(reason, "Post discusses vector storage and retrieval.");
    }

    #[test]
    fn test_parse_tier2_json_missing_dimension_defaults_to_new_topic() {
        let json = serde_json::json!({
            "cluster_topic": "unknown-area",
            "reason": "No matching dimension found."
        });
        let (dim, _topic, _reason) = parse_tier2_json(&json);
        assert_eq!(dim, "new-topic");
    }

    #[test]
    fn test_parse_tier2_json_missing_cluster_topic_defaults_to_unknown() {
        let json = serde_json::json!({
            "dimension_target": "cli-tooling",
            "reason": "Relevant."
        });
        let (_dim, topic, _reason) = parse_tier2_json(&json);
        assert_eq!(topic, "unknown");
    }

    #[test]
    fn test_parse_tier2_json_missing_reason_defaults_to_empty() {
        let json = serde_json::json!({
            "dimension_target": "cli-tooling",
            "cluster_topic": "rust-cli"
        });
        let (_dim, _topic, reason) = parse_tier2_json(&json);
        assert_eq!(reason, "");
    }

    #[test]
    fn test_build_tier2_prompt_contains_author_and_title() {
        let tags = vec!["rust".to_string(), "cli".to_string()];
        let prompt = build_tier2_prompt("linkedin", "Alice", "Building CLIs in Rust", &tags, "- cli-tooling\n- agent-memory");
        assert!(prompt.contains("Alice"), "prompt must contain author");
        assert!(prompt.contains("Building CLIs in Rust"), "prompt must contain title_signal");
        assert!(prompt.contains("rust cli"), "prompt must contain joined tags");
        assert!(prompt.contains("cli-tooling"), "prompt must contain dim list");
    }

    #[test]
    fn test_build_tier2_prompt_requests_json_response() {
        let prompt = build_tier2_prompt("linkedin", "Bob", "AI agents", &[], "- agent-memory");
        assert!(prompt.contains("Respond with JSON only"), "prompt must request JSON response");
        assert!(prompt.contains("dimension_target"), "prompt must mention dimension_target key");
        assert!(prompt.contains("cluster_topic"), "prompt must mention cluster_topic key");
    }

    // ── build_tier1_prompt ───────────────────────────────────────────────────

    fn make_url_event_entry(author: &str, title_signal: &str, tags: &[&str]) -> kp::UrlEventEntry {
        kp::UrlEventEntry {
            url: "https://linkedin.com/posts/test".to_string(),
            author: author.to_string(),
            title_signal: title_signal.to_string(),
            tags: tags.iter().map(|s| s.to_string()).collect(),
            logged_date: "2026-06-09".to_string(),
        }
    }

    #[test]
    fn test_build_tier1_prompt_contains_author_and_title() {
        let entry = make_url_event_entry("carol", "Building agent memory systems", &["agents", "memory"]);
        let prompt = build_tier1_prompt(&entry, "- agent-memory\n- cli-tooling");
        assert!(prompt.contains("carol"), "prompt must contain author");
        assert!(prompt.contains("Building agent memory systems"), "prompt must contain title_signal");
        assert!(prompt.contains("agents memory"), "prompt must contain joined tags");
        assert!(prompt.contains("agent-memory"), "prompt must contain dim list");
        assert!(prompt.contains("cli-tooling"), "prompt must contain all dims");
    }

    #[test]
    fn test_build_tier1_prompt_requests_json_with_score_and_reason() {
        let entry = make_url_event_entry("dave", "Rust async patterns", &[]);
        let prompt = build_tier1_prompt(&entry, "- rust-tooling");
        assert!(prompt.contains("Respond with JSON only"), "prompt must request JSON response");
        assert!(prompt.contains("\"score\""), "prompt must mention score key");
        assert!(prompt.contains("\"reason\""), "prompt must mention reason key");
    }

    // ── platform-aware prompt wording (t-3175/t-3178, ADR-087 Context #2) ──

    fn make_url_event_entry_at(url: &str, author: &str, title_signal: &str) -> kp::UrlEventEntry {
        kp::UrlEventEntry {
            url: url.to_string(),
            author: author.to_string(),
            title_signal: title_signal.to_string(),
            tags: vec![],
            logged_date: "2026-08-24".to_string(),
        }
    }

    #[test]
    fn test_build_tier1_prompt_github_wording() {
        let entry = make_url_event_entry_at("https://github.com/foo/bar", "foo", "bar");
        let prompt = build_tier1_prompt(&entry, "- cli-tooling");
        assert!(prompt.contains("GitHub repository"), "github entries must be labeled as such, got: {prompt}");
        assert!(!prompt.contains("LinkedIn post"), "github entries must not be mislabeled LinkedIn");
    }

    #[test]
    fn test_build_tier1_prompt_substack_wording() {
        let entry = make_url_event_entry_at("https://foo.substack.com/p/bar", "foo", "bar");
        let prompt = build_tier1_prompt(&entry, "- cli-tooling");
        assert!(prompt.contains("Substack article"), "substack entries must be labeled as such");
        assert!(!prompt.contains("LinkedIn post"));
    }

    #[test]
    fn test_build_tier1_prompt_arxiv_wording() {
        let entry = make_url_event_entry_at("https://arxiv.org/abs/2408.01234", "arxiv", "2408.01234");
        let prompt = build_tier1_prompt(&entry, "- cli-tooling");
        assert!(prompt.contains("arXiv paper"), "arxiv entries must be labeled as such");
        assert!(!prompt.contains("LinkedIn post"));
    }

    #[test]
    fn test_build_tier1_prompt_linkedin_regression_lock() {
        // Byte-exact lock on LinkedIn's live Tier1 prompt (t-3175): the
        // platform generalization must not change LinkedIn output at all.
        let entry = make_url_event_entry_at(
            "https://linkedin.com/posts/carol_agents-7437",
            "carol",
            "agent memory",
        );
        let prompt = build_tier1_prompt(&entry, "agent-memory, cli-tooling");
        let expected = "You are classifying a LinkedIn post for relevance to a personal knowledge base \
about AI systems, agent design, developer tooling, and knowledge management.\n\n\
Author: carol\nTitle signal: agent memory\nTags: \n\n\
Score the relevance 1-5 where:\n\
1 = personal update, marketing, unrelated\n\
2 = tangentially related, low signal\n\
3 = relevant, worth reading\n\
4 = directly relevant to known topics (memory, agents, CLI tooling, CC patterns)\n\
5 = high-signal, likely new dimension content\n\n\
Known dimension topics: agent-memory, cli-tooling\n\n\
Respond with JSON only: {\"score\": N, \"reason\": \"one sentence\"}";
        assert_eq!(prompt, expected, "LinkedIn Tier1 prompt must stay byte-identical");
    }

    #[test]
    fn test_build_tier2_prompt_platform_wording() {
        let tags: Vec<String> = vec![];
        let prompt = build_tier2_prompt("github", "foo", "bar", &tags, "- cli-tooling");
        assert!(prompt.contains("GitHub repository"), "tier2 github wording, got: {prompt}");
        assert!(!prompt.contains("LinkedIn post"));
        let prompt = build_tier2_prompt("arxiv", "arxiv", "2408.01234", &tags, "- cli-tooling");
        assert!(prompt.contains("arXiv paper"));
    }

    #[test]
    fn test_build_tier2_prompt_linkedin_regression_lock() {
        // Locks LinkedIn's live Tier2 prompt text (t-3175) — identical to
        // the pre-generalization literal, only the platform param is new.
        let tags = vec!["agents".to_string()];
        let prompt = build_tier2_prompt("linkedin", "carol", "agent memory", &tags, "- agent-memory");
        let expected = "You are assigning a LinkedIn post to the nearest topic in a knowledge base.\n\n\
Author: carol\nTitle signal: agent memory\nTags: agents\n\n\
Existing dimension topics:\n- agent-memory\n\n\
Assign this post to the best-matching dimension, or flag as \"new-topic\" \
if it doesn't fit any existing dimension.\n\n\
Respond with JSON only:\n\
{\"dimension_target\": \"slug or new-topic\", \"cluster_topic\": \"short label\", \"reason\": \"one sentence\"}";
        assert_eq!(prompt, expected, "LinkedIn Tier2 prompt must stay byte-identical");
    }

    // ── channel-backfill CLI wiring (t-2999) ─────────────────────────────
    // resolve_channel_tab / build_channel_link_task_json are pure — no
    // subprocess, no I/O — the same split as extract_capture_url above.
    // cmd_channel_backfill itself (network + subprocess shellout to `brana
    // backlog add`) stays untested here, same discipline as cmd_ingest and
    // feed.rs's "task" action.

    // ── resolve_yt_dlp_cookies (t-3036, feature spec §7) ─────────────────

    #[test]
    fn resolve_yt_dlp_cookies_neither_flag_is_none() {
        // Hermetic: the `resolve_yt_dlp_cookies` wrapper consults the real
        // `$HOME` default jar (spec §8), so the neither-flag contract is
        // pinned on the injectable form (challenger finding, t-3038).
        assert_eq!(resolve_yt_dlp_cookies_with(None, None, None).unwrap(), kp::YtDlpCookies::None);
    }

    #[test]
    fn resolve_yt_dlp_cookies_browser_passes_value_verbatim() {
        assert_eq!(
            resolve_yt_dlp_cookies(Some("chrome+gnomekeyring:Default".into()), None).unwrap(),
            kp::YtDlpCookies::FromBrowser("chrome+gnomekeyring:Default".into())
        );
    }

    // Spec §7: the child runs with current_dir(work_dir), so a --cookies
    // path must be canonicalized at resolve time. A `..` segment stands in
    // for a relative path (chdir is process-global — unsafe under parallel
    // tests) — canonicalize() resolves both the same way.
    #[test]
    fn resolve_yt_dlp_cookies_readable_file_is_canonicalized() {
        let dir = tempfile::tempdir().unwrap();
        let jar = dir.path().join("jar.txt");
        std::fs::write(&jar, "# Netscape HTTP Cookie File\n").unwrap();
        let dotted = dir.path().join("sub").join("..").join("jar.txt");
        std::fs::create_dir(dir.path().join("sub")).unwrap();
        match resolve_yt_dlp_cookies(None, Some(dotted)).unwrap() {
            kp::YtDlpCookies::File(p) => {
                assert!(p.is_absolute(), "{}", p.display());
                assert!(!p.components().any(|c| c == std::path::Component::ParentDir));
                assert_eq!(p, jar.canonicalize().unwrap());
            }
            other => panic!("expected File, got {other:?}"),
        }
    }

    #[test]
    fn resolve_yt_dlp_cookies_missing_file_errs_naming_path() {
        let err = resolve_yt_dlp_cookies(None, Some(PathBuf::from("/nonexistent/brana-jar.txt"))).unwrap_err();
        assert!(err.to_string().contains("/nonexistent/brana-jar.txt"), "{err}");
    }

    // Existence alone misses the cron-user-can't-read case (challenger §7 #5).
    #[cfg(unix)]
    #[test]
    fn resolve_yt_dlp_cookies_unreadable_file_errs() {
        use std::os::unix::fs::PermissionsExt as _;
        if unsafe { libc_geteuid() } == 0 {
            return; // root ignores mode bits
        }
        let dir = tempfile::tempdir().unwrap();
        let jar = dir.path().join("locked.txt");
        std::fs::write(&jar, "x").unwrap();
        std::fs::set_permissions(&jar, std::fs::Permissions::from_mode(0o000)).unwrap();
        let err = resolve_yt_dlp_cookies(None, Some(jar.clone())).unwrap_err();
        assert!(err.to_string().contains("locked.txt"), "{err}");
    }

    #[cfg(unix)]
    unsafe fn libc_geteuid() -> u32 {
        unsafe extern "C" {
            fn geteuid() -> u32;
        }
        unsafe { geteuid() }
    }

    // ── resolve_yt_dlp_cookies_with — persisted default jar (t-3038, spec §8) ──

    fn default_jar_in(dir: &std::path::Path, mode: u32) -> PathBuf {
        use std::os::unix::fs::OpenOptionsExt as _;
        let jar = dir.join("yt-cookies.txt");
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .open(&jar)
            .unwrap();
        std::io::Write::write_all(&mut f, b"# Netscape HTTP Cookie File\n").unwrap();
        jar
    }

    #[test]
    fn default_jar_absent_is_none() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("yt-cookies.txt");
        assert_eq!(
            resolve_yt_dlp_cookies_with(None, None, Some(&missing)).unwrap(),
            kp::YtDlpCookies::None
        );
    }

    #[test]
    fn default_jar_no_default_is_none() {
        assert_eq!(resolve_yt_dlp_cookies_with(None, None, None).unwrap(), kp::YtDlpCookies::None);
    }

    #[cfg(unix)]
    #[test]
    fn default_jar_0600_is_used() {
        let dir = tempfile::tempdir().unwrap();
        let jar = default_jar_in(dir.path(), 0o600);
        assert_eq!(
            resolve_yt_dlp_cookies_with(None, None, Some(&jar)).unwrap(),
            kp::YtDlpCookies::File(jar.canonicalize().unwrap())
        );
    }

    // Spec §8: an implicitly picked-up jar must be private — refuse, don't warn.
    #[cfg(unix)]
    #[test]
    fn default_jar_group_or_other_bits_errs_naming_chmod() {
        for mode in [0o644, 0o640, 0o604, 0o660] {
            let dir = tempfile::tempdir().unwrap();
            let jar = default_jar_in(dir.path(), mode);
            let err = resolve_yt_dlp_cookies_with(None, None, Some(&jar)).unwrap_err().to_string();
            assert!(err.contains("chmod 600"), "mode {mode:o}: {err}");
            assert!(err.contains(&jar.display().to_string()), "mode {mode:o}: {err}");
        }
    }

    #[cfg(unix)]
    #[test]
    fn default_jar_owner_only_stricter_modes_are_accepted() {
        // 0400 is stricter than 0600 and still owner-only: accepted.
        let dir = tempfile::tempdir().unwrap();
        let jar = default_jar_in(dir.path(), 0o400);
        assert!(matches!(
            resolve_yt_dlp_cookies_with(None, None, Some(&jar)).unwrap(),
            kp::YtDlpCookies::File(_)
        ));
    }

    #[cfg(unix)]
    #[test]
    fn explicit_flags_win_over_present_default_jar() {
        let dir = tempfile::tempdir().unwrap();
        let default = default_jar_in(dir.path(), 0o600);
        assert_eq!(
            resolve_yt_dlp_cookies_with(Some("firefox".into()), None, Some(&default)).unwrap(),
            kp::YtDlpCookies::FromBrowser("firefox".into())
        );
        let explicit = dir.path().join("explicit.txt");
        std::fs::write(&explicit, "x").unwrap();
        assert_eq!(
            resolve_yt_dlp_cookies_with(None, Some(explicit.clone()), Some(&default)).unwrap(),
            kp::YtDlpCookies::File(explicit.canonicalize().unwrap())
        );
    }

    // A loose default jar must not poison an explicit flag: the mode check
    // is only for the implicit path.
    #[cfg(unix)]
    #[test]
    fn loose_default_jar_does_not_affect_explicit_flags() {
        let dir = tempfile::tempdir().unwrap();
        let default = default_jar_in(dir.path(), 0o644);
        assert!(resolve_yt_dlp_cookies_with(Some("chrome".into()), None, Some(&default)).is_ok());
    }

    // 0000 passes the "no group/other bits" check but is unreadable: the
    // operator placed a file there, so fail loud rather than drain unauthenticated.
    #[cfg(unix)]
    #[test]
    fn default_jar_unreadable_errs() {
        if unsafe { libc_geteuid() } == 0 {
            return; // root ignores mode bits
        }
        let dir = tempfile::tempdir().unwrap();
        let jar = default_jar_in(dir.path(), 0o000);
        let err = resolve_yt_dlp_cookies_with(None, None, Some(&jar)).unwrap_err().to_string();
        assert!(err.contains("yt-cookies.txt"), "{err}");
    }

    #[test]
    fn default_yt_dlp_cookie_jar_is_under_config_brana() {
        let p = default_yt_dlp_cookie_jar_in(std::path::Path::new("/home/someone")).unwrap();
        assert_eq!(p, PathBuf::from("/home/someone/.config/brana/yt-cookies.txt"));
    }

    // Panel finding (t-3038 rung-2, C3): `home()` yields "" when $HOME is
    // unset, which would make the default jar a cwd-relative path — a
    // planted file in a stripped scheduler env would become the trusted
    // credential. Non-absolute homes produce no default at all.
    #[test]
    fn default_yt_dlp_cookie_jar_requires_absolute_home() {
        assert_eq!(default_yt_dlp_cookie_jar_in(std::path::Path::new("")), None);
        assert_eq!(default_yt_dlp_cookie_jar_in(std::path::Path::new("relative/home")), None);
    }

    #[test]
    fn resolve_channel_tab_videos() {
        assert_eq!(resolve_channel_tab("videos").unwrap(), kp::ChannelTab::Videos);
    }

    #[test]
    fn resolve_channel_tab_shorts() {
        assert_eq!(resolve_channel_tab("shorts").unwrap(), kp::ChannelTab::Shorts);
    }

    #[test]
    fn resolve_channel_tab_rejects_unknown_value() {
        let err = resolve_channel_tab("live").unwrap_err();
        assert!(
            err.to_string().contains("live"),
            "error should name the invalid value, got: {err}"
        );
    }

    #[test]
    fn channel_link_task_json_carries_link_tag_and_url_marker() {
        let json = build_channel_link_task_json(
            "https://www.youtube.com/@example",
            "https://www.youtube.com/watch?v=abc123",
        );
        assert_eq!(json["tags"], serde_json::json!(["link", "channel-backfill"]));
        assert_eq!(json["type"], serde_json::json!("task"));
        // extract_capture_url (drain-links' own parser, tested above) must
        // round-trip the context this produces — the two functions share
        // the "URL: {url}" contract without either importing the other.
        assert_eq!(
            extract_capture_url(json["context"].as_str().unwrap()),
            Some("https://www.youtube.com/watch?v=abc123".to_string())
        );
    }

    #[test]
    fn channel_link_task_json_subject_names_the_source_channel() {
        let json = build_channel_link_task_json(
            "https://www.youtube.com/@example",
            "https://www.youtube.com/watch?v=abc123",
        );
        let subject = json["subject"].as_str().unwrap();
        assert!(subject.contains("https://www.youtube.com/@example"));
    }
}

// --- vector-sync (t-2620) ---------------------------------------------------

/// `brana knowledge vector-sync` — sync the brana-owned vector store from
/// ruflo `memory_entries` DBs (local-vector-recall.md). Idempotent: newest
/// row per key wins across sources; unreadable sources are skipped loudly.
pub fn cmd_vector_sync(
    sources: Vec<PathBuf>,
    dest: Option<PathBuf>,
    json: bool,
) -> Result<()> {
    let default_src = home().join(".swarm").join("memory.db");
    let requested: Vec<PathBuf> = if sources.is_empty() { vec![default_src] } else { sources };

    let (readable, skipped): (Vec<PathBuf>, Vec<PathBuf>) = requested
        .into_iter()
        .partition(|p| brana_core::vector::probe_memory_entries(p));
    for s in &skipped {
        eprintln!("⚠ skipping unreadable source: {}", s.display());
    }
    if readable.is_empty() {
        bail!("no readable memory_entries source among the given paths");
    }

    let dest = dest.unwrap_or_else(brana_core::vector::knowledge_db_path);
    let stats = brana_core::vector::migrate_from_memory_entries(&readable, &dest)?;
    let total = brana_core::vector::KnowledgeStore::open(&dest)?.count()?;

    if json {
        println!(
            "{}",
            serde_json::json!({
                "dest": dest,
                "sources": readable,
                "sources_skipped": skipped,
                "scanned": stats.scanned,
                "migrated": stats.migrated,
                "skipped_no_embedding": stats.skipped_no_embedding,
                "deduped": stats.deduped,
                "store_total": total,
            })
        );
    } else {
        println!(
            "vector-sync: scanned {} rows from {} source(s) → migrated {} (deduped {}, no-embedding {}). Store now holds {} entries at {}",
            stats.scanned, readable.len(), stats.migrated, stats.deduped,
            stats.skipped_no_embedding, total, dest.display()
        );
    }
    Ok(())
}
