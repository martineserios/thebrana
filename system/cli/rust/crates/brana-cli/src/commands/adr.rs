//! `brana adr` — ADR number reservation, collision-safe across concurrent sessions and
//! separate git worktrees (t-3294). See `brana_core::adr` for the locking mechanism.

use anyhow::{bail, Context, Result};
use std::fs;

use crate::cli::AdrCmd;
use brana_core::util::find_project_root;

pub fn cmd_adr(cmd: AdrCmd) -> Result<()> {
    match cmd {
        AdrCmd::Reserve { slug } => cmd_reserve(&slug),
    }
}

fn cmd_reserve(slug: &str) -> Result<()> {
    if slug.trim().is_empty() {
        bail!("slug must not be empty");
    }

    let project_root = find_project_root().context("not in a git repository")?;
    let decisions_dir = project_root.join("docs/architecture/decisions");
    fs::create_dir_all(&decisions_dir)
        .with_context(|| format!("create {} failed", decisions_dir.display()))?;

    let number = brana_core::adr::reserve_next_adr_number(&decisions_dir)
        .map_err(|e| anyhow::anyhow!(e))
        .context("ADR number reservation failed")?;

    let filename = format!("ADR-{number:03}-{slug}.md");
    let path = decisions_dir.join(&filename);
    let stub = format!(
        "# ADR-{number:03}: {slug}\n\n\
         Status: draft\n\n\
         ## Context\n\n\
         ## Decision\n\n\
         ## Consequences\n"
    );
    fs::write(&path, stub).with_context(|| format!("write {} failed", path.display()))?;

    println!("Reserved ADR-{number:03} -> {}", path.display());
    Ok(())
}
