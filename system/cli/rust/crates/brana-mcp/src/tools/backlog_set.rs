use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Task ID to modify
    pub task_id: String,

    /// Field to set (e.g. "status", "priority", "effort", "tags", "context", "notes")
    pub field: String,

    /// New value for the field. For tags: "+tag" to add, "-tag" to remove.
    pub value: String,

    /// If true, append to existing value instead of replacing (for context, notes)
    #[serde(default)]
    pub append: bool,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_set", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            // Serialize the read-modify-write against concurrent writers (t-2166).
            let _lock = brana_core::tasks::lock_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;
            let mut val = brana_core::tasks::load_raw(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            // Scoped mutable borrow for task mutation
            let actual_value = {
                let tasks = val["tasks"].as_array_mut()
                    .ok_or_else(|| pmcp::Error::validation("tasks.json has no tasks array"))?;

                let task = tasks.iter_mut()
                    .find(|t| t["id"].as_str() == Some(&input.task_id))
                    .ok_or_else(|| pmcp::Error::validation(format!("task {} not found", input.task_id)))?;

                brana_core::tasks::set_field(task, &input.field, &input.value, input.append)
                    .map_err(|e| pmcp::Error::validation(e))?;

                task[&input.field].clone()
            };

            brana_core::tasks::save_tasks(&tf, &val)
                .map_err(|e| pmcp::Error::validation(e))?;

            Ok(serde_json::json!({
                "ok": true,
                "id": input.task_id,
                "field": input.field,
                "value": actual_value,
            }))
        })
    })
    .with_description("Set a field on a task. Supports status, priority, effort, tags (+/-), context, notes, and more.")
}
