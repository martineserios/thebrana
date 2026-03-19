//! brana inbox — Gmail newsletter subscription management via IMAP.
//!
//! Config: ~/.claude/scheduler/inbox.json (multi-account)
//! State:  ~/.claude/scheduler/state/inbox-{account}.json
//! Log:    ~/.claude/scheduler/inbox-log.jsonl
//!
//! Credentials via env vars per account (e.g., BRANA_GMAIL_USER, BRANA_GMAIL_APP_PASSWORD)

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
    pub accounts: Vec<Account>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Account {
    pub name: String,
    pub imap_host: String,
    pub imap_port: u16,
    pub user_env: String,
    pub password_env: String,
    pub label: String,
    pub enabled: bool,
    pub subscriptions: Vec<Subscription>,
}

impl Default for InboxConfig {
    fn default() -> Self {
        Self {
            accounts: vec![Account {
                name: "default".into(),
                imap_host: "imap.gmail.com".into(),
                imap_port: 993,
                user_env: "BRANA_GMAIL_USER".into(),
                password_env: "BRANA_GMAIL_APP_PASSWORD".into(),
                label: "Newsletters".into(),
                enabled: true,
                subscriptions: Vec::new(),
            }],
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

fn inbox_state_path(account: &str) -> PathBuf {
    dirs_home().join(format!(".claude/scheduler/state/inbox-{account}.json"))
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

fn load_state(account: &str) -> InboxState {
    let path = inbox_state_path(account);
    match fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_default(),
        Err(_) => InboxState::default(),
    }
}

fn save_state(account: &str, state: &InboxState) -> Result<()> {
    ensure_state_dir();
    let path = inbox_state_path(account);
    let tmp = path.with_extension("tmp");
    let json = serde_json::to_string_pretty(state)?;
    fs::write(&tmp, &json)?;
    fs::rename(&tmp, &path)?;
    Ok(())
}

// ── Commands ────────────────────────────────────────────────────────────

pub fn cmd_inbox(cmd: InboxCmd) {
    let result = match cmd {
        InboxCmd::Add { name, from, frequency, account } => cmd_add(&name, &from, &frequency, account.as_deref()),
        InboxCmd::List => cmd_list(),
        InboxCmd::Poll { label, account } => cmd_poll(label.as_deref(), account.as_deref()),
        InboxCmd::Remove { name } => cmd_remove(&name),
        InboxCmd::Status => cmd_status(),
        InboxCmd::AddAccount { name, user_env, pass_env, label } => cmd_add_account(&name, &user_env, &pass_env, &label),
    };
    if let Err(e) = result {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn find_account_mut<'a>(config: &'a mut InboxConfig, name: Option<&str>) -> Result<&'a mut Account> {
    match name {
        Some(n) => config.accounts.iter_mut()
            .find(|a| a.name == n)
            .with_context(|| format!("account '{n}' not found")),
        None => config.accounts.first_mut()
            .context("no accounts configured — run `brana inbox add-account` first"),
    }
}

fn cmd_add_account(name: &str, user_env: &str, pass_env: &str, label: &str) -> Result<()> {
    let mut config = load_config();
    if config.accounts.iter().any(|a| a.name == name) {
        anyhow::bail!("account '{name}' already exists");
    }
    config.accounts.push(Account {
        name: name.to_string(),
        imap_host: "imap.gmail.com".into(),
        imap_port: 993,
        user_env: user_env.to_string(),
        password_env: pass_env.to_string(),
        label: label.to_string(),
        enabled: true,
        subscriptions: Vec::new(),
    });
    save_config(&config)?;
    println!("{{\"ok\":true,\"account\":\"{name}\",\"user_env\":\"{user_env}\",\"pass_env\":\"{pass_env}\"}}");
    Ok(())
}

fn cmd_add(name: &str, from: &str, frequency: &str, account: Option<&str>) -> Result<()> {
    let valid = ["daily", "weekly", "monthly"];
    if !valid.contains(&frequency) {
        anyhow::bail!("frequency must be daily, weekly, or monthly — got '{frequency}'");
    }

    let mut config = load_config();

    // Check across all accounts for duplicate
    if config.accounts.iter().any(|a| a.subscriptions.iter().any(|s| s.name == name)) {
        anyhow::bail!("subscription '{name}' already exists");
    }

    let acct = find_account_mut(&mut config, account)?;
    acct.subscriptions.push(Subscription {
        name: name.to_string(),
        from: from.to_string(),
        frequency: frequency.to_string(),
        enabled: true,
    });
    let acct_name = acct.name.clone();
    save_config(&config)?;

    println!("{{\"ok\":true,\"name\":\"{name}\",\"from\":\"{from}\",\"frequency\":\"{frequency}\",\"account\":\"{acct_name}\"}}");
    Ok(())
}

fn cmd_list() -> Result<()> {
    let config = load_config();
    let result: Vec<_> = config.accounts.iter().map(|a| {
        serde_json::json!({
            "account": a.name,
            "enabled": a.enabled,
            "label": a.label,
            "subscriptions": a.subscriptions,
        })
    }).collect();
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

fn cmd_remove(name: &str) -> Result<()> {
    let mut config = load_config();
    let mut found = false;
    for acct in &mut config.accounts {
        let before = acct.subscriptions.len();
        acct.subscriptions.retain(|s| s.name != name);
        if acct.subscriptions.len() < before { found = true; }
    }
    if !found {
        anyhow::bail!("subscription '{name}' not found in any account");
    }
    save_config(&config)?;
    println!("{{\"ok\":true,\"removed\":\"{name}\"}}");
    Ok(())
}

fn cmd_status() -> Result<()> {
    let config = load_config();
    let mut results = Vec::new();
    for acct in &config.accounts {
        let state = load_state(&acct.name);
        results.push(serde_json::json!({
            "account": acct.name,
            "enabled": acct.enabled,
            "subscriptions": acct.subscriptions.len(),
            "last_poll": state.last_poll,
            "last_uid": state.last_uid,
            "unmatched_count": state.unmatched_count,
            "details": acct.subscriptions.iter().map(|s| {
                serde_json::json!({
                    "name": s.name,
                    "from": s.from,
                    "frequency": s.frequency,
                    "enabled": s.enabled,
                })
            }).collect::<Vec<_>>(),
        }));
    }
    println!("{}", serde_json::to_string_pretty(&results)?);
    Ok(())
}

fn cmd_poll(label_override: Option<&str>, account_filter: Option<&str>) -> Result<()> {
    let config = load_config();
    let targets: Vec<&Account> = match account_filter {
        Some(name) => {
            let acct = config.accounts.iter().find(|a| a.name == name)
                .with_context(|| format!("account '{name}' not found"))?;
            vec![acct]
        }
        None => config.accounts.iter().filter(|a| a.enabled).collect(),
    };

    let mut all_results = Vec::new();
    for acct in targets {
        match poll_account(acct, label_override) {
            Ok(result) => all_results.push(result),
            Err(e) => {
                all_results.push(serde_json::json!({
                    "account": acct.name,
                    "new_emails": 0,
                    "matched": 0,
                    "unmatched": 0,
                    "status": "error",
                    "error": format!("{e:#}"),
                }));
            }
        }
    }

    println!("{}", serde_json::to_string_pretty(&all_results)?);
    Ok(())
}

fn poll_account(acct: &Account, label_override: Option<&str>) -> Result<serde_json::Value> {
    let mut state = load_state(&acct.name);
    let label = label_override.unwrap_or(&acct.label);

    // Read credentials from env
    let user = std::env::var(&acct.user_env)
        .with_context(|| format!("set {} env var with your Gmail address", acct.user_env))?;
    let password = std::env::var(&acct.password_env)
        .with_context(|| format!("set {} env var with your Gmail App Password", acct.password_env))?;

    // Connect via IMAP over TLS
    let tls = native_tls::TlsConnector::builder().build()
        .context("building TLS connector")?;
    let client = imap::connect(
        (&*acct.imap_host, acct.imap_port),
        &acct.imap_host,
        &tls,
    ).context("connecting to IMAP server")?;

    let mut session = client.login(&user, &password)
        .map_err(|e| anyhow::anyhow!("IMAP login failed for {}: {}", acct.name, e.0))?;

    // Select the label/folder
    let mailbox_name = format!("[Gmail]/{label}");
    let _mailbox = session.select(&mailbox_name)
        .or_else(|_| session.select(label))
        .with_context(|| format!("selecting mailbox '{label}' on account '{}'", acct.name))?;

    // Search for unseen messages
    let uids = session.uid_search("UNSEEN")
        .context("searching for unseen messages")?;

    if uids.is_empty() {
        state.last_poll = Some(Utc::now().to_rfc3339());
        state.unmatched_count = 0;
        save_state(&acct.name, &state)?;
        session.logout().ok();
        return Ok(serde_json::json!({
            "account": acct.name, "new_emails": 0, "matched": 0, "unmatched": 0, "status": "ok"
        }));
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

        let sub_match = acct.subscriptions.iter()
            .find(|s| s.enabled && from.to_lowercase().contains(&s.from.to_lowercase()));

        let is_matched = sub_match.is_some();
        if is_matched { matched += 1; } else { unmatched += 1; }

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

        if let Some(uid) = msg.uid {
            if uid > state.last_uid {
                state.last_uid = uid;
            }
        }
    }

    state.last_poll = Some(Utc::now().to_rfc3339());
    state.unmatched_count = unmatched;
    save_state(&acct.name, &state)?;
    session.logout().ok();

    Ok(serde_json::json!({
        "account": acct.name,
        "new_emails": uids.len(),
        "matched": matched,
        "unmatched": unmatched,
        "status": "ok",
    }))
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

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::env;

    /// Must be used with #[serial] — env::set_var is process-global.
    fn with_temp_home() -> tempfile::TempDir {
        let tmp = tempfile::tempdir().unwrap();
        // SAFETY: all callers are #[serial], so no concurrent env mutation
        unsafe { env::set_var("HOME", tmp.path()) };
        tmp
    }

    #[test]
    fn test_inbox_config_default() {
        let config = InboxConfig::default();
        assert_eq!(config.accounts.len(), 1);
        let acct = &config.accounts[0];
        assert_eq!(acct.name, "default");
        assert_eq!(acct.imap_host, "imap.gmail.com");
        assert_eq!(acct.imap_port, 993);
        assert_eq!(acct.user_env, "BRANA_GMAIL_USER");
        assert_eq!(acct.password_env, "BRANA_GMAIL_APP_PASSWORD");
        assert_eq!(acct.label, "Newsletters");
        assert!(acct.subscriptions.is_empty());
    }

    #[test]
    #[serial]
    fn test_subscription_crud() {
        let _tmp = with_temp_home();

        // Default has one account with empty subs
        let config = load_config();
        assert!(config.accounts[0].subscriptions.is_empty());

        // Add subscription to first account
        let mut config = load_config();
        config.accounts[0].subscriptions.push(Subscription {
            name: "test-sub".into(),
            from: "test@example.com".into(),
            frequency: "weekly".into(),
            enabled: true,
        });
        save_config(&config).unwrap();

        // Verify persisted
        let config = load_config();
        assert_eq!(config.accounts[0].subscriptions.len(), 1);
        assert_eq!(config.accounts[0].subscriptions[0].name, "test-sub");
        assert_eq!(config.accounts[0].subscriptions[0].from, "test@example.com");

        // Remove
        let mut config = load_config();
        config.accounts[0].subscriptions.retain(|s| s.name != "test-sub");
        save_config(&config).unwrap();
        assert!(load_config().accounts[0].subscriptions.is_empty());
    }

    #[test]
    fn test_multi_account_config() {
        let _tmp = with_temp_home();

        let mut config = load_config();
        config.accounts.push(Account {
            name: "work".into(),
            imap_host: "imap.gmail.com".into(),
            imap_port: 993,
            user_env: "BRANA_WORK_USER".into(),
            password_env: "BRANA_WORK_PASS".into(),
            label: "Newsletters".into(),
            enabled: true,
            subscriptions: vec![],
        });
        save_config(&config).unwrap();

        let loaded = load_config();
        assert_eq!(loaded.accounts.len(), 2);
        assert_eq!(loaded.accounts[0].name, "default");
        assert_eq!(loaded.accounts[1].name, "work");
        assert_eq!(loaded.accounts[1].user_env, "BRANA_WORK_USER");
    }

    #[test]
    #[serial]
    fn test_inbox_state_roundtrip() {
        let _tmp = with_temp_home();

        let state = InboxState {
            last_poll: Some("2026-03-19T16:00:00Z".into()),
            last_uid: 4523,
            unmatched_count: 2,
        };
        save_state("default", &state).unwrap();

        let loaded = load_state("default");
        assert_eq!(loaded.last_uid, 4523);
        assert_eq!(loaded.unmatched_count, 2);
        assert_eq!(loaded.last_poll, Some("2026-03-19T16:00:00Z".into()));
    }

    #[test]
    #[serial]
    fn test_per_account_state_isolation() {
        let _tmp = with_temp_home();

        let state1 = InboxState { last_poll: None, last_uid: 100, unmatched_count: 0 };
        let state2 = InboxState { last_poll: None, last_uid: 200, unmatched_count: 3 };
        save_state("personal", &state1).unwrap();
        save_state("work", &state2).unwrap();

        assert_eq!(load_state("personal").last_uid, 100);
        assert_eq!(load_state("work").last_uid, 200);
    }

    #[test]
    #[serial]
    fn test_inbox_state_missing_returns_default() {
        let _tmp = with_temp_home();
        let state = load_state("nonexistent");
        assert!(state.last_poll.is_none());
        assert_eq!(state.last_uid, 0);
        assert_eq!(state.unmatched_count, 0);
    }

    #[test]
    fn test_extract_header_from() {
        let headers = "From: ben@stratechery.com\r\nSubject: Weekly Article\r\nDate: Wed, 19 Mar 2026 10:00:00 +0000\r\n";
        assert_eq!(extract_header(headers, "From"), "ben@stratechery.com");
        assert_eq!(extract_header(headers, "Subject"), "Weekly Article");
        assert_eq!(extract_header(headers, "Date"), "Wed, 19 Mar 2026 10:00:00 +0000");
    }

    #[test]
    fn test_extract_header_case_insensitive() {
        let headers = "from: test@example.com\r\nSUBJECT: Test\r\n";
        assert_eq!(extract_header(headers, "From"), "test@example.com");
        assert_eq!(extract_header(headers, "Subject"), "Test");
    }

    #[test]
    fn test_extract_header_missing() {
        let headers = "From: test@example.com\r\n";
        assert_eq!(extract_header(headers, "Subject"), "");
    }

    #[test]
    fn test_subscription_matching() {
        let subs = vec![
            Subscription {
                name: "stratechery".into(),
                from: "ben@stratechery.com".into(),
                frequency: "weekly".into(),
                enabled: true,
            },
            Subscription {
                name: "disabled-sub".into(),
                from: "no@example.com".into(),
                frequency: "daily".into(),
                enabled: false,
            },
        ];

        // Match by from (case-insensitive, contains)
        let from = "Ben Thompson <ben@stratechery.com>";
        let matched = subs.iter()
            .find(|s| s.enabled && from.to_lowercase().contains(&s.from.to_lowercase()));
        assert!(matched.is_some());
        assert_eq!(matched.unwrap().name, "stratechery");

        // Disabled sub doesn't match
        let from2 = "no@example.com";
        let matched2 = subs.iter()
            .find(|s| s.enabled && from2.to_lowercase().contains(&s.from.to_lowercase()));
        assert!(matched2.is_none());

        // No match
        let from3 = "unknown@other.com";
        let matched3 = subs.iter()
            .find(|s| s.enabled && from3.to_lowercase().contains(&s.from.to_lowercase()));
        assert!(matched3.is_none());
    }

    #[test]
    fn test_inbox_log_entry_serialization() {
        let entry = InboxLogEntry {
            subscription: Some("stratechery".into()),
            from: "ben@stratechery.com".into(),
            subject: "Weekly Article".into(),
            date: "2026-03-19".into(),
            matched: true,
            polled_at: "2026-03-19T16:00:00Z".into(),
        };
        let json = serde_json::to_string(&entry).unwrap();
        assert!(json.contains("\"matched\":true"));

        let parsed: InboxLogEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.subscription, Some("stratechery".into()));
    }

    #[test]
    #[serial]
    fn test_config_preserves_imap_settings() {
        let _tmp = with_temp_home();

        let mut config = InboxConfig::default();
        config.accounts[0].label = "CustomLabel".into();
        config.accounts[0].subscriptions.push(Subscription {
            name: "test".into(),
            from: "a@b.com".into(),
            frequency: "daily".into(),
            enabled: true,
        });
        save_config(&config).unwrap();

        let loaded = load_config();
        assert_eq!(loaded.accounts[0].imap_host, "imap.gmail.com");
        assert_eq!(loaded.accounts[0].label, "CustomLabel");
        assert_eq!(loaded.accounts[0].subscriptions.len(), 1);
    }
}
