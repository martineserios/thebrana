//! Shared helpers for path discovery and config loading.

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

/// Find the authoritative tasks.json, shared across git worktrees.
///
/// Resolution order:
/// 1. Git common-dir root (shared across all worktrees) — auto-inits if missing
/// 2. Git show-toplevel (worktree root) — auto-inits if missing
/// 3. CWD fallback — CLAUDE_PROJECT_DIR (CC-injected since v2.1.139) takes priority over process CWD
pub fn find_tasks_file() -> Option<PathBuf> {
    find_tasks_file_with_hint(
        std::env::var("CLAUDE_PROJECT_DIR").ok().map(PathBuf::from),
        git_common_root(),
        git_toplevel(),
        std::env::current_dir().ok(),
    )
}

/// Testable variant. hint overrides cwd as the non-git fallback (CLAUDE_PROJECT_DIR pattern).
fn find_tasks_file_with_hint(
    hint: Option<PathBuf>,
    common_root: Option<PathBuf>,
    toplevel: Option<PathBuf>,
    cwd: Option<PathBuf>,
) -> Option<PathBuf> {
    let effective_cwd = hint.filter(|p| p.is_dir()).or(cwd);
    find_tasks_file_from(common_root, toplevel, effective_cwd)
}

fn git_common_root() -> Option<PathBuf> {
    Command::new("git")
        .args(["rev-parse", "--git-common-dir"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                let common_git =
                    PathBuf::from(String::from_utf8_lossy(&o.stdout).trim().to_string());
                common_git.parent().map(|p| p.to_path_buf())
            } else {
                None
            }
        })
}

fn git_toplevel() -> Option<PathBuf> {
    Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()
        .and_then(|o| {
            if o.status.success() {
                Some(PathBuf::from(
                    String::from_utf8_lossy(&o.stdout).trim().to_string(),
                ))
            } else {
                None
            }
        })
}

/// Inner function — accepts roots directly for testability.
/// All callers except tests go through `find_tasks_file()` which resolves roots via git.
fn find_tasks_file_from(
    common_root: Option<PathBuf>,
    toplevel: Option<PathBuf>,
    cwd: Option<PathBuf>,
) -> Option<PathBuf> {
    // 1. Git common-dir (main repo root, shared across worktrees)
    if let Some(root) = &common_root {
        let f = root.join(".claude/tasks.json");
        if f.exists() {
            return Some(f);
        }
        if let Some(dir) = f.parent() {
            if std::fs::create_dir_all(dir).is_ok() && std::fs::write(&f, b"{\"tasks\":[]}").is_ok()
            {
                return Some(f);
            }
        }
    }

    // 2. Worktree root (fallback for repos where common-dir == show-toplevel)
    if let Some(root) = &toplevel {
        let f = root.join(".claude/tasks.json");
        if f.exists() {
            return Some(f);
        }
        if let Some(dir) = f.parent() {
            if std::fs::create_dir_all(dir).is_ok() && std::fs::write(&f, b"{\"tasks\":[]}").is_ok()
            {
                return Some(f);
            }
        }
    }

    // 3. CWD fallback for non-git projects (mandawa, prediktive-prep, etc.)
    // Only auto-inits if .claude/ already exists — avoids spraying files into arbitrary dirs.
    if let Some(cwd) = &cwd {
        let f = cwd.join(".claude/tasks.json");
        if f.exists() {
            return Some(f);
        }
        let dot_claude = cwd.join(".claude");
        if dot_claude.exists() {
            if std::fs::write(&f, b"{\"tasks\":[]}").is_ok() {
                return Some(f);
            }
        }
    }

    None
}

/// Find the project root directory.
///
/// Resolution order:
/// 1. CLAUDE_PROJECT_DIR env var (CC-injected since v2.1.139) — authoritative
/// 2. Git show-toplevel (inside a git repo)
/// 3. CWD fallback for non-git projects
pub fn find_project_root() -> Option<PathBuf> {
    find_project_root_with_hint(
        std::env::var("CLAUDE_PROJECT_DIR").ok().map(PathBuf::from),
        git_toplevel(),
        std::env::current_dir().ok(),
    )
}

/// Testable variant. hint wins before git_root (CLAUDE_PROJECT_DIR pattern).
fn find_project_root_with_hint(
    hint: Option<PathBuf>,
    git_root: Option<PathBuf>,
    cwd: Option<PathBuf>,
) -> Option<PathBuf> {
    hint.filter(|p| p.is_dir())
        .or_else(|| find_project_root_from(git_root, cwd))
}

/// Testable variant. git_root wins; cwd is the non-git fallback.
pub fn find_project_root_from(
    git_root: Option<PathBuf>,
    cwd: Option<PathBuf>,
) -> Option<PathBuf> {
    git_root.or(cwd)
}

/// Return the user's home directory.
pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_default())
}

/// Expand a leading `~/` to the user's home directory. Paths without the
/// prefix pass through unchanged.
pub fn expand_home(p: &str) -> PathBuf {
    if let Some(rest) = p.strip_prefix("~/") {
        return home().join(rest);
    }
    PathBuf::from(p)
}

/// Compare two dotted numeric version strings (e.g. `"1.0.10"`).
/// Returns `true` when `installed` is greater than or equal to `floor`.
///
/// Each dot-separated component is parsed as its leading run of ASCII digits,
/// so a trailing suffix (`"1.0.10-rc1"`) compares on its numeric core and a
/// missing trailing component is treated as `0` (`"1.2"` == `"1.2.0"`). This
/// avoids the lexical trap where `"1.0.9" > "1.0.10"` as plain strings.
///
/// Conservative on garbage: if `installed` does not start with a digit it is
/// treated as below any floor (returns `false`) — an unrecognizable version
/// must fail the floor loudly rather than silently pass.
pub fn version_at_least(installed: &str, floor: &str) -> bool {
    fn parse(v: &str) -> Vec<u64> {
        v.split('.')
            .map(|seg| {
                seg.chars()
                    .take_while(|c| c.is_ascii_digit())
                    .collect::<String>()
                    .parse::<u64>()
                    .unwrap_or(0)
            })
            .collect()
    }
    if !installed.trim_start().starts_with(|c: char| c.is_ascii_digit()) {
        return false;
    }
    let a = parse(installed.trim());
    let b = parse(floor.trim());
    for i in 0..a.len().max(b.len()) {
        let ai = a.get(i).copied().unwrap_or(0);
        let bi = b.get(i).copied().unwrap_or(0);
        if ai != bi {
            return ai > bi;
        }
    }
    true
}

/// Load scheduler config from `~/.claude/scheduler/scheduler.json`.
pub fn load_scheduler() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/scheduler.json");
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|c| serde_json::from_str(&c).ok())
        .unwrap_or_default()
}

/// Load scheduler status from `~/.claude/scheduler/last-status.json`.
pub fn load_status() -> HashMap<String, serde_json::Value> {
    let path = home().join(".claude/scheduler/last-status.json");
    let content = std::fs::read_to_string(&path).unwrap_or_default();
    let content = content.trim();
    if content.is_empty() {
        return HashMap::new();
    }
    serde_json::from_str(content).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::{find_project_root_from, find_project_root_with_hint, find_tasks_file_from, find_tasks_file_with_hint};
    use std::path::PathBuf;
    use std::fs;
    use tempfile::TempDir;

    fn tmp() -> TempDir {
        tempfile::tempdir().expect("tempdir")
    }

    // ── git-root (common_root) path ──────────────────────────────────────────

    #[test]
    fn existing_tasks_json_returned_immediately() {
        let dir = tmp();
        let claude = dir.path().join(".claude");
        fs::create_dir_all(&claude).unwrap();
        let f = claude.join("tasks.json");
        fs::write(&f, b"{\"tasks\":[{\"id\":\"t-001\"}]}").unwrap();

        let result = find_tasks_file_from(Some(dir.path().to_path_buf()), None, None);
        assert_eq!(result, Some(f));
    }

    #[test]
    fn git_root_auto_inits_when_tasks_missing() {
        let dir = tmp();
        // .claude/ does not exist yet
        let result = find_tasks_file_from(Some(dir.path().to_path_buf()), None, None);
        let expected = dir.path().join(".claude/tasks.json");
        assert_eq!(result, Some(expected.clone()));
        assert!(expected.exists(), "tasks.json should be created");
    }

    #[test]
    fn auto_init_creates_valid_empty_json() {
        let dir = tmp();
        let result = find_tasks_file_from(Some(dir.path().to_path_buf()), None, None);
        let path = result.expect("should return a path");
        let contents = fs::read_to_string(&path).expect("readable");
        let parsed: serde_json::Value =
            serde_json::from_str(&contents).expect("valid JSON");
        assert_eq!(parsed["tasks"], serde_json::json!([]));
    }

    #[test]
    fn toplevel_fallback_used_when_common_root_absent() {
        let dir = tmp();
        let result = find_tasks_file_from(None, Some(dir.path().to_path_buf()), None);
        let expected = dir.path().join(".claude/tasks.json");
        assert_eq!(result, Some(expected.clone()));
        assert!(expected.exists());
    }

    #[test]
    fn common_root_takes_precedence_over_toplevel() {
        let common = tmp();
        let top = tmp();
        // Put tasks.json in both — common_root should win
        let common_f = common.path().join(".claude/tasks.json");
        let top_f = top.path().join(".claude/tasks.json");
        fs::create_dir_all(common_f.parent().unwrap()).unwrap();
        fs::create_dir_all(top_f.parent().unwrap()).unwrap();
        fs::write(&common_f, b"{\"tasks\":[{\"id\":\"common\"}]}").unwrap();
        fs::write(&top_f, b"{\"tasks\":[{\"id\":\"top\"}]}").unwrap();

        let result = find_tasks_file_from(
            Some(common.path().to_path_buf()),
            Some(top.path().to_path_buf()),
            None,
        );
        assert_eq!(result, Some(common_f));
    }

    // ── CWD fallback (non-git projects) ─────────────────────────────────────

    #[test]
    fn cwd_fallback_returns_existing_tasks_json() {
        let dir = tmp();
        let claude = dir.path().join(".claude");
        fs::create_dir_all(&claude).unwrap();
        let f = claude.join("tasks.json");
        fs::write(&f, b"{\"tasks\":[]}").unwrap();

        let result = find_tasks_file_from(None, None, Some(dir.path().to_path_buf()));
        assert_eq!(result, Some(f));
    }

    #[test]
    fn cwd_auto_inits_when_dot_claude_exists_but_no_tasks_json() {
        let dir = tmp();
        // .claude/ exists but tasks.json does not
        fs::create_dir_all(dir.path().join(".claude")).unwrap();

        let result = find_tasks_file_from(None, None, Some(dir.path().to_path_buf()));
        let expected = dir.path().join(".claude/tasks.json");
        assert_eq!(result, Some(expected.clone()));
        assert!(expected.exists(), "tasks.json should be auto-created");
    }

    #[test]
    fn cwd_does_not_auto_init_when_dot_claude_absent() {
        let dir = tmp();
        // No .claude/ dir — should NOT create anything
        let result = find_tasks_file_from(None, None, Some(dir.path().to_path_buf()));
        assert_eq!(result, None);
        assert!(
            !dir.path().join(".claude").exists(),
            ".claude/ must not be created"
        );
    }

    #[test]
    fn returns_none_when_all_roots_absent() {
        let result = find_tasks_file_from(None, None, None);
        assert_eq!(result, None);
    }

    // ── find_project_root_from ───────────────────────────────────────────────

    #[test]
    fn project_root_returns_git_root_when_available() {
        let dir = tmp();
        let result = find_project_root_from(Some(dir.path().to_path_buf()), None);
        assert_eq!(result, Some(dir.path().to_path_buf()));
    }

    #[test]
    fn project_root_falls_back_to_cwd_for_non_git_dirs() {
        let dir = tmp();
        let result = find_project_root_from(None, Some(dir.path().to_path_buf()));
        assert_eq!(result, Some(dir.path().to_path_buf()));
    }

    #[test]
    fn project_root_git_takes_precedence_over_cwd() {
        let git_dir = tmp();
        let cwd_dir = tmp();
        let result = find_project_root_from(
            Some(git_dir.path().to_path_buf()),
            Some(cwd_dir.path().to_path_buf()),
        );
        assert_eq!(result, Some(git_dir.path().to_path_buf()));
    }

    #[test]
    fn project_root_returns_none_when_both_absent() {
        let result = find_project_root_from(None, None);
        assert_eq!(result, None);
    }

    // ── CLAUDE_PROJECT_DIR hint (t-1418) ─────────────────────────────────────

    #[test]
    fn project_root_hint_takes_priority_over_git_root() {
        let hint_dir = tmp();
        let git_dir = tmp();
        let result = find_project_root_with_hint(
            Some(hint_dir.path().to_path_buf()),
            Some(git_dir.path().to_path_buf()),
            None,
        );
        assert_eq!(result, Some(hint_dir.path().to_path_buf()));
    }

    #[test]
    fn project_root_hint_nonexistent_dir_falls_back_to_git() {
        let git_dir = tmp();
        let result = find_project_root_with_hint(
            Some(PathBuf::from("/nonexistent-brana-test-dir")),
            Some(git_dir.path().to_path_buf()),
            None,
        );
        assert_eq!(result, Some(git_dir.path().to_path_buf()));
    }

    #[test]
    fn tasks_file_hint_used_as_cwd_fallback() {
        let dir = tmp();
        fs::create_dir_all(dir.path().join(".claude")).unwrap();
        let f = dir.path().join(".claude/tasks.json");
        fs::write(&f, b"{\"tasks\":[]}").unwrap();

        let result = find_tasks_file_with_hint(Some(dir.path().to_path_buf()), None, None, None);
        assert_eq!(result, Some(f));
    }

    #[test]
    fn tasks_file_git_root_still_wins_over_hint() {
        let git_dir = tmp();
        let hint_dir = tmp();
        let f = git_dir.path().join(".claude/tasks.json");
        fs::create_dir_all(f.parent().unwrap()).unwrap();
        fs::write(&f, b"{\"tasks\":[]}").unwrap();

        let result = find_tasks_file_with_hint(
            Some(hint_dir.path().to_path_buf()),
            Some(git_dir.path().to_path_buf()),
            None,
            None,
        );
        assert_eq!(result, Some(f));
    }

    // ── version_at_least (agy version floor) ────────────────────────────────

    #[test]
    fn version_floor_accepts_equal() {
        assert!(super::version_at_least("1.0.10", "1.0.10"));
    }

    #[test]
    fn version_floor_accepts_higher_patch() {
        assert!(super::version_at_least("1.0.11", "1.0.10"));
    }

    #[test]
    fn version_floor_rejects_lower_patch_lexical_trap() {
        // "1.0.9" > "1.0.10" as plain strings — must NOT pass the floor.
        assert!(!super::version_at_least("1.0.9", "1.0.10"));
    }

    #[test]
    fn version_floor_accepts_higher_minor_and_major() {
        assert!(super::version_at_least("1.1.0", "1.0.10"));
        assert!(super::version_at_least("2.0.0", "1.0.10"));
    }

    #[test]
    fn version_floor_rejects_lower_major() {
        assert!(!super::version_at_least("0.9.99", "1.0.10"));
    }

    #[test]
    fn version_floor_treats_missing_component_as_zero() {
        assert!(super::version_at_least("1.0", "1.0.0"));
        assert!(super::version_at_least("1.0.10", "1.0"));
        assert!(!super::version_at_least("1.0", "1.0.1"));
    }

    #[test]
    fn version_floor_tolerates_prerelease_suffix() {
        assert!(super::version_at_least("1.0.10-rc1", "1.0.10"));
    }

    #[test]
    fn version_floor_rejects_unparseable_installed() {
        assert!(!super::version_at_least("unknown", "1.0.10"));
        assert!(!super::version_at_least("", "1.0.10"));
    }

    #[test]
    fn tasks_file_hint_nonexistent_falls_back_to_cwd() {
        let cwd_dir = tmp();
        fs::create_dir_all(cwd_dir.path().join(".claude")).unwrap();
        let f = cwd_dir.path().join(".claude/tasks.json");
        fs::write(&f, b"{\"tasks\":[]}").unwrap();

        let result = find_tasks_file_with_hint(
            Some(PathBuf::from("/nonexistent-brana-test-dir")),
            None,
            None,
            Some(cwd_dir.path().to_path_buf()),
        );
        assert_eq!(result, Some(f));
    }
}

// ── Shared JSON-store primitives (ADR-051/052 pattern) ─────────────────

/// Hex-encode 8 random bytes from the OS → `{prefix}-xxxxxxxxxxxxxxxx`.
/// Falls back to a time+pid mix if /dev/urandom is unavailable.
pub fn random_store_id(prefix: &str) -> String {
    let mut buf = [0u8; 8];
    if std::fs::File::open("/dev/urandom")
        .and_then(|mut f| std::io::Read::read_exact(&mut f, &mut buf))
        .is_err()
    {
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64
            ^ ((std::process::id() as u64) << 32);
        buf = t.to_le_bytes();
    }
    let hex: String = buf.iter().map(|b| format!("{b:02x}")).collect();
    format!("{prefix}-{hex}")
}

/// Take an exclusive advisory lock on `<store>.lock` (sidecar — the store
/// inode itself is replaced by atomic rename, so locking it would not
/// serialize the next writer). Held until the returned File drops.
pub fn lock_sidecar(store_path: &std::path::Path) -> Result<std::fs::File, String> {
    let lock_path = store_path.with_extension("json.lock");
    if let Some(dir) = lock_path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("create store dir failed: {e}"))?;
    }
    let f = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&lock_path)
        .map_err(|e| format!("open lock file failed: {e}"))?;
    f.lock().map_err(|e| format!("lock failed: {e}"))?;
    Ok(f)
}

/// Serialize `value` and write it to `path` atomically: temp file created
/// in the store's own directory (same filesystem → rename is atomic),
/// PID-scoped name, rename over the target.
pub fn write_json_atomic<T: serde::Serialize>(
    path: &std::path::Path,
    value: &T,
) -> Result<(), String> {
    let content =
        serde_json::to_string_pretty(value).map_err(|e| format!("serialize failed: {e}"))?;
    let dir = path.parent().ok_or("store path has no parent directory")?;
    std::fs::create_dir_all(dir).map_err(|e| format!("create store dir failed: {e}"))?;
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("store");
    let tmp = dir.join(format!("{}.{}.tmp", file_name, std::process::id()));
    std::fs::write(&tmp, content).map_err(|e| format!("write tmp failed: {e}"))?;
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("atomic rename failed: {e}")
    })
}
