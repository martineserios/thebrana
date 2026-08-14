use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Memory type: feedback, project, user, pattern, convention, field-note, adr
    #[serde(rename = "type")]
    pub memory_type: String,

    /// Scope: project | global | cross-project
    #[serde(default = "default_scope")]
    pub scope: String,

    /// Kebab-case slug — stable topic identifier, consistent across sessions
    pub slug: String,

    /// Memory content to store
    pub content: String,
}

fn default_scope() -> String { "project".into() }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("memory_write", |input: Input, _extra| {
        Box::pin(async move {
            // Synchronous file write run off the async executor (t-2631): a
            // handler that blocks the tokio worker running pmcp's single,
            // fully-serialized stdio dispatch task (t-2305) freezes every
            // other tool for its duration — this is a write path, not just
            // a read, so a stall here is the highest-cost instance of the
            // pattern in the tool set.
            let result = tokio::task::spawn_blocking(move || -> Result<serde_json::Value, String> {
                let root = brana_core::util::find_project_root()
                    .ok_or_else(|| "could not resolve project root".to_string())?;

                let dest = brana_core::memory::write_memory(
                    &input.memory_type,
                    &input.scope,
                    &input.slug,
                    &input.content,
                    &root,
                )
                .map_err(|e| e.to_string())?;

                Ok(serde_json::json!({
                    "ok": true,
                    "path": dest.to_string_lossy(),
                    "type": input.memory_type,
                    "scope": input.scope,
                    "slug": input.slug,
                }))
            })
            .await
            .map_err(|e| pmcp::Error::validation(format!("blocking task panicked: {e}")))?;

            result.map_err(pmcp::Error::validation)
        })
    })
    .with_description("Write a memory entry — routes to the correct destination by type and scope (ADR-038). Types: feedback (dated, parallel-safe), project (upsert), user (upsert), pattern (upsert). Scope: project | global.")
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::CWD_LOCK;
    use pmcp::ToolHandler;
    use serde_json::json;

    /// RAII guard: isolates HOME and CLAUDE_PROJECT_DIR to a tempdir, so
    /// write_memory's destination resolution (which always roots under
    /// `home()`, even for "project" scope — see resolve_memory_dir) never
    /// touches the real `~/.claude/projects/...` tree. Callers must hold
    /// CWD_LOCK for its lifetime.
    struct Hermetic {
        orig_home: Option<String>,
        orig_project_dir: Option<String>,
        _dir: tempfile::TempDir,
    }

    impl Hermetic {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let project_root = dir.path().join("project");
            std::fs::create_dir_all(&project_root).unwrap();

            let orig_home = std::env::var("HOME").ok();
            let orig_project_dir = std::env::var("CLAUDE_PROJECT_DIR").ok();
            // SAFETY: caller holds CWD_LOCK; no other test in this binary
            // reads or writes these env vars concurrently.
            unsafe {
                std::env::set_var("HOME", dir.path());
                std::env::set_var("CLAUDE_PROJECT_DIR", &project_root);
            }

            Self { orig_home, orig_project_dir, _dir: dir }
        }
    }

    impl Drop for Hermetic {
        fn drop(&mut self) {
            // SAFETY: still under CWD_LOCK.
            unsafe {
                match &self.orig_home {
                    Some(v) => std::env::set_var("HOME", v),
                    None => std::env::remove_var("HOME"),
                }
                match &self.orig_project_dir {
                    Some(v) => std::env::set_var("CLAUDE_PROJECT_DIR", v),
                    None => std::env::remove_var("CLAUDE_PROJECT_DIR"),
                }
            }
        }
    }

    /// t-2631 (Challenger iteration 2 follow-up): memory_write is a write
    /// path, the highest-cost instance of the spawn_blocking sweep — this
    /// locks in that it still writes correct content after the refactor.
    #[tokio::test]
    async fn test_write_project_memory_creates_file_with_content() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new();

        let out = build()
            .handle(
                json!({"type": "project", "scope": "project", "slug": "t2631-test", "content": "hello memory"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect("write must succeed");

        assert_eq!(out["ok"], true);
        let path = out["path"].as_str().expect("path must be a string");
        assert!(path.ends_with("project_t2631-test.md"), "unexpected path: {path}");
        let written = std::fs::read_to_string(path).expect("file must exist");
        assert_eq!(written, "hello memory");
    }

    #[tokio::test]
    async fn test_write_rejects_unimplemented_type() {
        let _g = CWD_LOCK.lock().unwrap_or_else(|p| p.into_inner());
        let _h = Hermetic::new();

        let err = build()
            .handle(
                json!({"type": "adr", "scope": "project", "slug": "x", "content": "y"}),
                pmcp::RequestHandlerExtra::default(),
            )
            .await
            .expect_err("unimplemented type must be rejected, not silently accepted");

        assert!(err.to_string().contains("not yet implemented"), "error must explain why: {err}");
    }
}
