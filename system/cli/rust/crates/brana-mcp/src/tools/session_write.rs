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
            // Synchronous git subprocess call + file write (archive, validate,
            // atomic rename) run off the async executor (t-2631): a handler
            // that blocks the tokio worker running pmcp's single, fully-
            // serialized stdio dispatch task (t-2305) freezes every other
            // tool for its duration — this is a write path, not just a read.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
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
                    .map_err(|e| format!("invalid session payload: {e}"))?;

                // Find project root
                let root = brana_core::util::find_project_root()
                    .ok_or_else(|| "not in a git repository".to_string())?;

                // Write (archives previous, validates, atomic rename).
                // A `base_written_at` on the payload acts as a compare-and-swap token and is
                // picked up by write_state → write_state_with_base (t-2506).
                let report = session::write_state(&root, &state).map_err(|e| e.to_string())?;

                let branch = state.branch.as_deref().unwrap_or("");
                let state_path = session::epic_scoped_state_path(&root, branch);
                // next[] accounting is always reported: a caller must be able to see that
                // what it submitted is not what landed (t-2506 — this write path previously
                // returned a bare ok:true while silently discarding entries).
                Ok(serde_json::json!({
                    "ok": true,
                    "written_at": state.written_at,
                    "path": state_path.to_string_lossy(),
                    "next": report.next_json(),
                    "warning": report.warning(),
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Write the current session state. Accepts a session-state JSON payload. Auto-fills written_at and branch. Archives the previous state before writing. Returns next[] accounting (incoming/written/dropped_duplicates/retained_from_existing/mode) plus a warning when entries were dropped or a concurrent write forced a union — check it, the counts are the only signal that what you submitted is not what landed. Pass base_written_at (the written_at you read) to make next[] authoritative so entries can be corrected and withdrawn.")
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;

    /// RAII guard: isolates HOME and CLAUDE_PROJECT_DIR to a tempdir, so
    /// session state writes never touch the real `~/.claude/projects/...`
    /// tree. Callers must hold CWD_LOCK for its lifetime.
    struct Hermetic {
        orig_home: Option<String>,
        orig_project_dir: Option<String>,
        _dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let project_root = dir.path().join("project");
            std::fs::create_dir_all(&project_root).unwrap();

            let orig_home = std::env::var("HOME").ok();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            // SAFETY: caller holds CWD_LOCK; no other test in this binary
            // reads or writes these env vars concurrently.
            unsafe {
                std::env::set_var("HOME", dir.path());
                std::env::set_var("CLAUDE_PROJECT_DIR", &project_root);
            }

            Self { orig_home, orig_project_dir, _dir: dir }
        }
    }

    impl Drop for Hermetic {
        fn drop(&mut self) {
            // SAFETY: still under CWD_LOCK.
            unsafe {
                match &self.orig_home {
                    Some(v) => std::env::set_var("HOME", v),
                    None => std::env::remove_var("HOME"),
                }
                match &self.orig_project_dir {
                    Some(v) => std::env::set_var("CLAUDE_PROJECT_DIR", v),
                    None => std::env::remove_var("CLAUDE_PROJECT_DIR"),
                }
            }
        }
    }

    /// t-2631 (Challenger iteration 2 follow-up): session_write is a write
    /// path, one of the two highest-cost instances of the spawn_blocking
    /// sweep — this locks in that it still writes correct state after the
    /// refactor. `branch` is supplied explicitly so the test never shells
    /// out to git for auto-fill.
    #[tokio::test]
    async fn test_write_session_state_persists_and_reports_next() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new();

        let out = build()
            .handle(
                json!({"payload": {"version": 1, "branch": "test/fix/t-0000-dummy", "accomplished": ["did a thing"]}}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("write must succeed");

        assert_eq!(out["ok"], true);
        assert!(!out["written_at"].as_str().unwrap_or("").is_empty(), "written_at must be auto-filled");
        let path = out["path"].as_str().expect("path must be a string");
        assert!(std::path::Path::new(path).exists(), "state file must actually exist on disk: {path}");
    }
}
