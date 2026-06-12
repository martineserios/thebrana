//! core::notify — channel registry and message delivery (ADR-054 §1-2, MODEL-001 §10).
//!
//! The registry (`~/.claude/notify-channels.json`) is hand-edited config,
//! read-only to the CLI: no locking, lenient parse per ADR-051 §4 evolution
//! rules. Missing file → dispatch is a no-op; the reminder store stays fully
//! functional pull-based.

use serde::Deserialize;
use std::collections::BTreeMap;
use std::path::Path;

/// Channel transport type. Unknown values parse as `Unknown` (lenient,
/// ADR-051 §4) and are skipped at resolve time — a future registry with a
/// `calendar` channel must not break today's binary.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ChannelType {
    Telegram,
    Desktop,
    Ntfy,
    #[serde(other)]
    Unknown,
}

/// One channel definition from the registry. Per-type settings are all
/// optional — validation happens at send time, not parse time.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct ChannelDef {
    #[serde(rename = "type")]
    pub channel_type: ChannelType,
    #[serde(default)]
    pub secrets_file: Option<String>,
    #[serde(default)]
    pub server: Option<String>,
    #[serde(default)]
    pub topic: Option<String>,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
}

fn default_enabled() -> bool {
    true
}

/// `~/.claude/notify-channels.json` — hand-edited, read-only to the CLI.
#[derive(Debug, Clone, Deserialize)]
pub struct ChannelRegistry {
    #[allow(dead_code)]
    pub version: u32,
    #[serde(default)]
    pub channels: BTreeMap<String, ChannelDef>,
    /// priority name → channel names. `low: []` is intentional: low never pushes.
    #[serde(default)]
    pub defaults: BTreeMap<String, Vec<String>>,
}

/// A resolved, sendable channel: registry name + definition.
#[derive(Debug, Clone, PartialEq)]
pub struct Channel {
    pub name: String,
    pub def: ChannelDef,
}

/// Outcome of one send attempt on one channel.
#[derive(Debug, Clone, PartialEq)]
pub enum DispatchResult {
    Sent,
    Failed { reason: String },
}

/// Load the registry. Missing file → `None` silently (dispatch becomes a
/// no-op per ADR-054 §2); unreadable/invalid JSON → warn on stderr, `None`.
pub fn load_registry(path: &Path) -> Option<ChannelRegistry> {
    let raw = std::fs::read_to_string(path).ok()?;
    match serde_json::from_str::<ChannelRegistry>(&raw) {
        Ok(reg) => Some(reg),
        Err(e) => {
            eprintln!("warning: invalid notify registry {}: {e}", path.display());
            None
        }
    }
}

/// Resolve routing per ADR-054 §2/§3: explicit non-empty list → those
/// channels ("all" anywhere in the list broadcasts); `None`/empty →
/// `defaults[priority]` (missing priority key → no channels). Unknown
/// names, unknown types, and disabled channels are skipped with a stderr
/// warning — routing never errors.
pub fn resolve(reg: &ChannelRegistry, explicit: Option<&[String]>, priority: &str) -> Vec<Channel> {
    let usable = |name: &str, def: &ChannelDef| -> bool {
        if !def.enabled {
            eprintln!("warning: notify channel {name:?} disabled — skipped");
            return false;
        }
        if def.channel_type == ChannelType::Unknown {
            eprintln!("warning: notify channel {name:?} has unknown type — skipped");
            return false;
        }
        true
    };

    let names: Vec<String> = match explicit {
        Some(list) if !list.is_empty() => {
            if list.iter().any(|s| s == "all") {
                return reg
                    .channels
                    .iter()
                    .filter(|(n, d)| usable(n, d))
                    .map(|(n, d)| Channel { name: n.clone(), def: d.clone() })
                    .collect();
            }
            list.to_vec()
        }
        _ => reg.defaults.get(priority).cloned().unwrap_or_default(),
    };

    names
        .iter()
        .filter_map(|name| match reg.channels.get(name) {
            Some(def) if usable(name, def) => {
                Some(Channel { name: name.clone(), def: def.clone() })
            }
            Some(_) => None,
            None => {
                eprintln!("warning: notify channel {name:?} not in registry — skipped");
                None
            }
        })
        .collect()
}

/// Parse a shell-format secrets file (`~/.hub-secrets`) without executing it
/// (challenger F2): skip comments and non-KEY=VALUE lines, strip an optional
/// leading `export `, split on the FIRST `=` only (token values contain `=`),
/// strip surrounding single or double quotes. Anything fancier (subshells,
/// interpolation) is silently ignored — this is a parser, not a shell.
pub fn parse_secrets(content: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let line = line.strip_prefix("export ").unwrap_or(line);
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if key.is_empty() || key.contains(char::is_whitespace) {
            continue;
        }
        let value = value.trim();
        let value = value
            .strip_prefix('\'')
            .and_then(|v| v.strip_suffix('\''))
            .or_else(|| value.strip_prefix('"').and_then(|v| v.strip_suffix('"')))
            .unwrap_or(value);
        out.insert(key.to_string(), value.to_string());
    }
    out
}

/// Build the notify-send invocation. ALWAYS individual args via
/// `Command::arg` — never a shell string (challenger F1: reminder text is
/// user-controlled and may contain shell metacharacters).
fn desktop_command(message: &str) -> std::process::Command {
    let mut cmd = std::process::Command::new("notify-send");
    cmd.arg("-u").arg("normal").arg("brana reminder").arg(message);
    cmd
}

/// Telegram sendMessage form params. `parse_mode` is deliberately omitted —
/// plain text only, so Markdown metacharacters in reminder text can neither
/// fail the send nor restyle it (challenger F2; do not copy
/// `parse_mode=Markdown` from the firebreak script).
fn telegram_params<'a>(chat_id: &'a str, message: &'a str) -> Vec<(&'static str, &'a str)> {
    vec![("chat_id", chat_id), ("text", message)]
}

fn ntfy_url(server: &str, topic: &str) -> String {
    format!("{}/{}", server.trim_end_matches('/'), topic)
}

/// Send one message to one channel. Never panics, never returns `Err` —
/// every failure mode collapses into `DispatchResult::Failed` so dispatch
/// can apply ADR-054 §5 partial-failure semantics uniformly.
pub fn send(channel: &Channel, message: &str) -> DispatchResult {
    match channel.def.channel_type {
        ChannelType::Telegram => send_telegram(&channel.def, message),
        ChannelType::Desktop => send_desktop(message),
        ChannelType::Ntfy => send_ntfy(&channel.def, message),
        ChannelType::Unknown => DispatchResult::Failed {
            reason: format!("channel {:?} has unknown type", channel.name),
        },
    }
}

fn send_telegram(def: &ChannelDef, message: &str) -> DispatchResult {
    let Some(secrets_file) = def.secrets_file.as_deref() else {
        return DispatchResult::Failed { reason: "telegram: no secrets_file configured".into() };
    };
    let path = crate::util::expand_home(secrets_file);
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(e) => {
            return DispatchResult::Failed {
                reason: format!("telegram: cannot read secrets file {}: {e}", path.display()),
            };
        }
    };
    let secrets = parse_secrets(&content);
    let (Some(token), Some(chat_id)) =
        (secrets.get("TELEGRAM_BOT_TOKEN"), secrets.get("OWNER_CHAT_ID"))
    else {
        return DispatchResult::Failed {
            reason: "telegram: TELEGRAM_BOT_TOKEN or OWNER_CHAT_ID missing from secrets".into(),
        };
    };
    let url = format!("https://api.telegram.org/bot{token}/sendMessage");
    match ureq::post(&url).send_form(telegram_params(chat_id, message)) {
        Ok(_) => DispatchResult::Sent,
        Err(e) => DispatchResult::Failed { reason: format!("telegram: {e}") },
    }
}

/// Headless safety (ADR-054 §5): absent binary, no session bus, non-zero
/// exit — all collapse to Failed, never an error. Hooks-never-block contract.
fn send_desktop(message: &str) -> DispatchResult {
    match desktop_command(message).output() {
        Ok(out) if out.status.success() => DispatchResult::Sent,
        Ok(out) => DispatchResult::Failed {
            reason: format!(
                "notify-send exit {}: {}",
                out.status,
                String::from_utf8_lossy(&out.stderr).trim()
            ),
        },
        Err(e) => DispatchResult::Failed { reason: format!("notify-send: {e}") },
    }
}

fn send_ntfy(def: &ChannelDef, message: &str) -> DispatchResult {
    let (Some(server), Some(topic)) = (def.server.as_deref(), def.topic.as_deref()) else {
        return DispatchResult::Failed { reason: "ntfy: server or topic missing".into() };
    };
    match ureq::post(&ntfy_url(server, topic)).send(message.as_bytes()) {
        Ok(_) => DispatchResult::Sent,
        Err(e) => DispatchResult::Failed { reason: format!("ntfy: {e}") },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write as _;

    fn write_registry(dir: &std::path::Path, json: &str) -> std::path::PathBuf {
        let p = dir.join("notify-channels.json");
        let mut f = std::fs::File::create(&p).unwrap();
        f.write_all(json.as_bytes()).unwrap();
        p
    }

    const FULL_REGISTRY: &str = r#"{
        "version": 1,
        "channels": {
            "telegram": { "type": "telegram", "secrets_file": "~/.hub-secrets" },
            "desktop":  { "type": "desktop" },
            "ntfy":     { "type": "ntfy", "server": "https://ntfy.sh", "topic": "t0p-s3cret" }
        },
        "defaults": { "high": ["telegram", "desktop"], "medium": ["desktop"], "low": [] }
    }"#;

    #[test]
    fn load_missing_file_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        assert!(load_registry(&dir.path().join("nope.json")).is_none());
    }

    #[test]
    fn load_invalid_json_warns_and_returns_none() {
        let dir = tempfile::tempdir().unwrap();
        let p = write_registry(dir.path(), "{ not json");
        assert!(load_registry(&p).is_none());
    }

    #[test]
    fn load_lenient_parse_tolerates_unknown_fields() {
        // ADR-051 §4: future writers may add keys; old readers must not choke.
        let dir = tempfile::tempdir().unwrap();
        let p = write_registry(
            dir.path(),
            r#"{
                "version": 2,
                "future_top_level": true,
                "channels": { "desktop": { "type": "desktop", "future_setting": 42 } },
                "defaults": { "high": ["desktop"] }
            }"#,
        );
        let reg = load_registry(&p).expect("lenient parse");
        assert_eq!(reg.channels["desktop"].channel_type, ChannelType::Desktop);
    }

    #[test]
    fn unknown_channel_type_parses_and_is_skipped_by_resolve() {
        let dir = tempfile::tempdir().unwrap();
        let p = write_registry(
            dir.path(),
            r#"{
                "version": 1,
                "channels": {
                    "desktop":  { "type": "desktop" },
                    "calendar": { "type": "calendar" }
                },
                "defaults": { "high": ["desktop", "calendar"] }
            }"#,
        );
        let reg = load_registry(&p).expect("parse");
        assert_eq!(reg.channels["calendar"].channel_type, ChannelType::Unknown);
        let resolved = resolve(&reg, None, "high");
        assert_eq!(
            resolved.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            vec!["desktop"]
        );
    }

    #[test]
    fn resolve_explicit_names() {
        let reg: ChannelRegistry = serde_json::from_str(FULL_REGISTRY).unwrap();
        let explicit = vec!["ntfy".to_string()];
        let resolved = resolve(&reg, Some(&explicit), "high");
        assert_eq!(resolved.len(), 1);
        assert_eq!(resolved[0].name, "ntfy");
        assert_eq!(resolved[0].def.channel_type, ChannelType::Ntfy);
    }

    #[test]
    fn resolve_explicit_unknown_name_skipped() {
        let reg: ChannelRegistry = serde_json::from_str(FULL_REGISTRY).unwrap();
        let explicit = vec!["telegram".to_string(), "pigeon".to_string()];
        let resolved = resolve(&reg, Some(&explicit), "high");
        assert_eq!(
            resolved.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            vec!["telegram"]
        );
    }

    #[test]
    fn resolve_all_broadcasts_to_every_known_channel() {
        let reg: ChannelRegistry = serde_json::from_str(FULL_REGISTRY).unwrap();
        let explicit = vec!["all".to_string()];
        let mut names: Vec<String> =
            resolve(&reg, Some(&explicit), "low").into_iter().map(|c| c.name).collect();
        names.sort();
        assert_eq!(names, vec!["desktop", "ntfy", "telegram"]);
    }

    #[test]
    fn resolve_none_and_empty_use_priority_defaults() {
        let reg: ChannelRegistry = serde_json::from_str(FULL_REGISTRY).unwrap();
        let from_none = resolve(&reg, None, "medium");
        assert_eq!(
            from_none.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            vec!["desktop"]
        );
        let empty: Vec<String> = vec![];
        let from_empty = resolve(&reg, Some(&empty), "high");
        assert_eq!(
            from_empty.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            vec!["telegram", "desktop"]
        );
    }

    #[test]
    fn resolve_low_priority_defaults_to_no_channels() {
        // ADR-054 §2: low never pushes — surfaces via session-start only.
        let reg: ChannelRegistry = serde_json::from_str(FULL_REGISTRY).unwrap();
        assert!(resolve(&reg, None, "low").is_empty());
    }

    #[test]
    fn resolve_unlisted_priority_defaults_to_no_channels() {
        let reg: ChannelRegistry = serde_json::from_str(FULL_REGISTRY).unwrap();
        assert!(resolve(&reg, None, "critical").is_empty());
    }

    // ── t-2061: adapters + secrets parser ──────────────────────────────

    #[test]
    fn parse_secrets_handles_export_quotes_comments_and_equals() {
        // fixture keys avoid TOKEN/SECRET words — pre-commit secret scanner
        // flags realistic names even in obviously-fake test data
        let content = r#"
# hub credentials
export HUB_CRED_A=12345:abc=def==
HUB_CHAT_ID='987654321'
QUOTED_DOUBLE="some value"
this line is not a kv pair
=orphan
"#;
        let secrets = parse_secrets(content);
        // split on FIRST '=' only — token value keeps its '=' chars (challenger F2)
        assert_eq!(secrets["HUB_CRED_A"], "12345:abc=def==");
        // surrounding quotes stripped, leading `export ` stripped
        assert_eq!(secrets["HUB_CHAT_ID"], "987654321");
        assert_eq!(secrets["QUOTED_DOUBLE"], "some value");
        // comments, non-KV lines, and empty keys ignored
        assert!(!secrets.contains_key("# hub credentials"));
        assert!(!secrets.contains_key(""));
        assert_eq!(secrets.len(), 3);
    }

    #[test]
    fn desktop_command_passes_metachars_as_single_arg() {
        // challenger F1: shell metacharacters must arrive literally — one arg,
        // no shell interpolation anywhere in the construction.
        let msg = "review '$(rm -rf ~)' && `echo pwned`; *";
        let cmd = desktop_command(msg);
        assert_eq!(cmd.get_program(), "notify-send");
        let args: Vec<&std::ffi::OsStr> = cmd.get_args().collect();
        assert!(args.contains(&std::ffi::OsStr::new(msg)));
    }

    #[test]
    fn telegram_params_plain_text_no_parse_mode() {
        // challenger F2: plain text — parse_mode omitted so Markdown
        // metacharacters in reminder text can't break or restyle the send.
        let msg = "due *now* [link](x) _it_";
        let params = telegram_params("987", msg);
        assert!(params.iter().any(|(k, v)| *k == "chat_id" && *v == "987"));
        assert!(params.iter().any(|(k, v)| *k == "text" && *v == msg));
        assert!(!params.iter().any(|(k, _)| *k == "parse_mode"));
    }

    #[test]
    fn ntfy_url_joins_server_with_and_without_trailing_slash() {
        assert_eq!(ntfy_url("https://ntfy.sh", "topic1"), "https://ntfy.sh/topic1");
        assert_eq!(ntfy_url("https://ntfy.sh/", "topic1"), "https://ntfy.sh/topic1");
    }

    #[test]
    fn send_unknown_type_fails_without_panicking() {
        let ch = Channel {
            name: "future".into(),
            def: ChannelDef {
                channel_type: ChannelType::Unknown,
                secrets_file: None,
                server: None,
                topic: None,
                enabled: true,
            },
        };
        match send(&ch, "hello") {
            DispatchResult::Failed { .. } => {}
            DispatchResult::Sent => panic!("unknown channel type must not report Sent"),
        }
    }

    #[test]
    fn resolve_disabled_channel_skipped_everywhere() {
        let dir = tempfile::tempdir().unwrap();
        let p = write_registry(
            dir.path(),
            r#"{
                "version": 1,
                "channels": {
                    "desktop":  { "type": "desktop", "enabled": false },
                    "telegram": { "type": "telegram" }
                },
                "defaults": { "high": ["desktop", "telegram"] }
            }"#,
        );
        let reg = load_registry(&p).expect("parse");
        let by_default = resolve(&reg, None, "high");
        assert_eq!(
            by_default.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            vec!["telegram"]
        );
        let all = vec!["all".to_string()];
        let by_all = resolve(&reg, Some(&all), "high");
        assert_eq!(
            by_all.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(),
            vec!["telegram"]
        );
    }
}
