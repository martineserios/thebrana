use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Human-readable wave name
    pub name: String,
    /// Selector query text — stored opaque, not parsed or executed by this tool
    pub selector: String,
    /// Ship criteria (free text)
    pub contract: Option<String>,
    /// Wave ID that must be `shipped` before this wave may drain (not enforced in this slice)
    pub gate: Option<String>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_wave_add", |input: Input, _extra| {
        Box::pin(async move {
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let _lock = brana_core::tasks::lock_tasks_timeout(&tf)?;
                let mut val = brana_core::tasks::load_raw(&tf)?;

                if val["waves"].is_null() {
                    val["waves"] = serde_json::json!([]);
                }
                let waves_arr = val["waves"].as_array().cloned().unwrap_or_default();
                let id = brana_core::tasks::next_wave_id(&waves_arr);

                let wave = serde_json::json!({
                    "id": id,
                    "name": input.name,
                    "selector": input.selector,
                    "contract": input.contract,
                    "gate": input.gate,
                    "status": "queued",
                    "created": chrono::Local::now().format("%Y-%m-%d").to_string(),
                });

                val["waves"].as_array_mut()
                    .ok_or_else(|| "tasks.json waves is not an array".to_string())?
                    .push(wave.clone());
                brana_core::tasks::save_tasks(&tf, &val)?;

                Ok(serde_json::json!({"ok": true, "id": id, "wave": wave}))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Create a wave — a thin stored process object (ADR-065): {selector, contract, gate, status}. Storage only; does not resolve the selector against tasks.")
}
