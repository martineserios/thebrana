use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Wave ID (e.g. "wave-1")
    pub wave_id: String,
    /// Optional: return only a specific field (e.g. "status", "selector")
    pub field: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_wave_get", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let data = brana_core::tasks::load_tasks(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let wave = data.waves.iter()
                .find(|w| w["id"].as_str() == Some(&input.wave_id))
                .ok_or_else(|| pmcp::Error::validation(format!("wave {} not found", input.wave_id)))?;

            match input.field {
                Some(ref f) => Ok(serde_json::json!({
                    "id": input.wave_id,
                    "field": f,
                    "value": wave[f],
                })),
                None => Ok(wave.clone()),
            }
        })
    })
    .with_description("Get a single wave by ID, optionally returning only a specific field.")
}
