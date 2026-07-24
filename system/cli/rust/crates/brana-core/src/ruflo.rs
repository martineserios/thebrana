//! Ruflo binary resolution — single source of truth for locating ruflo/claude-flow.

use anyhow::{Context, Result, bail};
use crate::util::home;
use std::path::PathBuf;

/// Resolve the ruflo or claude-flow binary path.
///
/// Priority:
/// 1. `RUFLO_BIN` env var (explicit override)
/// 2. `CF` env var (set by cf-env.sh or shell profile)
/// 3. `~/.claude/scripts/cf-env.sh` — sources it, reads `$CF`
/// 4. NVM node version directories — tries `ruflo` then `claude-flow`
/// 5. `PATH` — tries `ruflo` then `claude-flow`
///
/// Returns `None` when ruflo is not installed. All callers must fail-open.
pub fn resolve_ruflo_binary() -> Option<PathBuf> {
    // 1. RUFLO_BIN env var
    if let Ok(v) = std::env::var("RUFLO_BIN") {
        let p = PathBuf::from(&v);
        if p.exists() {
            return Some(p);
        }
    }

    // 2. CF env var (e.g. set by shell profile after cf-env.sh)
    if let Ok(v) = std::env::var("CF") {
        if !v.is_empty() {
            let p = PathBuf::from(&v);
            if p.exists() {
                return Some(p);
            }
        }
    }

    // 3. Source cf-env.sh (sets $CF in the subprocess, captures the path)
    let home_dir = home();
    let cf_env = home_dir.join(".claude/scripts/cf-env.sh");
    if cf_env.exists() {
        if let Ok(output) = std::process::Command::new("bash")
            .args([
                "-c",
                &format!("source '{}' 2>/dev/null && echo \"$CF\"", cf_env.display()),
            ])
            .output()
        {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() {
                    let p = PathBuf::from(&path);
                    if p.exists() {
                        return Some(p);
                    }
                }
            }
        }
    }

    // 4. NVM node version directories (ruflo is not always on PATH in subshells)
    let nvm_root = std::env::var("NVM_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir.join(".nvm"));
    if let Ok(entries) = std::fs::read_dir(nvm_root.join("versions/node")) {
        for entry in entries.flatten() {
            for name in ["ruflo", "claude-flow"] {
                let candidate = entry.path().join("bin").join(name);
                if candidate.exists() {
                    return Some(candidate);
                }
            }
        }
    }

    // 5. PATH
    for name in ["ruflo", "claude-flow"] {
        if let Ok(out) = std::process::Command::new("which").arg(name).output() {
            if out.status.success() {
                let path = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !path.is_empty() {
                    return Some(PathBuf::from(path));
                }
            }
        }
    }

    None
}

/// Call `ruflo memory search` and return raw stdout JSON, or `None` on failure.
///
/// Resolves the ruflo binary, spawns the process with a 15-second timeout, and
/// returns the raw JSON string from stdout. Returns `None` when ruflo is absent,
/// the process exits non-zero, or the timeout is exceeded.
///
/// All callers should fail-open on `None`.
pub fn ruflo_memory_search_raw(
    query: &str,
    namespace: &str,
    limit: usize,
    threshold: Option<f64>,
    json: bool,
) -> Option<String> {
    let ruflo = resolve_ruflo_binary()?;
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let limit_str = limit.to_string();
    let threshold_str = threshold.map(|t| format!("{t:.2}"));

    let mut cmd = std::process::Command::new(&ruflo);
    cmd.args([
        "memory", "search",
        "-q", query,
        "--namespace", namespace,
        "--limit", &limit_str,
    ])
    .env("HOME", &home)
    .current_dir(&home)
    .stdout(std::process::Stdio::piped())
    .stderr(std::process::Stdio::piped());

    if let Some(ref ts) = threshold_str {
        cmd.args(["--threshold", ts]);
    }
    if json {
        cmd.arg("--json");
    }

    let mut child = cmd.spawn().ok()?;

    let timeout = std::time::Duration::from_secs(15);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() {
                    return None;
                }
                break;
            }
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    return None;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(_) => return None,
        }
    }

    let output = child.wait_with_output().ok()?;
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

/// Store a value in ruflo memory under an exact key (ADR-068). Unlike
/// `ruflo_memory_search_raw`, storage failures are surfaced to the caller
/// rather than failing open — a silent store failure would let a URL be
/// re-processed forever without ever landing in knowledge memory.
pub fn ruflo_memory_store(key: &str, value: &str, namespace: &str, tags: &[&str]) -> Result<()> {
    let ruflo = resolve_ruflo_binary()
        .context("ruflo binary not found (RUFLO_BIN/CF unset, not on PATH)")?;
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());

    let mut cmd = std::process::Command::new(&ruflo);
    cmd.args(["memory", "store", "-k", key, "--value", value, "-n", namespace, "--upsert"])
        .env("HOME", &home)
        .current_dir(&home)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    let tags_csv;
    if !tags.is_empty() {
        tags_csv = tags.join(",");
        cmd.args(["--tags", &tags_csv]);
    }

    let mut child = cmd.spawn().context("failed to spawn ruflo memory store")?;

    let timeout = std::time::Duration::from_secs(15);
    let start = std::time::Instant::now();
    let mut timed_out = false;
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    timed_out = true;
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => bail!("ruflo memory store wait failed: {e}"),
        }
    }

    let output = child
        .wait_with_output()
        .context("failed to collect ruflo memory store output")?;
    if timed_out {
        bail!("ruflo memory store timed out after {}s", timeout.as_secs());
    }
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("ruflo memory store failed: {stderr}");
    }
    Ok(())
}

/// Exact-match lookup in ruflo memory (ADR-068). Distinct from
/// `ruflo_memory_search_raw`, which is semantic/fuzzy — reusing that for
/// idempotency checks risks a false-positive "already stored" skip on an
/// unrelated prior entry. Returns `Ok(None)` for a genuine miss, `Err` for
/// an actual failure (ruflo absent, timeout, process error) so callers don't
/// conflate "not found" with "couldn't check."
pub fn ruflo_memory_get(key: &str, namespace: &str) -> Result<Option<String>> {
    let ruflo = resolve_ruflo_binary()
        .context("ruflo binary not found (RUFLO_BIN/CF unset, not on PATH)")?;
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());

    let mut cmd = std::process::Command::new(&ruflo);
    cmd.args(["memory", "retrieve", "-k", key, "-n", namespace, "--value-only"])
        .env("HOME", &home)
        .current_dir(&home)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());

    let mut child = cmd.spawn().context("failed to spawn ruflo memory retrieve")?;

    let timeout = std::time::Duration::from_secs(15);
    let start = std::time::Instant::now();
    let mut timed_out = false;
    loop {
        match child.try_wait() {
            Ok(Some(_status)) => break,
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    timed_out = true;
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => bail!("ruflo memory retrieve wait failed: {e}"),
        }
    }

    let output = child
        .wait_with_output()
        .context("failed to collect ruflo memory retrieve output")?;
    if timed_out {
        bail!("ruflo memory retrieve timed out after {}s", timeout.as_secs());
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !output.status.success() {
        // ruflo exits non-zero on a genuine miss and prints "Key not found"
        // to stdout — treat that specific shape as Ok(None); anything else
        // non-zero is a real failure the caller must not silently swallow.
        if stdout.contains("Key not found") {
            return Ok(None);
        }
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("ruflo memory retrieve failed: {stderr}");
    }
    if stdout.is_empty() {
        return Ok(None);
    }
    Ok(Some(stdout))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use tempfile::TempDir;

    fn make_fake_binary(dir: &TempDir, name: &str) -> PathBuf {
        let p = dir.path().join(name);
        fs::write(&p, b"#!/bin/sh\n").unwrap();
        p
    }

    /// Writes an executable shell-script stub standing in for the real
    /// `ruflo` binary, driven purely by its exit code + stdout/stderr — the
    /// same "fake CLI" approach the crate already uses for
    /// `resolve_ruflo_binary` tests, extended here to actually run.
    fn make_fake_ruflo_cli(dir: &TempDir, script_body: &str) -> PathBuf {
        let p = dir.path().join("fake-ruflo");
        fs::write(&p, format!("#!/bin/sh\n{script_body}\n")).unwrap();
        let mut perms = fs::metadata(&p).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&p, perms).unwrap();
        p
    }

    /// SAFETY: caller must hold #[serial] — mutates process-global env.
    unsafe fn with_ruflo_bin<T>(bin: &PathBuf, f: impl FnOnce() -> T) -> T {
        let prev = std::env::var("RUFLO_BIN").ok();
        unsafe { std::env::set_var("RUFLO_BIN", bin.to_str().unwrap()) };
        let result = f();
        unsafe {
            match prev {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
        }
        result
    }

    #[test]
    #[serial]
    fn store_success_returns_ok() {
        let dir = TempDir::new().unwrap();
        let fake = make_fake_ruflo_cli(&dir, "exit 0");
        let result = unsafe { with_ruflo_bin(&fake, || ruflo_memory_store("k", "v", "knowledge", &[])) };
        assert!(result.is_ok(), "expected Ok, got {result:?}");
    }

    #[test]
    #[serial]
    fn store_failure_returns_err_with_stderr() {
        let dir = TempDir::new().unwrap();
        let fake = make_fake_ruflo_cli(&dir, "echo 'disk full' >&2; exit 1");
        let result = unsafe { with_ruflo_bin(&fake, || ruflo_memory_store("k", "v", "knowledge", &[])) };
        let err = result.expect_err("expected Err on nonzero exit");
        assert!(err.to_string().contains("disk full"), "error should surface stderr, got: {err}");
    }

    #[test]
    #[serial]
    fn get_found_returns_some_value() {
        let dir = TempDir::new().unwrap();
        let fake = make_fake_ruflo_cli(&dir, "echo 'hello world'; exit 0");
        let result = unsafe { with_ruflo_bin(&fake, || ruflo_memory_get("k", "knowledge")) };
        assert_eq!(result.unwrap(), Some("hello world".to_string()));
    }

    #[test]
    #[serial]
    fn get_not_found_returns_ok_none() {
        let dir = TempDir::new().unwrap();
        let fake = make_fake_ruflo_cli(&dir, "echo '[WARN] Key not found: k'; exit 1");
        let result = unsafe { with_ruflo_bin(&fake, || ruflo_memory_get("k", "knowledge")) };
        assert_eq!(result.unwrap(), None, "a genuine miss must be Ok(None), not an error");
    }

    #[test]
    #[serial]
    fn get_real_failure_returns_err_not_none() {
        // Boundary: a non-"not found" failure (e.g. DB locked) must NOT be
        // silently swallowed as Ok(None) — that would let idempotency
        // false-positive-skip a URL that was never actually checked.
        let dir = TempDir::new().unwrap();
        let fake = make_fake_ruflo_cli(&dir, "echo 'database is locked' >&2; exit 1");
        let result = unsafe { with_ruflo_bin(&fake, || ruflo_memory_get("k", "knowledge")) };
        let err = result.expect_err("a real failure must be Err, not Ok(None)");
        assert!(err.to_string().contains("database is locked"));
    }

    #[test]
    #[serial]
    fn get_empty_stdout_on_success_is_none() {
        // Boundary: exit 0 with truly empty output (unexpected but not a
        // crash condition) must not be mistaken for a stored empty string.
        let dir = TempDir::new().unwrap();
        let fake = make_fake_ruflo_cli(&dir, "exit 0");
        let result = unsafe { with_ruflo_bin(&fake, || ruflo_memory_get("k", "knowledge")) };
        assert_eq!(result.unwrap(), None);
    }

    #[test]
    fn does_not_panic_without_ruflo() {
        // None is acceptable; the important contract is no panic.
        let _ = resolve_ruflo_binary();
    }

    #[test]
    #[serial]
    fn ruflo_bin_env_returns_existing_file() {
        let dir = TempDir::new().unwrap();
        let fake = make_fake_binary(&dir, "ruflo");

        let prev = std::env::var("RUFLO_BIN").ok();
        // SAFETY: serial ensures single-threaded access to env
        unsafe { std::env::set_var("RUFLO_BIN", fake.to_str().unwrap()) };

        let result = resolve_ruflo_binary();

        unsafe {
            match prev {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
        }

        assert_eq!(result, Some(fake));
    }

    #[test]
    #[serial]
    fn ruflo_bin_env_nonexistent_falls_through() {
        let prev = std::env::var("RUFLO_BIN").ok();
        // SAFETY: serial ensures single-threaded access to env
        unsafe { std::env::set_var("RUFLO_BIN", "/nonexistent-ruflo-brana-test-binary") };

        let result = resolve_ruflo_binary();

        unsafe {
            match prev {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
        }

        // Must not return the nonexistent path
        if let Some(p) = result {
            assert_ne!(p, PathBuf::from("/nonexistent-ruflo-brana-test-binary"));
        }
    }

    #[test]
    #[serial]
    fn cf_env_returns_existing_file() {
        let dir = TempDir::new().unwrap();
        let fake = make_fake_binary(&dir, "ruflo");

        let prev_ruflo = std::env::var("RUFLO_BIN").ok();
        let prev_cf = std::env::var("CF").ok();
        // SAFETY: serial ensures single-threaded access to env
        unsafe {
            std::env::remove_var("RUFLO_BIN");
            std::env::set_var("CF", fake.to_str().unwrap());
        }

        let result = resolve_ruflo_binary();

        unsafe {
            match prev_ruflo {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
            match prev_cf {
                Some(v) => std::env::set_var("CF", v),
                None => std::env::remove_var("CF"),
            }
        }

        assert_eq!(result, Some(fake));
    }

    #[test]
    #[serial]
    fn cf_env_empty_falls_through() {
        let prev_ruflo = std::env::var("RUFLO_BIN").ok();
        let prev_cf = std::env::var("CF").ok();
        // SAFETY: serial ensures single-threaded access to env
        unsafe {
            std::env::remove_var("RUFLO_BIN");
            std::env::set_var("CF", "");
        }

        let result = resolve_ruflo_binary();

        unsafe {
            match prev_ruflo {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
            match prev_cf {
                Some(v) => std::env::set_var("CF", v),
                None => std::env::remove_var("CF"),
            }
        }

        // empty CF must not match — result (if Some) must not be an empty path
        if let Some(p) = result {
            assert!(!p.as_os_str().is_empty());
        }
    }

    #[test]
    #[serial]
    fn ruflo_bin_takes_priority_over_cf() {
        let dir = TempDir::new().unwrap();
        let fake_ruflo_bin = make_fake_binary(&dir, "via-ruflo-bin");
        let fake_cf = make_fake_binary(&dir, "via-cf");

        let prev_ruflo = std::env::var("RUFLO_BIN").ok();
        let prev_cf = std::env::var("CF").ok();
        // SAFETY: serial ensures single-threaded access to env
        unsafe {
            std::env::set_var("RUFLO_BIN", fake_ruflo_bin.to_str().unwrap());
            std::env::set_var("CF", fake_cf.to_str().unwrap());
        }

        let result = resolve_ruflo_binary();

        unsafe {
            match prev_ruflo {
                Some(v) => std::env::set_var("RUFLO_BIN", v),
                None => std::env::remove_var("RUFLO_BIN"),
            }
            match prev_cf {
                Some(v) => std::env::set_var("CF", v),
                None => std::env::remove_var("CF"),
            }
        }

        assert_eq!(result, Some(fake_ruflo_bin));
    }
}
