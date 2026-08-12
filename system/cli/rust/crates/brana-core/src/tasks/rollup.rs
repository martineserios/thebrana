use super::*;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::path::Path;


/// t-2283: ac-propose drain candidates — the queue the ac-propose loop drains.
/// Candidates = tasks with `ac_state == "none"` MINUS work_type in {research, review}
/// (research/audit tasks yield only thin disjunctive ACs — route L2-only, per the
/// Step-1 dry run 2026-07-21). Legacy tasks (`ac_state` key absent) are never
/// candidates: only key-present, `none`-valued tasks are under v3 AC management.
pub fn ac_propose_candidates(tasks: &[Value]) -> Vec<&Value> {
    // AC#7 phrases the exclusion as "research/audit". There is no `audit`
    // work_type in the canonical enum (see `validate_work_type`) — "audit" maps
    // to `review` by convention, so the exclusion set is {research, review}.
    tasks
        .iter()
        .filter(|t| t["ac_state"].as_str() == Some(AC_STATE_DEFAULT))
        .filter(|t| !matches!(t["work_type"].as_str(), Some("research") | Some("review")))
        .collect()
}

/// t-2288: the inert field the ac-propose loop writes a candidate criterion into.
/// Deliberately SEPARATE from `acceptance_criteria` (the live gating field) so a
/// proposed AC gates nothing until a human promotes it — promotion moves this
/// array into `acceptance_criteria` and flips `ac_state` to `approved`. Array form
/// mirrors `acceptance_criteria` so promotion is a lossless move.
pub const PROPOSED_AC_FIELD: &str = "proposed_acceptance_criteria";

/// t-2288: apply ac-propose proposals in memory. For each `(id, criteria)` whose
/// task is a CURRENT drain candidate (`ac_propose_candidates`), set
/// `ac_state = "proposed"` + `proposed_acceptance_criteria = criteria` and mutate
/// **nothing else**. Returns the ids actually applied.
///
/// Forward-only safety (AC#3 scoped mutation, AC#5 legacy untouched): the candidate
/// set is recomputed from the live `tasks` slice — never trusted from the caller —
/// so a proposal targeting a non-candidate is a silent no-op. Legacy tasks
/// (`ac_state` key absent), already-`proposed`/`approved` tasks, and research/review
/// work_types are never mutated. Proposed ACs are inert (AC#4): this writes only
/// the holding field, never `acceptance_criteria`.
pub fn apply_ac_proposals(
    tasks: &mut [Value],
    proposals: &HashMap<String, Vec<String>>,
) -> Vec<String> {
    // Immutable borrow first (compute the candidate id-set), then mutate — the two
    // borrows cannot overlap, so materialize owned ids before iterating mutably.
    let candidates: HashSet<String> = ac_propose_candidates(tasks)
        .iter()
        .filter_map(|t| t["id"].as_str().map(str::to_string))
        .collect();

    let mut applied = Vec::new();
    for t in tasks.iter_mut() {
        let id = match t["id"].as_str() {
            Some(id) => id.to_string(),
            None => continue,
        };
        // Non-candidate → never touched (legacy key-absent / proposed / approved /
        // research / review). This is the forward-only guard.
        if !candidates.contains(&id) {
            continue;
        }
        if let Some(criteria) = proposals.get(&id) {
            t["ac_state"] = Value::String("proposed".into());
            t[PROPOSED_AC_FIELD] =
                Value::Array(criteria.iter().map(|c| Value::String(c.clone())).collect());
            applied.push(id);
        }
    }
    applied
}

/// t-2288: file-level ac-propose apply — lock, load, apply proposals, save.
/// Mirrors `perform_rollup`'s read-modify-write over a raw `Value` (unknown fields
/// round-trip, so the write is sealed). `dry_run` computes the applied set without
/// writing. Returns the ids applied (or that would be applied under `dry_run`).
pub fn perform_ac_propose(
    path: &Path,
    proposals: &HashMap<String, Vec<String>>,
    dry_run: bool,
) -> Result<Vec<String>, String> {
    let _lock = lock_tasks(path)?;
    let mut val = load_raw(path)?;
    let tasks = val["tasks"].as_array_mut().ok_or("tasks is not an array")?;
    let applied = apply_ac_proposals(tasks, proposals);

    if applied.is_empty() || dry_run {
        return Ok(applied);
    }

    val["last_modified"] = Value::String(chrono::Local::now().to_rfc3339());
    save_tasks(path, &val).map_err(|e| format!("ac-propose write failed: {e}"))?;
    Ok(applied)
}

/// Find parent IDs that should be auto-completed (all children done).
pub fn find_rollup_candidates(tasks: &[Value]) -> Vec<String> {
    let mut candidates = Vec::new();
    for parent in tasks
        .iter()
        .filter(|t| matches!(t["type"].as_str(), Some("milestone" | "phase")))
    {
        let pid = match parent["id"].as_str() {
            Some(id) => id,
            None => continue,
        };
        if parent["status"].as_str() == Some("completed") {
            continue;
        }

        let children: Vec<_> = tasks
            .iter()
            .filter(|t| t["parent"].as_str() == Some(pid))
            .collect();

        if !children.is_empty()
            && children
                .iter()
                .all(|c| c["status"].as_str() == Some("completed"))
        {
            candidates.push(pid.to_string());
        }
    }
    candidates
}

/// Perform rollup: mark parents as completed, write back to file.
/// Returns list of completed parent IDs.
pub fn perform_rollup(path: &Path, dry_run: bool) -> Result<Vec<String>, String> {
    // Serialize the rollup's read-modify-write against concurrent writers
    // (t-2166). Sole caller is cmd_rollup, which holds no lock — no nesting.
    let _lock = lock_tasks(path)?;
    let content =
        std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut val: Value =
        serde_json::from_str(content.trim()).map_err(|e| format!("invalid JSON: {e}"))?;

    let tasks = val["tasks"]
        .as_array()
        .ok_or("tasks is not an array")?;
    let candidates = find_rollup_candidates(tasks);

    if candidates.is_empty() || dry_run {
        return Ok(candidates);
    }

    let today = chrono::Local::now().format("%Y-%m-%d").to_string();
    let now = chrono::Local::now().to_rfc3339();

    if let Some(tasks) = val["tasks"].as_array_mut() {
        for t in tasks.iter_mut() {
            if let Some(id) = t["id"].as_str() {
                if candidates.contains(&id.to_string()) {
                    t["status"] = Value::String("completed".into());
                    t["completed"] = Value::String(today.clone());
                }
            }
        }
    }
    val["last_modified"] = Value::String(now);

    save_tasks(path, &val).map_err(|e| format!("rollup write failed: {e}"))?;

    Ok(candidates)
}
