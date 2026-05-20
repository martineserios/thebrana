use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Optional: include only tasks with this tag
    pub tag: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_stats", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let tasks = if let Some(ref tag) = input.tag {
                data.tasks.iter()
                    .filter(|t| {
                        t["tags"].as_array()
                            .map(|a| a.iter().any(|v| v.as_str() == Some(tag)))
                            .unwrap_or(false)
                    })
                    .cloned()
                    .collect::<Vec<_>>()
            } else {
                data.tasks.clone()
            };

            let stats = brana_core::tasks::compute_stats(&tasks, &data.tasks);
            Ok(stats)
        })
    })
    .with_description("Get aggregate statistics for backlog tasks (by status, priority, type, work_type, initiative).")
}
