//! Session lane pins (ADR-069 D2, t-2521).
//!
//! A lane pin records which session owns a worktree: written once at session start (or,
//! for the autonomous sandbox — which fires no `SessionStart` at all, per ADR-069's
//! Constraints — by `brana session lane init`, called by the runner as it builds the
//! jail). `BRANA_SESSION_ID` is set but never exported (verified directly), so a pin
//! cannot be found by id from a child process; `cwd` IS inherited, so every pin is
//! discoverable by `worktree_path` first, matching `resolve_resume_lane`'s ranking.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::session::{resolve_memory_dir, LaneCandidate, ResumeMatchRule};

// ── Path helpers ────────────────────────────────────────────────────────

/// Directory holding every lane pin for a project's shared session store.
pub fn lane_dir(project_root: &Path) -> PathBuf {
    resolve_memory_dir(project_root).join("lanes")
}

/// A single lane pin's file path, keyed by session id.
pub fn lane_pin_path(project_root: &Path, session_id: &str) -> PathBuf {
    lane_dir(project_root).join(format!("{session_id}.json"))
}

// ── Schema ──────────────────────────────────────────────────────────────

/// A session's pinned lane identity (ADR-069 D2). `dirty_at_start` is recorded but
/// deliberately non-key — it feeds D3.3's shared-checkout guard (t-2524), not lane
/// resolution here.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LanePin {
    pub session_id: String,
    pub worktree_path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub head_at_start: Option<String>,
    #[serde(default)]
    pub dirty_at_start: Vec<String>,
    pub created_at: String,
}

impl LanePin {
    /// Project onto the ranking-only view `resolve_resume_lane` operates on. The label
    /// is the session id — the caller looks the winning pin back up by it.
    pub fn as_candidate(&self) -> LaneCandidate {
        LaneCandidate {
            label: self.session_id.clone(),
            worktree_path: Some(self.worktree_path.clone()),
            branch: self.branch.clone(),
            task_id: self.task_id.clone(),
        }
    }
}

// ── Git helpers ─────────────────────────────────────────────────────────

/// Current HEAD sha in `cwd`, if in a git repo. Best-effort: `None` on any git error,
/// never a hard failure — a pin is still useful without it.
pub fn git_head_sha() -> Option<String> {
    let mut cmd = std::process::Command::new("git");
    crate::util::scrub_git_env(&mut cmd);
    cmd.args(["rev-parse", "HEAD"]).output().ok().and_then(|o| {
        if o.status.success() {
            let sha = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if sha.is_empty() { None } else { Some(sha) }
        } else {
            None
        }
    })
}

/// Paths with uncommitted changes in `cwd` at pin time (`git status --porcelain`'s path
/// column), for D3.3's `dirty_at_start` guard (t-2524, not this task). Best-effort:
/// empty on any git error, same failure posture as [`git_head_sha`].
pub fn git_dirty_paths() -> Vec<String> {
    let mut cmd = std::process::Command::new("git");
    crate::util::scrub_git_env(&mut cmd);
    let Ok(out) = cmd.args(["status", "--porcelain"]).output() else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&out.stdout)
        .lines()
        // Porcelain format: "XY path" or "XY orig -> path" for renames — the path (or
        // rename target) starts at column 3.
        .filter_map(|line| {
            let rest = line.get(3..)?;
            let path = rest.rsplit(" -> ").next().unwrap_or(rest);
            if path.is_empty() { None } else { Some(path.to_string()) }
        })
        .collect()
}

// ── I/O ─────────────────────────────────────────────────────────────────

/// Write a lane pin atomically (same-dir temp + rename). Single-writer: only the
/// owning session ever writes its own session_id's file, so no cross-session lock is
/// needed — re-running `lane init` for the same session id is an idempotent overwrite,
/// not a race.
pub fn write_lane_pin(project_root: &Path, pin: &LanePin) -> Result<()> {
    let dir = lane_dir(project_root);
    fs::create_dir_all(&dir).context("creating lane pin directory")?;
    let path = lane_pin_path(project_root, &pin.session_id);
    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(pin).context("serializing lane pin")?;
    fs::write(&tmp, &json).context("writing lane pin temp file")?;
    fs::rename(&tmp, &path).context("renaming lane pin into place")?;
    Ok(())
}

/// Read one lane pin by session id. A missing or corrupt pin is treated identically —
/// `None` — never partially parsed (ADR-069 D2 edge case).
pub fn read_lane_pin(project_root: &Path, session_id: &str) -> Option<LanePin> {
    let path = lane_pin_path(project_root, session_id);
    fs::read_to_string(&path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
}

/// List every lane pin in the store. Corrupt files are skipped, same rule as
/// [`read_lane_pin`]. Sorted by session_id for deterministic iteration order.
pub fn list_lane_pins(project_root: &Path) -> Vec<LanePin> {
    let dir = lane_dir(project_root);
    let Ok(entries) = fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut pins: Vec<LanePin> = entries
        .flatten()
        .filter_map(|entry| {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                return None;
            }
            fs::read_to_string(&path)
                .ok()
                .and_then(|data| serde_json::from_str(&data).ok())
        })
        .collect();
    pins.sort_by(|a, b| a.session_id.cmp(&b.session_id));
    pins
}

/// Resolve at most one lane pin to resume into, by the same worktree_path > branch >
/// task_id ranking `resolve_resume_lane` implements. Thin wrapper: projects every
/// stored pin to a [`LaneCandidate`], runs the ranking, then looks the winning pin back
/// up by its session_id label.
pub fn resolve_current_lane(
    project_root: &Path,
    worktree_path: Option<&str>,
    branch: Option<&str>,
    task_id: Option<&str>,
) -> Option<(LanePin, ResumeMatchRule)> {
    let pins = list_lane_pins(project_root);
    let candidates: Vec<LaneCandidate> = pins.iter().map(LanePin::as_candidate).collect();
    let (matched, rule) =
        crate::session::resolve_resume_lane(&candidates, worktree_path, branch, task_id)?;
    let pin = pins.into_iter().find(|p| p.session_id == matched.label)?;
    Some((pin, rule))
}

// ── Tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn make_pin(session_id: &str, worktree_path: &str) -> LanePin {
        LanePin {
            session_id: session_id.to_string(),
            worktree_path: worktree_path.to_string(),
            branch: Some("main".to_string()),
            task_id: None,
            head_at_start: Some("deadbeef".to_string()),
            dirty_at_start: Vec::new(),
            created_at: "2026-09-04T10:00:00Z".to_string(),
        }
    }

    #[test]
    fn write_then_read_round_trips() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        let pin = make_pin("sess-1", "/repo");
        write_lane_pin(root, &pin).unwrap();

        let loaded = read_lane_pin(root, "sess-1").expect("pin must be readable after write");
        assert_eq!(loaded, pin);
    }

    #[test]
    fn read_missing_pin_is_none() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        assert!(read_lane_pin(root, "nonexistent").is_none());
    }

    #[test]
    fn read_corrupt_pin_is_none_not_a_panic() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(lane_dir(root)).unwrap();
        fs::write(lane_pin_path(root, "corrupt-sess"), b"not json").unwrap();
        assert!(
            read_lane_pin(root, "corrupt-sess").is_none(),
            "a corrupt pin must read as missing, never partially parsed"
        );
    }

    #[test]
    fn list_skips_corrupt_and_non_json_files() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        write_lane_pin(root, &make_pin("good", "/repo")).unwrap();
        fs::create_dir_all(lane_dir(root)).unwrap();
        fs::write(lane_dir(root).join("corrupt.json"), b"not json").unwrap();
        fs::write(lane_dir(root).join("README.md"), b"not a pin").unwrap();

        let pins = list_lane_pins(root);
        assert_eq!(pins.len(), 1);
        assert_eq!(pins[0].session_id, "good");
    }

    #[test]
    fn resolve_current_lane_finds_unique_worktree_match() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        write_lane_pin(root, &make_pin("sess-a", "/repo-a")).unwrap();
        write_lane_pin(root, &make_pin("sess-b", "/repo-b")).unwrap();

        let (pin, rule) = resolve_current_lane(root, Some("/repo-a"), Some("main"), None)
            .expect("unique worktree_path match must resolve");
        assert_eq!(pin.session_id, "sess-a");
        assert_eq!(rule, ResumeMatchRule::WorktreePath);
    }

    #[test]
    fn resolve_current_lane_no_pins_is_a_miss() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        assert!(resolve_current_lane(root, Some("/repo"), Some("main"), None).is_none());
    }
}
