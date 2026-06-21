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

    /// Override active epic slug (defaults to tasks-config.json active_epic)
    pub epic: Option<String>,

    /// Filter by work_type: implement, research, design, ops, review
    pub work_type: Option<String>,
}

fn default_top() -> usize { 3 }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_focus", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            // Load active_epic with per-repo scoping (t-2158): a project with no local
            // config does NOT inherit the global/foreign active_epic.
            let active: Option<String> = input.epic.clone().or_else(|| {
                brana_core::util::load_tasks_config()["active_epic"]
                    .as_str()
                    .map(|s| s.to_string())
            });

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
                        .filter(|a| t["epic"].as_str() == Some(a))
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
    })
    .with_description("Get top focus tasks ranked by epic match + priority + effort + blocking depth.")
}
