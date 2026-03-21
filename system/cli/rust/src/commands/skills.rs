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

/// Score a skill against task context per ADR-025.
///
/// score = (keyword_overlap × 0.4) + (tag_overlap × 0.3)
///       + (strategy_match × 0.2) + (stream_match × 0.1)
pub fn score_skill(skill: &SkillMeta, ctx: &TaskContext) -> (f64, String) {
    let mut reasons = Vec::new();

    // Keyword overlap: task description words ∩ skill keywords
    let skill_kw: HashSet<&str> = skill.keywords.iter().map(|s| s.as_str()).collect();
    let kw_overlap = if skill_kw.is_empty() {
        0.0
    } else {
        let matches: Vec<&str> = ctx
            .description_words
            .iter()
            .filter(|w| skill_kw.contains(w.as_str()))
            .map(|s| s.as_str())
            .collect();
        if !matches.is_empty() {
            reasons.push(format!("keywords: {}", matches.join(", ")));
        }
        matches.len() as f64 / skill_kw.len() as f64
    };

    // Tag overlap: task tags ∩ skill keywords
    let tag_overlap = if skill_kw.is_empty() {
        0.0
    } else {
        let matches: Vec<&str> = ctx
            .tags
            .iter()
            .filter(|t| skill_kw.contains(t.as_str()))
            .map(|s| s.as_str())
            .collect();
        if !matches.is_empty() {
            reasons.push(format!("tags: {}", matches.join(", ")));
        }
        matches.len() as f64 / skill_kw.len() as f64
    };

    // Strategy match
    let strategy_match = match &ctx.strategy {
        Some(s) if skill.task_strategies.iter().any(|ts| ts == s) => {
            reasons.push(format!("strategy: {s}"));
            1.0
        }
        _ => 0.0,
    };

    // Stream match
    let stream_match = match &ctx.stream {
        Some(s) if skill.stream_affinity.iter().any(|sa| sa == s) => {
            reasons.push(format!("stream: {s}"));
            1.0
        }
        _ => 0.0,
    };

    let score = (kw_overlap * 0.4) + (tag_overlap * 0.3) + (strategy_match * 0.2) + (stream_match * 0.1);
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

/// `brana skills suggest --task <id>` or `--query <text>`
pub fn cmd_suggest(task_id: Option<&str>, query: Option<&str>) {
    let skills = scan_skills(&skill_dirs());

    let ctx = if let Some(tid) = task_id {
        // Read task metadata via backlog get
        match build_context_from_task(tid) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("Error reading task {tid}: {e}");
                std::process::exit(1);
            }
        }
    } else if let Some(q) = query {
        TaskContext {
            description_words: q.split_whitespace().map(|w| w.to_lowercase()).collect(),
            tags: HashSet::new(),
            strategy: None,
            stream: None,
        }
    } else {
        eprintln!("Provide --task <id> or --query <text>");
        std::process::exit(1);
    };

    let matches = suggest(&skills, &ctx, 3);
    let json = serde_json::to_string_pretty(&matches).unwrap_or_default();
    println!("{json}");
}

/// `brana skills search <query>`
pub fn cmd_search(query: &str) {
    let skills = scan_skills(&skill_dirs());
    let results = search(&skills, query);
    let json = serde_json::to_string_pretty(&results).unwrap_or_default();
    println!("{json}");
}

/// `brana skills list`
pub fn cmd_list() {
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
