//! Scheduler analysis: health checks, collision detection, drift comparison.
//!
//! Pure functions on scheduler config/status data. No subprocess calls —
//! those stay in brana-cli.

use serde_json::{Map, Value};
use std::collections::{BTreeSet, HashMap};

/// Detect schedule collisions: multiple enabled jobs with the same schedule on the same project.
pub fn find_collisions(jobs: &Map<String, Value>) -> Vec<Collision> {
    let mut groups: HashMap<(String, String), Vec<String>> = HashMap::new();
    for (name, cfg) in jobs {
        if !cfg["enabled"].as_bool().unwrap_or(true) {
            continue;
        }
        let schedule = cfg["schedule"].as_str().unwrap_or("").to_string();
        let project = std::path::Path::new(cfg["project"].as_str().unwrap_or(""))
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        groups.entry((schedule, project)).or_default().push(name.clone());
    }
    groups
        .into_iter()
        .filter(|(_, v)| v.len() > 1)
        .map(|((schedule, project), jobs)| Collision { schedule, project, jobs })
        .collect()
}

/// A collision: multiple jobs sharing the same schedule and project.
#[derive(Debug, Clone)]
pub struct Collision {
    pub schedule: String,
    pub project: String,
    pub jobs: Vec<String>,
}

/// Health report for the scheduler.
#[derive(Debug, Clone)]
pub struct HealthReport {
    pub failures: Vec<String>,
    pub skipped: Vec<String>,
    pub collisions: Vec<Collision>,
    pub enabled_count: usize,
    pub disabled_count: usize,
    pub total_count: usize,
}

/// Compute scheduler health from config and last-run status.
pub fn check_health(
    jobs: &Map<String, Value>,
    status: &HashMap<String, Value>,
) -> HealthReport {
    let mut failures = vec![];
    let mut skipped = vec![];

    for (name, info) in status {
        match info["status"].as_str() {
            Some("FAILED") => failures.push(name.clone()),
            Some("SKIPPED") => skipped.push(name.clone()),
            _ => {}
        }
    }

    let collisions = find_collisions(jobs);
    let enabled = jobs.values().filter(|v| v["enabled"].as_bool().unwrap_or(true)).count();

    HealthReport {
        failures,
        skipped,
        collisions,
        enabled_count: enabled,
        disabled_count: jobs.len() - enabled,
        total_count: jobs.len(),
    }
}

/// A single drift item between template and live config.
#[derive(Debug, Clone)]
pub struct DriftItem {
    pub kind: DriftKind,
    pub job_name: String,
    pub field: Option<String>,
    pub template_value: Option<String>,
    pub live_value: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DriftKind {
    /// Job exists in live but not in template.
    Added,
    /// Job exists in template but not in live.
    Removed,
    /// A field differs between template and live.
    Changed,
}

/// Compare template vs live scheduler config to detect drift.
pub fn detect_drift(
    template_jobs: &Map<String, Value>,
    live_jobs: &Map<String, Value>,
) -> Vec<DriftItem> {
    let all_names: BTreeSet<&String> = template_jobs.keys().chain(live_jobs.keys()).collect();
    let mut drifts = vec![];

    for name in all_names {
        if !template_jobs.contains_key(name) {
            drifts.push(DriftItem {
                kind: DriftKind::Added,
                job_name: name.clone(),
                field: None,
                template_value: None,
                live_value: None,
            });
        } else if !live_jobs.contains_key(name) {
            drifts.push(DriftItem {
                kind: DriftKind::Removed,
                job_name: name.clone(),
                field: None,
                template_value: None,
                live_value: None,
            });
        } else {
            for field in &["schedule", "enabled", "command", "project", "type"] {
                let tv = &template_jobs[name][*field];
                let lv = &live_jobs[name][*field];
                if tv != lv {
                    drifts.push(DriftItem {
                        kind: DriftKind::Changed,
                        job_name: name.clone(),
                        field: Some(field.to_string()),
                        template_value: Some(tv.to_string()),
                        live_value: Some(lv.to_string()),
                    });
                }
            }
        }
    }

    drifts
}

/// Validate a job name (alphanumeric, hyphens, underscores only).
pub fn validate_job_name(name: &str) -> Result<(), String> {
    if name.chars().all(|c| c.is_alphanumeric() || c == '-' || c == '_') {
        Ok(())
    } else {
        Err(format!("invalid job name '{name}': use alphanumeric, hyphens, underscores"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn make_jobs(items: &[(&str, &str, &str, bool)]) -> Map<String, Value> {
        let mut map = Map::new();
        for (name, schedule, project, enabled) in items {
            map.insert(name.to_string(), json!({
                "schedule": schedule,
                "project": project,
                "enabled": enabled,
            }));
        }
        map
    }

    #[test]
    fn test_no_collisions() {
        let jobs = make_jobs(&[
            ("job-a", "*/5 * * * *", "/home/user/proj-a", true),
            ("job-b", "*/10 * * * *", "/home/user/proj-a", true),
        ]);
        assert!(find_collisions(&jobs).is_empty());
    }

    #[test]
    fn test_collision_same_schedule_same_project() {
        let jobs = make_jobs(&[
            ("job-a", "*/5 * * * *", "/home/user/proj-a", true),
            ("job-b", "*/5 * * * *", "/home/user/proj-a", true),
        ]);
        let c = find_collisions(&jobs);
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].jobs.len(), 2);
    }

    #[test]
    fn test_collision_ignores_disabled() {
        let jobs = make_jobs(&[
            ("job-a", "*/5 * * * *", "/home/user/proj-a", true),
            ("job-b", "*/5 * * * *", "/home/user/proj-a", false),
        ]);
        assert!(find_collisions(&jobs).is_empty());
    }

    #[test]
    fn test_health_report() {
        let jobs = make_jobs(&[
            ("job-a", "*/5 * * * *", "/proj", true),
            ("job-b", "*/10 * * * *", "/proj", false),
        ]);
        let mut status = HashMap::new();
        status.insert("job-a".into(), json!({"status": "FAILED"}));

        let report = check_health(&jobs, &status);
        assert_eq!(report.failures, vec!["job-a"]);
        assert!(report.skipped.is_empty());
        assert_eq!(report.enabled_count, 1);
        assert_eq!(report.disabled_count, 1);
    }

    #[test]
    fn test_drift_added_removed_changed() {
        let template = make_jobs(&[
            ("existing", "*/5 * * * *", "/proj", true),
            ("removed", "*/10 * * * *", "/proj", true),
        ]);
        let mut live = make_jobs(&[
            ("existing", "*/15 * * * *", "/proj", true), // changed schedule
            ("added", "*/20 * * * *", "/proj", true),
        ]);
        // Ensure same fields exist
        for (_, v) in live.iter_mut() {
            if v.get("command").is_none() {
                v.as_object_mut().unwrap().insert("command".into(), Value::Null);
                v.as_object_mut().unwrap().insert("type".into(), Value::Null);
            }
        }
        for (_, v) in template.iter() {
            if v.get("command").is_none() {
                // template needs same fields
            }
        }

        let drifts = detect_drift(&template, &live);
        assert!(drifts.iter().any(|d| d.kind == DriftKind::Added && d.job_name == "added"));
        assert!(drifts.iter().any(|d| d.kind == DriftKind::Removed && d.job_name == "removed"));
        assert!(drifts.iter().any(|d| d.kind == DriftKind::Changed && d.job_name == "existing" && d.field.as_deref() == Some("schedule")));
    }

    #[test]
    fn test_validate_job_name() {
        assert!(validate_job_name("my-job_01").is_ok());
        assert!(validate_job_name("bad name!").is_err());
        assert!(validate_job_name("").is_ok()); // empty is technically all-valid chars
    }
}
