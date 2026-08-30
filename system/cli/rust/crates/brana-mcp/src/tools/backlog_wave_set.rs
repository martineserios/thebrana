use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Wave ID to modify
    pub wave_id: String,
    /// Field to set: status, selector, contract, gate, name, wip_limit
    /// (non-negative integer or "null"; selector/gate frozen while draining)
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

                // t-3234: field=status value=shipped must evaluate the same
                // CHECK: gauge the CLI's `wave ship` runs — computed before
                // the mutation below, from the same shared function, so this
                // surface can never silently skip it again.
                let is_ship = input.field == "status" && input.value == "shipped";
                let check_report = if is_ship {
                    let wave = val["waves"].as_array()
                        .and_then(|arr| arr.iter().find(|w| w["id"].as_str() == Some(&input.wave_id)))
                        .ok_or_else(|| format!("wave {} not found", input.wave_id))?;
                    let empty = Vec::new();
                    let all_tasks = val["tasks"].as_array().unwrap_or(&empty);
                    let repo_root = tf.parent().and_then(|p| p.parent()).map(|p| p.to_path_buf());
                    Some(brana_core::wave_ship::build_ship_report(wave, all_tasks, repo_root.as_deref()))
                } else {
                    None
                };

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

                let mut out = serde_json::json!({
                    "ok": true,
                    "id": input.wave_id,
                    "field": input.field,
                    "value": actual_value,
                });
                if let Some(report) = check_report {
                    out["check_report"] = serde_json::json!(report);
                }
                Ok(out)
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Set a field on a wave: status, selector, contract, gate, name, or wip_limit (non-negative integer or \"null\" = unbounded; ADR-079). selector/gate are frozen while the wave is draining — requeue first. Setting field=status value=shipped evaluates the wave's CHECK: contract lines the same way the CLI's `wave ship` does and returns them under `check_report` (t-3234) — display-only, never blocks the flip.")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;

    struct Hermetic {
        orig_cwd: PathBuf,
        orig_project_dir: Option<String>,
        dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn new(tasks_body: &str) -> Self {
            let dir = tempfile::tempdir().unwrap();
            let claude = dir.path().join(".claude");
            std::fs::create_dir_all(&claude).unwrap();
            std::fs::write(claude.join("tasks.json"), tasks_body).unwrap();
            let orig_cwd = std::env::current_dir().unwrap();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
            std::env::set_current_dir(dir.path()).unwrap();
            Self { orig_cwd, orig_project_dir, dir }
        }
        fn tasks_file(&self) -> PathBuf {
            self.dir.path().join(".claude/tasks.json")
        }
    }

    impl Drop for Hermetic {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.orig_cwd);
            if let Some(v) = &self.orig_project_dir {
                unsafe { std::env::set_var("CLAUDE_PROJECT_DIR", v) };
            }
        }
    }

    fn fixture(wave_status: &str, contract: &str) -> String {
        format!(
            r#"{{"project":"test","tasks":[{{"id":"t-1","subject":"a","status":"pending","tags":["shipme"]}}],
                "waves":[{{"id":"wave-1","name":"w","selector":"tag:shipme","gate":null,"status":"{wave_status}","contract":"{contract}"}}]}}"#
        )
    }

    #[tokio::test]
    async fn test_mcp_wave_set_status_shipped_returns_check_report() {
        // t-3234: the MCP surface used to flip status=shipped with ZERO
        // CHECK: evaluation — the CLI's `wave ship` gauge (t-3162) was
        // silently skipped on the surface most used interactively.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(&fixture("draining", "CHECK: all selector tasks completed"));

        let out = build()
            .handle(
                json!({"wave_id": "wave-1", "field": "status", "value": "shipped"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .unwrap();

        assert_eq!(out["value"], "shipped");
        let report = out["check_report"].as_array().expect("check_report must be present and an array");
        let joined: String = report.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join("\n");
        assert!(joined.contains("FAIL"), "t-1 is pending, not completed — must FAIL:\n{joined}");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["waves"][0]["status"], "shipped", "a red check must not block the flip");
    }

    #[tokio::test]
    async fn test_mcp_wave_set_status_shipped_no_contract_empty_report() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture("draining", ""));

        let out = build()
            .handle(
                json!({"wave_id": "wave-1", "field": "status", "value": "shipped"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .unwrap();

        assert_eq!(out["check_report"], serde_json::json!([]), "no contract lines — empty report, not absent");
    }

    #[tokio::test]
    async fn test_mcp_wave_set_non_ship_field_has_no_check_report() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture("queued", "CHECK: all selector tasks completed"));

        let out = build()
            .handle(
                json!({"wave_id": "wave-1", "field": "wip_limit", "value": "3"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .unwrap();

        assert!(out.get("check_report").is_none(), "non-ship sets must not carry a check_report key");
    }
}
