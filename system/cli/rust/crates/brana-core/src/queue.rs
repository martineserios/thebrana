//! Close queue — single Rust-owned mutation path (ADR-052).
//!
//! Store: `~/.claude/close-queue.json` (caller passes the path).
//! Same hardening as the reminder store (ADR-051): sidecar advisory lock,
//! parse-before-write validation, same-dir tmp + atomic rename, lenient
//! serde. The nightly extraction cron interacts with this store ONLY
//! through these functions (via `brana queue` subcommands) — never raw JSON.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const STORE_VERSION: u64 = 1;
/// Processed/failed entries older than this are pruned.
const PRUNE_DAYS: i64 = 30;

/// One queued close snapshot. Evolution rules (ADR-052 §1): no
/// deny_unknown_fields, every post-v1 field Option<T> or #[serde(default)].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    /// Idempotency key: `{project}:{branch}:{git_range}` (ADR-052 §3).
    pub dedup_key: String,
    pub timestamp: DateTime<Utc>,
    pub branch: String,
    pub project: String,
    pub git_root: String,
    pub git_range: String,
    #[serde(default)]
    pub commit_count: u64,
    /// Always absolute — `append` expands `~` at write time (ADR-052 §4).
    pub snapshot_path: String,
    #[serde(default)]
    pub snapshot_truncated: bool,
    /// Files dropped by the hunk-boundary cap (ADR-052 §4). None when not truncated.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub omitted_files: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_notes_path: Option<String>,
    #[serde(default)]
    pub processed: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub processed_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary_path: Option<String>,
    #[serde(default)]
    pub failed: bool,
    #[serde(default)]
    pub retry_count: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// ADR-056: entry awaits the nightly L3 propagation audit. Set at append
    /// (fail-safe — every queueing close), cleared by `mark_propagated` when
    /// the in-session L2 audit completed successfully.
    #[serde(default)]
    pub propagate: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Store {
    pub version: u64,
    pub entries: Vec<Entry>,
}

/// Input for `append`.
#[derive(Debug, Default)]
pub struct NewEntry {
    pub project: String,
    pub branch: String,
    pub git_root: String,
    pub git_range: String,
    pub snapshot_path: String,
    pub commit_count: u64,
    pub snapshot_truncated: bool,
    /// Files dropped by the hunk-boundary cap. None when not truncated.
    pub omitted_files: Option<Vec<String>>,
    pub session_notes_path: Option<String>,
    pub propagate: bool,
}

/// Outcome of `append` — distinguishes a fresh entry from a dedup no-op.
#[derive(Debug)]
pub struct AppendResult {
    pub entry: Entry,
    /// true when an unprocessed entry with the same dedup_key already
    /// existed and was returned instead of creating a duplicate.
    pub deduplicated: bool,
}

// ── implementation ──────────────────────────────────────────────────────

fn now() -> DateTime<Utc> {
    Utc::now()
}

fn read_store(path: &Path) -> Result<Store, String> {
    if !path.exists() {
        return Ok(Store {
            version: STORE_VERSION,
            entries: Vec::new(),
        });
    }
    let raw = std::fs::read_to_string(path).map_err(|e| format!("read store failed: {e}"))?;
    if raw.trim().is_empty() {
        return Ok(Store {
            version: STORE_VERSION,
            entries: Vec::new(),
        });
    }
    let val: serde_json::Value =
        serde_json::from_str(&raw).map_err(|e| format!("store is not valid JSON: {e}"))?;
    let version = val.get("version").and_then(|v| v.as_u64()).unwrap_or(1);
    if version > STORE_VERSION {
        return Err(format!(
            "store version {version} is newer than supported {STORE_VERSION} — upgrade brana"
        ));
    }
    serde_json::from_value(val).map_err(|e| format!("store schema mismatch: {e}"))
}

/// Expand a leading `~/` to the user's home directory (ADR-052 §4:
/// snapshot paths are stored absolute; Rust `Path::new` never sees `~`).
fn expand_home(p: &str) -> String {
    if let Some(rest) = p.strip_prefix("~/") {
        return crate::util::home().join(rest).to_string_lossy().into_owned();
    }
    p.to_string()
}

/// Append a close entry. A matching **unprocessed, non-failed** entry with
/// the same dedup_key is a no-op returning the existing entry — the same
/// work range is already queued. Processed/failed entries never absorb.
pub fn append(path: &Path, new: NewEntry) -> Result<AppendResult, String> {
    for (field, val) in [
        ("project", &new.project),
        ("branch", &new.branch),
        ("git_root", &new.git_root),
        ("git_range", &new.git_range),
        ("snapshot_path", &new.snapshot_path),
    ] {
        if val.trim().is_empty() {
            return Err(format!("{field} must not be empty"));
        }
    }
    let _lock = crate::util::lock_sidecar(path)?;
    let mut store = read_store(path)?;
    let dedup_key = format!("{}:{}:{}", new.project, new.branch, new.git_range);

    if let Some(existing) = store
        .entries
        .iter()
        .find(|e| e.dedup_key == dedup_key && !e.processed && !e.failed)
    {
        return Ok(AppendResult {
            entry: existing.clone(),
            deduplicated: true,
        });
    }

    let entry = Entry {
        id: crate::util::random_store_id("q"),
        dedup_key,
        timestamp: now(),
        branch: new.branch,
        project: new.project,
        git_root: expand_home(&new.git_root),
        git_range: new.git_range,
        commit_count: new.commit_count,
        snapshot_path: expand_home(&new.snapshot_path),
        snapshot_truncated: new.snapshot_truncated,
        omitted_files: new.omitted_files,
        session_notes_path: new.session_notes_path.as_deref().map(expand_home),
        processed: false,
        processed_at: None,
        summary_path: None,
        failed: false,
        retry_count: 0,
        error: None,
        propagate: new.propagate,
    };
    store.entries.push(entry.clone());
    crate::util::write_json_atomic(path, &store)?;
    Ok(AppendResult {
        entry,
        deduplicated: false,
    })
}

/// List entries. `unprocessed_only` filters to `processed == false`.
pub fn list(path: &Path, unprocessed_only: bool) -> Result<Vec<Entry>, String> {
    let _lock = crate::util::lock_sidecar(path)?;
    let store = read_store(path)?;
    let mut entries = store.entries;
    if unprocessed_only {
        entries.retain(|e| !e.processed);
    }
    entries.sort_by_key(|e| e.timestamp); // chronological — cron contract (Q3)
    Ok(entries)
}

/// Mark an entry successfully processed. Clears `failed` (a retry succeeded).
pub fn mark_processed(path: &Path, id: &str, summary_path: &str) -> Result<Entry, String> {
    let _lock = crate::util::lock_sidecar(path)?;
    let mut store = read_store(path)?;
    let e = store
        .entries
        .iter_mut()
        .find(|e| e.id == id)
        .ok_or_else(|| format!("no queue entry with id {id}"))?;
    e.processed = true;
    e.processed_at = Some(now());
    e.summary_path = Some(expand_home(summary_path));
    e.failed = false;
    e.error = None;
    let out = e.clone();
    crate::util::write_json_atomic(path, &store)?;
    Ok(out)
}

/// Mark an entry failed: sets `failed`, increments `retry_count`, records
/// the error. Never touches `processed` (ADR-052 §6: never partial writes,
/// never skip-and-mark-processed).
pub fn mark_failed(path: &Path, id: &str, error: &str) -> Result<Entry, String> {
    let _lock = crate::util::lock_sidecar(path)?;
    let mut store = read_store(path)?;
    let e = store
        .entries
        .iter_mut()
        .find(|e| e.id == id)
        .ok_or_else(|| format!("no queue entry with id {id}"))?;
    if e.processed {
        return Err(format!("entry {id} is already processed"));
    }
    e.failed = true;
    e.retry_count += 1;
    e.error = Some(error.to_string());
    let out = e.clone();
    crate::util::write_json_atomic(path, &store)?;
    Ok(out)
}

/// Clear the `propagate` flag on the unprocessed entry matching the dedup
/// key (`{project}:{branch}:{git_range}`). Called by close Step 8b after a
/// successful in-session L2 audit (ADR-056 §4) so the nightly L3 pass skips
/// this entry. Errors when no unprocessed entry matches — processed entries
/// never match (extraction already ran; clearing is meaningless).
pub fn mark_propagated(
    path: &Path,
    project: &str,
    branch: &str,
    git_range: &str,
) -> Result<Entry, String> {
    let _lock = crate::util::lock_sidecar(path)?;
    let mut store = read_store(path)?;
    let dedup_key = format!("{project}:{branch}:{git_range}");
    let e = store
        .entries
        .iter_mut()
        .find(|e| e.dedup_key == dedup_key && !e.processed)
        .ok_or_else(|| format!("no unprocessed queue entry with dedup_key {dedup_key}"))?;
    e.propagate = false;
    let out = e.clone();
    crate::util::write_json_atomic(path, &store)?;
    Ok(out)
}

/// Prune processed-or-failed entries older than 30 days. Returns the number
/// removed. Unprocessed healthy entries are never pruned (the stale-queue
/// monitor surfaces those instead).
pub fn prune(path: &Path) -> Result<usize, String> {
    let _lock = crate::util::lock_sidecar(path)?;
    let mut store = read_store(path)?;
    let cutoff = now() - Duration::days(PRUNE_DAYS);
    let before = store.entries.len();
    store
        .entries
        .retain(|e| !((e.processed || e.failed) && e.timestamp < cutoff));
    let removed = before - store.entries.len();
    if removed > 0 {
        crate::util::write_json_atomic(path, &store)?;
    }
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn store_path(dir: &tempfile::TempDir) -> PathBuf {
        dir.path().join("close-queue.json")
    }

    fn new_entry(branch: &str, range: &str) -> NewEntry {
        NewEntry {
            project: "thebrana".into(),
            branch: branch.into(),
            git_root: "/repo".into(),
            git_range: range.into(),
            snapshot_path: "/snaps/a.diff".into(),
            commit_count: 2,
            ..Default::default()
        }
    }

    #[test]
    fn append_creates_store_with_entry() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r = append(&path, new_entry("feat/x", "a..b")).unwrap();
        assert!(!r.deduplicated);
        assert!(r.entry.id.starts_with("q-"));
        assert_eq!(r.entry.dedup_key, "thebrana:feat/x:a..b");
        assert!(!r.entry.processed);
        let raw: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(raw["version"], 1);
        assert_eq!(raw["entries"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn append_rejects_empty_required_fields() {
        let dir = tempfile::TempDir::new().unwrap();
        let mut e = new_entry("feat/x", "a..b");
        e.git_range = "  ".into();
        assert!(append(&store_path(&dir), e).is_err());
    }

    #[test]
    fn duplicate_unprocessed_dedup_key_is_noop() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r1 = append(&path, new_entry("feat/x", "a..b")).unwrap();
        let r2 = append(&path, new_entry("feat/x", "a..b")).unwrap();
        assert!(r2.deduplicated);
        assert_eq!(r1.entry.id, r2.entry.id);
        assert_eq!(list(&path, false).unwrap().len(), 1);
    }

    #[test]
    fn processed_and_failed_entries_never_absorb_appends() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r1 = append(&path, new_entry("feat/x", "a..b")).unwrap();
        mark_processed(&path, &r1.entry.id, "/sum.md").unwrap();
        let r2 = append(&path, new_entry("feat/x", "a..b")).unwrap();
        assert!(!r2.deduplicated);
        assert_ne!(r1.entry.id, r2.entry.id);
        mark_failed(&path, &r2.entry.id, "boom").unwrap();
        let r3 = append(&path, new_entry("feat/x", "a..b")).unwrap();
        assert!(!r3.deduplicated);
        assert_eq!(list(&path, false).unwrap().len(), 3);
    }

    #[test]
    fn tilde_paths_are_expanded_absolute() {
        let dir = tempfile::TempDir::new().unwrap();
        let mut e = new_entry("feat/x", "a..b");
        e.snapshot_path = "~/.claude/sessions/snap.diff".into();
        e.git_root = "~/enter_thebrana/thebrana".into();
        e.session_notes_path = Some("~/.claude/notes.md".into());
        let r = append(&store_path(&dir), e).unwrap();
        assert!(!r.entry.snapshot_path.starts_with('~'));
        assert!(r.entry.snapshot_path.starts_with('/'));
        assert!(!r.entry.git_root.starts_with('~'));
        assert!(r.entry.git_root.starts_with('/'));
        assert!(!r.entry.session_notes_path.unwrap().starts_with('~'));
    }

    #[test]
    fn mark_processed_sets_fields_and_clears_failed() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r = append(&path, new_entry("feat/x", "a..b")).unwrap();
        mark_failed(&path, &r.entry.id, "transient").unwrap();
        let e = mark_processed(&path, &r.entry.id, "/sum.md").unwrap();
        assert!(e.processed);
        assert!(!e.failed);
        assert!(e.error.is_none());
        assert_eq!(e.retry_count, 1); // history preserved
        assert_eq!(e.summary_path.as_deref(), Some("/sum.md"));
        assert!(e.processed_at.is_some());
    }

    #[test]
    fn mark_failed_increments_retry_count() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r = append(&path, new_entry("feat/x", "a..b")).unwrap();
        mark_failed(&path, &r.entry.id, "e1").unwrap();
        let e = mark_failed(&path, &r.entry.id, "e2").unwrap();
        assert_eq!(e.retry_count, 2);
        assert_eq!(e.error.as_deref(), Some("e2"));
        assert!(!e.processed);
    }

    #[test]
    fn mark_failed_on_processed_entry_is_rejected() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r = append(&path, new_entry("feat/x", "a..b")).unwrap();
        mark_processed(&path, &r.entry.id, "/sum.md").unwrap();
        assert!(mark_failed(&path, &r.entry.id, "late").is_err());
    }

    #[test]
    fn unknown_ids_error() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        append(&path, new_entry("feat/x", "a..b")).unwrap();
        assert!(mark_processed(&path, "q-nope", "/s.md").is_err());
        assert!(mark_failed(&path, "q-nope", "e").is_err());
    }

    #[test]
    fn list_unprocessed_filters_and_sorts_chronologically() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r1 = append(&path, new_entry("feat/a", "a..b")).unwrap();
        append(&path, new_entry("feat/b", "c..d")).unwrap();
        mark_processed(&path, &r1.entry.id, "/s.md").unwrap();
        let un = list(&path, true).unwrap();
        assert_eq!(un.len(), 1);
        assert_eq!(un[0].branch, "feat/b");
        // chronological order on full list
        let all = list(&path, false).unwrap();
        assert!(all[0].timestamp <= all[1].timestamp);
    }

    #[test]
    fn prune_removes_only_old_terminal_entries() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r1 = append(&path, new_entry("feat/old-done", "a..b")).unwrap();
        mark_processed(&path, &r1.entry.id, "/s.md").unwrap();
        let r2 = append(&path, new_entry("feat/old-pending", "c..d")).unwrap();
        append(&path, new_entry("feat/new", "e..f")).unwrap();
        // Age the first two entries 40 days via direct file edit.
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        let old = (Utc::now() - Duration::days(40)).to_rfc3339();
        for e in val["entries"].as_array_mut().unwrap() {
            if e["id"] == r1.entry.id.as_str() || e["id"] == r2.entry.id.as_str() {
                e["timestamp"] = serde_json::json!(old);
            }
        }
        std::fs::write(&path, serde_json::to_string(&val).unwrap()).unwrap();
        let removed = prune(&path).unwrap();
        assert_eq!(removed, 1); // only old+processed; old+unprocessed survives
        let left = list(&path, false).unwrap();
        assert_eq!(left.len(), 2);
        assert!(left.iter().any(|e| e.branch == "feat/old-pending"));
    }

    #[test]
    fn parse_before_write_never_clobbers_corrupt_store() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, "{not json").unwrap();
        assert!(append(&path, new_entry("feat/x", "a..b")).is_err());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "{not json");
    }

    #[test]
    fn newer_store_version_is_rejected() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, r#"{"version": 99, "entries": []}"#).unwrap();
        assert!(append(&path, new_entry("feat/x", "a..b")).is_err());
    }

    #[test]
    fn unknown_fields_are_tolerated() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        append(&path, new_entry("feat/x", "a..b")).unwrap();
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        val["future_field"] = serde_json::json!("hi");
        val["entries"][0]["future_entry_field"] = serde_json::json!(42);
        std::fs::write(&path, serde_json::to_string(&val).unwrap()).unwrap();
        assert_eq!(list(&path, false).unwrap().len(), 1);
    }

    #[test]
    fn append_with_propagate_sets_flag_and_default_is_false() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let mut e = new_entry("feat/x", "a..b");
        e.propagate = true;
        let r = append(&path, e).unwrap();
        assert!(r.entry.propagate);
        let r2 = append(&path, new_entry("feat/y", "c..d")).unwrap();
        assert!(!r2.entry.propagate); // NewEntry::default → false
    }

    #[test]
    fn legacy_entries_without_propagate_field_default_false() {
        // ADR-056 backward compat: stores written before the field existed.
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        append(&path, new_entry("feat/x", "a..b")).unwrap();
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        val["entries"][0].as_object_mut().unwrap().remove("propagate");
        std::fs::write(&path, serde_json::to_string(&val).unwrap()).unwrap();
        let entries = list(&path, false).unwrap();
        assert!(!entries[0].propagate);
    }

    #[test]
    fn mark_propagated_clears_flag_on_unprocessed_match() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let mut e = new_entry("feat/x", "a..b");
        e.propagate = true;
        append(&path, e).unwrap();
        let out = mark_propagated(&path, "thebrana", "feat/x", "a..b").unwrap();
        assert!(!out.propagate);
        assert!(!list(&path, false).unwrap()[0].propagate); // persisted
    }

    #[test]
    fn mark_propagated_errors_when_no_unprocessed_match() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        // no entry at all
        assert!(mark_propagated(&path, "thebrana", "feat/x", "a..b").is_err());
        // processed entries never match — L2 ran after extraction is nonsensical
        let mut e = new_entry("feat/x", "a..b");
        e.propagate = true;
        let r = append(&path, e).unwrap();
        mark_processed(&path, &r.entry.id, "/s.md").unwrap();
        assert!(mark_propagated(&path, "thebrana", "feat/x", "a..b").is_err());
    }

    /// ADR-052 race test: parallel closes all survive (distinct ranges), and
    /// same-range parallel closes dedup to exactly one entry — no losses,
    /// no duplicates, under concurrent append + mark from multiple threads.
    #[test]
    fn concurrent_appends_all_survive() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let n_threads = 8;
        let per_thread = 5;
        let handles: Vec<_> = (0..n_threads)
            .map(|t| {
                let p = path.clone();
                std::thread::spawn(move || {
                    for i in 0..per_thread {
                        append(&p, new_entry(&format!("feat/w{t}"), &format!("r{t}-{i}")))
                            .unwrap();
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        assert_eq!(list(&path, false).unwrap().len(), n_threads * per_thread);
    }

    #[test]
    fn omitted_files_roundtrip() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let e = NewEntry {
            project: "thebrana".into(),
            branch: "feat/x".into(),
            git_root: "/repo".into(),
            git_range: "a..b".into(),
            snapshot_path: "/snaps/a.diff".into(),
            commit_count: 1,
            snapshot_truncated: true,
            omitted_files: Some(vec!["foo.rs".into(), "bar.rs".into()]),
            ..Default::default()
        };
        let r = append(&path, e).unwrap();
        assert_eq!(r.entry.omitted_files, Some(vec!["foo.rs".to_string(), "bar.rs".to_string()]));
        let listed = list(&path, false).unwrap();
        assert_eq!(listed[0].omitted_files, Some(vec!["foo.rs".to_string(), "bar.rs".to_string()]));
    }

    #[test]
    fn back_compat_parse_without_omitted_files() {
        let json = r#"{"version":1,"entries":[{"id":"q-001","dedup_key":"p:b:r","timestamp":"2026-01-01T00:00:00Z","branch":"feat/x","project":"p","git_root":"/r","git_range":"a..b","snapshot_path":"/s","snapshot_truncated":true,"processed":false,"failed":false,"retry_count":0,"propagate":false}]}"#;
        let store: Store = serde_json::from_str(json).unwrap();
        assert_eq!(store.entries[0].omitted_files, None);
    }

    #[test]
    fn concurrent_same_range_appends_dedup_to_one() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let p = path.clone();
                std::thread::spawn(move || append(&p, new_entry("feat/x", "a..b")).unwrap())
            })
            .collect();
        let results: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        assert_eq!(list(&path, false).unwrap().len(), 1);
        assert_eq!(results.iter().filter(|r| !r.deduplicated).count(), 1);
    }
}
