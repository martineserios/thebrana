use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Wave ID to modify
    pub wave_id: String,
    /// Field to set: status, selector, contract, gate, name
    pub field: String,
    /// New value. Use "null" to clear an optional field.
    pub value: String,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_wave_set", |input: Input, _extra| {
        Box::pin(async move {
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let _lock = brana_core::tasks::lock_tasks_timeout(&tf)?;
                let mut val = brana_core::tasks::load_raw(&tf)?;

                let actual_value = {
                    let waves = val["waves"].as_array_mut()
                        .ok_or_else(|| "tasks.json has no waves array".to_string())?;

                    let wave = waves.iter_mut()
                        .find(|w| w["id"].as_str() == Some(&input.wave_id))
                        .ok_or_else(|| format!("wave {} not found", input.wave_id))?;

                    brana_core::tasks::set_wave_field(wave, &input.field, &input.value)?;

                    wave[&input.field].clone()
                };

                brana_core::tasks::save_tasks(&tf, &val)?;

                Ok(serde_json::json!({
                    "ok": true,
                    "id": input.wave_id,
                    "field": input.field,
                    "value": actual_value,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Set a field on a wave: status, selector, contract, gate, or name.")
}
