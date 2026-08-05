use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Memory type: feedback, project, user, pattern, convention, field-note, adr
    #[serde(rename = "type")]
    pub memory_type: String,

    /// Scope: project | global | cross-project
    #[serde(default = "default_scope")]
    pub scope: String,

    /// Kebab-case slug — stable topic identifier, consistent across sessions
    pub slug: String,

    /// Memory content to store
    pub content: String,
}

fn default_scope() -> String { "project".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("memory_write", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file write run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration — this is a write path, not just
            // a read, so a stall here is the highest-cost instance of the
            // pattern in the tool set.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let root = brana_core::util::find_project_root()
                    .ok_or_else(|| "could not resolve project root".to_string())?;

                let dest = brana_core::memory::write_memory(
                    &input.memory_type,
                    &input.scope,
                    &input.slug,
                    &input.content,
                    &root,
                )
                .map_err(|e| e.to_string())?;

                Ok(serde_json::json!({
                    "ok": true,
                    "path": dest.to_string_lossy(),
                    "type": input.memory_type,
                    "scope": input.scope,
                    "slug": input.slug,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Write a memory entry — routes to the correct destination by type and scope (ADR-038). Types: feedback (dated, parallel-safe), project (upsert), user (upsert), pattern (upsert). Scope: project | global.")
}
