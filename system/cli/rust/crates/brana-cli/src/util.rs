//! CLI-only utilities. Core helpers re-exported from brana_core::util.

// Re-export core utilities so existing `use crate::util::*` still works
pub use brana_core::util::*;

/// Fall back to Python CLI for complex commands (to be removed after Python elimination).
pub fn delegate_python(args: &[&str]) {
    let status = std::process::Command::new("uv")
        .args(["run", "brana"])
        .args(args)
        .status();
    match status {
        Ok(s) => std::process::exit(s.code().unwrap_or(1)),
        Err(_) => {
            eprintln!("Python CLI not available. Install with: uv pip install -e .");
            std::process::exit(1);
        }
    }
}
