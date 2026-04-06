//! session_history — list past session states.
//!
//! Returns an array of past session state summaries (most recent first).
//! Defaults to last 5 entries. Full objects are returned so callers can
//! extract any field.

use brana_core::session;
use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Maximum number of history entries to return. Defaults to 5.
    pub limit: Option<u32>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("session_history", |input: Input, _extra| {
        Box::pin(async move {
            let root = brana_core::util::find_project_root()
                .ok_or_else(|| pmcp::Error::validation("not in a git repository"))?;

            let limit = input.limit.unwrap_or(5) as usize;
            let entries = session::read_history(&root, limit);

            let items: Vec<serde_json::Value> = entries
                .iter()
                .map(|s| serde_json::to_value(s).unwrap_or(serde_json::Value::Null))
                .collect();

            Ok(serde_json::json!({
                "count": items.len(),
                "entries": items,
            }))
        })
    })
    .with_description("List past session states, most recent first. Returns up to `limit` entries (default 5).")
}
