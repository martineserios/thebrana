use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Scope to index: project | global
    #[serde(default = "default_scope")]
    pub scope: String,
}

fn default_scope() -> String { "project".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("memory_index", |input: Input, _extra| {
        Box::pin(async move {
            let root = brana_core::util::find_project_root()
                .ok_or_else(|| pmcp::Error::validation("could not resolve project root"))?;

            brana_core::memory::index_memory(&input.scope, &root)
                .map_err(|e| pmcp::Error::validation(e.to_string()))?;

            Ok(serde_json::json!({
                "ok": true,
                "scope": input.scope,
            }))
        })
    })
    .with_description("Regenerate MEMORY.md from the filesystem — groups by slug, picks newest dated file per slug (ADR-038 §D).")
}
