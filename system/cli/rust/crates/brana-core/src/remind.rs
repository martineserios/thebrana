//! Reminder store — single Rust-owned mutation path (ADR-051).
//!
//! Store: `~/.claude/reminders.json` (caller passes the path).
//! Every mutation takes an exclusive advisory lock on a sidecar
//! `<store>.lock` file (the store itself is replaced by atomic rename,
//! so locking the store inode would not serialize writers).
//! Writes are parse-before-write validated and use same-dir tmp + rename.

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::path::Path;

pub const STORE_VERSION: u64 = 1;
/// Pending reminders older than this auto-expire on `list`.
const EXPIRE_DAYS: i64 = 30;
/// Occurrences at or above this bump medium → high.
const ESCALATE_AT: u64 = 3;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Priority {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Pending,
    Resolved,
    Snoozed,
    Expired,
}

/// One reminder entry. Evolution rules (ADR-051): no deny_unknown_fields,
/// every post-v1 field must be Option<T> or #[serde(default)].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Reminder {
    pub id: String,
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    pub priority: Priority,
    pub status: Status,
    pub created: DateTime<Utc>,
    pub last_seen: DateTime<Utc>,
    pub occurrences: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dedup_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snoozed_until: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved_at: Option<DateTime<Utc>>,
    /// When to push (ADR-054 §3). None → pull-only reminder, never dispatched.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due: Option<DateTime<Utc>>,
    /// Explicit routing. None/empty → priority defaults; ["all"] → broadcast.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channels: Option<Vec<String>>,
    /// Dispatch idempotency marker: non-null → never dispatched again (ADR-054 §3).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dispatched_at: Option<DateTime<Utc>>,
    /// Backlog task linked to this reminder (t-2116). None → unlinked.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Store {
    pub version: u64,
    pub reminders: Vec<Reminder>,
}

/// Input for `write_reminder`.
#[derive(Debug, Default)]
pub struct NewReminder {
    pub text: String,
    pub action: Option<String>,
    pub priority: Option<Priority>,
    pub dedup_key: Option<String>,
    pub project: Option<String>,
    pub tags: Vec<String>,
    pub due: Option<DateTime<Utc>>,
    pub channels: Option<Vec<String>>,
    pub task_id: Option<String>,
}

// ── implementation ──────────────────────────────────────────────────────

fn now() -> DateTime<Utc> {
    Utc::now()
}

/// Hex-encode 8 random bytes from the OS → `r-xxxxxxxxxxxxxxxx`.
fn random_id() -> String {
    crate::util::random_store_id("r")
}

/// Take an exclusive advisory lock on `<store>.lock`. Held until drop.
fn lock_store(path: &Path) -> Result<std::fs::File, String> {
    crate::util::lock_sidecar(path)
}

/// Read + parse the store. Missing file → empty v1 store.
/// Unparseable file → Err (parse-before-write: never clobber it).
fn read_store(path: &Path) -> Result<Store, String> {
    if !path.exists() {
        return Ok(Store {
            version: STORE_VERSION,
            reminders: Vec::new(),
        });
    }
    let raw = std::fs::read_to_string(path).map_err(|e| format!("read store failed: {e}"))?;
    if raw.trim().is_empty() {
        return Ok(Store {
            version: STORE_VERSION,
            reminders: Vec::new(),
        });
    }
    // Version check via Value before strict parse (ADR-051 §4).
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

/// Same-dir tmp + atomic rename (the store dir, never /tmp).
fn write_store(path: &Path, store: &Store) -> Result<(), String> {
    crate::util::write_json_atomic(path, store)
}

/// Append a reminder (or dedup-increment an existing pending/snoozed one).
/// Returns the written/updated reminder.
pub fn write_reminder(path: &Path, new: NewReminder) -> Result<Reminder, String> {
    if new.text.trim().is_empty() {
        return Err("reminder text must not be empty".into());
    }
    let _lock = lock_store(path)?;
    let mut store = read_store(path)?;
    let ts = now();

    // Dedup: match on dedup_key among non-terminal entries.
    if let Some(key) = new.dedup_key.as_deref()
        && let Some(existing) = store.reminders.iter_mut().find(|r| {
            r.dedup_key.as_deref() == Some(key)
                && matches!(r.status, Status::Pending | Status::Snoozed)
        })
    {
        existing.occurrences += 1;
        existing.last_seen = ts;
        if existing.occurrences >= ESCALATE_AT && existing.priority == Priority::Medium {
            existing.priority = Priority::High;
        }
        let out = existing.clone();
        write_store(path, &store)?;
        return Ok(out);
    }

    let reminder = Reminder {
        id: random_id(),
        text: new.text,
        action: new.action,
        priority: new.priority.unwrap_or(Priority::Medium),
        status: Status::Pending,
        created: ts,
        last_seen: ts,
        occurrences: 1,
        dedup_key: new.dedup_key,
        project: new.project,
        tags: new.tags,
        snoozed_until: None,
        resolved_at: None,
        due: new.due,
        channels: new.channels,
        dispatched_at: None,
        task_id: new.task_id,
    };
    store.reminders.push(reminder.clone());
    write_store(path, &store)?;
    Ok(reminder)
}

/// The ONLY path that computes AND persists state transitions (ADR-051 §3):
/// snooze expiry (snoozed → pending) and 30-day pending → expired.
/// Returns the post-transition reminder list.
pub fn list(path: &Path) -> Result<Vec<Reminder>, String> {
    let _lock = lock_store(path)?;
    let mut store = read_store(path)?;
    let ts = now();
    let mut changed = false;
    for r in &mut store.reminders {
        match r.status {
            Status::Snoozed => {
                if r.snoozed_until.is_none_or(|u| u <= ts) {
                    r.status = Status::Pending;
                    r.snoozed_until = None;
                    changed = true;
                }
            }
            Status::Pending => {
                if ts - r.created > Duration::days(EXPIRE_DAYS) {
                    r.status = Status::Expired;
                    changed = true;
                }
            }
            _ => {}
        }
    }
    if changed {
        write_store(path, &store)?;
    }
    Ok(store.reminders)
}

/// List dispatch-eligible reminders (ADR-054 §4): pending, past-due,
/// never dispatched. Delegates to [`list`] so snooze-expiry and 30-day
/// expiry transitions settle under the write lock BEFORE filtering —
/// a snooze-expired entry with a past `due` must appear here.
pub fn due(path: &Path) -> Result<Vec<Reminder>, String> {
    let all = list(path)?;
    let ts = now();
    Ok(all
        .into_iter()
        .filter(|r| {
            r.status == Status::Pending
                && r.dispatched_at.is_none()
                && r.due.is_some_and(|d| d <= ts)
        })
        .collect())
}

/// Outcome of one `dispatch` run (ADR-054 §5).
#[derive(Debug, Clone, serde::Serialize)]
pub struct DispatchReport {
    /// Entries that were due-eligible at select time.
    pub selected: usize,
    /// Entry ids marked `dispatched_at` this run (≥1 channel succeeded).
    pub dispatched: Vec<String>,
    /// Entry ids where every resolved channel failed — left unmarked for retry.
    pub failed: Vec<String>,
}

fn priority_key(p: &Priority) -> &'static str {
    match p {
        Priority::Low => "low",
        Priority::Medium => "medium",
        Priority::High => "high",
    }
}

fn dispatch_message(r: &Reminder) -> String {
    match r.action.as_deref() {
        Some(a) if !a.is_empty() => format!("⏰ {}\n→ {}", r.text, a),
        _ => format!("⏰ {}", r.text),
    }
}

/// Two-phase dispatch (ADR-054 §5) — the lock is never held across I/O:
/// 1. **Select** (under lock, via [`due`]): due-eligible, undispatched entries.
/// 2. **Send** (no lock): resolve channels per entry, fire `sender` per channel.
/// 3. **Commit** (under lock): re-read via `read_store` — NOT `list`/`due`,
///    those write transitions — and set `dispatched_at` only for entries with
///    ≥1 successful send whose marker is *still* null (a concurrent run's
///    mark is left untouched).
///
/// Ordering is send-then-mark: a crash between phases yields a duplicate
/// ping next run, never a silent loss. `sender` is injected for testability;
/// the CLI passes [`crate::notify::send`].
pub fn dispatch(
    path: &Path,
    reg: &crate::notify::ChannelRegistry,
    sender: &dyn Fn(&crate::notify::Channel, &str) -> crate::notify::DispatchResult,
) -> Result<DispatchReport, String> {
    use crate::notify::DispatchResult;

    // Phase 1 — select (due() locks, settles transitions, releases).
    let selected = due(path)?;
    let mut report = DispatchReport {
        selected: selected.len(),
        dispatched: Vec::new(),
        failed: Vec::new(),
    };
    if selected.is_empty() {
        return Ok(report);
    }

    // Phase 2 — send, no lock held.
    let mut succeeded: Vec<String> = Vec::new();
    for r in &selected {
        let channels =
            crate::notify::resolve(reg, r.channels.as_deref(), priority_key(&r.priority));
        if channels.is_empty() {
            // e.g. low priority: never pushes, stays pull-only — not a failure.
            continue;
        }
        let msg = dispatch_message(r);
        let mut any_sent = false;
        for ch in &channels {
            match sender(ch, &msg) {
                DispatchResult::Sent => any_sent = true,
                DispatchResult::Failed { reason } => {
                    eprintln!("warning: dispatch {} via {:?} failed: {reason}", r.id, ch.name);
                }
            }
        }
        if any_sent {
            succeeded.push(r.id.clone());
        } else {
            report.failed.push(r.id.clone());
        }
    }
    if succeeded.is_empty() {
        return Ok(report);
    }

    // Phase 3 — commit under lock. Send-then-mark: only now record success.
    let _lock = lock_store(path)?;
    let mut store = read_store(path)?;
    let ts = now();
    for r in &mut store.reminders {
        if succeeded.contains(&r.id) && r.dispatched_at.is_none() {
            r.dispatched_at = Some(ts);
            report.dispatched.push(r.id.clone());
        }
    }
    write_store(path, &store)?;
    Ok(report)
}

/// Mark a reminder resolved.
pub fn resolve(path: &Path, id: &str) -> Result<Reminder, String> {
    let _lock = lock_store(path)?;
    let mut store = read_store(path)?;
    let r = store
        .reminders
        .iter_mut()
        .find(|r| r.id == id)
        .ok_or_else(|| format!("no reminder with id {id}"))?;
    r.status = Status::Resolved;
    r.resolved_at = Some(now());
    let out = r.clone();
    write_store(path, &store)?;
    Ok(out)
}

/// Parse a `--at` time spec (ADR-054 §4) into a UTC instant.
///
/// Accepted forms:
/// - RFC3339 (`2026-06-12T15:00:00-03:00`)
/// - `HH:MM` — today on the LOCAL date implied by `local_offset`
/// - `YYYY-MM-DD HH:MM` — local time in `local_offset`
///
/// `now` and `local_offset` are injected for testability; the CLI passes
/// `Utc::now()` and the machine's local offset. Returns the instant plus
/// an `is_past` flag — past times are accepted (dispatch on next run),
/// the caller decides how to warn.
pub fn parse_at(
    input: &str,
    now: DateTime<Utc>,
    local_offset: chrono::FixedOffset,
) -> Result<(DateTime<Utc>, bool), String> {
    use chrono::{NaiveDateTime, NaiveTime, TimeZone};
    let s = input.trim();
    if s.is_empty() {
        return Err("empty --at value — use RFC3339, HH:MM, or \"YYYY-MM-DD HH:MM\"".into());
    }
    let at: DateTime<Utc> = if let Ok(dt) = DateTime::parse_from_rfc3339(s) {
        dt.with_timezone(&Utc)
    } else if let Ok(t) = NaiveTime::parse_from_str(s, "%H:%M") {
        let local_today = now.with_timezone(&local_offset).date_naive();
        local_offset
            .from_local_datetime(&local_today.and_time(t))
            .single()
            .ok_or_else(|| format!("ambiguous local time {s:?}"))?
            .with_timezone(&Utc)
    } else if let Ok(dt) = NaiveDateTime::parse_from_str(s, "%Y-%m-%d %H:%M") {
        local_offset
            .from_local_datetime(&dt)
            .single()
            .ok_or_else(|| format!("ambiguous local time {s:?}"))?
            .with_timezone(&Utc)
    } else {
        return Err(format!(
            "invalid --at value {s:?} — use RFC3339, HH:MM, or \"YYYY-MM-DD HH:MM\""
        ));
    };
    Ok((at, at < now))
}

/// Parse "1d" / "3d" / "1w" style durations.
pub fn parse_duration(s: &str) -> Result<Duration, String> {
    let s = s.trim();
    let (num, unit) = s.split_at(s.len().saturating_sub(1));
    let n: i64 = num
        .parse()
        .map_err(|_| format!("invalid duration {s:?} — use forms like 1d, 3d, 1w"))?;
    if n <= 0 {
        return Err(format!("duration must be positive, got {s:?}"));
    }
    match unit {
        "d" => Ok(Duration::days(n)),
        "w" => Ok(Duration::weeks(n)),
        "h" => Ok(Duration::hours(n)),
        _ => Err(format!("invalid duration unit in {s:?} — use d, w, or h")),
    }
}

/// Snooze a reminder for a duration ("1d", "3d", "1w").
pub fn snooze(path: &Path, id: &str, dur: &str) -> Result<Reminder, String> {
    let dur = parse_duration(dur)?;
    let _lock = lock_store(path)?;
    let mut store = read_store(path)?;
    let r = store
        .reminders
        .iter_mut()
        .find(|r| r.id == id)
        .ok_or_else(|| format!("no reminder with id {id}"))?;
    if r.status == Status::Resolved {
        return Err(format!("reminder {id} is already resolved"));
    }
    r.status = Status::Snoozed;
    r.snoozed_until = Some(now() + dur);
    let out = r.clone();
    write_store(path, &store)?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn store_path(dir: &tempfile::TempDir) -> PathBuf {
        dir.path().join("reminders.json")
    }

    fn new(text: &str) -> NewReminder {
        NewReminder {
            text: text.into(),
            ..Default::default()
        }
    }

    #[test]
    fn write_creates_store_with_pending_reminder() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r = write_reminder(&path, new("run validate.sh")).unwrap();
        assert_eq!(r.status, Status::Pending);
        assert_eq!(r.occurrences, 1);
        assert_eq!(r.priority, Priority::Medium);
        assert!(r.id.starts_with("r-"));
        let raw: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(raw["version"], 1);
        assert_eq!(raw["reminders"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn write_rejects_empty_text() {
        let dir = tempfile::TempDir::new().unwrap();
        assert!(write_reminder(&store_path(&dir), new("  ")).is_err());
    }

    #[test]
    fn dedup_key_increments_occurrences_not_entries() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let mk = || NewReminder {
            text: "edited hooks — run validate".into(),
            dedup_key: Some("hooks-validate".into()),
            ..Default::default()
        };
        write_reminder(&path, mk()).unwrap();
        let r2 = write_reminder(&path, mk()).unwrap();
        assert_eq!(r2.occurrences, 2);
        assert_eq!(list(&path).unwrap().len(), 1);
    }

    #[test]
    fn three_occurrences_escalate_medium_to_high() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let mk = || NewReminder {
            text: "x".into(),
            dedup_key: Some("k".into()),
            ..Default::default()
        };
        write_reminder(&path, mk()).unwrap();
        write_reminder(&path, mk()).unwrap();
        let r3 = write_reminder(&path, mk()).unwrap();
        assert_eq!(r3.occurrences, 3);
        assert_eq!(r3.priority, Priority::High);
    }

    #[test]
    fn resolved_entry_does_not_absorb_dedup_writes() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let mk = || NewReminder {
            text: "x".into(),
            dedup_key: Some("k".into()),
            ..Default::default()
        };
        let r1 = write_reminder(&path, mk()).unwrap();
        resolve(&path, &r1.id).unwrap();
        let r2 = write_reminder(&path, mk()).unwrap();
        assert_ne!(r1.id, r2.id);
        assert_eq!(r2.occurrences, 1);
        assert_eq!(list(&path).unwrap().len(), 2);
    }

    #[test]
    fn parse_before_write_never_clobbers_corrupt_store() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, "{not json").unwrap();
        assert!(write_reminder(&path, new("x")).is_err());
        // original content untouched
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "{not json");
    }

    #[test]
    fn newer_store_version_is_rejected() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, r#"{"version": 99, "reminders": []}"#).unwrap();
        let err = write_reminder(&path, new("x")).unwrap_err();
        assert!(err.contains("version 99"));
    }

    #[test]
    fn unknown_fields_are_tolerated() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        write_reminder(&path, new("x")).unwrap();
        // Simulate a future writer adding fields.
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        val["future_top_level"] = serde_json::json!("hi");
        val["reminders"][0]["future_field"] = serde_json::json!(42);
        std::fs::write(&path, serde_json::to_string(&val).unwrap()).unwrap();
        assert_eq!(list(&path).unwrap().len(), 1);
    }

    #[test]
    fn resolve_and_snooze_transition_status() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let a = write_reminder(&path, new("a")).unwrap();
        let b = write_reminder(&path, new("b")).unwrap();
        let ra = resolve(&path, &a.id).unwrap();
        assert_eq!(ra.status, Status::Resolved);
        assert!(ra.resolved_at.is_some());
        let rb = snooze(&path, &b.id, "1d").unwrap();
        assert_eq!(rb.status, Status::Snoozed);
        assert!(rb.snoozed_until.unwrap() > Utc::now());
        assert!(resolve(&path, "r-nope").is_err());
        assert!(snooze(&path, &b.id, "5x").is_err());
    }

    #[test]
    fn snooze_resolved_reminder_is_rejected() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let a = write_reminder(&path, new("a")).unwrap();
        resolve(&path, &a.id).unwrap();
        assert!(snooze(&path, &a.id, "1d").is_err());
    }

    #[test]
    fn parse_duration_forms() {
        assert_eq!(parse_duration("1d").unwrap(), Duration::days(1));
        assert_eq!(parse_duration("3d").unwrap(), Duration::days(3));
        assert_eq!(parse_duration("1w").unwrap(), Duration::weeks(1));
        assert_eq!(parse_duration("2h").unwrap(), Duration::hours(2));
        assert!(parse_duration("0d").is_err());
        assert!(parse_duration("-1d").is_err());
        assert!(parse_duration("d").is_err());
        assert!(parse_duration("").is_err());
        assert!(parse_duration("1m").is_err());
    }

    #[test]
    fn list_transitions_expired_snooze_back_to_pending_and_persists() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let a = write_reminder(&path, new("a")).unwrap();
        snooze(&path, &a.id, "1d").unwrap();
        // Rewind snoozed_until into the past directly in the file.
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        val["reminders"][0]["snoozed_until"] = serde_json::json!("2020-01-01T00:00:00Z");
        std::fs::write(&path, serde_json::to_string(&val).unwrap()).unwrap();
        let out = list(&path).unwrap();
        assert_eq!(out[0].status, Status::Pending);
        // Persisted, not just computed:
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(raw.contains("\"pending\""));
        assert!(!raw.contains("snoozed_until"));
    }

    #[test]
    fn list_expires_pending_older_than_30_days_and_persists() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        write_reminder(&path, new("old")).unwrap();
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        val["reminders"][0]["created"] = serde_json::json!("2020-01-01T00:00:00Z");
        std::fs::write(&path, serde_json::to_string(&val).unwrap()).unwrap();
        let out = list(&path).unwrap();
        assert_eq!(out[0].status, Status::Expired);
        assert!(std::fs::read_to_string(&path).unwrap().contains("\"expired\""));
    }

    // ── t-1997: parse_at (--at forms, ADR-054 §4) ──────────────────────

    use chrono::FixedOffset;

    /// now = 2026-06-12T12:00:00Z; local = UTC-3 (09:00 local, date 2026-06-12).
    fn at_fixture() -> (DateTime<Utc>, FixedOffset) {
        (
            "2026-06-12T12:00:00Z".parse().unwrap(),
            FixedOffset::west_opt(3 * 3600).unwrap(),
        )
    }

    #[test]
    fn parse_at_rfc3339_converts_to_utc() {
        let (now, off) = at_fixture();
        let (at, past) = parse_at("2026-06-12T15:00:00-03:00", now, off).unwrap();
        assert_eq!(at, "2026-06-12T18:00:00Z".parse::<DateTime<Utc>>().unwrap());
        assert!(!past);
    }

    /// Challenger F2: the local→UTC conversion must actually be applied —
    /// with a non-UTC offset the stored instant differs from naive HH:MM-as-UTC.
    #[test]
    fn parse_at_hhmm_is_today_local_converted_to_utc() {
        let (now, off) = at_fixture();
        let (at, past) = parse_at("15:00", now, off).unwrap();
        assert_eq!(at, "2026-06-12T18:00:00Z".parse::<DateTime<Utc>>().unwrap());
        assert_ne!(at, "2026-06-12T15:00:00Z".parse::<DateTime<Utc>>().unwrap());
        assert!(!past);
    }

    #[test]
    fn parse_at_hhmm_earlier_today_is_past() {
        let (now, off) = at_fixture();
        // 08:00 local = 11:00Z < now (12:00Z) — accepted, flagged past.
        let (at, past) = parse_at("08:00", now, off).unwrap();
        assert_eq!(at, "2026-06-12T11:00:00Z".parse::<DateTime<Utc>>().unwrap());
        assert!(past);
    }

    /// "Today" means the LOCAL date, not the UTC date.
    #[test]
    fn parse_at_hhmm_uses_local_date_across_utc_midnight() {
        let now: DateTime<Utc> = "2026-06-13T01:00:00Z".parse().unwrap(); // local 2026-06-12 22:00
        let off = FixedOffset::west_opt(3 * 3600).unwrap();
        let (at, past) = parse_at("23:00", now, off).unwrap();
        assert_eq!(at, "2026-06-13T02:00:00Z".parse::<DateTime<Utc>>().unwrap());
        assert!(!past);
    }

    #[test]
    fn parse_at_date_time_form_converts_local_to_utc() {
        let (now, off) = at_fixture();
        let (at, past) = parse_at("2026-06-13 09:30", now, off).unwrap();
        assert_eq!(at, "2026-06-13T12:30:00Z".parse::<DateTime<Utc>>().unwrap());
        assert!(!past);
    }

    #[test]
    fn parse_at_rejects_invalid_forms() {
        let (now, off) = at_fixture();
        for bad in ["", "  ", "25:99", "garbage", "2026-13-40 12:00", "15:00:30:99"] {
            assert!(parse_at(bad, now, off).is_err(), "accepted {bad:?}");
        }
    }

    // ── t-1997: due() listing (ADR-054 §4) ─────────────────────────────

    fn with_due(text: &str, due: Option<DateTime<Utc>>) -> NewReminder {
        NewReminder {
            text: text.into(),
            due,
            ..Default::default()
        }
    }

    /// Patch one entry's field directly in the store file (simulates state
    /// only future writers — t-1998 dispatch — or the passage of time create).
    fn patch_entry(path: &std::path::Path, id: &str, field: &str, value: serde_json::Value) {
        let mut val: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        for r in val["reminders"].as_array_mut().unwrap() {
            if r["id"] == id {
                r[field] = value.clone();
            }
        }
        std::fs::write(path, serde_json::to_string(&val).unwrap()).unwrap();
    }

    #[test]
    fn due_returns_only_pending_past_due_undispatched() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let past = now() - Duration::hours(1);
        let future = now() + Duration::hours(1);
        let eligible = write_reminder(&path, with_due("eligible", Some(past))).unwrap();
        write_reminder(&path, with_due("future", Some(future))).unwrap();
        write_reminder(&path, with_due("no-due", None)).unwrap();
        let dispatched = write_reminder(&path, with_due("dispatched", Some(past))).unwrap();
        let resolved = write_reminder(&path, with_due("resolved", Some(past))).unwrap();
        resolve(&path, &resolved.id).unwrap();
        patch_entry(
            &path,
            &dispatched.id,
            "dispatched_at",
            serde_json::json!("2026-06-12T00:00:00Z"),
        );
        let out = due(&path).unwrap();
        let ids: Vec<_> = out.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, vec![eligible.id.as_str()]);
    }

    #[test]
    fn due_excludes_entries_expired_by_the_30_day_transition() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let past = now() - Duration::hours(1);
        let old = write_reminder(&path, with_due("ancient", Some(past))).unwrap();
        patch_entry(&path, &old.id, "created", serde_json::json!("2020-01-01T00:00:00Z"));
        assert!(due(&path).unwrap().is_empty());
        // The transition persisted (due() is a list-path: locked write).
        assert!(std::fs::read_to_string(&path).unwrap().contains("\"expired\""));
    }

    /// Challenger F1 (ADR-054 §3): a snoozed reminder whose snooze expired,
    /// with due in the past and never dispatched, IS eligible — the
    /// snooze-expiry transition must run BEFORE the due filter.
    #[test]
    fn due_includes_snooze_expired_past_due_undispatched() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let past = now() - Duration::hours(1);
        let a = write_reminder(&path, with_due("was snoozed", Some(past))).unwrap();
        snooze(&path, &a.id, "1d").unwrap();
        patch_entry(
            &path,
            &a.id,
            "snoozed_until",
            serde_json::json!("2020-01-01T00:00:00Z"),
        );
        let out = due(&path).unwrap();
        let ids: Vec<_> = out.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, vec![a.id.as_str()]);
        // Transition persisted: entry is pending again in the store file.
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(raw.contains("\"pending\""));
        assert!(!raw.contains("snoozed_until"));
    }

    // ── t-2062: dispatch — two-phase select/send/commit (ADR-054 §5) ───

    use crate::notify::{ChannelRegistry, DispatchResult};
    use std::cell::RefCell;

    fn dispatch_registry() -> ChannelRegistry {
        serde_json::from_str(
            r#"{
                "version": 1,
                "channels": {
                    "telegram": { "type": "telegram" },
                    "desktop":  { "type": "desktop" }
                },
                "defaults": { "high": ["telegram", "desktop"], "medium": ["desktop"], "low": [] }
            }"#,
        )
        .unwrap()
    }

    fn due_with_priority(
        text: &str,
        priority: Priority,
        channels: Option<Vec<String>>,
    ) -> NewReminder {
        NewReminder {
            text: text.into(),
            due: Some(now() - Duration::hours(1)),
            priority: Some(priority),
            channels,
            ..Default::default()
        }
    }

    #[test]
    fn dispatch_sends_via_priority_defaults_and_marks_dispatched_at() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        let r = write_reminder(&path, due_with_priority("pay rent", Priority::Medium, None))
            .unwrap();
        let calls: RefCell<Vec<(String, String)>> = RefCell::new(vec![]);
        let sender = |c: &crate::notify::Channel, m: &str| {
            calls.borrow_mut().push((c.name.clone(), m.to_string()));
            DispatchResult::Sent
        };
        let report = dispatch(&path, &reg, &sender).unwrap();
        assert_eq!(report.selected, 1);
        assert_eq!(report.dispatched, vec![r.id.clone()]);
        assert!(report.failed.is_empty());
        {
            let sent = calls.borrow();
            assert_eq!(sent.len(), 1, "medium routes to desktop only");
            assert_eq!(sent[0].0, "desktop");
            assert!(sent[0].1.contains("pay rent"));
        }
        let stored = list(&path).unwrap().into_iter().find(|x| x.id == r.id).unwrap();
        assert!(stored.dispatched_at.is_some());
        // Idempotency: a second run selects nothing and sends nothing.
        let report2 = dispatch(&path, &reg, &sender).unwrap();
        assert_eq!(report2.selected, 0);
        assert_eq!(calls.borrow().len(), 1);
    }

    #[test]
    fn dispatch_partial_failure_marks_when_at_least_one_send_succeeds() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        let r =
            write_reminder(&path, due_with_priority("urgent", Priority::High, None)).unwrap();
        let sender = |c: &crate::notify::Channel, _m: &str| {
            if c.name == "telegram" {
                DispatchResult::Failed { reason: "net down".into() }
            } else {
                DispatchResult::Sent
            }
        };
        let report = dispatch(&path, &reg, &sender).unwrap();
        assert_eq!(report.dispatched, vec![r.id.clone()]);
        let stored = list(&path).unwrap().into_iter().find(|x| x.id == r.id).unwrap();
        assert!(stored.dispatched_at.is_some(), "1-of-2 success must mark");
    }

    #[test]
    fn dispatch_all_channels_failing_leaves_entry_unmarked_for_retry() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        let r =
            write_reminder(&path, due_with_priority("urgent", Priority::High, None)).unwrap();
        let attempts = RefCell::new(0usize);
        let sender = |_c: &crate::notify::Channel, _m: &str| {
            *attempts.borrow_mut() += 1;
            DispatchResult::Failed { reason: "offline".into() }
        };
        let report = dispatch(&path, &reg, &sender).unwrap();
        assert!(report.dispatched.is_empty());
        assert_eq!(report.failed, vec![r.id.clone()]);
        let stored = list(&path).unwrap().into_iter().find(|x| x.id == r.id).unwrap();
        assert!(stored.dispatched_at.is_none(), "all-fail must leave null for retry");
        // Next run retries: entry still selected, channels attempted again.
        dispatch(&path, &reg, &sender).unwrap();
        assert_eq!(*attempts.borrow(), 4, "2 channels x 2 runs");
    }

    #[test]
    fn dispatch_explicit_channels_override_priority_defaults() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        write_reminder(
            &path,
            due_with_priority("ping", Priority::Medium, Some(vec!["telegram".into()])),
        )
        .unwrap();
        let calls: RefCell<Vec<String>> = RefCell::new(vec![]);
        let sender = |c: &crate::notify::Channel, _m: &str| {
            calls.borrow_mut().push(c.name.clone());
            DispatchResult::Sent
        };
        dispatch(&path, &reg, &sender).unwrap();
        assert_eq!(*calls.borrow(), vec!["telegram".to_string()]);
    }

    #[test]
    fn dispatch_broadcast_all_hits_every_channel() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        write_reminder(
            &path,
            due_with_priority("everywhere", Priority::Low, Some(vec!["all".into()])),
        )
        .unwrap();
        let calls: RefCell<Vec<String>> = RefCell::new(vec![]);
        let sender = |c: &crate::notify::Channel, _m: &str| {
            calls.borrow_mut().push(c.name.clone());
            DispatchResult::Sent
        };
        dispatch(&path, &reg, &sender).unwrap();
        let mut got = calls.borrow().clone();
        got.sort();
        assert_eq!(got, vec!["desktop".to_string(), "telegram".to_string()]);
    }

    #[test]
    fn dispatch_low_priority_resolves_no_channels_and_does_not_mark() {
        // ADR-054 §2: low never pushes; entry stays pull-only.
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        let r = write_reminder(&path, due_with_priority("quiet", Priority::Low, None)).unwrap();
        let calls = RefCell::new(0usize);
        let sender = |_c: &crate::notify::Channel, _m: &str| {
            *calls.borrow_mut() += 1;
            DispatchResult::Sent
        };
        dispatch(&path, &reg, &sender).unwrap();
        assert_eq!(*calls.borrow(), 0);
        let stored = list(&path).unwrap().into_iter().find(|x| x.id == r.id).unwrap();
        assert!(stored.dispatched_at.is_none());
    }

    /// Challenger O1: an entry marked by a CONCURRENT run between this run's
    /// select and commit phases must be left untouched — the commit re-reads
    /// the store and skips entries whose dispatched_at is no longer null.
    #[test]
    fn dispatch_commit_skips_entry_marked_concurrently_mid_run() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let reg = dispatch_registry();
        let r =
            write_reminder(&path, due_with_priority("racy", Priority::Medium, None)).unwrap();
        let sentinel = "2020-06-06T06:06:06Z";
        let sender = |_c: &crate::notify::Channel, _m: &str| {
            // Simulate a concurrent dispatch marking the entry during the
            // unlocked send phase.
            patch_entry(&path, &r.id, "dispatched_at", serde_json::json!(sentinel));
            DispatchResult::Sent
        };
        dispatch(&path, &reg, &sender).unwrap();
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(
            raw.contains(sentinel),
            "concurrent mark must survive — commit must not overwrite it"
        );
    }

    // ── t-1997: due / channels / dispatched_at (ADR-054 §3) ────────────

    /// Back-compat fixture: a literal pre-t-1997 store. Do not regenerate
    /// from current structs — its point is that old JSON keeps parsing.
    const PRE_T1997_STORE: &str = r#"{"version":1,"reminders":[{"id":"r-0011223344556677","text":"old entry","priority":"medium","status":"pending","created":"2026-06-01T00:00:00Z","last_seen":"2026-06-01T00:00:00Z","occurrences":1}]}"#;

    #[test]
    fn pre_t1997_store_parses_unchanged() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, PRE_T1997_STORE).unwrap();
        // Assert on the parse path (read_store), NOT list(): list() layers the
        // 30-day pending→expired transition on top, which is calendar-dependent
        // and would flip this fixture (created 2026-06-01) to Expired after
        // 2026-07-01. This test's invariant is that old JSON *parses* unchanged;
        // the expiry transition is covered by list_expires_pending_older_than_30_days.
        let out = read_store(&path).unwrap().reminders;
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].status, Status::Pending);
        assert!(out[0].due.is_none());
        assert!(out[0].channels.is_none());
        assert!(out[0].dispatched_at.is_none());
    }

    #[test]
    fn rewrite_does_not_add_new_fields_to_old_entries() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, PRE_T1997_STORE).unwrap();
        // Force a full store rewrite by appending a plain reminder.
        write_reminder(&path, new("fresh")).unwrap();
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(!raw.contains("\"due\""));
        assert!(!raw.contains("\"channels\""));
        assert!(!raw.contains("\"dispatched_at\""));
    }

    // ── t-2116: task_id field ───────────────────────────────────────────────

    #[test]
    fn write_with_task_id_roundtrips() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let r = write_reminder(
            &path,
            NewReminder { text: "check t-42".into(), task_id: Some("t-42".into()), ..Default::default() },
        )
        .unwrap();
        assert_eq!(r.task_id.as_deref(), Some("t-42"));
        let stored = list(&path).unwrap();
        assert_eq!(stored[0].task_id.as_deref(), Some("t-42"));
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(raw.contains("\"task_id\""));
        assert!(raw.contains("\"t-42\""));
    }

    #[test]
    fn write_without_task_id_omits_field_from_json() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        write_reminder(&path, new("no link")).unwrap();
        let raw = std::fs::read_to_string(&path).unwrap();
        assert!(!raw.contains("\"task_id\""));
    }

    #[test]
    fn pre_t2116_store_without_task_id_parses_unchanged() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        std::fs::write(&path, PRE_T1997_STORE).unwrap();
        let out = list(&path).unwrap();
        assert!(out[0].task_id.is_none());
    }

    #[test]
    fn write_with_due_and_channels_roundtrips_as_rfc3339_utc() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let due: DateTime<Utc> = "2026-06-12T18:00:00Z".parse().unwrap();
        let r = write_reminder(
            &path,
            NewReminder {
                text: "call Ramon".into(),
                due: Some(due),
                channels: Some(vec!["telegram".into(), "desktop".into()]),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(r.due, Some(due));
        assert_eq!(
            r.channels,
            Some(vec!["telegram".to_string(), "desktop".to_string()])
        );
        assert!(r.dispatched_at.is_none());
        // Wire format: due is an RFC3339 string that parses back to the same UTC instant.
        let raw: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        let wire = raw["reminders"][0]["due"].as_str().unwrap();
        assert_eq!(wire.parse::<DateTime<Utc>>().unwrap(), due);
        assert_eq!(
            raw["reminders"][0]["channels"],
            serde_json::json!(["telegram", "desktop"])
        );
        // Reads back intact through the full list path.
        let out = list(&path).unwrap();
        assert_eq!(out[0].due, Some(due));
    }

    /// ADR-051 §6 spirit, t-1997 edition: interleaved writers carrying the
    /// new fields — every append and every field survives.
    #[test]
    fn concurrent_writers_with_new_fields_survive() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let n_threads = 4;
        let writes_per_thread = 5;
        let handles: Vec<_> = (0..n_threads)
            .map(|t| {
                let p = path.clone();
                std::thread::spawn(move || {
                    for i in 0..writes_per_thread {
                        write_reminder(
                            &p,
                            NewReminder {
                                text: format!("writer {t} item {i}"),
                                due: Some("2026-06-12T15:00:00Z".parse().unwrap()),
                                channels: Some(vec![format!("ch-{t}")]),
                                ..Default::default()
                            },
                        )
                        .unwrap();
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        let out = list(&path).unwrap();
        assert_eq!(out.len(), n_threads * writes_per_thread);
        assert!(out.iter().all(|r| r.due.is_some() && r.channels.is_some()));
    }

    /// The test this module exists for (ADR-051 §6): two concurrent writers,
    /// both appends survive. Without the lock this fails via last-writer-wins.
    #[test]
    fn concurrent_writers_both_appends_survive() {
        let dir = tempfile::TempDir::new().unwrap();
        let path = store_path(&dir);
        let n_threads = 8;
        let writes_per_thread = 5;
        let handles: Vec<_> = (0..n_threads)
            .map(|t| {
                let p = path.clone();
                std::thread::spawn(move || {
                    for i in 0..writes_per_thread {
                        write_reminder(
                            &p,
                            NewReminder {
                                text: format!("writer {t} item {i}"),
                                ..Default::default()
                            },
                        )
                        .unwrap();
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        let out = list(&path).unwrap();
        assert_eq!(out.len(), n_threads * writes_per_thread);
    }
}
