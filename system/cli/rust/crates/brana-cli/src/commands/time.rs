//! `brana time start|close` — active-effort time tracking (ADR-083, t-2919/t-2920).
//!
//! I/O half of the split with `brana_core::time_tracking` (pure logic): locking,
//! atomic writes, git-common-dir/git-dir resolution, H2 git-env scrub, transcript
//! file reads. Mirrors `commands/receipt.rs`'s pure/IO split.
//!
//! Two different write shapes for two different files (spec Decision #2):
//! - `brana/time/<task_id>.jsonl` (the durable data store, `--git-common-dir`-scoped):
//!   blind atomic append, `decisions.rs`-shaped — one pre-serialized `write_all` per
//!   line, no lock. Concurrent appends to the same or different files never corrupt
//!   each other (POSIX `O_APPEND` atomicity for writes under `PIPE_BUF`).
//! - `brana-time-open-bracket.json` (the per-worktree open-bracket lock,
//!   `--git-dir`-scoped): genuinely read-modify-write ("is a bracket already open? if
//!   not, write") — uses `brana_core::util::lock_sidecar` + `write_json_atomic`,
//!   `queue.rs`/`remind.rs`-shaped.

use anyhow::{anyhow, bail, Context, Result};
use brana_core::time_tracking::{close_orphaned_bracket, BracketLine, Coverage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::Command;

fn git_in(dir: &Path, args: &[&str]) -> Result<String> {
    let mut cmd = Command::new("git");
    brana_core::util::scrub_git_env(&mut cmd);
    let out = cmd.current_dir(dir).args(args).output()?;
    if !out.status.success() {
        bail!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Run `git rev-parse {arg}` (H2-scrubbed) against the process cwd and resolve the
/// result against that same cwd if git printed a relative path — matches
/// `receipt.rs::store_dir`'s scrubbed inline pattern, deliberately not
/// `brana_core::util::find_tasks_file`/`git_common_root` (those resolve via an
/// unscrubbed `git rev-parse` — see this feature's spec, Decision #4).
fn resolve_git_path(arg: &str) -> Result<PathBuf> {
    let cwd = std::env::current_dir()?;
    let raw = git_in(&cwd, &["rev-parse", arg])?;
    let p = PathBuf::from(&raw);
    Ok(if p.is_absolute() { p } else { cwd.join(p) })
}

/// Resolve `$(git rev-parse --git-common-dir)/brana/time/<task_id>.jsonl` (H2-scrubbed).
fn data_store_path(task_id: &str) -> Result<PathBuf> {
    let common = resolve_git_path("--git-common-dir")?;
    Ok(common.join("brana/time").join(format!("{task_id}.jsonl")))
}

/// Resolve `$(git rev-parse --git-dir)/brana-time-open-bracket.json` (H2-scrubbed,
/// per-worktree unlike `--git-common-dir`).
fn open_bracket_lock_path() -> Result<PathBuf> {
    let git_dir = resolve_git_path("--git-dir")?;
    Ok(git_dir.join("brana-time-open-bracket.json"))
}

/// Per-worktree open-bracket marker. Presence of the file = a bracket is open;
/// absence = none open. `transcript_path` is resolved once at START (best-effort —
/// see Boundaries: START must not block on transcript resolvability) and read back
/// verbatim at CLOSE, never re-resolved ("snapshot, don't re-resolve").
#[derive(Debug, Clone, Serialize, Deserialize)]
struct OpenBracketLock {
    task_id: String,
    opened_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    transcript_path: Option<String>,
}

/// Mirrors `brana_core::session::encode_path` (private to that module, and this is a
/// new, independent transcript-resolution path per the spec's "session-transcript
/// parsing is new code" decision — not worth exposing a cross-module dependency for
/// one line of logic): `/` and `_` both become `-`.
fn encode_project_path(root: &Path) -> String {
    root.to_string_lossy().replace('/', "-").replace('_', "-")
}

/// Legacy CC encoding (`/` only, underscores preserved) — `commands/handoff.rs`'s
/// `encode_path_legacy` proved this fallback load-bearing for projects whose CC
/// project directory predates the current encoding scheme; a project root containing
/// `_` resolves to a different directory under each scheme, and this feature has no
/// other way to discover which one a given install actually has on disk.
fn encode_project_path_legacy(root: &Path) -> String {
    root.to_string_lossy().replace('/', "-")
}

/// Best-effort: the newest-mtime `.jsonl` in this project's CC transcript directory.
/// Tries the current encoding first, falling back to the legacy one if it yields no
/// directory or no `.jsonl` files — same dual-try order as `handoff.rs::resolve_handoff_path`.
/// A heuristic, not a guarantee (per spec Assumptions) — the only session actively
/// writing its transcript at this instant is presumed to be the current one. Returns
/// `None` on total resolution failure (no project root, no directory under either
/// encoding, no `.jsonl` files) — START does not require a resolvable transcript
/// (Boundaries table).
fn resolve_newest_transcript() -> Option<PathBuf> {
    let root = brana_core::util::find_project_root()?;
    let base = brana_core::util::home().join(".claude/projects");
    newest_jsonl_in(&base.join(encode_project_path(&root)))
        .or_else(|| newest_jsonl_in(&base.join(encode_project_path_legacy(&root))))
}

fn newest_jsonl_in(dir: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(dir).ok()?;
    let mut best: Option<(PathBuf, std::time::SystemTime)> = None;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
            continue;
        }
        let Ok(meta) = path.metadata() else { continue };
        let Ok(mtime) = meta.modified() else { continue };
        if best.as_ref().map(|(_, t)| mtime > *t).unwrap_or(true) {
            best = Some((path, mtime));
        }
    }
    best.map(|(p, _)| p)
}

/// Read a transcript JSONL file's per-line `timestamp` fields, in file order.
/// Malformed individual lines are skipped (best-effort, matches the lenient schema
/// convention elsewhere in this feature) — only the file itself failing to read
/// propagates an error (the caller checks existence first, so this is normally an
/// I/O-permission edge case, not the common "no transcript" path).
fn read_transcript_timestamps(path: &Path) -> Result<Vec<DateTime<Utc>>> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("reading transcript {}", path.display()))?;
    let mut timestamps = Vec::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(value) = serde_json::from_str::<serde_json::Value>(line) else {
            continue;
        };
        let Some(ts_str) = value.get("timestamp").and_then(|v| v.as_str()) else {
            continue;
        };
        let Ok(ts) = DateTime::parse_from_rfc3339(ts_str) else {
            continue;
        };
        timestamps.push(ts.with_timezone(&Utc));
    }
    Ok(timestamps)
}

/// Append one JSONL line via a single pre-serialized `write_all` (spec's
/// append-atomicity mandate — never `writeln!`/`Display`, which is a multi-syscall
/// write and can interleave with a concurrent writer's own multi-syscall write).
fn append_line<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)
            .with_context(|| format!("creating {}", dir.display()))?;
    }
    let mut line = serde_json::to_string(value)?;
    line.push('\n');
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .with_context(|| format!("opening {}", path.display()))?;
    f.write_all(line.as_bytes())
        .with_context(|| format!("appending to {}", path.display()))?;
    Ok(())
}

/// Open a bracket for `task_id`. Refuses (non-zero exit, no write) if a bracket is
/// already open for this worktree (per the `--git-dir`-scoped lock file) — the
/// serialized-one-open-bracket-per-worktree invariant (ADR-083, redesigned during
/// t-2921 SPECIFY away from an unverifiable `$BRANA_SESSION_ID` dependency).
pub fn cmd_start(task_id: &str) -> Result<()> {
    let lock_path = open_bracket_lock_path()?;
    // The whole check-then-write is the critical section a concurrent second `start`
    // must serialize behind — TOCTOU-safe via the OS flock, not a naive existence
    // check (see time_smoke.rs::a4).
    let _guard = brana_core::util::lock_sidecar(&lock_path).map_err(|e| anyhow!(e))?;

    if lock_path.exists() {
        let open_for = std::fs::read_to_string(&lock_path)
            .ok()
            .and_then(|s| serde_json::from_str::<OpenBracketLock>(&s).ok())
            .map(|l| l.task_id)
            .unwrap_or_else(|| "<unreadable lock>".to_string());
        bail!(
            "a time bracket is already open in this worktree for {open_for} — \
             close it before starting {task_id}"
        );
    }

    let opened_at = Utc::now();
    let transcript_path = resolve_newest_transcript();
    let session_label = std::env::var("BRANA_SESSION_ID").ok();

    let lock = OpenBracketLock {
        task_id: task_id.to_string(),
        opened_at,
        transcript_path: transcript_path
            .as_ref()
            .map(|p| p.to_string_lossy().into_owned()),
    };
    brana_core::util::write_json_atomic(&lock_path, &lock).map_err(|e| anyhow!(e))?;

    let start_line = BracketLine::Start {
        version: 1,
        task_id: task_id.to_string(),
        ts: opened_at,
        session_label,
    };
    append_line(&data_store_path(task_id)?, &start_line)?;

    Ok(())
}

/// Close the open bracket for `task_id`: read the transcript from the matching Start
/// timestamp forward, compute turn-delta-summed active time (15-min cap), append a
/// Close line with the computed duration + coverage annotation, remove the worktree's
/// open-bracket lock.
pub fn cmd_close(task_id: &str, partial: bool) -> Result<()> {
    let lock_path = open_bracket_lock_path()?;
    let _guard = brana_core::util::lock_sidecar(&lock_path).map_err(|e| anyhow!(e))?;

    if !lock_path.exists() {
        bail!("no time bracket is open in this worktree — nothing to close for {task_id}");
    }
    let raw = std::fs::read_to_string(&lock_path)
        .with_context(|| format!("reading {}", lock_path.display()))?;
    let lock: OpenBracketLock = serde_json::from_str(&raw)
        .with_context(|| format!("parsing {}", lock_path.display()))?;
    if lock.task_id != task_id {
        bail!(
            "the open bracket in this worktree belongs to {} — close that first \
             (attempted to close {task_id})",
            lock.task_id
        );
    }

    // Fail closed: no resolvable transcript at CLOSE time means no evidence to
    // compute a duration from (Boundaries table — this is CLOSE-only; START never
    // required a resolvable transcript).
    let transcript_path = lock
        .transcript_path
        .as_ref()
        .ok_or_else(|| anyhow!("no transcript was resolved when this bracket opened — cannot close {task_id}"))?;
    let transcript_path = PathBuf::from(transcript_path);
    if !transcript_path.exists() {
        bail!(
            "recorded transcript {} no longer exists — failing closed for {task_id}",
            transcript_path.display()
        );
    }

    // "Snapshot, don't re-resolve": read exactly the path START recorded, never the
    // current newest-mtime file (time_smoke.rs::d4).
    let timestamps = read_transcript_timestamps(&transcript_path)?;

    let start_marker = BracketLine::Start {
        version: 1,
        task_id: task_id.to_string(),
        ts: lock.opened_at,
        session_label: None,
    };
    let summary = close_orphaned_bracket(&start_marker, &timestamps);

    let close_line = BracketLine::Close {
        version: 1,
        task_id: task_id.to_string(),
        ts: Utc::now(),
        duration_capped_secs: summary.capped_total_secs,
        turn_count: summary.turn_count,
        gaps_capped: summary.gaps_capped,
        coverage: if partial { Coverage::Partial } else { Coverage::Full },
    };
    append_line(&data_store_path(task_id)?, &close_line)?;

    std::fs::remove_file(&lock_path)
        .with_context(|| format!("removing {}", lock_path.display()))?;

    Ok(())
}
