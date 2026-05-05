use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Task subject/title
    pub subject: String,

    /// Stream: roadmap, bugs, tech-debt, docs, experiments, research, personal
    #[serde(default = "default_stream")]
    pub stream: String,

    /// Task type: task, subtask, phase, milestone
    #[serde(default = "default_type")]
    pub task_type: String,

    /// Comma-separated tags
    pub tags: Option<String>,

    /// Task description
    pub description: Option<String>,

    /// Effort: S, M, L, XL
    pub effort: Option<String>,

    /// Priority: P0, P1, P2, P3
    pub priority: Option<String>,

    /// Parent task ID
    pub parent: Option<String>,
}

fn default_stream() -> String { "roadmap".into() }
fn default_type() -> String { "task".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("backlog_add", |input: Input, _extra| {
        Box::pin(async move {
            let tf = brana_core::util::find_tasks_file()
                .ok_or_else(|| pmcp::Error::validation("tasks.json not found"))?;
            let mut val = brana_core::tasks::load_raw(&tf)
                .map_err(|e| pmcp::Error::validation(e))?;

            let tasks = val["tasks"].as_array()
                .ok_or_else(|| pmcp::Error::validation("tasks.json has no tasks array"))?;

            if let Some(p) = input.priority.as_deref() {
                brana_core::tasks::validate_priority(p)
                    .map_err(pmcp::Error::validation)?;
            }

            let id = brana_core::tasks::next_id(tasks);

            let tags: Vec<serde_json::Value> = input.tags
                .as_deref()
                .map(|t| t.split(',').map(|s| serde_json::Value::String(s.trim().to_string())).collect())
                .unwrap_or_default();

            let today = chrono::Local::now().format("%Y-%m-%d").to_string();

            let task = serde_json::json!({
                "id": id,
                "subject": input.subject,
                "status": "pending",
                "stream": input.stream,
                "type": input.task_type,
                "tags": tags,
                "description": input.description,
                "effort": input.effort,
                "priority": input.priority,
                "parent": input.parent,
                "created": today,
                "started": null,
                "completed": null,
                "blocked_by": [],
                "branch": null,
                "context": null,
                "notes": null,
                "order": 0,
                "github_issue": null,
                "execution": "code",
            });

            val["tasks"].as_array_mut()
                .ok_or_else(|| pmcp::Error::validation("tasks.json has no tasks array"))?
                .push(task);

            brana_core::tasks::save_tasks(&tf, &val)
                .map_err(|e| pmcp::Error::validation(e))?;

            Ok(serde_json::json!({
                "ok": true,
                "id": id,
                "subject": input.subject,
            }))
        })
    })
    .with_description("Add a new task to the backlog. Returns the assigned task ID.")
}
