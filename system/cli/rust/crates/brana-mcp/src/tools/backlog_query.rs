use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Filter by tag (comma-separated for AND logic)
    #[schemars(description = "Filter by tag (comma-separated for AND logic, e.g. 'cli,rust')")]
    pub tag: Option<String>,

    /// Filter by status: pending, in_progress, completed, cancelled
    pub status: Option<String>,

    /// Filter by priority: P0, P1, P2, P3
    pub priority: Option<String>,

    /// Filter by effort: S, M, L, XL
    pub effort: Option<String>,

    /// Free-text search across subject, description, context, notes
    pub search: Option<String>,

    /// Filter by type: task, subtask, phase, milestone, initiative, epic
    /// (comma-separated). An unrecognized value errors rather than silently
    /// matching nothing (t-3233).
    pub task_type: Option<String>,

    /// Filter by parent task ID
    pub parent: Option<String>,

    /// Filter by epic slug
    pub epic: Option<String>,

    /// Filter by work_type: implement, research, design, ops, review
    pub work_type: Option<String>,

    /// Filter by ac_state (v3): none, proposed, approved. Matches only tasks whose
    /// ac_state key is present; legacy tasks (key absent) never match.
    pub ac_state: Option<String>,

    /// Filter by derived role (ADR-086 §3): needs-triage, needs-info,
    /// ready-for-agent, ready-for-human, wontfix, claimed, resolved. Never a
    /// stored field — computed from status/ac_state/tags.
    pub role: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_query", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;

                let types: Vec<&str> = match input.task_type.as_deref() {
                    Some(spec) => brana_core::tasks::validate_task_types(spec)?,
                    None => vec!["task", "subtask"],
                };

                let tag_list: Option<Vec<&str>> = input.tag.as_deref()
                    .map(|t| t.split(',').collect());

                // t-3160/t-3244 sibling gap: --role has no MCP parity without
                // this. Unknown names are rejected loud, same as task_type.
                let role_filter = input.role
                    .as_deref()
                    .map(|r| {
                        brana_core::tasks::Role::parse(r).ok_or_else(|| {
                            format!(
                                "unknown role {r:?} — must be one of needs-triage, needs-info, \
                                 ready-for-agent, ready-for-human, wontfix, claimed, resolved"
                            )
                        })
                    })
                    .transpose()?;

                let mut results = brana_core::tasks::filter_tasks_by(
                    &data.tasks, &data.tasks,
                    &brana_core::tasks::TaskFilter {
                        status: input.status.as_deref(),
                        priority: input.priority.as_deref(),
                        effort: input.effort.as_deref(),
                        search: input.search.as_deref(),
                        types: types.clone(),
                        epic: input.epic.as_deref(),
                        work_type: input.work_type.as_deref(),
                        ac_state: input.ac_state.as_deref(),
                        role: role_filter,
                        ..Default::default()
                    },
                );

                if let Some(ref tags) = tag_list {
                    results.retain(|t| {
                        let task_tags: Vec<&str> = t["tags"].as_array()
                            .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                            .unwrap_or_default();
                        tags.iter().all(|tag| task_tags.contains(tag))
                    });
                }

                if let Some(ref pid) = input.parent {
                    results.retain(|t| t["parent"].as_str() == Some(pid.as_str()));
                }

                brana_core::tasks::sort_by_priority(&mut results);

                let mut out = serde_json::json!({
                    "count": results.len(),
                    "tasks": results,
                });
                // t-3233: the default type scope (task/subtask only) silently
                // dropped every phase/milestone/epic node — including all of
                // the epic-only status vocabulary they carry. Report it,
                // never drop it silently, but only when the caller didn't
                // explicitly choose a narrower scope themselves.
                if input.task_type.is_none() {
                    let excluded = brana_core::tasks::excluded_by_type_count(&data.tasks, &types);
                    if excluded > 0 {
                        out["excluded_by_default_type"] = serde_json::json!(excluded);
                    }
                }

                Ok(out)
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Query backlog tasks with filters. Returns matching tasks as structured JSON. With no task_type given, the default scope is task/subtask only — if that excludes any phase/milestone/epic nodes, their count is reported under excluded_by_default_type (t-3233); pass task_type explicitly (e.g. \"task,subtask,phase,milestone,epic\") to include everything.")
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

    // t-3233: 2 tasks + 1 phase + 1 epic (the epic carries the epic-only
    // status vocabulary, "next" — ADR-065) — 4 nodes total, default query
    // scope (no task_type) only ever returns the 2 task-typed ones.
    fn fixture() -> String {
        r#"{"project":"test","tasks":[
            {"id":"t-1","subject":"a","type":"task","status":"pending","tags":[]},
            {"id":"t-2","subject":"b","type":"subtask","status":"completed","tags":[]},
            {"id":"ph-1","subject":"a phase","type":"phase","status":"pending","tags":[]},
            {"id":"in-1","subject":"an-epic","type":"epic","status":"next","tags":[]}
        ],"waves":[]}"#.to_string()
    }

    #[tokio::test]
    async fn test_default_query_reports_excluded_by_type_count() {
        // t-3233: the audit found `--output json` (no --type) returning
        // 2861 of 3111 tasks with zero indication anything was dropped.
        // This must never happen silently again — the default-scope
        // exclusion is now a machine-readable field on the result.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture());

        let out = build()
            .handle(json!({}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["count"], 2, "default scope still returns only task/subtask");
        assert_eq!(
            out["excluded_by_default_type"], 2,
            "the phase + epic node excluded by the default scope must be reported, not silently dropped"
        );
    }

    #[tokio::test]
    async fn test_explicit_task_type_has_no_excluded_field() {
        // An explicit --type is a deliberate scope choice by the caller —
        // not a silent drop, so no exclusion note is warranted.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture());

        let out = build()
            .handle(
                json!({"task_type": "task,subtask,phase,epic"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .unwrap();

        assert_eq!(out["count"], 4, "explicit type list covering everything returns everything");
        assert!(
            out.get("excluded_by_default_type").is_none(),
            "an explicit --type must not carry an exclusion note"
        );
    }

    #[tokio::test]
    async fn test_default_query_no_exclusions_omits_field() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"a","type":"task","status":"pending","tags":[]}],"waves":[]}"#,
        );

        let out = build()
            .handle(json!({}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["count"], 1);
        assert!(
            out.get("excluded_by_default_type").is_none(),
            "nothing excluded — the field should not appear at all (0 is not worth reporting)"
        );
    }

    #[tokio::test]
    async fn test_role_filters_by_derived_role_not_stored_field() {
        // t-3160/t-3244 sibling gap (second-variant finder): the CLI's
        // --role has no MCP backlog_query parity. This pins it.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[
                {"id":"t-1","subject":"a","type":"task","status":"pending","ac_state":"approved","tags":[]},
                {"id":"t-2","subject":"b","type":"task","status":"pending","ac_state":"proposed","tags":[]}
            ],"waves":[]}"#,
        );

        let out = build()
            .handle(json!({"role": "ready-for-agent"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["count"], 1);
        assert_eq!(out["tasks"][0]["id"], "t-1");
    }

    #[tokio::test]
    async fn test_role_rejects_unknown_name() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture());

        let err = build()
            .handle(json!({"role": "bogus"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("an unrecognized role name must error, not silently match nothing");
        assert!(err.to_string().contains("bogus"), "error must name the bad value: {err}");
    }

    #[tokio::test]
    async fn test_typo_in_task_type_errors_not_silent_empty() {
        // t-3233: before this fix, an unrecognized type token silently
        // matched nothing (count: 0) — the exact silent-drop failure class
        // this task exists to close, just triggered a different way.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture());

        let err = build()
            .handle(json!({"task_type": "taks"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("a typo'd task_type must error, not return an empty result");
        assert!(err.to_string().contains("taks"), "error must name the bad token: {err}");
    }
}
