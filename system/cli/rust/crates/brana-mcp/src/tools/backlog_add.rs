use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
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

    /// Epic slug (e.g. "cc-alignment", "backlog-schema-v2")
    pub epic: Option<String>,

    /// Work type: implement, research, design, infra, chore, review
    pub work_type: Option<String>,
}

fn default_type() -> String { "task".into() }
fn default_execution() -> String { "code".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_add", |input: Input, _extra| {
        Box::pin(async move {
            // Cross-project: --project slug resolves another repo's tasks.json via the
            // portfolio; default is the current project (t-2159).
            let tf = match input.project.as_deref() {
                Some(slug) => brana_core::util::resolve_project_tasks_file(slug)
                    .map_err(pmcp::Error::validation)?,
                None => brana_core::util::find_tasks_file()
                    .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?,
            };
            // Serialize the whole read-modify-write so next_id is computed
            // under the lock and concurrent writers can't clobber (t-2166).
            let _lock = brana_core::tasks::lock_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;
            let mut val = brana_core::tasks::load_raw(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let tasks = val["tasks"].as_array()
                .ok_or_else(|| pmcp::Error::validation("tasks.json has no tasks array"))?;

            if let Some(p) = input.priority.as_deref() {
                brana_core::tasks::validate_priority(p)
                    .map_err(pmcp::Error::validation)?;
            }
            if let Some(k) = input.kind.as_deref() {
                brana_core::tasks::validate_kind(k)
                    .map_err(pmcp::Error::validation)?;
            }
            if let Some(wt) = input.work_type.as_deref() {
                brana_core::tasks::validate_work_type(wt)
                    .map_err(pmcp::Error::validation)?;
            }
            brana_core::tasks::validate_execution(&input.execution)
                .map_err(pmcp::Error::validation)?;
            brana_core::tasks::validate_context_for_effort(
                input.effort.as_deref(),
                input.context.as_deref(),
            ).map_err(pmcp::Error::validation)?;

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
                "epic": input.epic,
                "work_type": input.work_type,
            });

            val["tasks"].as_array_mut()
                .ok_or_else(|| pmcp::Error::validation("tasks.json has no tasks array"))?
                .push(task);

            brana_core::tasks::save_tasks(&tf, &val)
                .map_err(|e| pmcp::Error::validation(e))?;

            Ok(serde_json::json!({
                "ok": true,
                "id": id,
                "subject": input.subject,
            }))
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
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;
    use std::sync::Mutex;

    /// Serializes cwd/env mutation across handler tests in this test binary.
    static CWD_LOCK: Mutex<()> = Mutex::new(());

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

    // ── t-2263: epic/work_type params were missing from the MCP schema, so
    // MCP-created tasks (unlike CLI-created ones, which already had --epic /
    // --work-type) could never carry an epic — the Tier 2b blind spot that fed
    // t-2263's epic-detection false positive. ──────────────────────────────

    #[tokio::test]
    async fn test_mcp_add_persists_epic_and_work_type() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(
                json!({
                    "subject": "task with epic",
                    "epic": "harness",
                    "work_type": "implement"
                }),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("handler must accept epic and work_type");

        assert_eq!(out["ok"], true);
        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == out["id"])
            .expect("added task must be persisted");
        assert_eq!(task["epic"], "harness", "epic must be persisted: {task}");
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
    async fn test_mcp_add_epic_and_work_type_default_absent() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();

        let out = build()
            .handle(json!({"subject": "task without epic"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect("handler must accept omitted epic/work_type");

        let tasks = h.tasks();
        let task = tasks["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|t| t["id"] == out["id"])
            .expect("added task must be persisted");
        assert!(
            task["epic"].is_null(),
            "epic should default to null, not error: {task}"
        );
        assert!(
            task["work_type"].is_null(),
            "work_type should default to null, not error: {task}"
        );
    }
}
