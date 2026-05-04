//! Doctor command — brana installation health check
//!
//! Verifies: binary, plugin registration, hooks, MCP servers,
//! rules files, CLI tool dependencies, and ruflo DB.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::themes;

// ── Check result ─────────────────────────────────────────────────────────────

/// Result of a single health check.
#[derive(Debug, PartialEq)]
pub struct CheckResult {
    pub name: String,
    pub passed: bool,
    pub detail: String,
}

impl CheckResult {
    pub fn pass(name: impl Into<String>, detail: impl Into<String>) -> Self {
        Self { name: name.into(), passed: true, detail: detail.into() }
    }
    pub fn fail(name: impl Into<String>, detail: impl Into<String>) -> Self {
        Self { name: name.into(), passed: false, detail: detail.into() }
    }
}

// ── Individual checks (pure functions, easy to unit-test) ────────────────────

/// Check 1: brana binary is on PATH (or at a known location).
pub fn check_binary() -> CheckResult {
    // Try `which brana` first
    if let Ok(out) = Command::new("which").arg("brana").output() {
        if out.status.success() {
            let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
            return CheckResult::pass("Binary on PATH", path);
        }
    }
    // Fallback: check known install location
    let fallback = PathBuf::from(
        std::env::var("HOME").unwrap_or_default()
    ).join(".local/bin/brana");
    if fallback.exists() {
        return CheckResult::pass("Binary on PATH", fallback.to_string_lossy().to_string());
    }
    CheckResult::fail("Binary on PATH", "brana not found — run cargo install or check PATH")
}

/// Check 2: brana is registered in `~/.claude/installed_plugins.json`.
pub fn check_plugin(home: &Path) -> CheckResult {
    let plugins_file = home.join(".claude/installed_plugins.json");
    if !plugins_file.exists() {
        return CheckResult::fail("Plugin registered", "~/.claude/installed_plugins.json not found");
    }
    let content = match fs::read_to_string(&plugins_file) {
        Ok(c) => c,
        Err(e) => return CheckResult::fail("Plugin registered", format!("cannot read file: {e}")),
    };
    let val: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => return CheckResult::fail("Plugin registered", format!("invalid JSON: {e}")),
    };

    // Look for a "brana" key at any level, or an entry with name == "brana"
    let found = find_brana_plugin(&val);
    if let Some(version) = found {
        CheckResult::pass("Plugin registered", format!("brana@brana {version}"))
    } else {
        CheckResult::fail("Plugin registered", "brana not found in installed_plugins.json")
    }
}

/// Recursively look for a brana plugin entry in the JSON value.
/// Returns the version string if found.
fn find_brana_plugin(val: &serde_json::Value) -> Option<String> {
    match val {
        serde_json::Value::Object(map) => {
            // Direct key "brana" at root
            if let Some(entry) = map.get("brana") {
                let ver = entry.get("version")
                    .or_else(|| entry.get("v"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();
                return Some(ver);
            }
            // Search nested
            for v in map.values() {
                if let Some(r) = find_brana_plugin(v) {
                    return Some(r);
                }
            }
            None
        }
        serde_json::Value::Array(arr) => {
            for item in arr {
                // Check if item is an object with name == "brana"
                if let serde_json::Value::Object(m) = item {
                    if m.get("name").and_then(|v| v.as_str()) == Some("brana") {
                        let ver = m.get("version")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_string();
                        return Some(ver);
                    }
                }
                if let Some(r) = find_brana_plugin(item) {
                    return Some(r);
                }
            }
            None
        }
        _ => None,
    }
}

/// Check 3: All hooks listed in `system/hooks/hooks.json` exist and are executable.
pub fn check_hooks(plugin_root: &Path) -> CheckResult {
    let hooks_json = plugin_root.join("hooks/hooks.json");
    if !hooks_json.exists() {
        return CheckResult::fail("Hooks", format!("hooks.json not found at {}", hooks_json.display()));
    }

    let content = match fs::read_to_string(&hooks_json) {
        Ok(c) => c,
        Err(e) => return CheckResult::fail("Hooks", format!("cannot read hooks.json: {e}")),
    };

    let val: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => return CheckResult::fail("Hooks", format!("invalid hooks.json JSON: {e}")),
    };

    // Collect all hook command paths from the hooks.json
    let paths = collect_hook_paths(&val, plugin_root);
    if paths.is_empty() {
        return CheckResult::pass("Hooks", "no hook paths found (empty hooks.json?)");
    }

    let total = paths.len();
    let mut missing: Vec<String> = Vec::new();
    let mut not_exec: Vec<String> = Vec::new();

    for path in &paths {
        if !path.exists() {
            missing.push(path.file_name().unwrap_or_default().to_string_lossy().to_string());
        } else if !is_executable(path) {
            not_exec.push(path.file_name().unwrap_or_default().to_string_lossy().to_string());
        }
    }

    if missing.is_empty() && not_exec.is_empty() {
        CheckResult::pass("Hooks", format!("{total}/{total} executable"))
    } else {
        let passed = total - missing.len() - not_exec.len();
        let mut issues = Vec::new();
        if !missing.is_empty() {
            issues.push(format!("missing: {}", missing.join(", ")));
        }
        if !not_exec.is_empty() {
            issues.push(format!("not executable: {}", not_exec.join(", ")));
        }
        CheckResult::fail("Hooks", format!("{passed}/{total} ok — {}", issues.join("; ")))
    }
}

/// Extract unique script paths from a hooks.json value tree,
/// substituting `${CLAUDE_PLUGIN_ROOT}` with `plugin_root`.
fn collect_hook_paths(val: &serde_json::Value, plugin_root: &Path) -> Vec<PathBuf> {
    let mut paths = std::collections::HashSet::new();
    collect_hook_paths_rec(val, plugin_root, &mut paths);
    paths.into_iter().collect()
}

fn collect_hook_paths_rec(
    val: &serde_json::Value,
    plugin_root: &Path,
    out: &mut std::collections::HashSet<PathBuf>,
) {
    match val {
        serde_json::Value::Object(map) => {
            if let Some(serde_json::Value::String(cmd)) = map.get("command") {
                let resolved = cmd.replace("${CLAUDE_PLUGIN_ROOT}", &plugin_root.to_string_lossy());
                out.insert(PathBuf::from(resolved));
            }
            for v in map.values() {
                collect_hook_paths_rec(v, plugin_root, out);
            }
        }
        serde_json::Value::Array(arr) => {
            for item in arr {
                collect_hook_paths_rec(item, plugin_root, out);
            }
        }
        _ => {}
    }
}

/// Check 4: MCP server command paths in `.mcp.json` exist.
pub fn check_mcp(project_root: &Path) -> CheckResult {
    let mcp_file = project_root.join(".mcp.json");
    if !mcp_file.exists() {
        return CheckResult::fail("MCP servers", ".mcp.json not found");
    }

    let content = match fs::read_to_string(&mcp_file) {
        Ok(c) => c,
        Err(e) => return CheckResult::fail("MCP servers", format!("cannot read .mcp.json: {e}")),
    };

    let val: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(e) => return CheckResult::fail("MCP servers", format!("invalid JSON: {e}")),
    };

    let servers = match val.get("mcpServers").and_then(|v| v.as_object()) {
        Some(s) => s.clone(),
        None => return CheckResult::pass("MCP servers", "no mcpServers defined"),
    };

    let total = servers.len();
    let mut missing: Vec<String> = Vec::new();

    for (name, entry) in &servers {
        if let Some(cmd) = entry.get("command").and_then(|v| v.as_str()) {
            // Expand common env vars
            let expanded = expand_env(cmd);
            if !PathBuf::from(&expanded).exists() {
                // Also try `which` — the command might be on PATH
                let on_path = Command::new("which")
                    .arg(&expanded)
                    .output()
                    .ok()
                    .map_or(false, |o| o.status.success());
                if !on_path {
                    missing.push(format!("{name} ({expanded})"));
                }
            }
        }
    }

    if missing.is_empty() {
        CheckResult::pass("MCP servers", format!("{total}/{total} commands found"))
    } else {
        let passed = total - missing.len();
        CheckResult::fail(
            "MCP servers",
            format!("{passed}/{total} ok — missing: {}", missing.join(", ")),
        )
    }
}

/// Expand `${VAR}` and `$VAR` patterns using environment variables.
fn expand_env(s: &str) -> String {
    let mut result = s.to_string();
    // Handle ${VAR_NAME} pattern
    while let Some(start) = result.find("${") {
        if let Some(end) = result[start..].find('}') {
            let var_name = &result[start + 2..start + end];
            let value = std::env::var(var_name).unwrap_or_default();
            result = format!("{}{}{}", &result[..start], value, &result[start + end + 1..]);
        } else {
            break;
        }
    }
    result
}

/// Check 5: Rules markdown files exist in `system/rules/`.
pub fn check_rules(plugin_root: &Path) -> CheckResult {
    let rules_dir = plugin_root.join("rules");
    if !rules_dir.exists() {
        return CheckResult::fail("Rules", format!("rules/ not found at {}", rules_dir.display()));
    }
    let count = match fs::read_dir(&rules_dir) {
        Ok(entries) => entries
            .flatten()
            .filter(|e| {
                e.path().extension().map_or(false, |ext| ext == "md")
            })
            .count(),
        Err(e) => return CheckResult::fail("Rules", format!("cannot read rules/: {e}")),
    };
    if count > 0 {
        CheckResult::pass("Rules", format!("{count} files"))
    } else {
        CheckResult::fail("Rules", "0 .md files in rules/")
    }
}

/// Check 6: Key CLI dependencies are on PATH.
pub fn check_dependencies() -> CheckResult {
    let tools = ["git", "jq", "cargo"];
    let mut missing: Vec<&str> = Vec::new();

    for tool in &tools {
        let found = Command::new("which")
            .arg(tool)
            .output()
            .ok()
            .map_or(false, |o| o.status.success());
        if !found {
            missing.push(tool);
        }
    }

    if missing.is_empty() {
        CheckResult::pass("Dependencies", tools.join(", "))
    } else {
        CheckResult::fail(
            "Dependencies",
            format!("missing: {} (found: {})",
                missing.join(", "),
                tools.iter().filter(|t| !missing.contains(t)).cloned().collect::<Vec<_>>().join(", ")),
        )
    }
}

/// Check 8: `pkg-config` is on PATH — required for cargo build of brana-core
/// (native-tls → openssl-sys → pkg-config).
pub fn check_pkg_config() -> CheckResult {
    let found = Command::new("which")
        .arg("pkg-config")
        .output()
        .ok()
        .map_or(false, |o| o.status.success());
    if found {
        CheckResult::pass("pkg-config", "on PATH")
    } else {
        CheckResult::fail("pkg-config", pkg_config_fail_message())
    }
}

/// Failure-message helper for `check_pkg_config` — exposed for testability.
fn pkg_config_fail_message() -> String {
    "not found — required by native-tls/openssl-sys for cargo build (apt: sudo apt install pkg-config; brew: brew install pkg-config)".to_string()
}

/// Check 9: `brana` resolves to the canonical install path (`~/.local/bin/brana`).
/// Catches PATH shadows (e.g. stale npm-link of an older JS prototype).
pub fn check_brana_resolution(home: &Path) -> CheckResult {
    let which_path = Command::new("which")
        .arg("brana")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string());
    check_brana_resolution_from(which_path.as_deref(), home)
}

/// Inner: testable variant taking the resolved path directly.
pub fn check_brana_resolution_from(which_path: Option<&str>, home: &Path) -> CheckResult {
    let canonical = home.join(".local/bin/brana");
    let canonical_str = canonical.to_string_lossy().to_string();
    match which_path {
        None => CheckResult::fail(
            "Binary resolution",
            format!("`brana` not on PATH (expected {})", canonical_str),
        ),
        Some(p) if p == canonical_str => CheckResult::pass(
            "Binary resolution",
            format!("canonical ({})", canonical_str),
        ),
        Some(p) => CheckResult::fail(
            "Binary resolution",
            format!(
                "shadowed: resolves to {} but expected {}. Check for npm-link or stale install (e.g. `npm rm -g brana`).",
                p, canonical_str
            ),
        ),
    }
}

/// Check 7: Ruflo DB exists at `~/.swarm/memory.db` and is non-empty.
pub fn check_ruflo_db(home: &Path) -> CheckResult {
    let db_path = home.join(".swarm/memory.db");
    if !db_path.exists() {
        return CheckResult::fail("Ruflo DB", format!("missing (~/.swarm/memory.db)"));
    }
    let size = fs::metadata(&db_path)
        .map(|m| m.len())
        .unwrap_or(0);
    if size == 0 {
        return CheckResult::fail("Ruflo DB", "~/.swarm/memory.db exists but is empty (0 bytes)");
    }
    CheckResult::pass(
        "Ruflo DB",
        format!("~/.swarm/memory.db ({} KB)", size / 1024),
    )
}

// ── Portable executable check ─────────────────────────────────────────────────

#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    path.metadata()
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable(path: &Path) -> bool {
    path.exists()
}

// ── Main command handler ──────────────────────────────────────────────────────

pub fn cmd_doctor(theme: &themes::Theme) {
    let ok = theme.icon("done");
    let fail = theme.icon("blocked");

    println!("\n\x1b[1mbrana doctor\x1b[0m\n{}\n", "=".repeat(40));

    let home = crate::util::home();

    // Resolve plugin root: CLAUDE_PLUGIN_ROOT env, or git root / system/
    let plugin_root = std::env::var("CLAUDE_PLUGIN_ROOT")
        .ok()
        .map(PathBuf::from)
        .or_else(|| crate::util::find_project_root().map(|r| r.join("system")))
        .unwrap_or_else(|| PathBuf::from("."));

    let project_root = crate::util::find_project_root()
        .unwrap_or_else(|| plugin_root.parent().map(|p| p.to_path_buf()).unwrap_or_else(|| PathBuf::from(".")));

    let checks = vec![
        check_binary(),
        check_brana_resolution(&home),
        check_plugin(&home),
        check_hooks(&plugin_root),
        check_mcp(&project_root),
        check_rules(&plugin_root),
        check_dependencies(),
        check_pkg_config(),
        check_ruflo_db(&home),
    ];

    let total = checks.len();
    let passed = checks.iter().filter(|c| c.passed).count();

    for c in &checks {
        let (ic, col) = if c.passed {
            (ok, "\x1b[32m")
        } else {
            (fail, "\x1b[31m")
        };
        let detail = if c.detail.is_empty() {
            String::new()
        } else {
            format!(": {}", c.detail)
        };
        println!("{col}{ic} {}{detail}{}", c.name, themes::RESET);
    }

    println!();

    if passed == total {
        println!("\x1b[32mHealth: {passed}/{total} checks passed\x1b[0m\n");
    } else {
        println!("\x1b[33mHealth: {passed}/{total} checks passed\x1b[0m\n");
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use std::io::Write;
    use tempfile::TempDir;

    // Helper: create a temp dir with a file at the given relative path.
    fn create_file(dir: &TempDir, rel: &str, content: &str) -> PathBuf {
        let path = dir.path().join(rel);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        let mut f = File::create(&path).unwrap();
        f.write_all(content.as_bytes()).unwrap();
        path
    }

    #[cfg(unix)]
    fn make_executable(path: &Path) {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(path).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(path, perms).unwrap();
    }

    // ── check_plugin ──────────────────────────────────────────────────────────

    #[test]
    fn test_check_plugin_missing_file() {
        let tmp = TempDir::new().unwrap();
        let result = check_plugin(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("not found"));
    }

    #[test]
    fn test_check_plugin_invalid_json() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, ".claude/installed_plugins.json", "not json {{{");
        let result = check_plugin(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("invalid JSON"));
    }

    #[test]
    fn test_check_plugin_not_registered() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, ".claude/installed_plugins.json", r#"{"other": {"version": "1.0"}}"#);
        let result = check_plugin(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("not found"));
    }

    #[test]
    fn test_check_plugin_registered_as_key() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, ".claude/installed_plugins.json", r#"{"brana": {"version": "1.0.0"}}"#);
        let result = check_plugin(tmp.path());
        assert!(result.passed);
        assert!(result.detail.contains("1.0.0"));
    }

    #[test]
    fn test_check_plugin_registered_in_array() {
        let tmp = TempDir::new().unwrap();
        create_file(
            &tmp,
            ".claude/installed_plugins.json",
            r#"{"plugins": [{"name": "brana", "version": "2.0.0"}]}"#,
        );
        let result = check_plugin(tmp.path());
        assert!(result.passed);
        assert!(result.detail.contains("2.0.0"));
    }

    // ── check_hooks ───────────────────────────────────────────────────────────

    #[test]
    fn test_check_hooks_missing_json() {
        let tmp = TempDir::new().unwrap();
        let result = check_hooks(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("not found"));
    }

    #[test]
    fn test_check_hooks_empty_hooks() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, "hooks/hooks.json", r#"{"hooks": {}}"#);
        let result = check_hooks(tmp.path());
        assert!(result.passed); // no paths → pass (nothing to check)
    }

    #[cfg(unix)]
    #[test]
    fn test_check_hooks_all_present_and_executable() {
        let tmp = TempDir::new().unwrap();
        // Create a script
        let script = create_file(&tmp, "hooks/session-start.sh", "#!/bin/bash\necho hi");
        make_executable(&script);

        let hooks_json = format!(
            r#"{{"hooks": {{"SessionStart": [{{"matcher": "", "hooks": [{{"type": "command", "command": "{}/hooks/session-start.sh", "timeout": 5000}}]}}]}}}}"#,
            tmp.path().display()
        );
        create_file(&tmp, "hooks/hooks.json", &hooks_json);

        let result = check_hooks(tmp.path());
        assert!(result.passed, "expected pass, got: {:?}", result.detail);
        assert!(result.detail.contains("1/1"));
    }

    #[test]
    fn test_check_hooks_missing_script() {
        let tmp = TempDir::new().unwrap();
        let hooks_json = format!(
            r#"{{"hooks": {{"SessionStart": [{{"matcher": "", "hooks": [{{"type": "command", "command": "{}/hooks/nonexistent.sh", "timeout": 5000}}]}}]}}}}"#,
            tmp.path().display()
        );
        create_file(&tmp, "hooks/hooks.json", &hooks_json);

        let result = check_hooks(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("missing"));
    }

    // ── check_mcp ─────────────────────────────────────────────────────────────

    #[test]
    fn test_check_mcp_missing_file() {
        let tmp = TempDir::new().unwrap();
        let result = check_mcp(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("not found"));
    }

    #[test]
    fn test_check_mcp_no_servers() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, ".mcp.json", r#"{"mcpServers": {}}"#);
        let result = check_mcp(tmp.path());
        assert!(result.passed);
    }

    #[test]
    fn test_check_mcp_command_exists() {
        let tmp = TempDir::new().unwrap();
        // Use `git` as the command since it's guaranteed to exist via `which`
        create_file(&tmp, ".mcp.json", r#"{"mcpServers": {"test": {"command": "git"}}}"#);
        let result = check_mcp(tmp.path());
        assert!(result.passed, "expected pass, got: {:?}", result.detail);
    }

    #[test]
    fn test_check_mcp_command_missing() {
        let tmp = TempDir::new().unwrap();
        create_file(
            &tmp,
            ".mcp.json",
            r#"{"mcpServers": {"bad": {"command": "/nonexistent/path/to/binary"}}}"#,
        );
        let result = check_mcp(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("missing"));
    }

    // ── check_rules ───────────────────────────────────────────────────────────

    #[test]
    fn test_check_rules_missing_dir() {
        let tmp = TempDir::new().unwrap();
        let result = check_rules(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("not found"));
    }

    #[test]
    fn test_check_rules_empty_dir() {
        let tmp = TempDir::new().unwrap();
        fs::create_dir_all(tmp.path().join("rules")).unwrap();
        let result = check_rules(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("0 .md files"));
    }

    #[test]
    fn test_check_rules_with_files() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, "rules/rule-a.md", "# Rule A");
        create_file(&tmp, "rules/rule-b.md", "# Rule B");
        create_file(&tmp, "rules/not-a-rule.txt", "ignored");
        let result = check_rules(tmp.path());
        assert!(result.passed);
        assert!(result.detail.contains("2 files"));
    }

    // ── check_ruflo_db ────────────────────────────────────────────────────────

    #[test]
    fn test_check_ruflo_db_missing() {
        let tmp = TempDir::new().unwrap();
        let result = check_ruflo_db(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("missing"));
    }

    #[test]
    fn test_check_ruflo_db_empty() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, ".swarm/memory.db", "");
        let result = check_ruflo_db(tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("empty"));
    }

    #[test]
    fn test_check_ruflo_db_present_and_nonempty() {
        let tmp = TempDir::new().unwrap();
        create_file(&tmp, ".swarm/memory.db", "SQLite format 3");
        let result = check_ruflo_db(tmp.path());
        assert!(result.passed);
    }

    // ── helper: collect_hook_paths ────────────────────────────────────────────

    #[test]
    fn test_collect_hook_paths_substitutes_plugin_root() {
        let root = PathBuf::from("/fake/plugin");
        let json: serde_json::Value = serde_json::json!({
            "hooks": {
                "SessionStart": [{
                    "matcher": "",
                    "hooks": [{
                        "type": "command",
                        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh",
                        "timeout": 5000
                    }]
                }]
            }
        });
        let paths = collect_hook_paths(&json, &root);
        assert_eq!(paths.len(), 1);
        assert_eq!(paths[0], PathBuf::from("/fake/plugin/hooks/session-start.sh"));
    }

    #[test]
    fn test_collect_hook_paths_deduplicates() {
        let root = PathBuf::from("/fake/plugin");
        let json: serde_json::Value = serde_json::json!({
            "hooks": {
                "PreToolUse": [
                    {"matcher": "Write|Edit", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh", "timeout": 5000}]},
                    {"matcher": "Bash",       "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh", "timeout": 5000}]}
                ]
            }
        });
        let paths = collect_hook_paths(&json, &root);
        assert_eq!(paths.len(), 1, "should deduplicate same path");
    }

    // ── helper: expand_env ────────────────────────────────────────────────────

    #[test]
    fn test_expand_env_no_vars() {
        assert_eq!(expand_env("/usr/bin/git"), "/usr/bin/git");
    }

    #[test]
    fn test_expand_env_known_var() {
        // HOME is always set in test environment
        let home = std::env::var("HOME").unwrap_or_default();
        let input = "${HOME}/.local/bin/brana";
        let result = expand_env(input);
        assert_eq!(result, format!("{home}/.local/bin/brana"));
    }

    #[test]
    fn test_expand_env_unknown_var_becomes_empty() {
        let result = expand_env("${_DEFINITELY_NOT_SET_XYZ}/bin");
        assert_eq!(result, "/bin");
    }

    // ── CheckResult helpers ───────────────────────────────────────────────────

    #[test]
    fn test_check_result_pass_and_fail() {
        let p = CheckResult::pass("Test", "all good");
        assert!(p.passed);
        assert_eq!(p.name, "Test");
        assert_eq!(p.detail, "all good");

        let f = CheckResult::fail("Test", "broken");
        assert!(!f.passed);
    }

    // ── check_brana_resolution ────────────────────────────────────────────────

    #[test]
    fn test_check_brana_resolution_canonical() {
        let tmp = TempDir::new().unwrap();
        let canonical = tmp.path().join(".local/bin/brana");
        let canonical_str = canonical.to_string_lossy().to_string();
        let result = check_brana_resolution_from(Some(&canonical_str), tmp.path());
        assert!(result.passed, "canonical path should pass; got: {:?}", result.detail);
        assert!(result.detail.contains("canonical"));
    }

    #[test]
    fn test_check_brana_resolution_shadowed() {
        let tmp = TempDir::new().unwrap();
        let shadow = "/home/u/.nvm/versions/node/v20/bin/brana";
        let result = check_brana_resolution_from(Some(shadow), tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("shadowed"));
        assert!(result.detail.contains(shadow));
    }

    #[test]
    fn test_check_brana_resolution_not_on_path() {
        let tmp = TempDir::new().unwrap();
        let result = check_brana_resolution_from(None, tmp.path());
        assert!(!result.passed);
        assert!(result.detail.contains("not on PATH"));
    }

    // ── check_pkg_config ──────────────────────────────────────────────────────

    #[test]
    fn test_check_pkg_config_returns_named_check() {
        let result = check_pkg_config();
        assert_eq!(result.name, "pkg-config");
        // Pass/fail depends on host env; only the structure is asserted here.
    }

    #[test]
    fn test_check_pkg_config_fail_message_includes_install_hint() {
        // When the tool is missing, the failure detail must guide the user.
        // We can't easily simulate "missing" without env manipulation, so
        // test the helper that formats the failure message directly.
        let result = pkg_config_fail_message();
        assert!(result.contains("apt"));
        assert!(result.contains("brew"));
        assert!(result.contains("native-tls") || result.contains("openssl"));
    }
}
