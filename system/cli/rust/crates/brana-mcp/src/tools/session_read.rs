//! session_read — read the current session state.
//!
//! Returns the full JSON state, or a single field if `field` is specified.
//! Returns `{"found": false}` if no session state exists yet.

use brana_core::session;
use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Optional: return only this field (e.g. "branch", "accomplished", "written_at").
    pub field: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("session_read", |input: Input, _extra| {
        Box::pin(async move {
            let root = brana_core::util::find_project_root()
                .ok_or_else(|| pmcp::Error::validation("not in a git repository"))?;

            match session::read_state(&root) {
                None => Ok(serde_json::json!({ "found": false })),
                Some(state) => {
                    let as_value = serde_json::to_value(&state)
                        .map_err(|e| pmcp::Error::validation(e.to_string()))?;

                    match input.field {
                        Some(ref f) => Ok(serde_json::json!({
                            "found": true,
                            "field": f,
                            "value": as_value[f],
                        })),
                        None => {
                            // Inject "found": true alongside the state
                            let mut result = serde_json::json!({ "found": true });
                            if let serde_json::Value::Object(map) = as_value {
                                for (k, v) in map {
                                    result[k] = v;
                                }
                            }
                            Ok(result)
                        }
                    }
                }
            }
        })
    })
    .with_description("Read the current session state. Returns the full JSON state or a specific field. Returns {found: false} when no state exists.")
}
