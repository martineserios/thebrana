use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Command as Cmd;

// Brana ecosystem tools whose live versions should be stamped when mentioned
// alongside a version claim in memory content.
const ECOSYSTEM_TOOLS: &[&str] = &["ruflo", "brana", "claude"];

pub fn cmd_memory_write(
    memory_type: &str,
    scope: &str,
    slug: &str,
    content: &str,
) -> Result<()> {
    let root = require_project_root()?;
    let stamped = inject_version_stamps(content);
    let dest = brana_core::memory::write_memory(memory_type, scope, slug, &stamped, &root)?;
    println!("wrote {}", dest.display());
    Ok(())
}

/// If content contains a version claim (`v` followed by a digit) AND mentions at
/// least one known ecosystem tool, append a "Verified at write time" block with
/// the live `--version` output for each detected tool.  Returns content unchanged
/// when neither condition fires.
fn inject_version_stamps(content: &str) -> String {
    let lower = content.to_lowercase();

    if !has_version_like_pattern(&lower) {
        return content.to_string();
    }

    let tools: Vec<&str> = ECOSYSTEM_TOOLS
        .iter()
        .filter(|&&t| lower.contains(t))
        .copied()
        .collect();

    if tools.is_empty() {
        return content.to_string();
    }

    let date = chrono::Utc::now().format("%Y-%m-%d");
    let stamps: Vec<String> = tools
        .iter()
        .map(|&tool| match run_version(tool) {
            Ok(v) => format!("- `{tool} --version`: {v}"),
            Err(_) => format!("- `{tool} --version`: not found in PATH"),
        })
        .collect();

    format!(
        "{content}\n\n---\n**Verified at write time ({date}):**\n{}",
        stamps.join("\n")
    )
}

/// Returns true when `lower` (already lowercased) contains `v` immediately
/// followed by an ASCII digit — the minimal fingerprint of a version claim.
fn has_version_like_pattern(lower: &str) -> bool {
    lower.as_bytes().windows(2).any(|w| w[0] == b'v' && w[1].is_ascii_digit())
}

fn run_version(tool: &str) -> Result<String> {
    let out = Cmd::new(tool)
        .arg("--version")
        .output()
        .context("failed to spawn version command")?;
    let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    let combined = if !stdout.is_empty() { stdout } else { stderr };
    if combined.is_empty() {
        anyhow::bail!("no output from `{tool} --version`");
    }
    Ok(combined)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_version_pattern_leaves_content_unchanged() {
        let content = "ruflo is a great tool for memory management";
        assert_eq!(inject_version_stamps(content), content);
    }

    #[test]
    fn version_pattern_but_no_known_tool_leaves_content_unchanged() {
        let content = "something at v3.5.1 was released by an unknown vendor";
        assert_eq!(inject_version_stamps(content), content);
    }

    #[test]
    fn version_pattern_with_known_tool_injects_verified_block() {
        let content = "ruflo agentdb is currently at v3.5.1";
        let result = inject_version_stamps(content);
        assert!(
            result.contains("Verified at write time"),
            "expected verified block, got: {result}"
        );
        assert!(
            result.contains("ruflo --version"),
            "stamp should name the tool, got: {result}"
        );
    }

    #[test]
    fn multiple_known_tools_all_appear_in_stamp() {
        let content = "ruflo v3 and brana v2 are both installed";
        let result = inject_version_stamps(content);
        assert!(result.contains("ruflo --version"), "ruflo missing from stamp");
        assert!(result.contains("brana --version"), "brana missing from stamp");
    }

    #[test]
    fn has_version_like_pattern_detects_v_digit() {
        assert!(has_version_like_pattern("v3.5.1"));
        assert!(has_version_like_pattern("version v10.0.0"));
        assert!(!has_version_like_pattern("version: latest"));
        assert!(!has_version_like_pattern("no version here"));
    }

    #[test]
    fn original_content_preserved_in_stamped_output() {
        let content = "ruflo v3.5.1 is the installed version";
        let result = inject_version_stamps(content);
        assert!(
            result.starts_with(content),
            "original content should be at the start of the stamped output"
        );
    }
}

pub fn cmd_memory_index(scope: &str) -> Result<()> {
    let root = require_project_root()?;
    brana_core::memory::index_memory(scope, &root)?;
    println!("MEMORY.md updated");
    Ok(())
}

fn require_project_root() -> Result<PathBuf> {
    crate::util::find_project_root()
        .context("could not resolve project root (not in git repo and CLAUDE_PROJECT_DIR not set)")
}
