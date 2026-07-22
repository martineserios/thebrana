use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Deserialize, JsonSchema)]
pub struct BatchOp {
    /// Task ID to modify
    pub task_id: String,

    /// Map of field name to value. Same field names as backlog_set.
    /// For tags/blocked_by: use "+tag" to add, "-tag" to remove.
    pub fields: HashMap<String, String>,

    /// If true, append to text fields (context, notes) instead of replacing
    #[serde(default)]
    pub append: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
pub struct Input {
    /// Array of operations. Each sets one or more fields on a task.
    /// All operations share one file read/write — much faster than N separate backlog_set calls.
    pub ops: Vec<BatchOp>,
}

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_batch", |input: Input, _extra| {
        Box::pin(async move {
            if input.ops.is_empty() {
                return Err(pmcp::Error::validation("ops array is empty"));
            }

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

                let mut results = Vec::new();

                {
                    let tasks = val["tasks"].as_array_mut()
                        .ok_or_else(|| "tasks.json has no tasks array".to_string())?;

                    for op in &input.ops {
                        let task = match tasks.iter_mut()
                            .find(|t| t["id"].as_str() == Some(&op.task_id))
                        {
                            Some(t) => t,
                            None => {
                                results.push(serde_json::json!({
                                    "id": op.task_id,
                                    "ok": false,
                                    "error": format!("task {} not found", op.task_id),
                                }));
                                continue;
                            }
                        };

                        // Sorted order: HashMap iteration is random, which made
                        // pre-fix partial applies nondeterministic (t-1958)
                        let mut fields: Vec<(String, String)> = op.fields.iter()
                            .map(|(k, v)| (k.clone(), v.clone()))
                            .collect();
                        fields.sort();

                        // All-or-nothing per op: a failed op leaves the task untouched
                        match brana_core::tasks::set_fields_atomic(task, &fields, op.append) {
                            Ok(updated) => {
                                results.push(serde_json::json!({
                                    "id": op.task_id,
                                    "ok": true,
                                    "fields": updated,
                                }));
                            }
                            Err(errors) => {
                                results.push(serde_json::json!({
                                    "id": op.task_id,
                                    "ok": false,
                                    "fields": {},
                                    "errors": errors,
                                }));
                            }
                        }
                    }
                }

                let any_ok = results.iter().any(|r| r["ok"] == true);
                if any_ok {
                    brana_core::tasks::save_tasks(&tf, &val)?;
                }

                let all_ok = results.iter().all(|r| r["ok"] == true);

                Ok(serde_json::json!({
                    "ok": all_ok,
                    "results": results,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Batch set fields on multiple tasks in one call. One file read/write for all operations. Each op specifies a task_id and a fields map.")
}
