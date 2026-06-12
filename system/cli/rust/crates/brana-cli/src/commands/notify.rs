//! `brana notify` — CLI surface for delivery channel notifications (t-1998, ADR-054).

use anyhow::{Result, anyhow};
use brana_core::notify::{self, Channel};
use std::path::PathBuf;

/// Registry lives per-user, cross-project: `~/.claude/notify-channels.json`.
pub fn registry_path() -> PathBuf {
    brana_core::util::home().join(".claude").join("notify-channels.json")
}

pub fn cmd_send(channel: &str, message: &str) -> Result<()> {
    let reg_path = registry_path();
    let reg = notify::load_registry(&reg_path)
        .ok_or_else(|| anyhow!("Failed to load notify registry from {}", reg_path.display()))?;
    
    let def = reg.channels.get(channel)
        .ok_or_else(|| anyhow!("Channel '{}' not found in registry", channel))?;
        
    let ch = Channel {
        name: channel.to_string(),
        def: def.clone(),
    };
    
    let res = notify::send(&ch, message);
    println!("{}", serde_json::to_string_pretty(&res)?);
    
    match res {
        notify::DispatchResult::Sent => Ok(()),
        notify::DispatchResult::Failed { reason } => Err(anyhow!("Dispatch failed: {reason}")),
    }
}

pub fn cmd_channels() -> Result<()> {
    // ADR-054 §4: list channels + routing defaults. Missing registry is not
    // an error — same graceful degradation as dispatch (empty output).
    match notify::load_registry(&registry_path()) {
        Some(reg) => println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "channels": reg.channels,
                "defaults": reg.defaults,
            }))?
        ),
        None => println!("{{\"channels\":{{}},\"defaults\":{{}}}}"),
    }
    Ok(())
}
