use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

/// t-2842 (ADR-080 §4): MCP has no stdin, so the "one explicit confirmation
/// per batch" gesture is the caller supplying an explicit `confirm_ids` list
/// (≤10) rather than a y/n prompt. Omitting it previews the plan and applies
/// nothing — the safe default for a first call.
#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Wave ID to approve against
    pub wave_id: String,
    /// Explicit task ids to approve this call (at most 10 — the rubber-stamp
    /// guard, ADR-080 §4). Omit to preview: returns batches + none_ids
    /// without approving anything.
    pub confirm_ids: Option<Vec<String>>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_wave_approve", |input: Input, _extra| {
        Box::pin(async move {
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                // Unlocked plan read (t-2166 precedent) — approval writes
                // below go through perform_ac_approve's own short-lived lock.
                let data = brana_core::tasks::load_raw(&tf)?;
                let wave = data["waves"].as_array()
                    .and_then(|ws| ws.iter().find(|w| w["id"].as_str() == Some(&input.wave_id)))
                    .ok_or_else(|| format!("wave {} not found", input.wave_id))?
                    .clone();
                let tasks_arr = data["tasks"].as_array().cloned().unwrap_or_default();
                let plan = brana_core::tasks::plan_wave_approve(&wave, &tasks_arr)?;

                let plan_json = |plan: &brana_core::tasks::WaveApprovePlan| {
                    serde_json::json!({
                        "batches": plan.batches.iter().map(|b| {
                            b.iter().map(|(id, criteria)| serde_json::json!({
                                "id": id, "proposed_acceptance_criteria": criteria,
                            })).collect::<Vec<_>>()
                        }).collect::<Vec<_>>(),
                        "none_ids": plan.none_ids,
                    })
                };

                let confirm_ids = match &input.confirm_ids {
                    None => {
                        return Ok(serde_json::json!({
                            "ok": true, "id": input.wave_id, "applied": null,
                            "plan": plan_json(&plan),
                        }));
                    }
                    Some(ids) => ids,
                };
                if confirm_ids.len() > brana_core::tasks::WAVE_APPROVE_BATCH_CAP {
                    return Err(format!(
                        "confirm_ids has {} entries — batches are capped at {} (ADR-080 §4 rubber-stamp guard)",
                        confirm_ids.len(), brana_core::tasks::WAVE_APPROVE_BATCH_CAP
                    ));
                }
                // Forward-only guard (apply_ac_proposals precedent): only ids
                // that are CURRENTLY proposed-and-matched are approvable —
                // never trust a caller-supplied id blindly.
                let approvable: std::collections::HashSet<&String> =
                    plan.batches.iter().flatten().map(|(id, _)| id).collect();
                let mut applied = Vec::new();
                for id in confirm_ids {
                    if !approvable.contains(id) {
                        return Err(format!(
                            "{id} is not a currently-matched ac_state:proposed task in wave {} — recompute the plan (nothing applied)",
                            input.wave_id
                        ));
                    }
                    let outcome = brana_core::tasks::perform_ac_approve(&tf, id)?;
                    applied.push(serde_json::json!({
                        "id": id, "promoted": outcome.promoted,
                        "already_approved": outcome.already_approved,
                    }));
                }

                Ok(serde_json::json!({
                    "ok": true, "id": input.wave_id, "applied": applied,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Batch AC approve over a wave (ADR-080 §4): resolves the wave selector, lists ac_state:proposed matches with proposed criteria. Omit confirm_ids to preview; pass an explicit id list (≤10) to approve — a batch loop over the sanctioned backlog_ac_approve verb, no new state semantics. Denied to the drain-loop runner manifest.")
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

    fn fixture(ac_state: &str) -> String {
        format!(
            r#"{{"project":"test","tasks":[{{"id":"t-1","subject":"x","status":"pending","tags":["w1"],
                "ac_state":"{ac_state}","proposed_acceptance_criteria":["done when green"]}}],
                "waves":[{{"id":"wave-1","name":"w","selector":"tag:w1","gate":null,"status":"draining"}}]}}"#
        )
    }

    #[tokio::test]
    async fn test_mcp_wave_approve_preview_applies_nothing() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(&fixture("proposed"));

        let out = build()
            .handle(json!({"wave_id": "wave-1"}), pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();
        assert_eq!(out["applied"], serde_json::Value::Null);
        assert_eq!(out["plan"]["batches"][0][0]["id"], "t-1");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["tasks"][0]["ac_state"], "proposed",
            "preview call must not approve anything");
    }

    #[tokio::test]
    async fn test_mcp_wave_approve_confirm_ids_approves() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(&fixture("proposed"));

        let out = build()
            .handle(json!({"wave_id": "wave-1", "confirm_ids": ["t-1"]}),
                pmcp::RequestHandlerExtra::default())
            .await
            .unwrap();
        assert_eq!(out["applied"][0]["id"], "t-1");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["tasks"][0]["ac_state"], "approved");
    }

    #[tokio::test]
    async fn test_mcp_wave_approve_confirm_ids_over_cap_rejected() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(&fixture("proposed"));
        let ids: Vec<String> = (0..11).map(|i| format!("t-{i}")).collect();

        let err = build()
            .handle(json!({"wave_id": "wave-1", "confirm_ids": ids}),
                pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("over-cap confirm_ids must be rejected");
        assert!(err.to_string().contains("capped at 10"), "got: {err}");
    }

    #[tokio::test]
    async fn test_mcp_wave_approve_confirm_id_not_matched_rejected() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new(&fixture("none"));

        let err = build()
            .handle(json!({"wave_id": "wave-1", "confirm_ids": ["t-1"]}),
                pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("ac_state:none task must not be approvable via confirm_ids");
        assert!(err.to_string().contains("not a currently-matched"), "got: {err}");

        let reloaded: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(h.tasks_file()).unwrap()).unwrap();
        assert_eq!(reloaded["tasks"][0]["ac_state"], "none",
            "rejected confirm must not mutate anything");
    }

    #[tokio::test]
    async fn test_mcp_wave_approve_unknown_wave_errors() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new(r#"{"project":"test","tasks":[],"waves":[]}"#);

        let err = build()
            .handle(json!({"wave_id": "wave-9"}), pmcp::RequestHandlerExtra::default())
            .await
            .expect_err("unknown wave must fail");
        assert!(err.to_string().contains("wave-9"), "got: {err}");
    }
}
