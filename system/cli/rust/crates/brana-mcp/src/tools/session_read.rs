//! session_read — read the current session state.
//!
//! Returns the full JSON state, or a single field if `field` is specified.
//! Returns `{"found": false}` if no session state exists yet.

use brana_core::session;
use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Optional: return only this field (e.g. "branch", "accomplished", "written_at").
    pub field: Option<String>,
    /// Optional: read by this explicit epic slug instead of guessing from the current git
    /// branch (pass "(orphan)" for the default/no-epic file). Mirrors the `epic` field
    /// session_write accepts on its payload — use it when you know, or want to force,
    /// which unit's state to read (t-3185).
    pub epic: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("session_read", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let root = brana_core::util::find_project_root()
                    .ok_or_else(|| "not in a git repository".to_string())?;

                // t-3185: read's mirror of write's unit-key routing — an explicit `epic`
                // (including the orphan sentinel) resolves by that unit, not by guessing
                // from the current branch. Omitted (the default): unchanged behavior.
                let resolved = match input.epic.as_deref() {
                    Some(slug) => {
                        let branch = session::current_branch().unwrap_or_default();
                        session::read_state_from_unit(&root, Some(slug), &branch)
                    }
                    None => session::read_state(&root),
                };

                match resolved {
                    None => Ok(serde_json::json!({ "found": false })),
                    Some(state) => {
                        let as_value = serde_json::to_value(&state).map_err(|e| e.to_string())?;

                        match input.field {
                            Some(ref f) => Ok(serde_json::json!({
                                "found": true,
                                "field": f,
                                "value": as_value[f],
                            })),
                            None => {
                                // Inject "found": true alongside the state
                                let mut result = serde_json::json!({ "found": true });
                                if let serde_json::Value::Object(map) = as_value {
                                    for (k, v) in map {
                                        result[k] = v;
                                    }
                                }
                                Ok(result)
                            }
                        }
                    }
                }
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Read the current session state. Returns the full JSON state or a specific field. Returns {found: false} when no state exists.")
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;

    /// RAII guard: isolates HOME and CLAUDE_PROJECT_DIR to a tempdir, so
    /// session state reads never touch the real `~/.claude/projects/...`
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

        fn project_root(&self) -> std::path::PathBuf {
            std::env::var("CLAUDE_PROJECT_DIR").unwrap().into()
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

    // t-3185: an explicit `epic` input must find state routed by that unit — including
    // when a branch-only guess (the default, no-epic behavior) would find nothing at all,
    // reproducing exactly the gap the second-variant finder identified in t-3169's gate.
    #[tokio::test]
    async fn test_session_read_explicit_epic_finds_state_branch_guess_would_miss() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new();
        let root = _h.project_root();

        session::write_state(
            &root,
            &serde_json::from_value(json!({
                "version": 1,
                "written_at": "2026-08-24T00:00:00Z",
                "branch": "close/fix/t-9999-dummy",
                "epic": session::ORPHAN_EPIC_SENTINEL,
                "accomplished": ["written under the orphan sentinel"]
            }))
            .unwrap(),
        )
        .unwrap();

        // Default (no epic given): branch "close/fix/t-9999-dummy" parses as epic "close",
        // which was never written — must report not-found, not the wrong file's content.
        let default_out = build()
            .handle(json!({}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();
        assert_eq!(default_out["found"], false, "branch-only guess must not find the orphan-routed state");

        // Explicit epic: must find it.
        let explicit_out = build()
            .handle(json!({"epic": session::ORPHAN_EPIC_SENTINEL}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();
        assert_eq!(explicit_out["found"], true);
        assert_eq!(explicit_out["accomplished"], json!(["written under the orphan sentinel"]));
    }
}
