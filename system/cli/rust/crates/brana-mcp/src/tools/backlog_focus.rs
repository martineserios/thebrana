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
}

fn default_top() -> usize { 3 }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_focus", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

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
                .map(|t| {
                    let score = brana_core::tasks::focus_score(t);
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
                "tasks": tasks,
            }))
        })
    })
    .with_description("Get top focus tasks ranked by priority + staleness + effort + blocking depth.")
}
