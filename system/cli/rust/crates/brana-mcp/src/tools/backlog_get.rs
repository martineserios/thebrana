use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Task ID (e.g. "t-123", "ph-cli-arch")
    pub task_id: String,

    /// Optional: return only a specific field (e.g. "status", "tags", "description")
    pub field: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_get", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;

                let task = data.tasks.iter()
                    .find(|t| t["id"].as_str() == Some(&input.task_id))
                    .ok_or_else(|| format!("task {} not found", input.task_id))?;
                // t-3160/t-3244 sibling gap (second-variant finder): the CLI's
                // `get` shows the derived `role` key; this MCP tool is the
                // same job and must not fall behind it. `role` is never a
                // stored field, so it's added to a display copy only.
                let display = brana_core::tasks::task_with_derived_role(task);

                match input.field {
                    Some(ref f) => Ok(serde_json::json!({
                        "id": input.task_id,
                        "field": f,
                        "value": display[f],
                    })),
                    None => Ok(display),
                }
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Get a single task by ID, optionally returning only a specific field.")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;

    struct Hermetic {
        orig_cwd: PathBuf,
        orig_project_dir: Option<String>,
        dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn new(tasks_body: &str) -> Self {
            let dir = tempfile::tempdir().unwrap();
            let claude = dir.path().join(".claude");
            std::fs::create_dir_all(&claude).unwrap();
            std::fs::write(claude.join("tasks.json"), tasks_body).unwrap();
            let orig_cwd = std::env::current_dir().unwrap();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
            std::env::set_current_dir(dir.path()).unwrap();
            Self { orig_cwd, orig_project_dir, dir }
        }
    }

    impl Drop for Hermetic {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.orig_cwd);
            if let Some(v) = &self.orig_project_dir {
                unsafe { std::env::set_var("CLAUDE_PROJECT_DIR", v) };
            }
        }
    }

    // t-3160/t-3244 sibling gap (second-variant finder): the CLI's `get`
    // shows the derived `role` key via task_with_derived_role(); this MCP
    // tool did the same job with raw task indexing and always returned null
    // for field:"role". These pin the fix.

    #[tokio::test]
    async fn test_get_field_role_returns_derived_role() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[
                {"id":"t-1","subject":"a","type":"task","status":"pending","ac_state":"approved","tags":[]}
            ],"waves":[]}"#,
        );

        let out = build()
            .handle(json!({"task_id": "t-1", "field": "role"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["value"], "ready-for-agent");
    }

    #[tokio::test]
    async fn test_get_whole_object_includes_role_key() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[
                {"id":"t-1","subject":"a","type":"task","status":"completed","tags":[]}
            ],"waves":[]}"#,
        );

        let out = build()
            .handle(json!({"task_id": "t-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["role"], "resolved");
        assert_eq!(out["subject"], "a", "existing fields must still be present unchanged");
    }

    #[tokio::test]
    async fn test_get_field_role_renders_none_as_null() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[
                {"id":"t-1","subject":"a","type":"task","status":"pending","ac_state":"approved","tags":["parked"]}
            ],"waves":[]}"#,
        );

        let out = build()
            .handle(json!({"task_id": "t-1", "field": "role"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["value"], serde_json::Value::Null);
    }
}
