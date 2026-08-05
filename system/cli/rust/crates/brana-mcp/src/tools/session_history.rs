//! session_history — list past session states.
//!
//! Returns an array of past session state summaries (most recent first).
//! Defaults to last 5 entries. Full objects are returned so callers can
//! extract any field.

use brana_core::session;
use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Maximum number of history entries to return. Defaults to 5.
    pub limit: Option<u32>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("session_history", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration. Read + parse is fast today, but
            // nothing here should ever run inline on that task.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let root = brana_core::util::find_project_root()
                    .ok_or_else(|| "not in a git repository".to_string())?;

                let limit = input.limit.unwrap_or(5) as usize;
                let entries = session::read_history(&root, limit);

                let items: Vec<serde_json::Value> = entries
                    .iter()
                    .map(|s| serde_json::to_value(s).unwrap_or(serde_json::Value::Null))
                    .collect();

                Ok(serde_json::json!({
                    "count": items.len(),
                    "entries": items,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("List past session states, most recent first. Returns up to `limit` entries (default 5).")
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;

    /// RAII guard: isolates HOME and CLAUDE_PROJECT_DIR to a tempdir, so
    /// `find_project_root()`/`resolve_memory_dir()` resolve entirely inside
    /// the fixture rather than the real `~/.claude/projects/...` tree.
    /// Callers must hold CWD_LOCK for its lifetime.
    struct Hermetic {
        orig_home: Option<String>,
        orig_project_dir: Option<String>,
        _dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn with_history(entries_jsonl: &str) -> Self {
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

            let history_path = brana_core::session::session_history_path(&project_root);
            std::fs::create_dir_all(history_path.parent().unwrap()).unwrap();
            std::fs::write(&history_path, entries_jsonl).unwrap();

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

    fn state_line(written_at: &str) -> String {
        json!({
            "version": 1,
            "written_at": written_at,
        })
        .to_string()
    }

    /// t-2631: session_history's handler runs its (file-read + parse) body via
    /// spawn_blocking, matching backlog_add/recall's established pattern, so a
    /// slow or contended read can never freeze pmcp's fully-serialized stdio
    /// dispatch loop (t-2305) for every other tool. This locks in that the
    /// handler still returns correct, matching results after that refactor.
    #[tokio::test]
    async fn test_history_returns_most_recent_first() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let jsonl = format!("{}\n{}\n{}\n", state_line("2026-01-01T00:00:00Z"), state_line("2026-01-02T00:00:00Z"), state_line("2026-01-03T00:00:00Z"));
        let _h = Hermetic::with_history(&jsonl);

        let out = build()
            .handle(json!({}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("history must succeed");

        assert_eq!(out["count"], 3);
        let entries = out["entries"].as_array().unwrap();
        assert_eq!(entries[0]["written_at"], "2026-01-03T00:00:00Z", "most recent must come first");
    }

    #[tokio::test]
    async fn test_history_limit_is_honored() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let jsonl: String = (0..10).map(|i| format!("{}\n", state_line(&format!("2026-01-{:02}T00:00:00Z", i + 1)))).collect();
        let _h = Hermetic::with_history(&jsonl);

        let out = build()
            .handle(json!({"limit": 2}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("history must succeed");

        assert_eq!(out["count"], 2, "limit=2 must cap results: {out}");
    }
}
