//! `brana close-queue` — CLI surface for the close queue (t-1972, ADR-052).
//! Thin marshalling layer: all mutation logic lives in `brana_core::queue`.

use anyhow::{Result, anyhow};
use brana_core::queue::{self, NewEntry};
use std::path::PathBuf;

/// Store lives per-user, cross-project: `~/.claude/close-queue.json`.
fn store_path() -> PathBuf {
    brana_core::util::home().join(".claude").join("close-queue.json")
}

#[allow(clippy::too_many_arguments)]
pub fn cmd_append(
    project: String,
    branch: String,
    git_root: String,
    git_range: String,
    snapshot_path: String,
    commit_count: u64,
    snapshot_truncated: bool,
    omitted_files: Vec<String>,
    session_notes_path: Option<String>,
    propagate: bool,
) -> Result<()> {
    let r = queue::append(
        &store_path(),
        NewEntry {
            project,
            branch,
            git_root,
            git_range,
            snapshot_path,
            commit_count,
            snapshot_truncated,
            omitted_files: if omitted_files.is_empty() { None } else { Some(omitted_files) },
            session_notes_path,
            propagate,
        },
    )
    .map_err(|e| anyhow!(e))?;
    if r.deduplicated {
        eprintln!("close-queue: range already queued — returning existing entry");
    }
    println!("{}", serde_json::to_string_pretty(&r.entry)?);
    Ok(())
}

pub fn cmd_list(unprocessed: bool) -> Result<()> {
    let entries = queue::list(&store_path(), unprocessed).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&entries)?);
    Ok(())
}

pub fn cmd_mark_processed(id: &str, summary_path: &str) -> Result<()> {
    let e = queue::mark_processed(&store_path(), id, summary_path).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&e)?);
    Ok(())
}

pub fn cmd_mark_propagated(project: &str, branch: &str, git_range: &str) -> Result<()> {
    let e = queue::mark_propagated(&store_path(), project, branch, git_range)
        .map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&e)?);
    Ok(())
}

pub fn cmd_mark_failed(id: &str, error: &str) -> Result<()> {
    let e = queue::mark_failed(&store_path(), id, error).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&e)?);
    Ok(())
}

pub fn cmd_prune() -> Result<()> {
    let removed = queue::prune(&store_path()).map_err(|e| anyhow!(e))?;
    println!("{removed}");
    Ok(())
}

/// Reset retry_count and failed state on a single entry (`id = Some(...)`) or
/// all failed-but-unprocessed entries (`id = None`). Recovery path for
/// transient tool regressions such as an agy version mismatch.
pub fn cmd_reset_retries(id: Option<&str>) -> Result<()> {
    let modified = queue::reset_retries(&store_path(), id).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&modified)?);
    Ok(())
}
