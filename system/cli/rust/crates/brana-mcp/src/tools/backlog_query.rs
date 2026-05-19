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

    /// Filter by stream: roadmap, bugs, tech-debt, docs, experiments, research, personal
    pub stream: Option<String>,

    /// Filter by priority: P0, P1, P2, P3
    pub priority: Option<String>,

    /// Filter by effort: S, M, L, XL
    pub effort: Option<String>,

    /// Free-text search across subject, description, context, notes
    pub search: Option<String>,

    /// Filter by type: task, subtask, phase, milestone (comma-separated)
    pub task_type: Option<String>,

    /// Filter by parent task ID
    pub parent: Option<String>,

    /// Filter by initiative slug
    pub initiative: Option<String>,

    /// Filter by work_type: implement, research, design, ops, review
    pub work_type: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_query", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let types: Vec<&str> = input.task_type.as_deref()
                .map(|t| t.split(',').collect())
                .unwrap_or_else(|| vec!["task", "subtask"]);

            let tag_list: Option<Vec<&str>> = input.tag.as_deref()
                .map(|t| t.split(',').collect());

            let mut results = brana_core::tasks::filter_tasks(
                &data.tasks, &data.tasks,
                None,
                input.status.as_deref(),
                input.stream.as_deref(),
                input.priority.as_deref(),
                input.effort.as_deref(),
                input.search.as_deref(),
                &types,
                input.initiative.as_deref(),
                input.work_type.as_deref(),
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

            Ok(serde_json::json!({
                "count": results.len(),
                "tasks": results,
            }))
        })
    })
    .with_description("Query backlog tasks with filters. Returns matching tasks as structured JSON.")
}
