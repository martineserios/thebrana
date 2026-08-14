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
            // Synchronous file I/O run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let data = brana_core::tasks::load_tasks(&tf)?;

                let wave = data.waves.iter()
                    .find(|w| w["id"].as_str() == Some(&input.wave_id))
                    .ok_or_else(|| format!("wave {} not found", input.wave_id))?;

                match input.field {
                    Some(ref f) => Ok(serde_json::json!({
                        "id": input.wave_id,
                        "field": f,
                        "value": wave[f],
                    })),
                    None => Ok(wave.clone()),
                }
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Get a single wave by ID, optionally returning only a specific field.")
}
