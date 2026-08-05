use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Period: "week" (7 days) or "month" (30 days)
    #[serde(default = "default_period")]
    pub period: String,
}

fn default_period() -> String { "week".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_burndown", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;
                Ok(brana_core::tasks::burndown(&data.tasks, &input.period))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Get burndown metrics: created vs completed tasks over a period (week or month).")
}
