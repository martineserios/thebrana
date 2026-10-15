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

/// Rebuild the embedded FTS5 recall index over project + global memory dirs.
pub fn cmd_memory_reindex(db: Option<String>) -> Result<()> {
    let root = require_project_root()?;
    let db_path = db
        .map(PathBuf::from)
        .unwrap_or_else(brana_core::memory::fts_index_path);
    let n = brana_core::memory::reindex_fts(&root, &db_path)?;
    println!("indexed {n} memory docs → {}", db_path.display());
    Ok(())
}

/// Full-text search the embedded recall index.
pub fn cmd_memory_search(query: &str, limit: usize, json: bool, db: Option<String>) -> Result<()> {
    let db_path = db
        .map(PathBuf::from)
        .unwrap_or_else(brana_core::memory::fts_index_path);
    let hits = brana_core::memory::search_fts(&db_path, query, limit)?;
    if json {
        println!("{}", serde_json::to_string(&hits)?);
        return Ok(());
    }
    if hits.is_empty() {
        println!("no matches for \"{query}\"");
        return Ok(());
    }
    for h in &hits {
        let mtype = if h.mtype.is_empty() { "?" } else { &h.mtype };
        println!("  [{mtype}] {} ({})", h.slug, h.scope);
        println!("    {}", h.snippet);
    }
    Ok(())
}

/// Project-scope memory writes land in the same `~/.claude/projects/<root>/memory/`
/// directory as session state, so they must key off the same root (t-2520). Leaving
/// this on `find_project_root` would split one store across two directories.
fn require_project_root() -> Result<PathBuf> {
    crate::util::find_session_root()
        .context("could not resolve project root (not in git repo and CLAUDE_PROJECT_DIR not set)")
}

/// `brana memory usage` (t-3517, ADR-099 §5-6). Returns the process exit code: 0, or 2 for
/// `--check` when a shown bundle is still waiting for its outcome.
pub fn cmd_memory_usage(
    task: Option<&str>,
    used: Option<Vec<String>>,
    ignored: Option<Vec<String>>,
    no_answer: bool,
    check: bool,
    report: bool,
    json: bool,
) -> Result<i32> {
    use brana_core::usage_log;
    let root = brana_core::util::find_session_root().context("no project root found")?;
    let paths = usage_log::log_paths(&brana_core::util::session_store_root(), &root);
    let read = usage_log::read_rows(&paths);

    if report {
        let r = usage_log::report(&read);
        if json {
            println!("{}", serde_json::to_string(&r)?);
        } else {
            println!("offered {} (shown {}, shadow {}) over {} task(s)", r.offered, r.shown, r.shadow, r.tasks);
            println!("outcomes {}; shown bundles without one {}", r.outcomes, r.unresolved_shown);
            println!("bundle size mean {:.1}, max {}; empty bundles {}", r.bundle_size_mean, r.bundle_size_max, r.empty_bundles);
            for (leg, n) in &r.legs_not_ok {
                println!("leg {leg}: {n}");
            }
            if r.malformed_lines > 0 {
                println!("malformed lines skipped: {}", r.malformed_lines);
            }
        }
        return Ok(0);
    }

    let task = task.context("a task id is required")?;
    if check {
        let c = usage_log::check(&read.rows, task);
        for o in &c.orphans {
            eprintln!("note: older shown bundle {o} for {task} has no outcome (not blocking)");
        }
        return Ok(match c.unresolved {
            None => 0,
            Some(id) => {
                eprintln!(
                    "{task}: the shown bundle {id} has no outcome. Run: brana memory usage {task} \
                     --used <refs> --ignored <refs>   (or --no-answer)"
                );
                2
            }
        });
    }

    // `--used ""` is a deliberate "used none"; a bare call is not an answer.
    if !no_answer && used.is_none() && ignored.is_none() {
        anyhow::bail!("give --used/--ignored (use --used \"\" for none) or --no-answer");
    }
    let clean = |v: Option<Vec<String>>| -> Vec<String> {
        v.unwrap_or_default().into_iter().filter(|s| !s.trim().is_empty()).collect()
    };
    let answer = if no_answer {
        usage_log::Answer::NoAnswer
    } else {
        usage_log::Answer::Given { used: clean(used), ignored: clean(ignored) }
    };
    let projects: Vec<PathBuf> =
        paths.iter().filter_map(|p| p.parent().and_then(|d| d.parent()).map(PathBuf::from)).collect();
    let row = usage_log::outcome_row(
        &read.rows,
        task,
        &answer,
        |offered| {
            let refs = usage_log::offered_refs(offered);
            let stem = offered["session"].as_str().filter(|s| !s.is_empty());
            match stem.and_then(|stem| {
                projects.iter().find_map(|d| usage_log::opened_in_transcript(&d.join(format!("{stem}.jsonl")), &refs))
            }) {
                Some(r) => usage_log::Opened::Refs(r),
                None => usage_log::Opened::Unavailable,
            }
        },
        chrono::Utc::now(),
    )
    .map_err(|e| anyhow::anyhow!(e))?;
    usage_log::append(&paths[0], &row).map_err(|e| anyhow::anyhow!(e))?;
    println!("recorded {} for {task}", row["answer"].as_str().unwrap_or("outcome"));
    Ok(0)
}
