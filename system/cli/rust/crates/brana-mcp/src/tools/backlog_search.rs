use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Free-text search query (searches subject, description, context, notes, tags)
    pub query: String,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_search", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration. Read + filter is fast today, but
            // nothing here should ever run inline on that task.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;

                let results = brana_core::tasks::filter_tasks_by(
                    &data.tasks, &data.tasks,
                    &brana_core::tasks::TaskFilter {
                        search: Some(&input.query),
                        types: vec!["task", "subtask", "phase", "milestone"],
                        ..Default::default()
                    },
                );

                Ok(serde_json::json!({
                    "query": input.query,
                    "count": results.len(),
                    "tasks": results,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Search all tasks by free text across subject, description, context, notes, and tags.")
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;

    /// RAII guard: chdir into an isolated non-git tempdir holding a fixture
    /// tasks.json, with CLAUDE_PROJECT_DIR cleared, so find_tasks_file()
    /// resolves to the fixture. Callers must hold CWD_LOCK for its lifetime.
    struct Hermetic {
        orig_cwd: PathBuf,
        orig_project_dir: Option<String>,
        _dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn with_tasks(tasks_json: &str) -> Self {
            let dir = tempfile::tempdir().unwrap();
            let claude = dir.path().join(".claude");
            std::fs::create_dir_all(&claude).unwrap();
            std::fs::write(claude.join("tasks.json"), tasks_json).unwrap();
            let orig_cwd = std::env::current_dir().unwrap();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            // SAFETY: caller holds CWD_LOCK; no other test in this binary
            // reads or writes the environment concurrently.
            unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
            std::env::set_current_dir(dir.path()).unwrap();
            Self { orig_cwd, orig_project_dir, _dir: dir }
        }
    }

    impl Drop for Hermetic {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.orig_cwd);
            if let Some(v) = &self.orig_project_dir {
                // SAFETY: still under CWD_LOCK (guard drops before the lock).
                unsafe { std::env::set_var("CLAUDE_PROJECT_DIR", v) };
            }
        }
    }

    const FIXTURE: &str = r#"{"project":"test","tasks":[
        {"id":"t-1","subject":"fix the wobble in the frobnicator","status":"pending","type":"task","tags":[]},
        {"id":"t-2","subject":"unrelated task","status":"pending","type":"task","tags":[]}
    ]}"#;

    /// t-2631: backlog_search's handler runs its (file-read + filter) body via
    /// spawn_blocking, matching backlog_add/recall's established pattern, so a
    /// slow or contended read can never freeze pmcp's fully-serialized stdio
    /// dispatch loop (t-2305) for every other tool. This locks in that the
    /// handler still returns correct, matching results after that refactor.
    #[tokio::test]
    async fn test_search_finds_matching_task_by_subject() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::with_tasks(FIXTURE);

        let out = build()
            .handle(json!({"query": "frobnicator"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("search must succeed");

        assert_eq!(out["count"], 1, "must find exactly the one matching task: {out}");
        let tasks = out["tasks"].as_array().unwrap();
        assert_eq!(tasks[0]["id"], "t-1");
    }

    #[tokio::test]
    async fn test_search_no_match_returns_empty_not_error() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::with_tasks(FIXTURE);

        let out = build()
            .handle(json!({"query": "nonexistent-xyzzy-term"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("search with no matches must still succeed, not error");

        assert_eq!(out["count"], 0);
        assert!(out["tasks"].as_array().unwrap().is_empty());
    }
}
