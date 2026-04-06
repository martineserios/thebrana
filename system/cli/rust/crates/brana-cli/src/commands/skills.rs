//! Skill discovery and routing — `brana skills suggest|search|list`
//!
//! Parses SKILL.md frontmatter from system/skills/ directories,
//! builds an in-memory index, and scores skills against task context.
//! Scoring algorithm per ADR-025.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;

/// Parsed skill frontmatter (subset of fields relevant for routing).
#[derive(Debug, Clone, Deserialize)]
pub struct SkillMeta {
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub effort: Option<String>,
    #[serde(default)]
    pub group: Option<String>,
    #[serde(default)]
    pub keywords: Vec<String>,
    #[serde(default)]
    pub task_strategies: Vec<String>,
    #[serde(default)]
    pub stream_affinity: Vec<String>,
}

/// A scored skill match.
#[derive(Debug, Serialize)]
pub struct SkillMatch {
    pub name: String,
    pub score: f64,
    pub reason: String,
}

/// Task context used for matching.
pub struct TaskContext {
    pub description_words: HashSet<String>,
    pub tags: HashSet<String>,
    pub strategy: Option<String>,
    pub stream: Option<String>,
}

/// Parse YAML frontmatter from a SKILL.md file.
pub fn parse_frontmatter(content: &str) -> Option<SkillMeta> {
    let trimmed = content.trim_start();
    if !trimmed.starts_with("---") {
        return None;
    }
    let after_first = &trimmed[3..];
    let end = after_first.find("\n---")?;
    let yaml_str = &after_first[..end];
    serde_yaml::from_str(yaml_str).ok()
}

/// Scan a directory for SKILL.md files and parse their frontmatter.
pub fn scan_skills(dirs: &[PathBuf]) -> Vec<SkillMeta> {
    let mut skills = Vec::new();
    for dir in dirs {
        if !dir.exists() {
            continue;
        }
        let Ok(entries) = fs::read_dir(dir) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                // Check if it's a command .md file (not in a subdirectory)
                if path.extension().is_some_and(|e| e == "md") {
                    if let Ok(content) = fs::read_to_string(&path) {
                        if let Some(meta) = parse_frontmatter(&content) {
                            skills.push(meta);
                        }
                    }
                }
                continue;
            }
            let skill_file = path.join("SKILL.md");
            if skill_file.exists() {
                if let Ok(content) = fs::read_to_string(&skill_file) {
                    if let Some(meta) = parse_frontmatter(&content) {
                        skills.push(meta);
                    }
                }
            }
        }
    }
    skills
}

/// Score a skill against task context.
///
/// Improved scoring: exact keyword match + description substring match + name match.
/// score = (keyword_match × 0.3) + (description_match × 0.2) + (name_match × 0.1)
///       + (tag_overlap × 0.2) + (strategy_match × 0.1) + (stream_match × 0.1)
pub fn score_skill(skill: &SkillMeta, ctx: &TaskContext) -> (f64, String) {
    let mut reasons = Vec::new();

    let skill_kw: HashSet<&str> = skill.keywords.iter().map(|s| s.as_str()).collect();

    // 1. Keyword match: task description words ∩ skill keywords (normalized by match count, not skill size)
    let kw_matches: Vec<&str> = ctx
        .description_words
        .iter()
        .filter(|w| skill_kw.contains(w.as_str()))
        .map(|s| s.as_str())
        .collect();
    let kw_score = if kw_matches.is_empty() {
        0.0
    } else {
        reasons.push(format!("keywords: {}", kw_matches.join(", ")));
        // Score by number of matches (capped at 1.0), not ratio to skill keywords
        (kw_matches.len() as f64 / 3.0).min(1.0)
    };

    // 2. Description match: task words found in skill description (fuzzy)
    let desc_lower = skill.description.as_deref().unwrap_or("").to_lowercase();
    let desc_matches: Vec<&str> = ctx
        .description_words
        .iter()
        .filter(|w| w.len() > 3 && desc_lower.contains(w.as_str()))
        .map(|s| s.as_str())
        .collect();
    let desc_score = if desc_matches.is_empty() {
        0.0
    } else {
        reasons.push(format!("description: {}", desc_matches.join(", ")));
        (desc_matches.len() as f64 / 3.0).min(1.0)
    };

    // 3. Name match: skill name appears in task description
    let name_score = if ctx.description_words.contains(&skill.name) {
        reasons.push(format!("name: {}", skill.name));
        1.0
    } else {
        0.0
    };

    // 4. Tag overlap: task tags ∩ skill keywords
    let tag_matches: Vec<&str> = ctx
        .tags
        .iter()
        .filter(|t| skill_kw.contains(t.as_str()))
        .map(|s| s.as_str())
        .collect();
    let tag_score = if tag_matches.is_empty() {
        0.0
    } else {
        reasons.push(format!("tags: {}", tag_matches.join(", ")));
        (tag_matches.len() as f64 / 2.0).min(1.0)
    };

    // 5. Strategy match
    let strategy_score = match &ctx.strategy {
        Some(s) if skill.task_strategies.iter().any(|ts| ts == s) => {
            reasons.push(format!("strategy: {s}"));
            1.0
        }
        _ => 0.0,
    };

    // 6. Stream match
    let stream_score = match &ctx.stream {
        Some(s) if skill.stream_affinity.iter().any(|sa| sa == s) => {
            reasons.push(format!("stream: {s}"));
            1.0
        }
        _ => 0.0,
    };

    let score = (kw_score * 0.3) + (desc_score * 0.2) + (name_score * 0.1)
        + (tag_score * 0.2) + (strategy_score * 0.1) + (stream_score * 0.1);
    let reason = if reasons.is_empty() {
        "no match".to_string()
    } else {
        reasons.join("; ")
    };

    (score, reason)
}

/// Suggest top N skills for a task context.
pub fn suggest(skills: &[SkillMeta], ctx: &TaskContext, top_n: usize) -> Vec<SkillMatch> {
    let mut scored: Vec<SkillMatch> = skills
        .iter()
        .map(|s| {
            let (score, reason) = score_skill(s, ctx);
            SkillMatch {
                name: s.name.clone(),
                score,
                reason,
            }
        })
        .filter(|m| m.score > 0.0)
        .collect();

    scored.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(top_n);
    scored
}

/// Search skills by free-text query (matches name, description, keywords).
pub fn search(skills: &[SkillMeta], query: &str) -> Vec<SkillMatch> {
    let terms: Vec<&str> = query.split_whitespace().collect();
    let mut results: Vec<SkillMatch> = skills
        .iter()
        .filter_map(|s| {
            let haystack = format!(
                "{} {} {}",
                s.name,
                s.description.as_deref().unwrap_or(""),
                s.keywords.join(" ")
            )
            .to_lowercase();

            let matched: Vec<&&str> = terms.iter().filter(|t| haystack.contains(&t.to_lowercase())).collect();
            if matched.is_empty() {
                None
            } else {
                let score = matched.len() as f64 / terms.len() as f64;
                Some(SkillMatch {
                    name: s.name.clone(),
                    score,
                    reason: format!("matched: {}", matched.iter().map(|t| **t).collect::<Vec<&str>>().join(", ")),
                })
            }
        })
        .collect();

    results.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
    results
}

// ── CLI command handlers ──────────────────────────────────────────

/// Resolve skill directories from git root.
fn skill_dirs() -> Vec<PathBuf> {
    let git_root = crate::util::find_project_root().unwrap_or_else(|| PathBuf::from("."));
    vec![
        git_root.join("system/skills"),
        git_root.join("system/skills/acquired"),
        git_root.join("system/commands"),
    ]
}

/// Build a query string from TaskContext for ruflo semantic search.
fn build_query_string(ctx: &TaskContext) -> String {
    let mut parts: Vec<String> = Vec::new();
    parts.extend(ctx.description_words.iter().cloned());
    parts.extend(ctx.tags.iter().cloned());
    if let Some(ref s) = ctx.strategy {
        parts.push(s.clone());
    }
    if let Some(ref s) = ctx.stream {
        parts.push(s.clone());
    }
    parts.join(" ")
}

/// Resolve the ruflo/claude-flow binary path.
/// Checks: $CF env → cf-env.sh → nvm global bins → PATH.
fn which_ruflo() -> Option<String> {
    // 1. Try sourcing cf-env.sh (sets $CF)
    let home = std::env::var("HOME").unwrap_or_default();
    let cf_env = format!("{home}/.claude/scripts/cf-env.sh");
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

    // 2. Try common nvm global bin locations
    let nvm_dir = std::env::var("NVM_DIR").unwrap_or_else(|_| format!("{home}/.nvm"));
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

    // 3. Try PATH (works when not in nvm)
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

/// Parse ruflo memory search output into SkillMatch entries.
fn parse_ruflo_results(text: &str) -> Option<Vec<SkillMatch>> {
    let val: serde_json::Value = serde_json::from_str(text).ok()?;
    let entries = val.as_array()?;
    let matches: Vec<SkillMatch> = entries
        .iter()
        .filter_map(|e| {
            let key = e["key"].as_str()?;
            let name = key.strip_prefix("skill:")?.to_string();
            let score = e["score"].as_f64().unwrap_or(0.0);
            Some(SkillMatch {
                name,
                score,
                reason: "ruflo semantic".to_string(),
            })
        })
        .collect();
    if matches.is_empty() {
        None
    } else {
        Some(matches)
    }
}

/// Try ruflo semantic search for skill suggestions.
/// Returns None if ruflo is unavailable or returns no results.
/// Uses a 15-second timeout because ruflo CLI can hang after completion.
fn try_ruflo_suggest(query: &str) -> Option<Vec<SkillMatch>> {
    // Resolve ruflo binary: check CF env var, then search PATH
    let cf = std::env::var("CF")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(which_ruflo)?;

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());

    // Spawn the ruflo process (don't use .output() — need timeout control)
    let mut child = std::process::Command::new(&cf)
        .args([
            "memory", "search", "-q", query, "--namespace", "skills", "--limit", "5",
        ])
        .env("HOME", &home)
        .current_dir(&home)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .ok()?;

    // Wait with 15-second timeout (ruflo hangs after completion — known issue)
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
    let text = String::from_utf8_lossy(&output.stdout);
    parse_ruflo_results(&text)
}

/// `brana skills suggest --task <id>` or `--query <text>`
pub fn cmd_suggest(task_id: Option<&str>, query: Option<&str>) -> Result<()> {
    let ctx = if let Some(tid) = task_id {
        // Read task metadata via backlog get
        build_context_from_task(tid)
            .with_context(|| format!("reading task {tid}"))?
    } else if let Some(q) = query {
        TaskContext {
            description_words: q.split_whitespace().map(|w| w.to_lowercase()).collect(),
            tags: HashSet::new(),
            strategy: None,
            stream: None,
        }
    } else {
        anyhow::bail!("Provide --task <id> or --query <text>");
    };

    // Build query string for ruflo semantic search
    let query_str = build_query_string(&ctx);

    // Try ruflo semantic search first (HNSW vectors, better than keyword matching)
    if !query_str.is_empty() {
        if let Some(ruflo_matches) = try_ruflo_suggest(&query_str) {
            if !ruflo_matches.is_empty() {
                let json = serde_json::to_string_pretty(&ruflo_matches).unwrap_or_default();
                println!("{json}");
                return Ok(());
            }
        }
    }

    // Fallback: local keyword/tag scoring
    let skills = scan_skills(&skill_dirs());
    let matches = suggest(&skills, &ctx, 3);
    let json = serde_json::to_string_pretty(&matches).unwrap_or_default();
    println!("{json}");
    Ok(())
}

/// `brana skills search <query>`
pub fn cmd_search(query: &str) -> Result<()> {
    let skills = scan_skills(&skill_dirs());
    let results = search(&skills, query);
    let json = serde_json::to_string_pretty(&results).unwrap_or_default();
    println!("{json}");
    Ok(())
}

/// `brana skills list`
pub fn cmd_list() -> Result<()> {
    let skills = scan_skills(&skill_dirs());

    #[derive(Serialize)]
    struct SkillInfo {
        name: String,
        description: String,
        effort: String,
        group: String,
        keywords: Vec<String>,
    }

    let infos: Vec<SkillInfo> = skills
        .iter()
        .map(|s| SkillInfo {
            name: s.name.clone(),
            description: s.description.clone().unwrap_or_default(),
            effort: s.effort.clone().unwrap_or_default(),
            group: s.group.clone().unwrap_or_default(),
            keywords: s.keywords.clone(),
        })
        .collect();

    let json = serde_json::to_string_pretty(&infos).unwrap_or_default();
    println!("{json}");
    Ok(())
}

/// `brana skills reindex [--changed] [--force]`
///
/// - No flags: full reindex (deletes mtime marker, runs script without `--changed`)
/// - `--changed`: incremental reindex (respects mtime marker)
/// - `--force`: always delete the mtime marker before running, even when combined with `--changed`
pub fn cmd_reindex(changed: bool, force: bool) {
    let root = crate::util::find_project_root().unwrap_or_else(|| {
        eprintln!("Not in git repo");
        std::process::exit(1);
    });
    let script = root.join("system/scripts/index-skills.sh");
    if !script.exists() {
        eprintln!("index-skills.sh not found at {}", script.display());
        std::process::exit(1);
    }

    let mtime_file = std::path::Path::new("/tmp/brana-skills-index-mtime");

    // Delete the mtime marker when:
    //   - not --changed (default full reindex), OR
    //   - --force is set (explicit bypass regardless of --changed)
    if !changed || force {
        if mtime_file.exists() {
            let _ = fs::remove_file(mtime_file);
        }
    }

    let mut cmd = std::process::Command::new("bash");
    cmd.arg(&script).current_dir(&root);
    // Pass --changed only when requested AND not forced (force wins over changed)
    if changed && !force {
        cmd.arg("--changed");
    }

    println!("\n  Running index-skills.sh...");
    match cmd.status() {
        Ok(s) if s.success() => println!("  \x1b[32mDone.\x1b[0m\n"),
        Ok(s) => {
            eprintln!("  \x1b[31mFailed (exit {}).\x1b[0m", s.code().unwrap_or(-1));
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("  \x1b[31mFailed: {e}\x1b[0m");
            std::process::exit(1);
        }
    }
}

/// Build a TaskContext from a task ID by reading tasks.json.
fn build_context_from_task(task_id: &str) -> Result<TaskContext> {
    let tasks_path = crate::util::find_tasks_file()
        .context("could not find tasks.json")?;
    let data: serde_json::Value = serde_json::from_str(
        &fs::read_to_string(&tasks_path).context("reading tasks.json")?,
    )?;

    let tasks = data["tasks"].as_array().context("no tasks array")?;
    let task = tasks
        .iter()
        .find(|t| t["id"].as_str() == Some(task_id))
        .context(format!("task {task_id} not found"))?;

    let description = task["description"].as_str().unwrap_or("");
    let subject = task["subject"].as_str().unwrap_or("");
    let desc_words: HashSet<String> = format!("{subject} {description}")
        .split_whitespace()
        .map(|w| w.to_lowercase().trim_matches(|c: char| !c.is_alphanumeric()).to_string())
        .filter(|w| w.len() > 2)
        .collect();

    let tags: HashSet<String> = task["tags"]
        .as_array()
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_lowercase())).collect())
        .unwrap_or_default();

    let strategy = task["strategy"].as_str().map(|s| s.to_string());
    let stream = task["stream"].as_str().map(|s| s.to_string());

    Ok(TaskContext {
        description_words: desc_words,
        tags,
        strategy,
        stream,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_skills() -> Vec<SkillMeta> {
        vec![
            SkillMeta {
                name: "meta-template".into(),
                description: Some("Write Meta WhatsApp templates".into()),
                effort: Some("medium".into()),
                group: Some("utility".into()),
                keywords: vec![
                    "whatsapp".into(), "meta".into(), "template".into(),
                    "messaging".into(), "waba".into(), "utility".into(), "business-api".into(),
                ],
                task_strategies: vec!["feature".into(), "spike".into()],
                stream_affinity: vec!["roadmap".into(), "research".into()],
            },
            SkillMeta {
                name: "financial-model".into(),
                description: Some("Revenue projections, scenario analysis".into()),
                effort: Some("high".into()),
                group: Some("venture".into()),
                keywords: vec![
                    "revenue".into(), "projections".into(), "p-and-l".into(),
                    "unit-economics".into(), "cash-flow".into(), "scenario".into(), "fundraise".into(),
                ],
                task_strategies: vec!["feature".into(), "spike".into()],
                stream_affinity: vec!["roadmap".into(), "research".into()],
            },
            SkillMeta {
                name: "build".into(),
                description: Some("Build anything".into()),
                effort: Some("high".into()),
                group: Some("execution".into()),
                keywords: vec![
                    "development".into(), "implementation".into(), "tdd".into(),
                    "feature".into(), "bug-fix".into(), "refactor".into(), "coding".into(),
                ],
                task_strategies: vec![
                    "feature".into(), "bug-fix".into(), "refactor".into(),
                    "spike".into(), "greenfield".into(), "migration".into(), "investigation".into(),
                ],
                stream_affinity: vec!["roadmap".into(), "bugs".into(), "tech-debt".into(), "experiments".into()],
            },
        ]
    }

    #[test]
    fn test_parse_frontmatter_valid() {
        let content = r#"---
name: test-skill
description: "A test skill"
effort: low
keywords: [testing, validation]
task_strategies: [feature]
stream_affinity: [roadmap]
---

# Body content
"#;
        let meta = parse_frontmatter(content).expect("should parse");
        assert_eq!(meta.name, "test-skill");
        assert_eq!(meta.keywords, vec!["testing", "validation"]);
        assert_eq!(meta.task_strategies, vec!["feature"]);
        assert_eq!(meta.stream_affinity, vec!["roadmap"]);
    }

    #[test]
    fn test_parse_frontmatter_no_routing_fields() {
        let content = "---\nname: old-skill\ndescription: \"No routing\"\n---\n# Body\n";
        let meta = parse_frontmatter(content).expect("should parse");
        assert_eq!(meta.name, "old-skill");
        assert!(meta.keywords.is_empty());
        assert!(meta.task_strategies.is_empty());
    }

    #[test]
    fn test_parse_frontmatter_invalid() {
        assert!(parse_frontmatter("no frontmatter here").is_none());
        assert!(parse_frontmatter("---\ninvalid: [yaml\n---").is_none());
    }

    #[test]
    fn test_score_whatsapp_task_matches_meta_template() {
        let skills = sample_skills();
        let ctx = TaskContext {
            description_words: ["whatsapp", "template", "appointment", "reminder"]
                .iter().map(|s| s.to_string()).collect(),
            tags: ["whatsapp", "messaging"].iter().map(|s| s.to_string()).collect(),
            strategy: Some("feature".into()),
            stream: Some("roadmap".into()),
        };

        let matches = suggest(&skills, &ctx, 3);
        assert!(!matches.is_empty());
        assert_eq!(matches[0].name, "meta-template");
        // With 2/7 keywords matching + tags + strategy + stream = ~0.5
        // This is above the 0.3 suggest threshold per ADR-025
        assert!(matches[0].score > 0.3, "score should be > 0.3 (suggest), got {}", matches[0].score);
    }

    #[test]
    fn test_score_financial_task_matches_financial_model() {
        let skills = sample_skills();
        let ctx = TaskContext {
            description_words: ["revenue", "projections", "fundraise", "scenario"]
                .iter().map(|s| s.to_string()).collect(),
            tags: HashSet::new(),
            strategy: Some("spike".into()),
            stream: Some("research".into()),
        };

        let matches = suggest(&skills, &ctx, 3);
        assert!(!matches.is_empty());
        assert_eq!(matches[0].name, "financial-model");
        assert!(matches[0].score > 0.5);
    }

    #[test]
    fn test_score_no_match_returns_empty() {
        let skills = sample_skills();
        let ctx = TaskContext {
            description_words: ["kubernetes", "helm", "deployment"]
                .iter().map(|s| s.to_string()).collect(),
            tags: HashSet::new(),
            strategy: None,
            stream: None,
        };

        let matches = suggest(&skills, &ctx, 3);
        assert!(matches.is_empty() || matches[0].score < 0.3);
    }

    #[test]
    fn test_search_by_keyword() {
        let skills = sample_skills();
        let results = search(&skills, "whatsapp");
        assert!(!results.is_empty());
        assert_eq!(results[0].name, "meta-template");
    }

    #[test]
    fn test_search_multi_term() {
        let skills = sample_skills();
        let results = search(&skills, "revenue projections");
        assert!(!results.is_empty());
        assert_eq!(results[0].name, "financial-model");
    }

    #[test]
    fn test_search_no_results() {
        let skills = sample_skills();
        let results = search(&skills, "kubernetes helm");
        assert!(results.is_empty());
    }

    #[test]
    fn test_build_query_string_full_context() {
        let ctx = TaskContext {
            description_words: ["deploy", "production"].iter().map(|s| s.to_string()).collect(),
            tags: ["infra", "ci"].iter().map(|s| s.to_string()).collect(),
            strategy: Some("feature".into()),
            stream: Some("roadmap".into()),
        };
        let q = build_query_string(&ctx);
        // All parts should be present (order may vary due to HashSet)
        assert!(q.contains("deploy"));
        assert!(q.contains("production"));
        assert!(q.contains("infra"));
        assert!(q.contains("ci"));
        assert!(q.contains("feature"));
        assert!(q.contains("roadmap"));
    }

    #[test]
    fn test_build_query_string_minimal_context() {
        let ctx = TaskContext {
            description_words: ["test"].iter().map(|s| s.to_string()).collect(),
            tags: HashSet::new(),
            strategy: None,
            stream: None,
        };
        let q = build_query_string(&ctx);
        assert_eq!(q, "test");
    }

    #[test]
    fn test_build_query_string_empty_context() {
        let ctx = TaskContext {
            description_words: HashSet::new(),
            tags: HashSet::new(),
            strategy: None,
            stream: None,
        };
        let q = build_query_string(&ctx);
        assert_eq!(q, "");
    }

    #[test]
    fn test_parse_ruflo_results_valid() {
        let json = r#"[
            {"key": "skill:build", "value": "Build anything", "score": 0.92},
            {"key": "skill:research", "value": "Research topics", "score": 0.78},
            {"key": "not-a-skill", "value": "ignored", "score": 0.5}
        ]"#;
        let results = parse_ruflo_results(json).expect("should parse");
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].name, "build");
        assert!((results[0].score - 0.92).abs() < f64::EPSILON);
        assert_eq!(results[0].reason, "ruflo semantic");
        assert_eq!(results[1].name, "research");
    }

    #[test]
    fn test_parse_ruflo_results_no_skills() {
        let json = r#"[{"key": "pattern:something", "value": "not a skill", "score": 0.9}]"#;
        let result = parse_ruflo_results(json);
        assert!(result.is_none());
    }

    #[test]
    fn test_parse_ruflo_results_empty_array() {
        let result = parse_ruflo_results("[]");
        assert!(result.is_none());
    }

    #[test]
    fn test_parse_ruflo_results_invalid_json() {
        let result = parse_ruflo_results("not json at all");
        assert!(result.is_none());
    }

    #[test]
    fn test_parse_ruflo_results_missing_score() {
        let json = r#"[{"key": "skill:close", "value": "End session"}]"#;
        let results = parse_ruflo_results(json).expect("should parse");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].name, "close");
        assert!((results[0].score - 0.0).abs() < f64::EPSILON);
    }

    // ── reindex --force flag tests ────────────────────────────────────

    /// Helper: simulate the mtime-check bypass logic from cmd_reindex.
    /// Returns (mtime_deleted, changed_flag_passed_to_script).
    fn reindex_mtime_logic(changed: bool, force: bool) -> (bool, bool) {
        // Delete mtime when: not --changed OR --force
        let mtime_deleted = !changed || force;
        // Pass --changed to script only when: --changed AND NOT --force
        let changed_flag_to_script = changed && !force;
        (mtime_deleted, changed_flag_to_script)
    }

    #[test]
    fn test_reindex_default_clears_mtime_and_runs_full() {
        let (mtime_deleted, changed_to_script) = reindex_mtime_logic(false, false);
        assert!(mtime_deleted, "default reindex must clear mtime marker");
        assert!(!changed_to_script, "default reindex must not pass --changed to script");
    }

    #[test]
    fn test_reindex_changed_only_preserves_mtime() {
        let (mtime_deleted, changed_to_script) = reindex_mtime_logic(true, false);
        assert!(!mtime_deleted, "--changed should NOT clear mtime marker");
        assert!(changed_to_script, "--changed must pass --changed flag to script");
    }

    #[test]
    fn test_reindex_force_clears_mtime_and_runs_full() {
        let (mtime_deleted, changed_to_script) = reindex_mtime_logic(false, true);
        assert!(mtime_deleted, "--force must clear mtime marker");
        assert!(!changed_to_script, "--force without --changed must not pass --changed to script");
    }

    #[test]
    fn test_reindex_force_plus_changed_still_clears_mtime_and_runs_full() {
        // --force wins over --changed: mtime deleted, script runs without --changed
        let (mtime_deleted, changed_to_script) = reindex_mtime_logic(true, true);
        assert!(mtime_deleted, "--force must clear mtime marker even when --changed is also set");
        assert!(!changed_to_script, "--force overrides --changed; script runs full reindex");
    }

    #[test]
    fn test_reindex_strategy_summary() {
        // Exhaustive truth table for the 4 combinations
        let cases = [
            // (changed, force, expect_mtime_deleted, expect_changed_to_script)
            (false, false, true,  false), // default: full reindex
            (true,  false, false, true),  // incremental: mtime preserved, --changed passed
            (false, true,  true,  false), // force alone: mtime cleared, full reindex
            (true,  true,  true,  false), // force+changed: force wins, full reindex
        ];
        for (changed, force, want_del, want_changed) in cases {
            let (got_del, got_changed) = reindex_mtime_logic(changed, force);
            assert_eq!(
                got_del, want_del,
                "mtime_deleted mismatch for changed={changed} force={force}"
            );
            assert_eq!(
                got_changed, want_changed,
                "changed_to_script mismatch for changed={changed} force={force}"
            );
        }
    }

    #[test]
    fn test_strategy_and_stream_boost_score() {
        let skills = sample_skills();

        // Without strategy/stream
        let ctx_bare = TaskContext {
            description_words: ["whatsapp"].iter().map(|s| s.to_string()).collect(),
            tags: HashSet::new(),
            strategy: None,
            stream: None,
        };
        let bare_matches = suggest(&skills, &ctx_bare, 3);

        // With strategy/stream
        let ctx_full = TaskContext {
            description_words: ["whatsapp"].iter().map(|s| s.to_string()).collect(),
            tags: HashSet::new(),
            strategy: Some("feature".into()),
            stream: Some("roadmap".into()),
        };
        let full_matches = suggest(&skills, &ctx_full, 3);

        // The full context should score higher
        let bare_score = bare_matches.iter().find(|m| m.name == "meta-template").map(|m| m.score).unwrap_or(0.0);
        let full_score = full_matches.iter().find(|m| m.name == "meta-template").map(|m| m.score).unwrap_or(0.0);
        assert!(full_score > bare_score, "full={full_score} should be > bare={bare_score}");
    }
}
