use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Task subject/title
    pub subject: String,

    /// Task type: task, subtask, phase, milestone
    #[serde(default = "default_type")]
    pub task_type: String,

    /// Comma-separated tags
    pub tags: Option<String>,

    /// Task description
    pub description: Option<String>,

    /// Effort: XS, S, M, L, XL
    pub effort: Option<String>,

    /// Priority: P0, P1, P2, P3
    pub priority: Option<String>,

    /// Parent task ID
    pub parent: Option<String>,

    /// Work kind: feature, fix, refactor, research, docs, design, ops
    pub kind: Option<String>,

    /// Context — required for effort M, L, or XL (t-939)
    pub context: Option<String>,

    /// Acceptance criteria items
    pub acceptance_criteria: Option<Vec<String>>,

    /// Execution mode: code (default) or autonomous
    #[serde(default = "default_execution")]
    pub execution: String,

    /// Create the task in another project's backlog by portfolio slug (cross-project).
    /// Resolves via ~/.claude/tasks-portfolio.json. Default: current project.
    pub project: Option<String>,

    /// Work type: implement, research, design, infra, chore, review
    pub work_type: Option<String>,
}

fn default_type() -> String { "task".into() }
fn default_execution() -> String { "code".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_add", |input: Input, _extra| {
        Box::pin(async move {
            // The whole read-modify-write is synchronous std I/O (including the lock
            // acquire) — run it off the async executor so it can never block the
            // (fully-serialized, t-2305) stdio dispatch loop while waiting.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                // Cross-project: --project slug resolves another repo's tasks.json via the
                // portfolio; default is the current project (t-2159).
                let tf = match input.project.as_deref() {
                    Some(slug) => brana_core::util::resolve_project_tasks_file(slug)?,
                    None => brana_core::util::find_tasks_file()
                        .ok_or_else(|| "tasks.json not found".to_string())?,
                };
                // Serialize the whole read-modify-write so next_id is computed
                // under the lock and concurrent writers can't clobber (t-2166).
                // Bounded acquire (t-2305): an unbounded flock() here can starve pmcp's
                // fully-serialized stdio dispatch loop for the rest of the session if
                // contended by a concurrent writer.
                let _lock = brana_core::tasks::lock_tasks_timeout(&tf)?;
                let mut val = brana_core::tasks::load_raw(&tf)?;

                let tasks = val["tasks"].as_array()
                    .ok_or_else(|| "tasks.json has no tasks array".to_string())?;

                if let Some(p) = input.priority.as_deref() {
                    brana_core::tasks::validate_priority(p)?;
                }
                if let Some(k) = input.kind.as_deref() {
                    brana_core::tasks::validate_kind(k)?;
                }
                if let Some(wt) = input.work_type.as_deref() {
                    brana_core::tasks::validate_work_type(wt)?;
                }
                brana_core::tasks::validate_execution(&input.execution)?;
                brana_core::tasks::validate_context_for_effort(
                    input.effort.as_deref(),
                    input.context.as_deref(),
                )?;

                let id = brana_core::tasks::next_id(tasks);

                let tags: Vec<serde_json::Value> = input.tags
                    .as_deref()
                    .map(|t| t.split(',').map(|s| serde_json::Value::String(s.trim().to_string())).collect())
                    .unwrap_or_default();

                let today = chrono::Local::now().format("%Y-%m-%d").to_string();

                let task = serde_json::json!({
                    "id": id,
                    "subject": input.subject,
                    "status": "pending",
                    "type": input.task_type,
                    "kind": input.kind,
                    "tags": tags,
                    "description": input.description,
                    "effort": input.effort,
                    "priority": input.priority,
                    "parent": input.parent,
                    "created": today,
                    "started": null,
                    "completed": null,
                    "blocked_by": [],
                    "branch": null,
                    "context": input.context,
                    "notes": null,
                    "order": 0,
                    "github_issue": null,
                    "execution": input.execution,
                    "acceptance_criteria": input.acceptance_criteria,
                    "work_type": input.work_type,
                    // t-2283: stamp ac_state:none on new tasks (v3 forward-only).
                    // Shared const with CLI cmd_add so the two write paths cannot drift.
                    "ac_state": brana_core::tasks::AC_STATE_DEFAULT,
                });

                val["tasks"].as_array_mut()
                    .ok_or_else(|| "tasks.json has no tasks array".to_string())?
                    .push(task);

                brana_core::tasks::save_tasks(&tf, &val)?;

                Ok(serde_json::json!({
                    "ok": true,
                    "id": id,
                    "subject": input.subject,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Add a new task to the backlog. Returns the assigned task ID. Context is required for effort M, L, or XL.")
}

// ── Tests ─────────────────────────────────────────────────────────────────────
//
// Handler-level tests live here rather than in tests/tool_tests.rs because
// brana-mcp is a binary-only crate: integration tests cannot import `tools::`.
// #[cfg(test)] code is never compiled into the shipped binary.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;

    /// RAII guard: chdir into an isolated non-git tempdir holding a fixture
    /// tasks.json, with CLAUDE_PROJECT_DIR cleared, so the handler's
    /// find_tasks_file() resolves to the fixture instead of the real repo's
    /// .claude/tasks.json. Restores cwd and env on drop. Callers must hold
    /// CWD_LOCK for the guard's whole lifetime.
    struct Hermetic {
        orig_cwd: PathBuf,
        orig_project_dir: Option<String>,
        dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let claude = dir.path().join(".claude");
            std::fs::create_dir_all(&claude).unwrap();
            std::fs::write(
                claude.join("tasks.json"),
                r#"{"project":"test","tasks":[]}"#,
            )
            .unwrap();
            let orig_cwd = std::env::current_dir().unwrap();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            // SAFETY: caller holds CWD_LOCK; no other test in this binary
            // reads or writes the environment concurrently.
            unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
            std::env::set_current_dir(dir.path()).unwrap();
            Self {
                orig_cwd,
                orig_project_dir,
                dir,
            }
        }

        fn tasks(&self) -> serde_json::Value {
            let raw = std::fs::read_to_string(self.dir.path().join(".claude/tasks.json")).unwrap();
            serde_json::from_str(&raw).unwrap()
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

    // ── t-1982: execution enum validation through the backlog_add handler ────

    #[tokio::test]
    async fn test_mcp_add_execution_bogus_rejected() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let err = build()
            .handle(
                json!({"subject": "bad execution", "execution": "bogus"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect_err("handler must reject execution=\"bogus\"");

        let msg = err.to_string();
        assert!(msg.contains("code"), "error must list 'code': {msg}");
        assert!(
            msg.contains("autonomous"),
            "error must list 'autonomous': {msg}"
        );
        assert_eq!(
            h.tasks()["tasks"].as_array().unwrap().len(),
            0,
            "rejected add must not persist a task"
        );
    }

    #[tokio::test]
    async fn test_mcp_add_handler_execution_autonomous_accepted() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(
                json!({"subject": "autonomous task", "execution": "autonomous"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("handler must accept execution=\"autonomous\"");

        assert_eq!(out["ok"], true);
        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == out["id"])
            .expect("added task must be persisted");
        assert_eq!(task["execution"], "autonomous");
    }

    // ── t-2310 (ADR-065): epic is retired as a flat field on MCP backlog_add —
    // it becomes a hierarchy node, not something a new task carries directly.
    // #[serde(deny_unknown_fields)] on Input makes submitting "epic" a hard
    // reject, matching the CLI JSON-ingestion path. work_type is unaffected.
    // ─────────────────────────────────────────────────────────────────────────

    #[tokio::test]
    async fn test_mcp_add_rejects_epic_field() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let err = build()
            .handle(
                json!({"subject": "task with epic", "epic": "harness"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect_err("handler must reject the retired epic field");

        let msg = err.to_string();
        assert!(msg.contains("epic"), "error must name the rejected field: {msg}");
        assert_eq!(
            h.tasks()["tasks"].as_array().unwrap().len(),
            0,
            "rejected add must not persist a task"
        );
    }

    #[tokio::test]
    async fn test_mcp_add_persists_work_type() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(
                json!({"subject": "task with work_type", "work_type": "implement"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("handler must accept work_type");

        assert_eq!(out["ok"], true);
        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == out["id"])
            .expect("added task must be persisted");
        assert_eq!(
            task["work_type"], "implement",
            "work_type must be persisted: {task}"
        );
    }

    #[tokio::test]
    async fn test_mcp_add_bogus_work_type_rejected() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let err = build()
            .handle(
                json!({"subject": "bad work_type", "work_type": "bogus"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect_err("handler must reject work_type=\"bogus\"");

        let msg = err.to_string();
        assert!(msg.contains("implement"), "error must list valid values: {msg}");
        assert_eq!(
            h.tasks()["tasks"].as_array().unwrap().len(),
            0,
            "rejected add must not persist a task"
        );
    }

    #[tokio::test]
    async fn test_mcp_add_work_type_default_absent() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(json!({"subject": "task without work_type"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("handler must accept omitted work_type");

        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == out["id"])
            .expect("added task must be persisted");
        assert!(
            task["work_type"].is_null(),
            "work_type should default to null, not error: {task}"
        );
    }

    // ── t-2283: ac_state forward-only slice through the MCP path ─────────────

    #[tokio::test]
    async fn test_mcp_add_stamps_ac_state_none() {
        // AC#3 (MCP path): backlog_add stamps ac_state:none.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(
                json!({"subject": "v3 task via mcp"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("handler must accept add");

        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == out["id"])
            .expect("added task must be persisted");
        assert_eq!(task["ac_state"], "none", "MCP add must stamp ac_state:none");
    }

    #[tokio::test]
    async fn test_mcp_set_unrelated_field_preserves_ac_state() {
        // AC#2 (MCP path): after an MCP-created task carries ac_state, an
        // MCP backlog_set on an unrelated field must not clobber it. This is the
        // MCP half of the both-paths sealing proof.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(
                json!({"subject": "sealed via mcp"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("add must succeed");
        let id = out["id"].as_str().unwrap().to_string();

        // Promote to proposed, then touch an unrelated field — both via MCP set.
        crate::tools::backlog_set::build()
            .handle(
                json!({"task_id": id, "field": "ac_state", "value": "proposed"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("mcp set ac_state must succeed");
        crate::tools::backlog_set::build()
            .handle(
                json!({"task_id": id, "field": "priority", "value": "P1"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("mcp set priority must succeed");

        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == id.as_str())
            .unwrap();
        assert_eq!(task["ac_state"], "proposed", "MCP set clobbered ac_state");
        assert_eq!(task["priority"], "P1");
    }
}
