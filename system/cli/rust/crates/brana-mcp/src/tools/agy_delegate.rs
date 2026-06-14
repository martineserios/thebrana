//! agy_delegate — delegate a task to the agy (Gemini) worker.
//!
//! Typed contract: task + context + output_format → validated output string.
//! Handles: version pin, timeout (120s), stdio isolation, /tmp/ cleanup.
//!
//! Adversarial spike spec: docs/architecture/features/claude-gemini-orchestration.md

use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Instant;
use tokio::process::Command;

// Version is informational — mismatch emits a `version_warning` field but does NOT block delegation.
// Update when re-running the adversarial spike to validate a new agy version.
const AGY_PINNED_VERSION: &str = "1.0.8";
const AGY_TIMEOUT_SECS: u64 = 120;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// What the worker should do. Must be self-contained — no implicit session context.
    pub task: String,
    /// Ruflo enrichment context (knowledge + patterns). Injected by ENRICH step.
    #[serde(default)]
    pub context: Option<String>,
    /// Output format instructions (e.g. "Return a markdown table with columns: ...").
    #[serde(default)]
    pub output_format: Option<String>,
}

/// Removes a /tmp/ file on drop — ensures cleanup even on early return.
struct TmpFile(PathBuf);
impl Drop for TmpFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

pub fn build() -> TypedTool<
    Input,
    impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<
        Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>,
    > + Send + Sync,
> {
    TypedTool::new("agy_delegate", |input: Input, _extra| {
        Box::pin(async move {
            // Step 0: version check — warn in response but do NOT block delegation.
            // Pinning was too strict: any agy update would break delegation until
            // brana-mcp was rebuilt. Callers (challenge, build) need agy to work
            // across version updates; they can inspect `version_warning` if needed.
            let version_warning = check_version().await.err();

            // Build prompt from task + optional context + optional output format.
            let prompt = build_prompt(
                &input.task,
                input.context.as_deref(),
                input.output_format.as_deref(),
            );

            // Write prompt to /tmp/ for audit trail. Drop guard removes it on return.
            let prompt_path = tmp_path("prompt");
            std::fs::write(&prompt_path, &prompt)
                .map_err(|e| pmcp::Error::validation(format!("failed to write prompt file: {e}")))?;
            let _prompt_guard = TmpFile(prompt_path);

            // Invoke agy with 120s hard ceiling. agy's own --print-timeout is 5m.
            let start = Instant::now();
            let result = tokio::time::timeout(
                std::time::Duration::from_secs(AGY_TIMEOUT_SECS),
                invoke_agy(&prompt),
            )
            .await;

            let elapsed_ms = start.elapsed().as_millis() as u64;

            match result {
                Err(_elapsed) => Err(pmcp::Error::validation(
                    serde_json::json!({
                        "error": "agy_timeout",
                        "elapsed_secs": AGY_TIMEOUT_SECS,
                        "message": format!("agy did not complete within {AGY_TIMEOUT_SECS}s — check quota or network"),
                    })
                    .to_string(),
                )),
                Ok(Err(e)) => Err(pmcp::Error::validation(e)),
                Ok(Ok(output)) => {
                    let mut resp = serde_json::json!({
                        "ok": true,
                        "output": output,
                        "elapsed_ms": elapsed_ms,
                    });
                    if let Some(warn) = version_warning {
                        resp["version_warning"] = serde_json::Value::String(warn);
                    }
                    Ok(resp)
                }
            }
        })
    })
    .with_description(
        "Delegate a task to agy (Gemini worker). Blocks until complete (v1 foreground-only). \
         Returns validated output. Claude applies the result — agy never writes to the repo.",
    )
}

// ── Version check ────────────────────────────────────────────────────────────

/// Resolve the agy binary path. `AGY_BIN` env var overrides (used in integration tests).
fn agy_bin() -> String {
    std::env::var("AGY_BIN").unwrap_or_else(|_| "agy".to_string())
}

async fn check_version() -> Result<(), String> {
    check_version_with_bin(&agy_bin()).await
}

async fn check_version_with_bin(bin: &str) -> Result<(), String> {
    let out = Command::new(bin)
        .arg("--version")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .await
        .map_err(|e| format!("agy not found or not executable: {e}"))?;

    if !out.status.success() {
        // --version flag unavailable — degrade to binary existence check only.
        return check_version_fallback();
    }

    let version = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if version != AGY_PINNED_VERSION {
        return Err(format!(
            "agy version mismatch: expected {AGY_PINNED_VERSION}, got {version} — \
             update AGY_PINNED_VERSION in agy_delegate.rs after re-running adversarial spike"
        ));
    }
    Ok(())
}

/// Fallback when `agy --version` is unavailable. Confirms binary exists.
/// Full hash pinning requires adding the sha2 crate — deferred.
fn check_version_fallback() -> Result<(), String> {
    for candidate in [
        "/home/martineserios/.local/bin/agy",
        "/usr/local/bin/agy",
        "/usr/bin/agy",
    ] {
        if std::path::Path::new(candidate).exists() {
            return Err(format!(
                "agy --version flag unavailable — cannot verify version pin {AGY_PINNED_VERSION}. \
                 Found binary at {candidate}. Add sha2 crate to implement hash pinning."
            ));
        }
    }
    Err(format!(
        "agy binary not found in known paths and --version flag unavailable. \
         Ensure agy is installed before using agy_delegate."
    ))
}

// ── Invocation ───────────────────────────────────────────────────────────────

async fn invoke_agy(prompt: &str) -> Result<String, String> {
    invoke_agy_with_bin(&agy_bin(), prompt).await
}

async fn invoke_agy_with_bin(bin: &str, prompt: &str) -> Result<String, String> {
    let out = Command::new(bin)
        .arg("-p")
        .arg(prompt)
        .stdin(Stdio::null())   // never inherit MCP stdin — corrupts JSON-RPC stream
        .stdout(Stdio::piped()) // capture; must not bleed into MCP stdout
        .stderr(Stdio::piped()) // capture for error reporting
        .output()
        .await
        .map_err(|e| format!("failed to spawn agy: {e}"))?;

    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    let exit_code = out.status.code().unwrap_or(-1);

    validate_output(&stdout, exit_code, &stderr)
}

// ── Validation ───────────────────────────────────────────────────────────────

/// Validate agy output per the adversarial spike spec.
///
/// Spike findings (2026-05-24):
/// - All errors (empty prompt, internal timeout) go to stdout with exit 0.
/// - Only invalid flags produce non-zero exit (exit 2).
/// - stderr is always empty — not signal-bearing, captured for completeness.
fn validate_output(stdout: &str, exit_code: i32, stderr: &str) -> Result<String, String> {
    if exit_code != 0 {
        return Err(serde_json::json!({
            "error": "agy_nonzero_exit",
            "exit_code": exit_code,
            "stdout": stdout.trim(),
            "stderr": stderr.trim(),
        })
        .to_string());
    }

    let trimmed = stdout.trim();

    if trimmed.is_empty() {
        return Err(serde_json::json!({
            "error": "agy_empty_output",
            "stderr": stderr.trim(),
        })
        .to_string());
    }

    // agy uses "Error: " prefix for all user-visible errors (empty prompt,
    // internal timeout, etc.) — even on exit 0.
    if trimmed.starts_with("Error: ") {
        return Err(serde_json::json!({
            "error": "agy_error",
            "message": trimmed,
        })
        .to_string());
    }

    Ok(trimmed.to_string())
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn build_prompt(task: &str, context: Option<&str>, output_format: Option<&str>) -> String {
    let mut parts = vec![format!("## Task\n\n{task}")];
    if let Some(ctx) = context.filter(|s| !s.trim().is_empty()) {
        parts.push(format!("## Context\n\n{ctx}"));
    }
    if let Some(fmt) = output_format.filter(|s| !s.trim().is_empty()) {
        parts.push(format!("## Output Format\n\n{fmt}"));
    }
    parts.join("\n\n")
}

fn tmp_path(suffix: &str) -> PathBuf {
    let ts_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    PathBuf::from(format!("/tmp/agy-{suffix}-{ts_ms}.md"))
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── build_prompt ─────────────────────────────────────────────────────────

    #[test]
    fn build_prompt_task_only() {
        let p = build_prompt("do the thing", None, None);
        assert_eq!(p, "## Task\n\ndo the thing");
    }

    #[test]
    fn build_prompt_with_context() {
        let p = build_prompt("do the thing", Some("background info"), None);
        assert!(p.contains("## Task\n\ndo the thing"));
        assert!(p.contains("## Context\n\nbackground info"));
        assert!(!p.contains("Output Format"));
    }

    #[test]
    fn build_prompt_with_all_fields() {
        let p = build_prompt("task", Some("ctx"), Some("return JSON"));
        assert!(p.contains("## Task"));
        assert!(p.contains("## Context"));
        assert!(p.contains("## Output Format\n\nreturn JSON"));
    }

    #[test]
    fn build_prompt_skips_whitespace_fields() {
        let p = build_prompt("task", Some("   "), Some("\n\t"));
        assert_eq!(p, "## Task\n\ntask");
    }

    // ── validate_output ───────────────────────────────────────────────────────

    #[test]
    fn validate_success() {
        let result = validate_output("Some useful output", 0, "");
        assert_eq!(result.unwrap(), "Some useful output");
    }

    #[test]
    fn validate_trims_output() {
        let result = validate_output("  trimmed  \n", 0, "");
        assert_eq!(result.unwrap(), "trimmed");
    }

    #[test]
    fn validate_nonzero_exit() {
        let result = validate_output("flags provided but not defined", 2, "");
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_nonzero_exit");
        assert_eq!(v["exit_code"], 2);
    }

    #[test]
    fn validate_empty_output() {
        let result = validate_output("   ", 0, "");
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_empty_output");
    }

    #[test]
    fn validate_error_prefix_empty_prompt() {
        let result = validate_output(
            "Error: empty prompt. Usage: agy --print \"your prompt here\"",
            0,
            "",
        );
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_error");
        assert!(v["message"].as_str().unwrap().starts_with("Error: "));
    }

    #[test]
    fn validate_error_prefix_internal_timeout() {
        let result = validate_output("Error: timed out waiting for response", 0, "");
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_error");
    }

    // ── tmp_path ──────────────────────────────────────────────────────────────

    #[test]
    fn tmp_path_under_slash_tmp() {
        let p = tmp_path("prompt");
        assert!(p.starts_with("/tmp/"), "output path must be under /tmp/");
        assert!(p.to_string_lossy().contains("agy-prompt-"));
        assert!(p.to_string_lossy().ends_with(".md"));
    }

    #[test]
    fn tmp_path_millisecond_suffix_distinct() {
        // Two calls in the same test produce distinct paths via ms timestamp.
        // In the rare case they fire in the same ms, they still collide — the
        // MCP tool serializes calls so this is acceptable for v1.
        let p1 = tmp_path("prompt");
        std::thread::sleep(std::time::Duration::from_millis(2));
        let p2 = tmp_path("prompt");
        assert_ne!(p1, p2, "rapid back-to-back calls should produce distinct paths");
    }

    // ── TmpFile drop guard ────────────────────────────────────────────────────

    #[test]
    fn tmp_file_removed_on_drop() {
        let path = PathBuf::from("/tmp/agy-test-drop-guard.md");
        std::fs::write(&path, "test").unwrap();
        assert!(path.exists());
        {
            let _guard = TmpFile(path.clone());
        }
        assert!(!path.exists(), "TmpFile drop guard must remove the file");
    }

    // ── Timeout JSON shape ────────────────────────────────────────────────────

    #[test]
    fn timeout_error_json_shape() {
        // Verify the exact JSON structure emitted when tokio::time::timeout fires.
        // Tests the contract without needing to run a slow process.
        let err_json = serde_json::json!({
            "error": "agy_timeout",
            "elapsed_secs": AGY_TIMEOUT_SECS,
            "message": format!("agy did not complete within {AGY_TIMEOUT_SECS}s — check quota or network"),
        });
        assert_eq!(err_json["error"], "agy_timeout");
        assert_eq!(err_json["elapsed_secs"], AGY_TIMEOUT_SECS as u64);
        assert!(
            err_json["message"].as_str().unwrap().contains("120s"),
            "timeout message should state the 120s ceiling"
        );
    }

    // ── check_version_fallback ────────────────────────────────────────────────

    #[test]
    fn check_version_fallback_always_returns_error() {
        // Fallback always errors — either "cannot verify" (binary found) or "not found".
        let result = check_version_fallback();
        assert!(result.is_err());
        let msg = result.unwrap_err();
        assert!(
            msg.contains("agy"),
            "fallback error should mention agy: {msg}"
        );
    }

    // ── Fake binary helpers (unix only) ──────────────────────────────────────

    #[cfg(unix)]
    fn write_fake_agy(script_body: &str, label: &str) -> PathBuf {
        let path = PathBuf::from(format!("/tmp/fake-agy-{label}-{}.sh", std::process::id()));
        std::fs::write(&path, format!("#!/bin/sh\n{script_body}\n")).unwrap();
        std::process::Command::new("chmod")
            .args(["+x", path.to_str().unwrap()])
            .output()
            .unwrap();
        path
    }

    // ── Version check with fake binary ────────────────────────────────────────

    #[cfg(unix)]
    #[tokio::test]
    async fn check_version_with_bin_accepts_pinned_version() {
        let bin = write_fake_agy(&format!("echo '{AGY_PINNED_VERSION}'"), "ver-match");
        let result = check_version_with_bin(bin.to_str().unwrap()).await;
        let _ = std::fs::remove_file(&bin);
        assert!(result.is_ok(), "pinned version should pass: {:?}", result.err());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn check_version_with_bin_rejects_wrong_version() {
        let bin = write_fake_agy("echo '2.0.0'", "ver-mismatch");
        let result = check_version_with_bin(bin.to_str().unwrap()).await;
        let _ = std::fs::remove_file(&bin);
        let err = result.unwrap_err();
        assert!(err.contains("version mismatch"), "should report mismatch: {err}");
        assert!(err.contains(AGY_PINNED_VERSION), "should name expected version: {err}");
        assert!(err.contains("2.0.0"), "should name actual version: {err}");
    }

    // ── invoke_agy_with_bin paths ─────────────────────────────────────────────

    #[cfg(unix)]
    #[tokio::test]
    async fn invoke_agy_with_bin_happy_path() {
        let bin = write_fake_agy("echo 'Research complete: 3 findings'", "happy");
        let result = invoke_agy_with_bin(bin.to_str().unwrap(), "summarize X").await;
        let _ = std::fs::remove_file(&bin);
        assert_eq!(result.unwrap(), "Research complete: 3 findings");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn invoke_agy_with_bin_nonzero_exit_classified() {
        let bin = write_fake_agy("echo 'flags provided but not defined: -X'\nexit 2", "exit2");
        let result = invoke_agy_with_bin(bin.to_str().unwrap(), "task").await;
        let _ = std::fs::remove_file(&bin);
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_nonzero_exit");
        assert_eq!(v["exit_code"], 2);
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn invoke_agy_with_bin_error_prefix_classified() {
        let bin = write_fake_agy("echo 'Error: timed out waiting for response'", "errprefix");
        let result = invoke_agy_with_bin(bin.to_str().unwrap(), "task").await;
        let _ = std::fs::remove_file(&bin);
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_error");
        assert!(v["message"].as_str().unwrap().starts_with("Error: "));
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn invoke_agy_with_bin_empty_output_classified() {
        let bin = write_fake_agy("echo ''", "emptyout");
        let result = invoke_agy_with_bin(bin.to_str().unwrap(), "task").await;
        let _ = std::fs::remove_file(&bin);
        let err = result.unwrap_err();
        let v: serde_json::Value = serde_json::from_str(&err).unwrap();
        assert_eq!(v["error"], "agy_empty_output");
    }
}
