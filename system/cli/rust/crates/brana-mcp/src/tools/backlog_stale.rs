use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Staleness threshold in days (default: 14)
    #[serde(default = "default_days")]
    pub days: i64,
}

fn default_days() -> i64 { 14 }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_stale", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let stale = brana_core::tasks::stale_tasks(&data.tasks, &data.tasks, input.days);

            Ok(serde_json::json!({
                "threshold_days": input.days,
                "count": stale.len(),
                "tasks": stale,
            }))
        })
    })
    .with_description("Find tasks that have been pending longer than a threshold (default 14 days).")
}
