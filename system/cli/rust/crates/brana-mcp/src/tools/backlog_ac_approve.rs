use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Task ID whose acceptance criteria to approve
    pub task_id: String,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_ac_approve", |_input: Input, _extra| {
        Box::pin(async move {
            Err(pmcp::Error::validation("unimplemented".to_string()))
        })
    })
    .with_description("Approve a task's acceptance criteria (ADR-079): promotes proposed_acceptance_criteria into acceptance_criteria and sets ac_state to approved. The sanctioned transition — backlog_set(ac_state, approved) is rejected.")
}

// Handler-level tests live here because brana-mcp is a binary-only crate:
// integration tests cannot import `tools::`. #[cfg(test)] code is never
// compiled into the shipped binary.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;

    /// RAII guard: chdir into an isolated non-git tempdir holding a fixture
    /// tasks.json so find_tasks_file() resolves to the fixture. Same pattern as
    /// backlog_set.rs; caller must hold CWD_LOCK for the guard's lifetime.
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
            // SAFETY: caller holds CWD_LOCK; no other test in this binary
            // reads or writes the environment concurrently.
            unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
            std::env::set_current_dir(dir.path()).unwrap();
            Self { orig_cwd, orig_project_dir, dir }
        }

        fn tasks_file(&self) -> PathBuf {
            self.dir.path().join(".claude/tasks.json")
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

    #[tokio::test]
    async fn test_mcp_ac_approve_promotes_and_persists() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"x","status":"pending","ac_state":"proposed","proposed_acceptance_criteria":["done when green"]}]}"#,
        );

        let out = build()
            .handle(json!({"task_id": "t-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("approve must succeed");
        assert_eq!(out["ok"], true);
        assert_eq!(out["ac_state"], "approved");
        assert_eq!(out["promoted"], 1);
        assert_eq!(out["already_approved"], false);

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        let t1 = &reloaded["tasks"][0];
        assert_eq!(t1["ac_state"], "approved");
        assert_eq!(t1["acceptance_criteria"], json!(["done when green"]));
        assert!(t1.get("proposed_acceptance_criteria").is_none());
    }

    #[tokio::test]
    async fn test_mcp_ac_approve_no_criteria_errors_persists_nothing() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"x","status":"pending","ac_state":"none"}]}"#,
        );

        let err = build()
            .handle(json!({"task_id": "t-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("approve with no criteria must fail");
        assert!(
            err.to_string().contains("no acceptance criteria to approve"),
            "got: {err}"
        );

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(
            reloaded["tasks"][0]["ac_state"], "none",
            "rejected approve must not persist"
        );
    }

    #[tokio::test]
    async fn test_mcp_ac_approve_unknown_task_errors() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(r#"{"project":"test","tasks":[]}"#);

        let err = build()
            .handle(json!({"task_id": "t-99"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("unknown task must fail");
        assert!(err.to_string().contains("t-99"), "got: {err}");
    }
}
