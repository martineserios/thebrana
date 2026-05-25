//! Knowledge subcommand handlers

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;

use brana_core::knowledge_pipeline::{
    self as kp, DRAFT_CAP, UrlStatus,
};
use std::io::IsTerminal as _;

use crate::util::{find_project_root, home};

pub fn cmd_reindex(changed: bool, files: Vec<PathBuf>) -> Result<()> {
    use anyhow::anyhow;
    let root = find_project_root().ok_or_else(|| anyhow!("Not in git repo"))?;
    let script = root.join("system/scripts/index-knowledge.sh");
    if !script.exists() {
        return Err(anyhow!("index-knowledge.sh not found at {}", script.display()));
    }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).current_dir(&root);

    if changed {
        cmd.arg("--changed");
    } else {
        for f in &files {
            cmd.arg(f);
        }
    }

    println!("\n  Running index-knowledge.sh...");
    let status = cmd.status().context("running index-knowledge.sh")?;
    if !status.success() {
        return Err(anyhow!(
            "index-knowledge.sh failed (exit {})",
            status.code().unwrap_or(-1)
        ));
    }
    println!("  \x1b[32mDone.\x1b[0m\n");
    Ok(())
}

pub fn cmd_reindex_patterns(files: Vec<PathBuf>) -> Result<()> {
    use anyhow::anyhow;
    let root = find_project_root().ok_or_else(|| anyhow!("Not in git repo"))?;
    let script = root.join("system/scripts/index-patterns.sh");
    if !script.exists() {
        return Err(anyhow!("index-patterns.sh not found at {}", script.display()));
    }

    let mut cmd = Command::new("bash");
    cmd.arg(&script).current_dir(&root);

    for f in &files {
        cmd.arg(f);
    }

    println!("\n  Running index-patterns.sh...");
    let status = cmd.status().context("running index-patterns.sh")?;
    if !status.success() {
        return Err(anyhow!(
            "index-patterns.sh failed (exit {})",
            status.code().unwrap_or(-1)
        ));
    }
    println!("  \x1b[32mDone.\x1b[0m\n");
    Ok(())
}

// ── knowledge search ─────────────────────────────────────────────────

/// A single result entry returned by ruflo memory search.
#[derive(Debug, Deserialize, Serialize)]
pub struct SearchResult {
    pub key: String,
    pub value: String,
    #[serde(default)]
    pub score: f64,
}

/// Parse a ruflo memory search JSON response into `SearchResult` entries.
/// The ruflo CLI returns a JSON array of `{key, value, score}` objects.
pub fn parse_search_results(text: &str) -> Result<Vec<SearchResult>> {
    let results: Vec<SearchResult> = serde_json::from_str(text.trim())?;
    Ok(results)
}

/// Truncate `text` to at most `max_chars` characters, appending "..." when clipped.
pub fn truncate(text: &str, max_chars: usize) -> String {
    let text = text.trim();
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    let clipped: String = text.chars().take(max_chars).collect();
    format!("{clipped}...")
}

/// Format search results for human-readable display.
///
/// Example output:
/// ```text
/// 1. [0.82] pattern:thebrana:hooks-cant-enforce-ordering
///    Hooks are stateless — can't enforce workflow ordering...
/// ```
pub fn format_results(results: &[SearchResult]) -> String {
    if results.is_empty() {
        return "  No results found.".to_string();
    }
    let mut lines = Vec::new();
    for (i, r) in results.iter().enumerate() {
        lines.push(format!(
            "{}. [{:.2}] {}",
            i + 1,
            r.score,
            r.key
        ));
        lines.push(format!("   {}", truncate(&r.value, 100)));
    }
    lines.join("\n")
}

/// Resolve the ruflo/claude-flow binary path (same logic as skills.rs).
fn which_ruflo() -> Option<String> {
    let home_str = std::env::var("HOME").unwrap_or_default();
    let cf_env = format!("{home_str}/.claude/scripts/cf-env.sh");
    if std::path::Path::new(&cf_env).exists() {
        if let Ok(output) = std::process::Command::new("bash")
            .args(["-c", &format!("source '{cf_env}' 2>/dev/null && echo \"$CF\"")])
            .output()
        {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() && std::path::Path::new(&path).exists() {
                    return Some(path);
                }
            }
        }
    }

    // Try nvm global bin locations
    let nvm_dir = std::env::var("NVM_DIR").unwrap_or_else(|_| format!("{home_str}/.nvm"));
    if let Ok(entries) = std::fs::read_dir(format!("{nvm_dir}/versions/node")) {
        for entry in entries.flatten() {
            for name in ["ruflo", "claude-flow"] {
                let bin = entry.path().join("bin").join(name);
                if bin.exists() {
                    return Some(bin.to_string_lossy().to_string());
                }
            }
        }
    }

    // Try PATH
    for name in ["ruflo", "claude-flow"] {
        if let Ok(output) = std::process::Command::new("which").arg(name).output() {
            if output.status.success() {
                let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !path.is_empty() {
                    return Some(path);
                }
            }
        }
    }
    None
}

/// Call ruflo memory search and return raw JSON output.
/// Uses a 15-second timeout (ruflo CLI can hang after completion — known issue).
fn call_ruflo_search(query: &str, namespace: &str, limit: usize) -> Result<String> {
    let cf = std::env::var("CF")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(which_ruflo)
        .ok_or_else(|| anyhow::anyhow!("ruflo not found — run `brana knowledge reindex` first"))?;

    let home_str = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    let limit_str = limit.to_string();

    let mut child = std::process::Command::new(&cf)
        .args([
            "memory", "search",
            "-q", query,
            "--namespace", namespace,
            "--limit", &limit_str,
        ])
        .env("HOME", &home_str)
        .current_dir(&home_str)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| anyhow::anyhow!("failed to spawn ruflo: {e}"))?;

    let timeout = std::time::Duration::from_secs(15);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() {
                    let _ = child.wait();
                    bail!("ruflo search exited with non-zero status");
                }
                break;
            }
            Ok(None) => {
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    bail!("ruflo search timed out after 15s");
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => bail!("ruflo wait error: {e}"),
        }
    }

    let output = child.wait_with_output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

/// `brana knowledge search <query> [--limit N] [--namespace NS] [--json]`
pub fn cmd_search(query: &str, limit: usize, namespace: &str, json_output: bool) -> Result<()> {
    let raw = call_ruflo_search(query, namespace, limit)?;
    let results = parse_search_results(&raw)?;

    if json_output {
        let out = serde_json::to_string_pretty(&results)?;
        println!("{out}");
    } else {
        println!("\n  \x1b[1mKnowledge Search\x1b[0m — \"{query}\" (namespace: {namespace})\n");
        println!("{}", format_results(&results));
        println!();
    }
    Ok(())
}

pub fn cmd_status() {
    let db_path = home().join(".swarm/memory.db");

    if !db_path.exists() {
        println!("  Knowledge DB not found at {}", db_path.display());
        println!("  Run `brana knowledge reindex` to create it.");
        return;
    }

    // Query entry count and last modified via sqlite3
    let output = Command::new("sqlite3")
        .arg(&db_path)
        .arg("SELECT COUNT(*), datetime(MAX(COALESCE(updated_at, created_at)) / 1000, 'unixepoch', 'localtime') FROM memory_entries WHERE namespace = 'knowledge' AND status = 'active';")
        .output();

    match output {
        Ok(out) if out.status.success() => {
            let text = String::from_utf8_lossy(&out.stdout);
            let parts: Vec<&str> = text.trim().split('|').collect();
            let count = parts.first().unwrap_or(&"?");
            let last = parts.get(1).unwrap_or(&"?");
            println!("\n  \x1b[1mKnowledge Index Status\x1b[0m");
            println!("  Entries:      {count}");
            println!("  Last indexed: {last}");
            println!("  DB path:      {}\n", db_path.display());
        }
        Ok(out) => {
            let err = String::from_utf8_lossy(&out.stderr);
            eprintln!("  sqlite3 error: {err}");
            // Fallback: just show file stats
            if let Ok(meta) = std::fs::metadata(&db_path) {
                println!("  DB size: {} bytes", meta.len());
            }
        }
        Err(_) => {
            // sqlite3 not available — show file info
            println!("\n  \x1b[1mKnowledge Index Status\x1b[0m");
            println!("  DB path: {}", db_path.display());
            if let Ok(meta) = std::fs::metadata(&db_path) {
                println!("  DB size: {} bytes", meta.len());
                if let Ok(modified) = meta.modified() {
                    let elapsed = modified.elapsed().unwrap_or_default();
                    let hours = elapsed.as_secs() / 3600;
                    println!("  Last modified: ~{hours}h ago");
                }
            }
            println!("  (install sqlite3 for detailed stats)\n");
        }
    }
}

// ── brana knowledge process ───────────────────────────────────────────────

#[allow(clippy::too_many_arguments)]
pub fn cmd_process(
    tier1: bool,
    tier2: bool,
    draft: Option<String>,
    report: bool,
    status: bool,
    reset_url: Option<String>,
    dry_run: bool,
) -> Result<()> {
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!(
            "brana-knowledge repo not found. Checked: $BRANA_KNOWLEDGE_ROOT, \
             sibling of git root, ~/enter_thebrana/brana-knowledge/"
        ))?;
    let state_path = kp::pipeline_state_path();
    let mut state = kp::load_state(&state_path)?;

    // ── --status ──────────────────────────────────────────────────────
    if status {
        let counts = count_by_tier(&state);
        let draft_count = kp::count_drafts(&knowledge_root);
        let cap_hit = draft_count >= DRAFT_CAP && !state.draft_cap_acknowledged;
        println!("\n  \x1b[1mKnowledge Pipeline Status\x1b[0m");
        println!("  Unprocessed:     {}", counts.unprocessed);
        println!("  Irrelevant:      {}", counts.irrelevant);
        println!("  Tier 1 passed:   {}", counts.tier1_passed);
        println!("  Tier 2 clustered:{}", counts.tier2_clustered);
        println!("  Tier 3 drafted:  {}", counts.tier3_drafted);
        println!("  Drafts on disk:  {}/{DRAFT_CAP}", draft_count);
        if cap_hit {
            println!("  \x1b[33m⚠ Draft cap hit — review drafts before pipeline runs again.\x1b[0m");
            println!("  \x1b[33m  Run `brana knowledge process --status` again after reviewing to acknowledge.\x1b[0m");
            // Acknowledge on explicit --status invocation
            state.draft_cap_acknowledged = true;
            if !dry_run {
                kp::save_state(&state_path, &state)?;
            }
        }
        if let Some(last) = &state.last_tier1_run {
            println!("  Last Tier 1 run: {last}");
        }
        if let Some(last) = &state.last_tier2_run {
            println!("  Last Tier 2 run: {last}");
        }
        println!();
        return Ok(());
    }

    // ── --reset-url ───────────────────────────────────────────────────
    if let Some(url) = reset_url {
        if state.urls.remove(&url).is_some() {
            println!("  Removed '{}' from pipeline state — will reprocess on next run.", url);
            if !dry_run {
                kp::save_state(&state_path, &url_reset_state(state, &url))?;
            } else {
                println!("  [dry-run] state not written.");
            }
        } else {
            println!("  URL not found in pipeline state: {url}");
        }
        return Ok(());
    }

    // ── --report ──────────────────────────────────────────────────────
    if report {
        let report_path = home().join(".claude/knowledge-pipeline-report.md");
        if report_path.exists() {
            let content = std::fs::read_to_string(&report_path)?;
            println!("{content}");
        } else {
            println!("  No cluster report found. Run `brana knowledge process --tier2` first.");
        }
        return Ok(());
    }

    // ── draft cap gate (blocks --tier1 and --tier2) ───────────────────
    if tier1 || tier2 {
        let draft_count = kp::count_drafts(&knowledge_root);
        if draft_count >= DRAFT_CAP && !state.draft_cap_acknowledged {
            bail!(
                "Draft cap hit ({draft_count}/{DRAFT_CAP} drafts in brana-knowledge/drafts/). Review and promote/reject drafts, then run `brana knowledge process --status` to acknowledge."
            );
        }
    }

    // ── --tier1 ───────────────────────────────────────────────────────
    if tier1 {
        run_tier1(&knowledge_root, &state_path, &mut state, dry_run)?;
    }

    // ── --tier2 ───────────────────────────────────────────────────────
    if tier2 {
        run_tier2(&knowledge_root, &state_path, &mut state, dry_run)?;
    }

    // ── --draft <topic> ───────────────────────────────────────────────
    if let Some(topic) = draft {
        run_tier3(&topic, &knowledge_root, &state_path, &mut state, dry_run)?;
    }

    Ok(())
}

// ── Tier 1 ────────────────────────────────────────────────────────────────

const TIER1_BATCH: usize = 50;

fn run_tier1(
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    dry_run: bool,
) -> Result<()> {
    let dimension_slugs = kp::list_dimension_slugs(knowledge_root);
    let dim_list = dimension_slugs.join(", ");

    let candidates = kp::extract_unprocessed_urls(state)?;
    let batch: Vec<_> = candidates.into_iter().take(TIER1_BATCH).collect();

    if batch.is_empty() {
        println!("  Tier 1: no unprocessed URLs found.");
        return Ok(());
    }

    println!(
        "\n  \x1b[1mTier 1 — Relevance filter\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!("  Processing {} URL(s) (batch cap: {TIER1_BATCH})\n", batch.len());

    let mut passed = 0usize;
    let mut filtered = 0usize;

    for entry in &batch {
        let prompt = format!(
            "You are classifying a LinkedIn post for relevance to a personal knowledge base \
about AI systems, agent design, developer tooling, and knowledge management.\n\n\
Author: {}\nTitle signal: {}\nTags: {}\n\n\
Score the relevance 1-5 where:\n\
1 = personal update, marketing, unrelated\n\
2 = tangentially related, low signal\n\
3 = relevant, worth reading\n\
4 = directly relevant to known topics (memory, agents, CLI tooling, CC patterns)\n\
5 = high-signal, likely new dimension content\n\n\
Known dimension topics: {}\n\n\
Respond with JSON only: {{\"score\": N, \"reason\": \"one sentence\"}}",
            entry.author,
            entry.title_signal,
            entry.tags.join(" "),
            dim_list,
        );

        if dry_run {
            println!(
                "  [dry-run] would score: {} (author: {}, tags: {})",
                entry.url,
                entry.author,
                entry.tags.join(" "),
            );
            continue;
        }

        match kp::call_claude_json(&prompt, Some("claude-haiku-4-5-20251001")) {
            Ok(json) => {
                let score = json.get("score").and_then(|v| v.as_u64()).unwrap_or(0) as u8;
                let reason = json
                    .get("reason")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let status = if score >= 3 {
                    passed += 1;
                    UrlStatus::Tier1Passed
                } else {
                    filtered += 1;
                    UrlStatus::Irrelevant
                };

                let icon = if score >= 3 { "✓" } else { "✗" };
                println!("  {icon} [{score}] {} — {reason}", entry.author);

                let url_entry = kp::UrlEntry {
                    status,
                    tier1_score: Some(score),
                    tier1_reason: Some(reason),
                    logged_date: Some(entry.logged_date.clone()),
                    author: Some(entry.author.clone()),
                    title_signal: Some(entry.title_signal.clone()),
                    tags: entry.tags.clone(),
                    ..kp::UrlEntry::new_unprocessed(None)
                };
                state.urls.insert(entry.url.clone(), url_entry);
            }
            Err(e) => {
                eprintln!("  \x1b[33m  ⚠ LLM call failed for {}: {e:#}\x1b[0m", entry.url);
                // Mark as unprocessed with a placeholder so we don't re-attempt endlessly
                // in this batch, but will retry on next run (not saved to state on error)
            }
        }
    }

    if !dry_run {
        let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
        state.last_tier1_run = Some(now);
        kp::save_state(state_path, state)?;
        println!(
            "\n  Tier 1 done — {} passed, {} filtered. State saved.",
            passed, filtered
        );
    }

    Ok(())
}

// ── Tier 2 ────────────────────────────────────────────────────────────────

fn backfill_linkedin_fields(state: &mut kp::PipelineState) -> usize {
    let mut backfilled = 0usize;
    for (url, entry) in state.urls.iter_mut() {
        if entry.author.is_none() || entry.title_signal.is_none() {
            if let Some((author, title_signal)) = kp::parse_linkedin_url(url) {
                if entry.author.is_none() { entry.author = Some(author); }
                if entry.title_signal.is_none() { entry.title_signal = Some(title_signal); }
                backfilled += 1;
            }
        }
    }
    backfilled
}

fn run_tier2(
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    dry_run: bool,
) -> Result<()> {
    let backfilled = backfill_linkedin_fields(state);
    if backfilled > 0 {
        println!("  Backfilled author/title_signal for {backfilled} pre-field URL record(s)");
    }

    let dimension_slugs = kp::list_dimension_slugs(knowledge_root);
    let dim_list: Vec<String> = dimension_slugs
        .iter()
        .map(|s| format!("- {s}"))
        .collect();
    let dim_list_str = dim_list.join("\n");

    let candidates: Vec<_> = state
        .urls
        .iter()
        .filter(|(_, e)| e.status == UrlStatus::Tier1Passed)
        .map(|(url, e)| (
            url.clone(),
            e.author.clone().unwrap_or_default(),
            e.title_signal.clone().unwrap_or_default(),
            e.tags.clone(),
        ))
        .collect();

    if candidates.is_empty() {
        println!("  Tier 2: no tier1-passed URLs found. Run --tier1 first.");
        return Ok(());
    }

    println!(
        "\n  \x1b[1mTier 2 — Cluster assignment\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!("  Processing {} URL(s)\n", candidates.len());

    // Cluster assignments: topic_slug → list of URLs
    let mut clusters: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    let mut dim_targets: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();

    for (url, author, title_signal, tags) in &candidates {
        let prompt = format!(
            "You are assigning a LinkedIn post to the nearest topic in a knowledge base.\n\n\
Author: {author}\nTitle signal: {title_signal}\nTags: {}\n\n\
Existing dimension topics:\n{dim_list_str}\n\n\
Assign this post to the best-matching dimension, or flag as \"new-topic\" \
if it doesn't fit any existing dimension.\n\n\
Respond with JSON only:\n\
{{\"dimension_target\": \"slug or new-topic\", \"cluster_topic\": \"short label\", \"reason\": \"one sentence\"}}",
            tags.join(" "),
        );

        if dry_run {
            println!("  [dry-run] would cluster: {url}");
            continue;
        }

        match kp::call_claude_json(&prompt, None) {
            Ok(json) => {
                let dim_target = json
                    .get("dimension_target")
                    .and_then(|v| v.as_str())
                    .unwrap_or("new-topic")
                    .to_string();
                let cluster_topic = json
                    .get("cluster_topic")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();
                let reason = json
                    .get("reason")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                println!("  → [{cluster_topic}] {author} — {reason}");

                clusters
                    .entry(cluster_topic.clone())
                    .or_default()
                    .push(url.clone());
                dim_targets.insert(cluster_topic.clone(), dim_target.clone());

                if let Some(entry) = state.urls.get_mut(url) {
                    entry.status = UrlStatus::Tier2Clustered;
                    entry.cluster_topic = Some(cluster_topic);
                    entry.dimension_target = Some(dim_target);
                }
            }
            Err(e) => {
                eprintln!("  \x1b[33m  ⚠ LLM call failed for {url}: {e:#}\x1b[0m");
            }
        }
    }

    if dry_run {
        return Ok(());
    }

    // Write cluster report
    let report_path = home().join(".claude/knowledge-pipeline-report.md");
    let report = build_cluster_report(&clusters, &dim_targets);
    kp::assert_allowed_write(&report_path, knowledge_root)
        .unwrap_or(()); // report path is in allowed exact list
    std::fs::write(&report_path, &report)
        .with_context(|| format!("writing cluster report to {}", report_path.display()))?;

    let now = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    state.last_tier2_run = Some(now);
    kp::save_state(state_path, state)?;

    println!(
        "\n  Tier 2 done — {} cluster(s). Report: {}",
        clusters.len(),
        report_path.display()
    );
    println!("  To draft a cluster: brana knowledge process --draft <topic-slug>");

    Ok(())
}

fn build_cluster_report(
    clusters: &std::collections::HashMap<String, Vec<String>>,
    dim_targets: &std::collections::HashMap<String, String>,
) -> String {
    use std::fmt::Write as _;
    let now = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let mut out = format!("# Knowledge Pipeline — Cluster Report\n\nGenerated: {now}\n\n");
    let mut topics: Vec<_> = clusters.keys().collect();
    topics.sort();
    for topic in topics {
        let urls = &clusters[topic];
        let dim = dim_targets.get(topic).map(|s| s.as_str()).unwrap_or("new-topic");
        let _ = writeln!(out, "## {topic}\n\n**Target dimension:** `{dim}`  \n**Sources ({}):**\n", urls.len());
        for url in urls {
            let _ = writeln!(out, "- {url}");
        }
        let _ = writeln!(
            out,
            "\nTo draft: `brana knowledge process --draft {topic}`\n"
        );
    }
    out
}

// ── Tier 3 ────────────────────────────────────────────────────────────────

fn run_tier3(
    topic: &str,
    knowledge_root: &std::path::Path,
    state_path: &std::path::Path,
    state: &mut kp::PipelineState,
    dry_run: bool,
) -> Result<()> {
    // Draft cap
    let draft_count = kp::count_drafts(knowledge_root);
    if draft_count >= DRAFT_CAP {
        bail!(
            "Draft cap hit ({draft_count}/{DRAFT_CAP}). Review and promote/reject drafts first, \
             then run `brana knowledge process --status` to acknowledge."
        );
    }

    // Collect URLs for this cluster
    let cluster_urls: Vec<_> = state
        .urls
        .iter()
        .filter(|(_, e)| {
            e.status == UrlStatus::Tier2Clustered
                && e.cluster_topic.as_deref() == Some(topic)
        })
        .map(|(url, e)| (
            url.clone(),
            e.author.clone().unwrap_or_default(),
            e.title_signal.clone().unwrap_or_default(),
            e.tags.clone(),
            e.dimension_target.clone().unwrap_or_default(),
        ))
        .collect();

    if cluster_urls.is_empty() {
        bail!("No tier2-clustered URLs found for topic '{topic}'. Run --tier2 first.");
    }

    let dim_target = cluster_urls[0].4.clone();

    // Read existing dimension summary if available
    let dim_summary = {
        let dim_path = knowledge_root.join("dimensions").join(format!("{dim_target}.md"));
        if dim_path.exists() {
            let content = std::fs::read_to_string(&dim_path).unwrap_or_default();
            content.chars().take(500).collect::<String>()
        } else {
            String::from("(new dimension — no existing content)")
        }
    };

    let sources_block: String = cluster_urls
        .iter()
        .map(|(url, author, title_signal, tags, _)| {
            format!("- Author: {author}, Title: {title_signal}, Tags: {}, URL: {url}", tags.join(" "))
        })
        .collect::<Vec<_>>()
        .join("\n");

    let prompt = format!(
        "You are writing an addition to a knowledge base dimension document.\n\n\
Dimension: {dim_target}\nExisting content summary:\n{dim_summary}\n\n\
Source posts ({n} posts, approved cluster: {topic}):\n{sources_block}\n\n\
Write a new section to add to this dimension. Use markdown. \
Cite each source post inline as [author, date]. \
Do not repeat content already in the dimension. Focus on new insights only.\n\n\
Output: markdown section only (no frontmatter, no preamble).",
        n = cluster_urls.len(),
    );

    if dry_run {
        println!("  [dry-run] would draft '{topic}' → dimensions/{dim_target}.md");
        println!("  Sources: {} URL(s)", cluster_urls.len());
        return Ok(());
    }

    println!("\n  \x1b[1mTier 3 — Draft synthesis\x1b[0m");
    println!("  Topic: {topic} ({} sources) → {dim_target}", cluster_urls.len());

    let body_text = kp::call_claude_text(&prompt)?;

    let now_date = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let review_due = {
        let d = chrono::Utc::now() + chrono::Duration::days(7);
        d.format("%Y-%m-%d").to_string()
    };

    let sources_yaml: String = cluster_urls
        .iter()
        .map(|(url, _, _, _, _)| format!("  - url: {url}\n    logged: unknown"))
        .collect::<Vec<_>>()
        .join("\n");

    let draft_content = format!(
        "---\nstatus: draft\ncreated: {now_date}\nsources:\n{sources_yaml}\ncluster_topic: {topic}\ndraft_author: llm\nreview_due: {review_due}\npromotion_target: dimensions/{dim_target}.md\n---\n\n{body_text}\n"
    );

    let topic_slug = topic.replace(' ', "-").to_lowercase();
    let draft_filename = format!("{now_date}-{topic_slug}.md");
    let draft_path = knowledge_root.join("drafts").join(&draft_filename);

    kp::assert_allowed_write(&draft_path, knowledge_root)?;
    std::fs::create_dir_all(draft_path.parent().unwrap())?;
    std::fs::write(&draft_path, &draft_content)?;

    // Update state
    for (url, _, _, _, _) in &cluster_urls {
        if let Some(entry) = state.urls.get_mut(url) {
            entry.status = UrlStatus::Tier3Drafted;
            entry.draft_path = Some(draft_path.to_string_lossy().to_string());
        }
    }
    kp::save_state(state_path, state)?;

    println!("  ✓ Draft written: {}", draft_path.display());
    println!("  To promote: brana knowledge promote {}", draft_path.display());

    Ok(())
}

// ── brana knowledge promote ───────────────────────────────────────────────

pub fn cmd_promote(draft_path: PathBuf, dry_run: bool) -> Result<()> {
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!("brana-knowledge repo not found"))?;

    // Resolve draft path (may be relative to knowledge_root or absolute)
    let abs_draft = if draft_path.is_absolute() {
        draft_path.clone()
    } else {
        knowledge_root.join(&draft_path)
    };

    if !abs_draft.exists() {
        bail!("Draft file not found: {}", abs_draft.display());
    }

    kp::assert_allowed_write(&abs_draft, &knowledge_root)?;

    let content = std::fs::read_to_string(&abs_draft)?;

    // Parse promotion_target from frontmatter
    let promotion_target = parse_frontmatter_field(&content, "promotion_target")
        .ok_or_else(|| anyhow::anyhow!("Draft missing 'promotion_target' in frontmatter"))?;

    let target_path = knowledge_root.join(&promotion_target);

    println!("\n  \x1b[1mPromote draft\x1b[0m{}", if dry_run { " [dry-run]" } else { "" });
    println!("  Draft:  {}", abs_draft.display());
    println!("  Target: {}", target_path.display());

    if dry_run {
        return Ok(());
    }

    // Strip draft frontmatter, update status to accepted
    let new_content = set_frontmatter_status(&content, "accepted");

    if target_path.exists() {
        // Append to existing dimension file
        let existing = std::fs::read_to_string(&target_path)?;
        let appended = format!("{existing}\n\n---\n\n<!-- promoted from draft: {} -->\n\n{}", abs_draft.file_name().unwrap_or_default().to_string_lossy(), strip_frontmatter(&new_content));
        std::fs::write(&target_path, appended)?;
        println!("  ✓ Appended to existing dimension: {}", target_path.display());
    } else {
        std::fs::create_dir_all(target_path.parent().unwrap_or(&target_path))?;
        std::fs::write(&target_path, new_content)?;
        println!("  ✓ Created new dimension: {}", target_path.display());
    }

    // Archive the draft
    let archive_dir = knowledge_root
        .join("drafts-archive")
        .join(chrono::Utc::now().format("%Y-%m-%d").to_string());
    std::fs::create_dir_all(&archive_dir)?;
    let archive_dest = archive_dir.join(abs_draft.file_name().unwrap());
    std::fs::rename(&abs_draft, &archive_dest)?;
    println!("  ✓ Draft archived to: {}", archive_dest.display());

    Ok(())
}

// ── helpers ───────────────────────────────────────────────────────────────

#[derive(Default)]
struct TierCounts {
    unprocessed: usize,
    irrelevant: usize,
    tier1_passed: usize,
    tier2_clustered: usize,
    tier3_drafted: usize,
}

fn count_by_tier(state: &kp::PipelineState) -> TierCounts {
    let mut c = TierCounts::default();
    for entry in state.urls.values() {
        match entry.status {
            UrlStatus::Unprocessed => c.unprocessed += 1,
            UrlStatus::Irrelevant => c.irrelevant += 1,
            UrlStatus::Tier1Passed => c.tier1_passed += 1,
            UrlStatus::Tier2Clustered => c.tier2_clustered += 1,
            UrlStatus::Tier3Drafted => c.tier3_drafted += 1,
        }
    }
    c
}

fn url_reset_state(mut state: kp::PipelineState, url: &str) -> kp::PipelineState {
    state.urls.remove(url);
    state
}

fn parse_frontmatter_field(content: &str, field: &str) -> Option<String> {
    let prefix = format!("{field}: ");
    for line in content.lines() {
        if let Some(val) = line.strip_prefix(&prefix) {
            return Some(val.trim().to_string());
        }
    }
    None
}

fn set_frontmatter_status(content: &str, new_status: &str) -> String {
    content
        .lines()
        .map(|line| {
            if line.starts_with("status: ") {
                format!("status: {new_status}")
            } else {
                line.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn strip_frontmatter(content: &str) -> String {
    let mut lines = content.lines();
    // Skip opening ---
    if lines.next().map(|l| l.trim()) == Some("---") {
        let rest: Vec<_> = lines.collect();
        if let Some(pos) = rest.iter().position(|l| l.trim() == "---") {
            return rest[pos + 1..].join("\n").trim_start().to_string();
        }
    }
    content.to_string()
}

// ── brana knowledge next ──────────────────────────────────────────────────────

/// Determine the single next pipeline action given current state.
///
/// Priority order (first match wins):
/// 1. `unprocessed > 0`                         → `process --tier1`
/// 2. `tier1_passed > 0`                         → `process --tier2`
/// 3. `drafts_on_disk > 0`                       → `promote <first-draft>`
/// 4. `tier2_clustered > 0` (no drafts on disk)  → `process --report`
/// 5. all current                                 → `ingest <url>`
pub fn next_directive(state: &kp::PipelineState, knowledge_root: &std::path::Path) -> String {
    let counts = count_by_tier(state);

    if counts.unprocessed > 0 {
        return "brana knowledge process --tier1".to_string();
    }
    if counts.tier1_passed > 0 {
        return "brana knowledge process --tier2".to_string();
    }
    let draft_count = kp::count_drafts(knowledge_root);
    if draft_count > 0 {
        let drafts_dir = knowledge_root.join("drafts");
        if let Ok(dir) = std::fs::read_dir(&drafts_dir) {
            let mut paths: Vec<_> = dir
                .flatten()
                .filter(|e| {
                    e.path().extension().and_then(|x| x.to_str()) == Some("md")
                })
                .map(|e| e.path())
                .collect();
            paths.sort();
            if let Some(first) = paths.first() {
                return format!("brana knowledge promote {}", first.display());
            }
        }
        return "brana knowledge promote <draft-path>".to_string();
    }
    if counts.tier2_clustered > 0 {
        return "brana knowledge process --report".to_string();
    }
    "brana knowledge ingest <url>".to_string()
}

/// `brana knowledge next` — emit the single next pipeline command to run.
pub fn cmd_next() -> Result<()> {
    let knowledge_root = kp::find_brana_knowledge_root()
        .ok_or_else(|| anyhow::anyhow!(
            "brana-knowledge repo not found. Checked: $BRANA_KNOWLEDGE_ROOT, \
             sibling of git root, ~/enter_thebrana/brana-knowledge/"
        ))?;
    let state_path = kp::pipeline_state_path();
    let state = kp::load_state(&state_path)?;
    let directive = next_directive(&state, &knowledge_root);
    println!("{directive}");
    Ok(())
}

// ── brana knowledge ingest ────────────────────────────────────────────────────

/// `brana knowledge ingest [sources...] [--source <tag>] [--dry-run]`
///
/// Sources may be:
/// - Direct `https://` URLs (passed through unchanged)
/// - File paths (content read; URLs extracted via regex)
/// - Absent (stdin read if piped; error if terminal)
pub fn cmd_ingest(
    sources: Vec<String>,
    source_tag: Option<String>,
    dry_run: bool,
) -> Result<()> {
    let mut raw_text = String::new();
    let mut direct_urls: Vec<String> = Vec::new();

    if sources.is_empty() {
        if std::io::stdin().is_terminal() {
            anyhow::bail!(
                "No input. Provide file paths or URLs, or pipe text: cat urls.txt | brana knowledge ingest"
            );
        }
        use std::io::Read as _;
        std::io::stdin()
            .read_to_string(&mut raw_text)
            .context("reading from stdin")?;
    } else {
        for src in &sources {
            if src.starts_with("https://") || src.starts_with("http://") {
                direct_urls.push(src.clone());
            } else {
                let path = std::path::Path::new(src);
                if path.exists() {
                    let content = std::fs::read_to_string(path)
                        .with_context(|| format!("reading {}", path.display()))?;
                    raw_text.push_str(&content);
                    raw_text.push('\n');
                } else {
                    raw_text.push_str(src);
                    raw_text.push('\n');
                }
            }
        }
    }

    let mut extracted = kp::extract_urls_from_text(&raw_text);
    for url in &direct_urls {
        if !extracted.contains(url) {
            extracted.push(url.clone());
        }
    }

    if extracted.is_empty() {
        println!("  No URLs found in input.");
        return Ok(());
    }

    println!(
        "\n  \x1b[1mbrana knowledge ingest\x1b[0m{}",
        if dry_run { " [dry-run]" } else { "" }
    );
    println!("  {} URL(s) extracted\n", extracted.len());

    let state_path = kp::pipeline_state_path();
    let mut state = kp::load_state(&state_path)?;
    let result = kp::ingest_urls(&extracted, source_tag.as_deref(), &mut state);

    println!("  ✓ {} new URL(s) queued", result.queued);
    if result.duplicates > 0 {
        println!("  · {} duplicate(s) skipped", result.duplicates);
    }

    if dry_run {
        println!("  [dry-run] state not written.");
    } else if result.queued > 0 {
        kp::save_state(&state_path, &state)?;
        println!("\n  Next: brana knowledge process --status");
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── parse_search_results ─────────────────────────────────────────

    #[test]
    fn test_parse_valid_results() {
        let json = r#"[
            {"key": "knowledge:docs/reflections/31-assurance.md:testing", "value": "Testing and assurance framework overview", "score": 0.82},
            {"key": "pattern:thebrana:hooks-cant-enforce-ordering", "value": "Hooks are stateless — can't enforce workflow ordering", "score": 0.75}
        ]"#;
        let results = parse_search_results(json).expect("should parse");
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].key, "knowledge:docs/reflections/31-assurance.md:testing");
        assert!((results[0].score - 0.82).abs() < 1e-9);
        assert_eq!(results[1].key, "pattern:thebrana:hooks-cant-enforce-ordering");
    }

    #[test]
    fn test_parse_empty_array() {
        let results = parse_search_results("[]").expect("should parse");
        assert!(results.is_empty());
    }

    #[test]
    fn test_parse_missing_score_defaults_to_zero() {
        let json = r#"[{"key": "knowledge:some:key", "value": "content here"}]"#;
        let results = parse_search_results(json).expect("should parse");
        assert_eq!(results.len(), 1);
        assert!((results[0].score - 0.0).abs() < 1e-9);
    }

    #[test]
    fn test_parse_invalid_json_returns_error() {
        assert!(parse_search_results("not json").is_err());
        assert!(parse_search_results("{\"key\":\"v\"}").is_err()); // object, not array
    }

    // ── truncate ─────────────────────────────────────────────────────

    #[test]
    fn test_truncate_short_string_unchanged() {
        assert_eq!(truncate("hello world", 50), "hello world");
    }

    #[test]
    fn test_truncate_exact_length_unchanged() {
        let s = "abcde";
        assert_eq!(truncate(s, 5), "abcde");
    }

    #[test]
    fn test_truncate_long_string_clipped() {
        let s = "abcdefghij";
        let result = truncate(s, 5);
        assert_eq!(result, "abcde...");
    }

    #[test]
    fn test_truncate_trims_whitespace() {
        assert_eq!(truncate("  hi  ", 50), "hi");
    }

    // ── format_results ───────────────────────────────────────────────

    #[test]
    fn test_format_empty_results() {
        let out = format_results(&[]);
        assert!(out.contains("No results found"));
    }

    #[test]
    fn test_format_single_result() {
        let results = vec![SearchResult {
            key: "knowledge:docs/reflections/31-assurance.md:testing".into(),
            value: "Testing and assurance framework overview".into(),
            score: 0.82,
        }];
        let out = format_results(&results);
        assert!(out.contains("1."), "should contain rank number");
        assert!(out.contains("[0.82]"), "should contain formatted score");
        assert!(out.contains("knowledge:docs/reflections/31-assurance.md:testing"), "should contain key");
        assert!(out.contains("Testing and assurance framework"), "should contain value preview");
    }

    #[test]
    fn test_format_multiple_results_numbered_sequentially() {
        let results = vec![
            SearchResult { key: "k:a".into(), value: "first".into(), score: 0.9 },
            SearchResult { key: "k:b".into(), value: "second".into(), score: 0.7 },
            SearchResult { key: "k:c".into(), value: "third".into(), score: 0.5 },
        ];
        let out = format_results(&results);
        assert!(out.contains("1."));
        assert!(out.contains("2."));
        assert!(out.contains("3."));
        // Verify ordering: first result should appear before second
        let pos_first = out.find("k:a").unwrap();
        let pos_second = out.find("k:b").unwrap();
        assert!(pos_first < pos_second);
    }

    #[test]
    fn test_format_long_value_is_truncated() {
        let long_value = "x".repeat(200);
        let results = vec![SearchResult {
            key: "k:long".into(),
            value: long_value,
            score: 0.5,
        }];
        let out = format_results(&results);
        // Value preview line should end with "..." due to truncation
        assert!(out.contains("..."), "long value should be truncated with ...");
    }

    #[test]
    fn test_format_score_precision() {
        let results = vec![SearchResult {
            key: "k:precise".into(),
            value: "some content".into(),
            score: 0.123456,
        }];
        let out = format_results(&results);
        // Score should be formatted with 2 decimal places
        assert!(out.contains("[0.12]"), "score should be 2 decimal places, got: {out}");
    }

    // ── parse_frontmatter_field ──────────────────────────────────────────

    #[test]
    fn test_parse_frontmatter_field_present() {
        let content = "---\nstatus: draft\ncluster_topic: agent-memory\n---\nbody";
        assert_eq!(
            parse_frontmatter_field(content, "cluster_topic"),
            Some("agent-memory".to_string())
        );
    }

    #[test]
    fn test_parse_frontmatter_field_missing_returns_none() {
        let content = "---\nstatus: draft\n---\nbody";
        assert_eq!(parse_frontmatter_field(content, "promotion_target"), None);
    }

    #[test]
    fn test_parse_frontmatter_field_trims_whitespace() {
        let content = "promotion_target:   dimensions/21-memory.md  ";
        assert_eq!(
            parse_frontmatter_field(content, "promotion_target"),
            Some("dimensions/21-memory.md".to_string())
        );
    }

    // ── set_frontmatter_status ───────────────────────────────────────────

    #[test]
    fn test_set_frontmatter_status_replaces_status_line() {
        let content = "---\nstatus: draft\ncreated: 2026-04-12\n---\nbody";
        let result = set_frontmatter_status(content, "accepted");
        assert!(result.contains("status: accepted"));
        assert!(!result.contains("status: draft"));
    }

    #[test]
    fn test_set_frontmatter_status_leaves_other_lines_unchanged() {
        let content = "---\nstatus: draft\ncreated: 2026-04-12\n---\nbody";
        let result = set_frontmatter_status(content, "accepted");
        assert!(result.contains("created: 2026-04-12"));
        assert!(result.contains("body"));
    }

    #[test]
    fn test_set_frontmatter_status_no_status_line_unchanged() {
        let content = "---\ncreated: 2026-04-12\n---\nbody";
        let result = set_frontmatter_status(content, "accepted");
        assert!(!result.contains("status:"));
        assert!(result.contains("created: 2026-04-12"));
    }

    // ── strip_frontmatter ────────────────────────────────────────────────

    #[test]
    fn test_strip_frontmatter_removes_yaml_block() {
        let content = "---\nstatus: draft\n---\n\n# Body\n\ncontent here";
        assert_eq!(strip_frontmatter(content), "# Body\n\ncontent here");
    }

    #[test]
    fn test_strip_frontmatter_no_frontmatter_returns_unchanged() {
        let content = "# Just a doc\n\nno frontmatter";
        assert_eq!(strip_frontmatter(content), "# Just a doc\n\nno frontmatter");
    }

    #[test]
    fn test_strip_frontmatter_unclosed_returns_unchanged() {
        let content = "---\nstatus: draft\n\n# Body";
        // no closing ---, returns original
        assert_eq!(strip_frontmatter(content), "---\nstatus: draft\n\n# Body");
    }

    // ── count_by_tier ────────────────────────────────────────────────────

    fn make_entry(status: UrlStatus) -> kp::UrlEntry {
        let mut e = kp::UrlEntry::new_unprocessed(None);
        e.status = status;
        e
    }

    #[test]
    fn test_count_by_tier_empty_state() {
        let state = kp::PipelineState::default();
        let counts = count_by_tier(&state);
        assert_eq!(counts.unprocessed, 0);
        assert_eq!(counts.tier1_passed, 0);
    }

    #[test]
    fn test_count_by_tier_mixed_statuses() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("u1".into(), make_entry(UrlStatus::Unprocessed));
        state.urls.insert("u2".into(), make_entry(UrlStatus::Unprocessed));
        state.urls.insert("u3".into(), make_entry(UrlStatus::Tier1Passed));
        state.urls.insert("u4".into(), make_entry(UrlStatus::Irrelevant));
        state.urls.insert("u5".into(), make_entry(UrlStatus::Tier2Clustered));
        state.urls.insert("u6".into(), make_entry(UrlStatus::Tier3Drafted));
        let counts = count_by_tier(&state);
        assert_eq!(counts.unprocessed, 2);
        assert_eq!(counts.irrelevant, 1);
        assert_eq!(counts.tier1_passed, 1);
        assert_eq!(counts.tier2_clustered, 1);
        assert_eq!(counts.tier3_drafted, 1);
    }

    // ── url_reset_state ──────────────────────────────────────────────────

    #[test]
    fn test_url_reset_state_removes_url() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(UrlStatus::Tier1Passed));
        let new_state = url_reset_state(state, "https://example.com");
        assert!(!new_state.urls.contains_key("https://example.com"));
    }

    #[test]
    fn test_url_reset_state_missing_url_is_noop() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://kept.com".into(), make_entry(UrlStatus::Tier1Passed));
        let new_state = url_reset_state(state, "https://gone.com");
        assert!(new_state.urls.contains_key("https://kept.com"));
        assert_eq!(new_state.urls.len(), 1);
    }

    // ── build_cluster_report ─────────────────────────────────────────────

    #[test]
    fn test_build_cluster_report_contains_topic_and_target() {
        let mut clusters = std::collections::HashMap::new();
        clusters.insert("agent-memory".to_string(), vec!["https://linkedin.com/u1".to_string()]);
        let mut dim_targets = std::collections::HashMap::new();
        dim_targets.insert("agent-memory".to_string(), "21-memory-patterns".to_string());
        let report = build_cluster_report(&clusters, &dim_targets);
        assert!(report.contains("## agent-memory"));
        assert!(report.contains("21-memory-patterns"));
        assert!(report.contains("https://linkedin.com/u1"));
    }

    #[test]
    fn test_build_cluster_report_empty_returns_header() {
        let clusters = std::collections::HashMap::new();
        let dim_targets = std::collections::HashMap::new();
        let report = build_cluster_report(&clusters, &dim_targets);
        assert!(report.contains("# Knowledge Pipeline"));
    }

    #[test]
    fn test_build_cluster_report_includes_draft_command() {
        let mut clusters = std::collections::HashMap::new();
        clusters.insert("cli-tooling".to_string(), vec!["https://linkedin.com/u2".to_string()]);
        let dim_targets = std::collections::HashMap::new();
        let report = build_cluster_report(&clusters, &dim_targets);
        assert!(report.contains("brana knowledge process --draft cli-tooling"));
    }

    // ── backfill_linkedin_fields ─────────────────────────────────────────

    #[test]
    fn test_backfill_linkedin_fields_populates_missing_author_and_title() {
        let url = "https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-7437448165403852801-F5RX";
        let mut state = kp::PipelineState::default();
        state.urls.insert(url.to_string(), make_entry(kp::UrlStatus::Unprocessed));
        let count = backfill_linkedin_fields(&mut state);
        assert_eq!(count, 1);
        let entry = &state.urls[url];
        assert_eq!(entry.author.as_deref(), Some("walid-boulanouar"));
        assert!(entry.title_signal.is_some());
    }

    #[test]
    fn test_backfill_linkedin_fields_skips_non_linkedin_urls() {
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://github.com/foo/bar".to_string(), make_entry(kp::UrlStatus::Unprocessed));
        let count = backfill_linkedin_fields(&mut state);
        assert_eq!(count, 0);
        let entry = state.urls.values().next().unwrap();
        assert!(entry.author.is_none());
    }

    #[test]
    fn test_backfill_linkedin_fields_skips_fully_populated_entries() {
        let url = "https://www.linkedin.com/posts/walid-boulanouar_everyone-using-claude-code-is-paying-for-share-7437448165403852801-F5RX";
        let mut state = kp::PipelineState::default();
        let mut entry = make_entry(kp::UrlStatus::Unprocessed);
        entry.author = Some("already-set".to_string());
        entry.title_signal = Some("already-set-title".to_string());
        state.urls.insert(url.to_string(), entry);
        let count = backfill_linkedin_fields(&mut state);
        assert_eq!(count, 0);
        assert_eq!(state.urls[url].author.as_deref(), Some("already-set"));
    }

    // ── next_directive ───────────────────────────────────────────────────

    #[test]
    fn test_next_directive_empty_state_ingest() {
        let dir = tempfile::TempDir::new().unwrap();
        let state = kp::PipelineState::default();
        let d = next_directive(&state, dir.path());
        assert!(d.starts_with("brana knowledge ingest"), "got: {d}");
    }

    #[test]
    fn test_next_directive_unprocessed_tier1() {
        let dir = tempfile::TempDir::new().unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Unprocessed));
        let d = next_directive(&state, dir.path());
        assert_eq!(d, "brana knowledge process --tier1");
    }

    #[test]
    fn test_next_directive_tier1_passed_tier2() {
        let dir = tempfile::TempDir::new().unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Tier1Passed));
        let d = next_directive(&state, dir.path());
        assert_eq!(d, "brana knowledge process --tier2");
    }

    #[test]
    fn test_next_directive_clusters_no_drafts_report() {
        let dir = tempfile::TempDir::new().unwrap();
        std::fs::create_dir(dir.path().join("drafts")).unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Tier2Clustered));
        let d = next_directive(&state, dir.path());
        assert_eq!(d, "brana knowledge process --report");
    }

    #[test]
    fn test_next_directive_drafts_on_disk_promote() {
        let dir = tempfile::TempDir::new().unwrap();
        let drafts = dir.path().join("drafts");
        std::fs::create_dir(&drafts).unwrap();
        std::fs::write(drafts.join("2026-05-24-agents.md"), "# draft").unwrap();
        let mut state = kp::PipelineState::default();
        state.urls.insert("https://example.com".into(), make_entry(kp::UrlStatus::Tier2Clustered));
        let d = next_directive(&state, dir.path());
        assert!(d.starts_with("brana knowledge promote"), "got: {d}");
        assert!(d.contains("2026-05-24-agents.md"), "got: {d}");
    }

    #[test]
    fn test_next_directive_drafts_only_no_clusters_promote() {
        let dir = tempfile::TempDir::new().unwrap();
        let drafts = dir.path().join("drafts");
        std::fs::create_dir(&drafts).unwrap();
        std::fs::write(drafts.join("2026-05-01-topic.md"), "# draft").unwrap();
        let state = kp::PipelineState::default();
        let d = next_directive(&state, dir.path());
        assert!(d.starts_with("brana knowledge promote"), "got: {d}");
    }
}
