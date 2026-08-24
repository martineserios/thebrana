use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Number of top tasks to return (default: 3)
    #[serde(default = "default_top")]
    pub top: usize,

    /// Optional tag filter
    pub tag: Option<String>,

    /// Override the resolved epic slug (ADR-088: normally task-derived —
    /// the most-recently-started in_progress task's epic)
    pub epic: Option<String>,

    /// Filter by work_type: implement, research, design, ops, review
    pub work_type: Option<String>,
}

fn default_top() -> usize { 3 }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_focus", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;

                // ADR-088 (t-3196): session-scoped, task-derived resolution —
                // replaces the retired shared active_epic config file entirely.
                // Shares one core helper with the CLI's cmd_focus, closing the
                // shape-divergence class ADR-066's own spec found between them.
                let active: Option<String> =
                    brana_core::tasks::resolve_focus_epic(input.epic.as_deref(), &data.tasks);

                // t-2314 (ADR-065): fail loud rather than silently no-op-ing the
                // epic-scoped boost/view when active_epic doesn't resolve to anything.
                if let Some(ref slug) = active {
                    brana_core::tasks::assert_active_epic_resolves(&data.tasks, slug)?;
                }

                // t-2765: the flat `epic` field is retired (RETIRED_FIELDS) — epic
                // membership is the nearest type:"epic" ancestor via the parent
                // chain, resolved the same way compute_stats() already does.
                let by_id: std::collections::HashMap<&str, &serde_json::Value> = data.tasks.iter()
                    .filter_map(|t| t["id"].as_str().map(|id| (id, t)))
                    .collect();

                let mut scored: Vec<_> = data.tasks.iter()
                    .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
                    .filter(|t| brana_core::tasks::classify(t, &data.tasks) == "pending")
                    .filter(|t| {
                        input.tag.as_deref().map_or(true, |tag| {
                            t["tags"].as_array()
                                .map(|a| a.iter().any(|v| v.as_str() == Some(tag)))
                                .unwrap_or(false)
                        })
                    })
                    .filter(|t| {
                        input.work_type.as_deref().map_or(true, |wt| {
                            t["work_type"].as_str().unwrap_or("") == wt
                        })
                    })
                    .map(|t| {
                        let boost = active.as_deref()
                            .filter(|a| brana_core::tasks::resolve_epic_ancestor(t, &by_id).as_deref() == Some(a))
                            .map_or(0.0, |_| 500.0);
                        let score = brana_core::tasks::focus_score(t, boost);
                        (t, score)
                    })
                    .collect();

                scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
                let top: Vec<_> = scored.into_iter().take(input.top).collect();

                let tasks: Vec<serde_json::Value> = top.iter().map(|(t, score)| {
                    serde_json::json!({
                        "task": t,
                        "focus_score": score,
                    })
                }).collect();

                Ok(serde_json::json!({
                    "count": tasks.len(),
                    "active_epic": active,
                    "tasks": tasks,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Get top focus tasks ranked by epic match + priority + effort + blocking depth.")
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
        fn new(tasks_json: &str) -> Self {
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
            Self {
                orig_cwd,
                orig_project_dir,
                dir,
            }
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

    // ── t-2314 (ADR-065): active_epic fail-loud resolution ───────────────────

    #[tokio::test]
    async fn test_mcp_focus_fails_loud_on_unresolved_epic_override() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"x","type":"task","status":"pending","tags":[],"blocked_by":[],"epic":"a-different-epic"}]}"#,
        );

        let err = build()
            .handle(
                json!({"epic": "nonexistent-epic"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect_err("handler must fail loud on an unresolved epic override");

        assert!(err.to_string().contains("nonexistent-epic"), "error must name the unresolved slug: {err}");
    }

    #[tokio::test]
    async fn test_mcp_focus_succeeds_when_epic_resolves_via_flat_tag() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"x","type":"task","status":"pending","tags":[],"blocked_by":[],"epic":"cc-alignment"}]}"#,
        );

        let out = build()
            .handle(
                json!({"epic": "cc-alignment"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("handler must succeed when epic resolves via the flat tag (pre-migration compat)");

        assert_eq!(out["active_epic"], "cc-alignment");
    }

    // ── t-2765: boost must use the parent-chain epic resolver, not the
    // retired flat `epic` field ─────────────────────────────────────────

    #[tokio::test]
    async fn test_mcp_focus_boost_fires_via_parent_chain_not_flat_field() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[
                {"id":"t-epic","subject":"cc-alignment","type":"epic","status":"next","tags":[],"blocked_by":[]},
                {"id":"t-member","subject":"in epic via parent","type":"task","status":"pending","tags":[],"blocked_by":[],"parent":"t-epic","priority":"P3"},
                {"id":"t-outsider","subject":"not in epic","type":"task","status":"pending","tags":[],"blocked_by":[],"priority":"P0"}
            ]}"#,
        );

        let out = build()
            .handle(
                json!({"epic": "cc-alignment", "top": 10}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("handler must succeed");

        let tasks = out["tasks"].as_array().expect("tasks array");
        let member = tasks.iter().find(|t| t["task"]["id"] == "t-member").expect("member task present");
        let outsider = tasks.iter().find(|t| t["task"]["id"] == "t-outsider").expect("outsider task present");

        // t-member is P3 (base priority 100) but gets the 500 epic boost via
        // its parent chain to the epic node -> outranks P0 (400) t-outsider,
        // which has no epic ancestor and gets no boost.
        let member_score = member["focus_score"].as_f64().unwrap();
        let outsider_score = outsider["focus_score"].as_f64().unwrap();
        assert!(
            member_score > outsider_score,
            "parent-chain epic member (P3+boost={member_score}) must outrank non-member (P0, no boost={outsider_score})"
        );
    }
}
