//! `brana remind` — CLI surface for the reminder store (t-1966, ADR-051).
//!
//! Thin marshalling layer: all mutation logic lives in `brana_core::remind`.

use anyhow::{Result, anyhow};
use brana_core::remind::{self, NewReminder, Priority, Status};
use std::path::PathBuf;

use crate::cli::{RemindPriority, RemindStatus};

/// Store lives per-user, cross-project: `~/.claude/reminders.json`.
fn store_path() -> PathBuf {
    brana_core::util::home().join(".claude").join("reminders.json")
}

fn to_priority(p: &RemindPriority) -> Priority {
    match p {
        RemindPriority::Low => Priority::Low,
        RemindPriority::Medium => Priority::Medium,
        RemindPriority::High => Priority::High,
    }
}

fn to_status(s: &RemindStatus) -> Status {
    match s {
        RemindStatus::Pending => Status::Pending,
        RemindStatus::Resolved => Status::Resolved,
        RemindStatus::Snoozed => Status::Snoozed,
        RemindStatus::Expired => Status::Expired,
    }
}

pub fn cmd_write(
    text: &str,
    action: Option<String>,
    priority: Option<RemindPriority>,
    dedup_key: Option<String>,
    project: Option<String>,
    tags: Option<String>,
    at: Option<String>,
    channels: Option<String>,
) -> Result<()> {
    let due = match at {
        Some(spec) => {
            let now = chrono::Utc::now();
            let local_offset = *chrono::Local::now().offset();
            let (instant, is_past) =
                remind::parse_at(&spec, now, local_offset).map_err(|e| anyhow!(e))?;
            if is_past {
                // warn on stderr — stdout stays pure JSON (ADR-054 §4)
                eprintln!("warning: --at {spec:?} is in the past — dispatches on next due run");
            }
            Some(instant)
        }
        None => None,
    };
    let channels = channels
        .map(|c| {
            c.split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
        })
        .filter(|v| !v.is_empty());
    let new = NewReminder {
        text: text.to_string(),
        action,
        priority: priority.as_ref().map(to_priority),
        dedup_key,
        project,
        tags: tags
            .map(|t| t.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
            .unwrap_or_default(),
        due,
        channels,
    };
    let r = remind::write_reminder(&store_path(), new).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&r)?);
    Ok(())
}

pub fn cmd_due() -> Result<()> {
    let reminders = remind::due(&store_path()).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&reminders)?);
    Ok(())
}

pub fn cmd_list(status: Option<RemindStatus>) -> Result<()> {
    let mut reminders = remind::list(&store_path()).map_err(|e| anyhow!(e))?;
    if let Some(s) = status {
        let want = to_status(&s);
        reminders.retain(|r| r.status == want);
    }
    println!("{}", serde_json::to_string_pretty(&reminders)?);
    Ok(())
}

pub fn cmd_resolve(id: &str) -> Result<()> {
    let r = remind::resolve(&store_path(), id).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&r)?);
    Ok(())
}

pub fn cmd_snooze(id: &str, duration: &str) -> Result<()> {
    let r = remind::snooze(&store_path(), id, duration).map_err(|e| anyhow!(e))?;
    println!("{}", serde_json::to_string_pretty(&r)?);
    Ok(())
}
