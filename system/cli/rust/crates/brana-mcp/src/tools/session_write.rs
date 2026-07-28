//! session_write — write (or overwrite) the current session state.
//!
//! Accepts a full session-state payload as a JSON object.
//! Auto-fills `written_at` if missing/empty. Reads current git branch
//! to fill `branch` if absent. Archives the previous state before writing.

use brana_core::session;
use chrono::Utc;
use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Full session-state payload (JSON object). Must include `version: 1`.
    /// `written_at` is auto-filled if empty. `branch` is auto-filled from git.
    ///
    /// Set `base_written_at` to the `written_at` you read before composing this payload to
    /// make `next[]` authoritative — entries you omit are then removed, and changed text
    /// replaces the stored text. Without it `next[]` is unioned and nothing can be
    /// withdrawn. If another session wrote in between, the write falls back to union and
    /// says so in `warning` (t-2506).
    pub payload: serde_json::Value,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("session_write", |input: Input, _extra| {
        Box::pin(async move {
            let mut payload = input.payload;

            // Auto-fill written_at if missing or empty
            if payload.get("written_at").and_then(|v| v.as_str()).map(|s| s.is_empty()).unwrap_or(true) {
                payload["written_at"] = serde_json::Value::String(Utc::now().to_rfc3339());
            }

            // Auto-fill branch from git if absent
            if payload.get("branch").is_none() || payload["branch"].is_null() {
                if let Some(branch) = session::current_branch() {
                    payload["branch"] = serde_json::Value::String(branch);
                }
            }

            // Deserialize and validate
            let state: session::SessionState = serde_json::from_value(payload)
                .map_err(|e| pmcp::Error::validation(format!("invalid session payload: {e}")))?;

            // Find project root
            let root = brana_core::util::find_project_root()
                .ok_or_else(|| pmcp::Error::validation("not in a git repository"))?;

            // Write (archives previous, validates, atomic rename).
            // A `base_written_at` on the payload acts as a compare-and-swap token and is
            // picked up by write_state → write_state_with_base (t-2506).
            let report = session::write_state(&root, &state)
                .map_err(|e| pmcp::Error::validation(e.to_string()))?;

            let branch = state.branch.as_deref().unwrap_or("");
            let state_path = session::epic_scoped_state_path(&root, branch);
            // next[] accounting is always reported: a caller must be able to see that
            // what it submitted is not what landed (t-2506 — this write path previously
            // returned a bare ok:true while silently discarding entries).
            Ok(serde_json::json!({
                "ok": true,
                "written_at": state.written_at,
                "path": state_path.to_string_lossy(),
                "next": {
                    "incoming": report.next_incoming,
                    "written": report.next_written,
                    "dropped_duplicates": report.next_dropped_duplicates,
                    "retained_from_existing": report.next_retained,
                    "mode": report.next_mode.as_str(),
                },
                "warning": report.warning(),
            }))
        })
    })
    .with_description("Write the current session state. Accepts a session-state JSON payload. Auto-fills written_at and branch. Archives the previous state before writing. Returns next[] accounting (incoming/written/dropped_duplicates/retained_from_existing/mode) plus a warning when entries were dropped or a concurrent write forced a union — check it, the counts are the only signal that what you submitted is not what landed. Pass base_written_at (the written_at you read) to make next[] authoritative so entries can be corrected and withdrawn.")
}
