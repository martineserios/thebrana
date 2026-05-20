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
            let root = brana_core::util::find_project_root()
                .ok_or_else(|| pmcp::Error::validation("could not resolve project root"))?;

            let dest = brana_core::memory::write_memory(
                &input.memory_type,
                &input.scope,
                &input.slug,
                &input.content,
                &root,
            )
            .map_err(|e| pmcp::Error::validation(e.to_string()))?;

            Ok(serde_json::json!({
                "ok": true,
                "path": dest.to_string_lossy(),
                "type": input.memory_type,
                "scope": input.scope,
                "slug": input.slug,
            }))
        })
    })
    .with_description("Write a memory entry — routes to the correct destination by type and scope (ADR-038). Types: feedback (dated, parallel-safe), project (upsert), user (upsert), pattern (upsert). Scope: project | global.")
}
