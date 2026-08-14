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

/// t-2812 (ADR-079 §1): what an approve did — consumed by the CLI/MCP verbs
/// for their result payload.
#[derive(Debug, PartialEq, Eq)]
pub struct AcApprove {
    /// Criteria newly moved from `proposed_acceptance_criteria` into
    /// `acceptance_criteria` (post-dedup — items already present don't count).
    pub promoted: usize,
    /// The task was already `approved` before this call (idempotent re-approve).
    pub already_approved: bool,
}

/// t-2812: read a criteria field into owned strings. Array-of-strings is the
/// canonical shape; a bare non-empty string (legacy pre-ADR-047 data, still on
/// disk — see `test_normalize_array_fields_does_not_split_acceptance_criteria`)
/// coerces to a single-element vec, whole-string, never comma-split. Null /
/// absent / empty-string are empty. A non-string array element is an error:
/// silently dropping it would approve a different contract than the one stored.
fn criteria_vec(v: &Value, field: &str) -> Result<Vec<String>, String> {
    match v {
        Value::Null => Ok(vec![]),
        Value::String(s) if s.trim().is_empty() => Ok(vec![]),
        Value::String(s) => Ok(vec![s.clone()]),
        Value::Array(arr) => arr
            .iter()
            .map(|e| {
                e.as_str().map(str::to_string).ok_or_else(|| {
                    format!("{field} contains a non-string element ({e}) — fix the task data before approving")
                })
            })
            .collect(),
        other => Err(format!("{field} must be an array of strings (got: {other})")),
    }
}

/// t-2812 (ADR-079 §1): the sanctioned transition to `ac_state:approved` —
/// approve = promote + flip, atomically. Completes the promotion path t-2288's
/// proposer (`apply_ac_proposals` above) was built against:
///
/// 1. **Promote:** dedup-union `proposed_acceptance_criteria` into
///    `acceptance_criteria` (existing order first — a human-authored contract is
///    never destroyed by a loop proposal), then remove the proposed key.
/// 2. **Flip:** `ac_state = "approved"`.
///
/// Precondition: at least one of the two fields non-empty — approving nothing
/// is an error, not a silent flip. Accepts from `none`, `proposed`, or a
/// key-absent legacy task (opt-in, same precedent as set_field's ac_state arm);
/// idempotent on `approved`. Errors leave the task untouched: all fallible
/// reads happen before the first write.
///
/// Writes the fields directly rather than via `set_field` — deliberately, twice
/// over: set_field rejects `ac_state:approved` (this verb IS the sanctioned
/// path), and set_field's acceptance_criteria arm resets approved→proposed
/// (promotion must not immediately un-approve itself).
pub fn approve_ac(task: &mut Value) -> Result<AcApprove, String> {
    let state = match task.get("ac_state") {
        None | Some(Value::Null) => "none",
        Some(Value::String(s)) => s.as_str(),
        Some(other) => return Err(format!("ac_state is not a string: {other}")),
    };
    let already_approved = match state {
        "none" | "proposed" | "approved" | "" => state == "approved",
        other => return Err(format!("invalid ac_state {other:?} on task — fix before approving")),
    };

    let existing = criteria_vec(&task["acceptance_criteria"], "acceptance_criteria")?;
    let proposed = criteria_vec(&task[PROPOSED_AC_FIELD], PROPOSED_AC_FIELD)?;
    if existing.is_empty() && proposed.is_empty() {
        return Err(
            "no acceptance criteria to approve — populate acceptance_criteria \
             or proposed_acceptance_criteria first"
                .into(),
        );
    }

    let mut merged = existing;
    let mut promoted = 0;
    for p in proposed {
        if !merged.contains(&p) {
            merged.push(p);
            promoted += 1;
        }
    }

    task["acceptance_criteria"] =
        Value::Array(merged.into_iter().map(Value::String).collect());
    if let Some(obj) = task.as_object_mut() {
        obj.remove(PROPOSED_AC_FIELD);
    }
    task["ac_state"] = Value::String("approved".into());

    Ok(AcApprove { promoted, already_approved })
}

/// t-2812: file-level approve — lock, load, find, approve, save. Mirrors
/// `perform_ac_propose`'s sealed read-modify-write over a raw `Value`.
pub fn perform_ac_approve(path: &Path, task_id: &str) -> Result<AcApprove, String> {
    let _lock = lock_tasks(path)?;
    let mut val = load_raw(path)?;
    let tasks = val["tasks"].as_array_mut().ok_or("tasks is not an array")?;
    let task = tasks
        .iter_mut()
        .find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| format!("task {task_id} not found"))?;

    let outcome = approve_ac(task)?;

    val["last_modified"] = Value::String(chrono::Local::now().to_rfc3339());
    save_tasks(path, &val).map_err(|e| format!("ac approve write failed: {e}"))?;
    Ok(outcome)
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
                    // t-2841: rollup is a status writer too — ack it the same
                    // way set_field does, or a leased parent completed via
                    // rollup strands its lease forever.
                    super::ack_status_write(t, "completed");
                }
            }
        }
    }
    val["last_modified"] = Value::String(now);

    save_tasks(path, &val).map_err(|e| format!("rollup write failed: {e}"))?;

    Ok(candidates)
}
