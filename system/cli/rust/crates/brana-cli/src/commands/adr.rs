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

/// Reject anything but a bare kebab-case slug before it ever reaches a filename. Without
/// this, `slug` flows unsanitized into `decisions_dir.join(format!("ADR-{n}-{slug}.md"))` —
/// a slug containing `../` (or an absolute-path-like `/etc/passwd`) would let `PathBuf::join`
/// escape `decisions_dir` entirely.
fn validate_slug(slug: &str) -> Result<()> {
    if slug.trim().is_empty() {
        bail!("slug must not be empty");
    }
    if !slug
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        bail!("slug must be kebab-case (letters, digits, '-', '_' only), got: {slug}");
    }
    Ok(())
}

fn cmd_reserve(slug: &str) -> Result<()> {
    validate_slug(slug)?;

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

#[cfg(test)]
mod tests {
    use super::validate_slug;

    #[test]
    fn accepts_plain_kebab_case() {
        assert!(validate_slug("backfill-retry-policy").is_ok());
        assert!(validate_slug("worktree_lock_registry").is_ok());
        assert!(validate_slug("adr123").is_ok());
    }

    #[test]
    fn rejects_empty_or_whitespace() {
        assert!(validate_slug("").is_err());
        assert!(validate_slug("   ").is_err());
    }

    #[test]
    fn rejects_path_traversal_attempts() {
        assert!(validate_slug("../../../etc/passwd").is_err());
        assert!(validate_slug("foo/../bar").is_err());
        assert!(validate_slug("/etc/passwd").is_err());
        assert!(validate_slug("a/b").is_err());
    }

    #[test]
    fn rejects_other_path_metacharacters() {
        assert!(validate_slug("has spaces").is_err());
        assert!(validate_slug("has.dot").is_err());
        assert!(validate_slug("has\\backslash").is_err());
    }
}
