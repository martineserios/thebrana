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
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;

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

                Ok(brana_core::tasks::compute_stats(&tasks, &data.tasks))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Get aggregate statistics for backlog tasks (by status, priority, type, work_type, epic).")
}
