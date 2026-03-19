//! brana inbox — Gmail newsletter subscription management via IMAP.
//!
//! Config: ~/.claude/scheduler/inbox.json
//! State:  ~/.claude/scheduler/state/inbox.json
//! Log:    ~/.claude/scheduler/inbox-log.jsonl
//!
//! Credentials via env vars: BRANA_GMAIL_USER, BRANA_GMAIL_APP_PASSWORD

use crate::cli::InboxCmd;
use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{BufWriter, Write};
use std::path::PathBuf;

// ── Data types ──────────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct InboxConfig {
    pub imap_host: String,
    pub imap_port: u16,
    pub user_env: String,
    pub password_env: String,
    pub label: String,
    pub subscriptions: Vec<Subscription>,
}

impl Default for InboxConfig {
    fn default() -> Self {
        Self {
            imap_host: "imap.gmail.com".into(),
            imap_port: 993,
            user_env: "BRANA_GMAIL_USER".into(),
            password_env: "BRANA_GMAIL_APP_PASSWORD".into(),
            label: "Newsletters".into(),
            subscriptions: Vec::new(),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Subscription {
    pub name: String,
    pub from: String,
    pub frequency: String, // "daily" | "weekly" | "monthly"
    pub enabled: bool,
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct InboxState {
    pub last_poll: Option<String>,
    pub last_uid: u32,
    pub unmatched_count: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct InboxLogEntry {
    pub subscription: Option<String>,
    pub from: String,
    pub subject: String,
    pub date: String,
    pub matched: bool,
    pub polled_at: String,
}

// ── Paths ───────────────────────────────────────────────────────────────

fn dirs_home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into()))
}

fn inbox_config_path() -> PathBuf {
    dirs_home().join(".claude/scheduler/inbox.json")
}

fn inbox_state_path() -> PathBuf {
    dirs_home().join(".claude/scheduler/state/inbox.json")
}

fn inbox_log_path() -> PathBuf {
    dirs_home().join(".claude/scheduler/inbox-log.jsonl")
}

fn ensure_state_dir() {
    let dir = dirs_home().join(".claude/scheduler/state");
    let _ = fs::create_dir_all(&dir);
}

// ── Config CRUD ─────────────────────────────────────────────────────────

fn load_config() -> InboxConfig {
    let path = inbox_config_path();
    match fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
        Err(_) => InboxConfig::default(),
    }
}

fn save_config(config: &InboxConfig) -> Result<()> {
    let path = inbox_config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(config)?;
    fs::write(&path, json).context("writing inbox.json")?;
    Ok(())
}

fn load_state() -> InboxState {
    let path = inbox_state_path();
    match fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
        Err(_) => InboxState::default(),
    }
}

fn save_state(state: &InboxState) -> Result<()> {
    ensure_state_dir();
    let path = inbox_state_path();
    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(state)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

// ── Commands ────────────────────────────────────────────────────────────

pub fn cmd_inbox(cmd: InboxCmd) {
    let result = match cmd {
        InboxCmd::Add { name, from, frequency } => cmd_add(&name, &from, &frequency),
        InboxCmd::List => cmd_list(),
        InboxCmd::Poll { label } => cmd_poll(&label),
        InboxCmd::Remove { name } => cmd_remove(&name),
        InboxCmd::Status => cmd_status(),
    };
    if let Err(e) = result {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn cmd_add(name: &str, from: &str, frequency: &str) -> Result<()> {
    let valid = ["daily", "weekly", "monthly"];
    if !valid.contains(&frequency) {
        anyhow::bail!("frequency must be daily, weekly, or monthly — got '{frequency}'");
    }

    let mut config = load_config();
    if config.subscriptions.iter().any(|s| s.name == name) {
        anyhow::bail!("subscription '{name}' already exists");
    }

    config.subscriptions.push(Subscription {
        name: name.to_string(),
        from: from.to_string(),
        frequency: frequency.to_string(),
        enabled: true,
    });
    save_config(&config)?;

    println!("{{\"ok\":true,\"name\":\"{name}\",\"from\":\"{from}\",\"frequency\":\"{frequency}\"}}");
    Ok(())
}

fn cmd_list() -> Result<()> {
    let config = load_config();
    let json = serde_json::to_string_pretty(&config.subscriptions)?;
    println!("{json}");
    Ok(())
}

fn cmd_remove(name: &str) -> Result<()> {
    let mut config = load_config();
    let before = config.subscriptions.len();
    config.subscriptions.retain(|s| s.name != name);
    if config.subscriptions.len() == before {
        anyhow::bail!("subscription '{name}' not found");
    }
    save_config(&config)?;
    println!("{{\"ok\":true,\"removed\":\"{name}\"}}");
    Ok(())
}

fn cmd_status() -> Result<()> {
    let config = load_config();
    let state = load_state();
    let result = serde_json::json!({
        "subscriptions": config.subscriptions.len(),
        "last_poll": state.last_poll,
        "last_uid": state.last_uid,
        "unmatched_count": state.unmatched_count,
        "details": config.subscriptions.iter().map(|s| {
            serde_json::json!({
                "name": s.name,
                "from": s.from,
                "frequency": s.frequency,
                "enabled": s.enabled,
            })
        }).collect::<Vec<_>>(),
    });
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

fn cmd_poll(label: &str) -> Result<()> {
    let config = load_config();
    let mut state = load_state();

    // Read credentials from env
    let user = std::env::var(&config.user_env)
        .with_context(|| format!("set {} env var with your Gmail address", config.user_env))?;
    let password = std::env::var(&config.password_env)
        .with_context(|| format!("set {} env var with your Gmail App Password", config.password_env))?;

    // Connect via IMAP over TLS
    let tls = native_tls::TlsConnector::builder().build()
        .context("building TLS connector")?;
    let client = imap::connect(
        (&*config.imap_host, config.imap_port),
        &config.imap_host,
        &tls,
    ).context("connecting to IMAP server")?;

    let mut session = client.login(&user, &password)
        .map_err(|e| anyhow::anyhow!("IMAP login failed: {}", e.0))?;

    // Select the label/folder
    let mailbox_name = format!("[Gmail]/{label}");
    // Try the Gmail-style label first, fall back to plain label name
    let _mailbox = session.select(&mailbox_name)
        .or_else(|_| session.select(label))
        .with_context(|| format!("selecting mailbox '{label}' (also tried '{mailbox_name}')"))?;

    // Search for unseen messages
    let uids = session.uid_search("UNSEEN")
        .context("searching for unseen messages")?;

    if uids.is_empty() {
        state.last_poll = Some(Utc::now().to_rfc3339());
        state.unmatched_count = 0;
        save_state(&state)?;
        session.logout().ok();
        println!("{{\"new_emails\":0,\"matched\":0,\"unmatched\":0}}");
        return Ok(());
    }

    // Fetch headers for unseen messages
    let uid_list: String = uids.iter()
        .map(|u| u.to_string())
        .collect::<Vec<_>>()
        .join(",");
    let messages = session.uid_fetch(&uid_list, "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]")
        .context("fetching message headers")?;

    let mut matched = 0usize;
    let mut unmatched = 0usize;

    for msg in messages.iter() {
        let header_bytes = msg.body().unwrap_or(b"");
        let header_str = String::from_utf8_lossy(header_bytes);

        let from = extract_header(&header_str, "From");
        let subject = extract_header(&header_str, "Subject");
        let date = extract_header(&header_str, "Date");

        // Match against subscriptions
        let sub_match = config.subscriptions.iter()
            .find(|s| s.enabled && from.to_lowercase().contains(&s.from.to_lowercase()));

        let is_matched = sub_match.is_some();
        if is_matched { matched += 1; } else { unmatched += 1; }

        // Log entry
        let log_entry = InboxLogEntry {
            subscription: sub_match.map(|s| s.name.clone()),
            from: from.clone(),
            subject,
            date,
            matched: is_matched,
            polled_at: Utc::now().to_rfc3339(),
        };
        if let Ok(line) = serde_json::to_string(&log_entry) {
            let log_path = inbox_log_path();
            if let Ok(file) = fs::OpenOptions::new()
                .create(true).append(true).open(&log_path)
            {
                let mut w = BufWriter::new(file);
                let _ = writeln!(w, "{line}");
            }
        }

        // Track highest UID
        if let Some(uid) = msg.uid {
            if uid > state.last_uid {
                state.last_uid = uid;
            }
        }
    }

    state.last_poll = Some(Utc::now().to_rfc3339());
    state.unmatched_count = unmatched;
    save_state(&state)?;
    session.logout().ok();

    println!("{}", serde_json::to_string_pretty(&serde_json::json!({
        "new_emails": uids.len(),
        "matched": matched,
        "unmatched": unmatched,
    }))?);
    Ok(())
}

/// Extract a header value from raw header text.
fn extract_header(headers: &str, name: &str) -> String {
    let prefix = format!("{name}: ");
    for line in headers.lines() {
        if line.to_lowercase().starts_with(&prefix.to_lowercase()) {
            return line[prefix.len()..].trim().to_string();
        }
    }
    String::new()
}
