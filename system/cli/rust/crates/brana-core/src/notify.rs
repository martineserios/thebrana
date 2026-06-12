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
