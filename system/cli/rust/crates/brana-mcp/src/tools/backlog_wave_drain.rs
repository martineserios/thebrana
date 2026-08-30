use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

/// Drain a wave (t-3235, mirroring CLI `cmd_wave_drain`): gate check +
/// selector resolution, sets status to "draining" — does NOT execute
/// anything or touch matched tasks. Before this tool, MCP had no path at
/// all to a gate-enforced draining transition — only the generic
/// `backlog_wave_set` existed, whose `set_wave_field` deliberately defers
/// gate enforcement (brana-core validation.rs, "that's the intent-CLI's
/// job"). This tool is that CLI job's MCP equivalent, calling the same
/// `check_wave_gate`/`resolve_wave_selector` functions the CLI's `wave
/// drain` verb calls — single shared implementation, no reimplementation.
#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Wave ID to drain
    pub wave_id: String,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_wave_drain", |input: Input, _extra| {
        Box::pin(async move {
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                let _lock = brana_core::tasks::lock_tasks_timeout(&tf)?;
                let mut val = brana_core::tasks::load_raw(&tf)?;

                let waves = val["waves"].as_array().cloned().unwrap_or_default();
                let idx = waves
                    .iter()
                    .position(|w| w["id"].as_str() == Some(&input.wave_id))
                    .ok_or_else(|| format!("wave {} not found", input.wave_id))?;
                let wave = &waves[idx];

                // Draining finished work is a caller error; re-draining a
                // draining wave is idempotent (re-resolves, re-reports —
                // ADR-079's re-resolve model). Mirrors cmd_wave_drain exactly.
                if wave["status"].as_str() == Some("shipped") {
                    return Err(format!("wave {} already shipped — nothing to drain", input.wave_id));
                }

                brana_core::tasks::check_wave_gate(wave, &waves)?;

                let tasks_arr = val["tasks"].as_array().cloned().unwrap_or_default();
                let matched = brana_core::tasks::resolve_wave_selector(wave, &tasks_arr)?;
                let report: Vec<serde_json::Value> = matched
                    .iter()
                    .map(|t| serde_json::json!({"id": t["id"], "subject": t["subject"]}))
                    .collect();

                val["waves"][idx]["status"] = serde_json::Value::String("draining".into());
                brana_core::tasks::save_tasks(&tf, &val)?;

                Ok(serde_json::json!({
                    "ok": true,
                    "id": input.wave_id,
                    "status": "draining",
                    "matched": report,
                    "count": report.len(),
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Drain a wave (t-3235): gate check (check_wave_gate — the wave named in `gate` must be shipped) + selector resolution, sets status to \"draining\". Does NOT execute anything or touch matched tasks. Mirrors the CLI's `wave drain` verb exactly, via the same shared brana-core functions — the MCP equivalent of gate-enforced draining, filling the gap `backlog_wave_set(status=draining)` deliberately never enforced.")
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
    async fn test_drain_sets_status_and_reports_matched() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(
            r#"{"project":"test","tasks":[{"id":"t-1","subject":"a","status":"pending","tags":["shipme"]}],
                "waves":[{"id":"wave-1","name":"w","selector":"tag:shipme","gate":null,"status":"queued"}]}"#,
        );

        let out = build()
            .handle(json!({"wave_id": "wave-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();

        assert_eq!(out["status"], "draining");
        assert_eq!(out["count"], 1);
        assert_eq!(out["matched"][0]["id"], "t-1");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["waves"][0]["status"], "draining");
        assert_eq!(reloaded["tasks"][0]["status"], "pending", "drain must not touch matched tasks");
    }

    #[tokio::test]
    async fn test_gate_not_shipped_blocks_drain() {
        // t-3235's whole point: this must be enforced, unlike backlog_wave_set.
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(
            r#"{"project":"test","tasks":[],
                "waves":[
                    {"id":"wave-0","name":"gate","selector":"tag:none","gate":null,"status":"queued"},
                    {"id":"wave-1","name":"w","selector":"tag:none","gate":"wave-0","status":"queued"}
                ]}"#,
        );

        let err = build()
            .handle(json!({"wave_id": "wave-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("gate wave-0 is not shipped — drain must be blocked");
        assert!(err.to_string().contains("wave-0"), "error must name the unmet gate: {err}");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["waves"][1]["status"], "queued", "blocked drain must not mutate status");
    }

    #[tokio::test]
    async fn test_gate_shipped_allows_drain() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[],
                "waves":[
                    {"id":"wave-0","name":"gate","selector":"tag:none","gate":null,"status":"shipped"},
                    {"id":"wave-1","name":"w","selector":"tag:none","gate":"wave-0","status":"queued"}
                ]}"#,
        );

        let out = build()
            .handle(json!({"wave_id": "wave-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();
        assert_eq!(out["status"], "draining");
    }

    #[tokio::test]
    async fn test_already_shipped_wave_errors() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(
            r#"{"project":"test","tasks":[],"waves":[{"id":"wave-1","name":"w","selector":"tag:x","gate":null,"status":"shipped"}]}"#,
        );

        let err = build()
            .handle(json!({"wave_id": "wave-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("already-shipped wave must not be drainable");
        assert!(err.to_string().contains("already shipped"), "got: {err}");
    }

    #[tokio::test]
    async fn test_unknown_wave_errors() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(r#"{"project":"test","tasks":[],"waves":[]}"#);

        let err = build()
            .handle(json!({"wave_id": "wave-99"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("unknown wave must fail");
        assert!(err.to_string().contains("wave-99"), "got: {err}");
    }
}
