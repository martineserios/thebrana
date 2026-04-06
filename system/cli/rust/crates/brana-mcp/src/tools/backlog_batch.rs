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

            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let mut val = brana_core::tasks::load_raw(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let mut results = Vec::new();

            {
                let tasks = val["tasks"].as_array_mut()
                    .ok_or_else(|| pmcp::Error::validation("tasks.json has no tasks array"))?;

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

                    let mut updated = serde_json::Map::new();
                    let mut errors = Vec::new();

                    for (field, value) in &op.fields {
                        match brana_core::tasks::set_field(task, field, value, op.append) {
                            Ok(()) => {
                                updated.insert(field.clone(), task[field.as_str()].clone());
                            }
                            Err(e) => {
                                errors.push(format!("{field}: {e}"));
                            }
                        }
                    }

                    if errors.is_empty() {
                        results.push(serde_json::json!({
                            "id": op.task_id,
                            "ok": true,
                            "fields": updated,
                        }));
                    } else {
                        results.push(serde_json::json!({
                            "id": op.task_id,
                            "ok": false,
                            "fields": updated,
                            "errors": errors,
                        }));
                    }
                }
            }

            brana_core::tasks::save_tasks(&tf, &val)
                .map_err(|e| pmcp::Error::validation(e))?;

            let all_ok = results.iter().all(|r| r["ok"] == true);

            Ok(serde_json::json!({
                "ok": all_ok,
                "results": results,
            }))
        })
    })
    .with_description("Batch set fields on multiple tasks in one call. One file read/write for all operations. Each op specifies a task_id and a fields map.")
}
