use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Human-readable wave name
    pub name: String,
    /// Selector query text — stored without resolution; role: selectors are
    /// validated at add time (only role:ready-for-agent is pullable, t-3250)
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
                // t-3250: same valve guard as cmd_wave_add — a role: selector
                // the pull step can never drain would stall forever.
                brana_core::tasks::validate_wave_selector_role(&input.selector)?;

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

    #[tokio::test]
    async fn test_add_rejects_non_pullable_role_selector() {
        // t-3250: same valve guard as cmd_wave_add — a role:needs-triage wave
        // can never pull (pull step is role:ready-for-agent only).
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(r#"{"project":"test","tasks":[],"waves":[]}"#);

        let err = build()
            .handle(
                json!({"name": "w", "selector": "role:needs-triage"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect_err("non-pullable role selector must be rejected at add");
        let msg = err.to_string();
        assert!(msg.contains("needs-triage") && msg.contains("ready-for-agent"), "got: {msg}");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert!(reloaded["waves"].as_array().map(|a| a.is_empty()).unwrap_or(true),
            "rejected add must not store a wave");
    }

    #[tokio::test]
    async fn test_add_accepts_ready_for_agent_role_selector() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(r#"{"project":"test","tasks":[],"waves":[]}"#);

        let out = build()
            .handle(
                json!({"name": "standing", "selector": "role:ready-for-agent"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .unwrap();
        assert_eq!(out["ok"], true);

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["waves"][0]["selector"], "role:ready-for-agent");
    }
}
