use anyhow::{Context, Result};
use std::path::PathBuf;

pub fn cmd_memory_write(
    memory_type: &str,
    scope: &str,
    slug: &str,
    content: &str,
) -> Result<()> {
    let root = require_project_root()?;
    let dest = brana_core::memory::write_memory(memory_type, scope, slug, content, &root)?;
    println!("wrote {}", dest.display());
    Ok(())
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
