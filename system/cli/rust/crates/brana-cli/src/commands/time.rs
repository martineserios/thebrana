//! `brana time start|close` — active-effort time tracking (ADR-083, t-2919/t-2920).
//!
//! I/O half of the split with `brana_core::time_tracking` (pure logic): locking,
//! atomic writes, git-common-dir/git-dir resolution, H2 git-env scrub, transcript
//! file reads. Mirrors `commands/receipt.rs`'s pure/IO split.
//!
//! t-2921 (this file): stub only — no real implementation. t-2922 fills this in.

use anyhow::Result;

/// Resolve `$(git rev-parse --git-common-dir)/brana/time/<task_id>.jsonl` (H2-scrubbed).
/// Stub only — t-2922 implements real resolution, matching `commands/receipt.rs::store_dir`'s
/// scrubbed-inline pattern (never `util::find_tasks_file`/`git_common_root`, which is
/// unscrubbed).
#[allow(dead_code)]
fn data_store_path(_task_id: &str) -> Result<std::path::PathBuf> {
    todo!("t-2922: scrubbed git-common-dir resolution for brana/time/<task_id>.jsonl")
}

/// Resolve `$(git rev-parse --git-dir)/brana-time-open-bracket.json` (H2-scrubbed,
/// per-worktree unlike `--git-common-dir`).
#[allow(dead_code)]
fn open_bracket_lock_path() -> Result<std::path::PathBuf> {
    todo!("t-2922: scrubbed git-dir resolution for the per-worktree open-bracket lock")
}

/// Open a bracket for `task_id`. Refuses (non-zero exit, no write) if a bracket is
/// already open for this worktree (per the `--git-dir`-scoped lock file) — the
/// serialized-one-open-bracket-per-worktree invariant (ADR-083, redesigned during
/// t-2921 SPECIFY away from an unverifiable `$BRANA_SESSION_ID` dependency).
pub fn cmd_start(task_id: &str) -> Result<()> {
    todo!("t-2922: implement brana time start {task_id} — see time-tracking-metric-1.md")
}

/// Close the open bracket for `task_id`: read the transcript from the matching Start
/// timestamp forward, compute turn-delta-summed active time (15-min cap), append a
/// Close line with the computed duration + coverage annotation, remove the worktree's
/// open-bracket lock.
pub fn cmd_close(task_id: &str) -> Result<()> {
    todo!("t-2922: implement brana time close {task_id} — see time-tracking-metric-1.md")
}
