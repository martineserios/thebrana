use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Free-text search query (searches subject, description, context, notes, tags)
    pub query: String,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_search", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let results = brana_core::tasks::filter_tasks(
                &data.tasks, &data.tasks,
                None, None, None, None, None, Some(&input.query),
                &["task", "subtask", "phase", "milestone"], None, None,
            );

            Ok(serde_json::json!({
                "query": input.query,
                "count": results.len(),
                "tasks": results,
            }))
        })
    })
    .with_description("Search all tasks by free text across subject, description, context, notes, and tags.")
}
