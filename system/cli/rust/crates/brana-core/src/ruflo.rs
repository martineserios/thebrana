//! Ruflo binary resolution — single source of truth for locating ruflo/claude-flow.

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

#[cfg(test)]
mod tests {
    use super::*;
    use serial_test::serial;
    use std::fs;
    use tempfile::TempDir;

    fn make_fake_binary(dir: &TempDir, name: &str) -> PathBuf {
        let p = dir.path().join(name);
        fs::write(&p, b"#!/bin/sh\n").unwrap();
        p
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
