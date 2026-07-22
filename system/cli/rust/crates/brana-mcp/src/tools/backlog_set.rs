use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Task ID to modify
    pub task_id: String,

    /// Field to set (e.g. "status", "priority", "effort", "tags", "context", "notes")
    pub field: String,

    /// New value for the field. For tags: "+tag" to add, "-tag" to remove.
    pub value: String,

    /// If true, append to existing value instead of replacing (for context, notes)
    #[serde(default)]
    pub append: bool,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_set", |input: Input, _extra| {
        Box::pin(async move {
            // The whole read-modify-write is synchronous std I/O (including the lock
            // acquire) — run it off the async executor so it can never block the
            // (fully-serialized, t-2305) stdio dispatch loop while waiting.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let tf = brana_core::util::find_tasks_file()
                    .ok_or_else(|| "tasks.json not found".to_string())?;
                // Serialize the read-modify-write against concurrent writers (t-2166).
                // Bounded acquire (t-2305): an unbounded flock() here can starve pmcp's
                // fully-serialized stdio dispatch loop for the rest of the session if
                // contended by a concurrent writer.
                let _lock = brana_core::tasks::lock_tasks_timeout(&tf)?;
                let mut val = brana_core::tasks::load_raw(&tf)?;

                // Scoped mutable borrow for task mutation
                let actual_value = {
                    let tasks = val["tasks"].as_array_mut()
                        .ok_or_else(|| "tasks.json has no tasks array".to_string())?;

                    let task = tasks.iter_mut()
                        .find(|t| t["id"].as_str() == Some(&input.task_id))
                        .ok_or_else(|| format!("task {} not found", input.task_id))?;

                    brana_core::tasks::set_field(task, &input.field, &input.value, input.append)?;

                    task[&input.field].clone()
                };

                brana_core::tasks::save_tasks(&tf, &val)?;

                Ok(serde_json::json!({
                    "ok": true,
                    "id": input.task_id,
                    "field": input.field,
                    "value": actual_value,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Set a field on a task. Supports status, priority, effort, tags (+/-), context, notes, and more.")
}

// Handler-level test lives here rather than in tests/tool_tests.rs because
// brana-mcp is a binary-only crate: integration tests cannot import `tools::`.
// #[cfg(test)] code is never compiled into the shipped binary.

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;
    use std::path::PathBuf;

    /// RAII guard: chdir into an isolated non-git tempdir holding a fixture
    /// tasks.json, with CLAUDE_PROJECT_DIR cleared, so the handler's
    /// find_tasks_file() resolves to the fixture instead of the real repo's
    /// .claude/tasks.json. Restores cwd and env on drop. Callers must hold
    /// CWD_LOCK for the guard's whole lifetime.
    struct Hermetic {
        orig_cwd: PathBuf,
        orig_project_dir: Option<String>,
        dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let claude = dir.path().join(".claude");
            std::fs::create_dir_all(&claude).unwrap();
            std::fs::write(
                claude.join("tasks.json"),
                r#"{"project":"test","tasks":[{"id":"t-1","subject":"x","status":"pending"}]}"#,
            )
            .unwrap();
            let orig_cwd = std::env::current_dir().unwrap();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            // SAFETY: caller holds CWD_LOCK; no other test in this binary
            // reads or writes the environment concurrently.
            unsafe { std::env::remove_var("CLAUDE_PROJECT_DIR") };
            std::env::set_current_dir(dir.path()).unwrap();
            Self {
                orig_cwd,
                orig_project_dir,
                dir,
            }
        }

        fn tasks_file(&self) -> PathBuf {
            self.dir.path().join(".claude/tasks.json")
        }
    }

    impl Drop for Hermetic {
        fn drop(&mut self) {
            let _ = std::env::set_current_dir(&self.orig_cwd);
            if let Some(v) = &self.orig_project_dir {
                // SAFETY: still under CWD_LOCK (guard drops before the lock).
                unsafe { std::env::set_var("CLAUDE_PROJECT_DIR", v) };
            }
        }
    }

    /// End-to-end reproduction for t-2305: through the REAL tool handler (not just the
    /// library function), with the lock genuinely held by another thread, the handler
    /// must return the bounded timeout error — not hang. Waits out the real
    /// `DEFAULT_LOCK_TIMEOUT` (10s), so it's excluded from the default fast suite;
    /// run explicitly with `cargo test -- --ignored` to verify.
    #[tokio::test]
    #[ignore = "waits out the real DEFAULT_LOCK_TIMEOUT (10s) end-to-end — run with `cargo test -- --ignored` (t-2305)"]
    // ASSUMPTION (t-2305 AC4, documented per spec-assumptions.md — flagged by Challenger
    // gate iteration 1): AC4's literal text names `backlog_get` as the repro target, but
    // backlog_get never calls lock_tasks/lock_sidecar — it's a pure unlocked read, so it
    // architecturally cannot produce a lock-timeout error. Chose backlog_set instead
    // because it's the mechanism-accurate target: a real lock-acquiring writer. The
    // *dispatch-queue* symptom AC4 was reaching for (an unrelated queued call recovering
    // once the blocking call ahead of it resolves) is separately covered by
    // `queued_unrelated_request_recovers_after_blocking_request_times_out` below, which
    // exercises pmcp's actual serialized dispatch loop rather than a single handler.
    async fn test_mcp_set_handler_times_out_cleanly_under_contention() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let h = Hermetic::new();
        let tf = h.tasks_file();

        // Hold the lock from a background thread for the whole test — never released
        // within the timeframe below, mirroring the anomalous-contention scenario
        // that froze the server in the original bug report.
        let holder = std::thread::spawn(move || {
            let _guard = brana_core::util::lock_sidecar(&tf).expect("holder should acquire immediately");
            std::thread::sleep(std::time::Duration::from_secs(30));
        });
        std::thread::sleep(std::time::Duration::from_millis(50)); // let the holder acquire first

        let start = std::time::Instant::now();
        // Outer safety net: fail the test explicitly (not the whole process hanging
        // forever) if the handler somehow still doesn't bound itself.
        let outer = tokio::time::timeout(
            std::time::Duration::from_secs(20),
            build().handle(
                json!({"task_id": "t-1", "field": "status", "value": "in_progress"}),
                pmcp::RequestHandlerExtra::default(),
            ),
        )
        .await
        .expect("handler must return well within the outer safety window, not hang forever");
        let elapsed = start.elapsed();

        let err = outer.expect_err("handler must fail while the lock is held, not succeed");
        let msg = err.to_string();
        assert!(
            msg.contains(brana_core::util::LOCK_TIMEOUT_PREFIX),
            "error should be the identifiable lock-timeout error, got: {msg}"
        );
        assert!(
            elapsed >= brana_core::util::DEFAULT_LOCK_TIMEOUT
                && elapsed < brana_core::util::DEFAULT_LOCK_TIMEOUT + std::time::Duration::from_secs(3),
            "should return promptly after DEFAULT_LOCK_TIMEOUT elapses, not hang: waited {elapsed:?}"
        );

        drop(holder); // thread outlives the assertion; process exit reclaims it
    }
}
