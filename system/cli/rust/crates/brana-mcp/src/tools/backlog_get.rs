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
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let task = data.tasks.iter()
                .find(|t| t["id"].as_str() == Some(&input.task_id))
                .ok_or_else(|| pmcp::Error::validation(format!("task {} not found", input.task_id)))?;

            match input.field {
                Some(ref f) => Ok(serde_json::json!({
                    "id": input.task_id,
                    "field": f,
                    "value": task[f],
                })),
                None => Ok(task.clone()),
            }
        })
    })
    .with_description("Get a single task by ID, optionally returning only a specific field.")
}
