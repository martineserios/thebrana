use serde_json::Value;
use std::collections::HashSet;
use std::path::Path;


/// Find duplicate task IDs.
pub fn find_duplicate_ids(tasks: &[Value]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut dupes = Vec::new();
    for t in tasks {
        if let Some(id) = t["id"].as_str() {
            if !seen.insert(id) {
                dupes.push(id.to_string());
            }
        }
    }
    dupes
}

/// Validate tasks.json schema. Returns list of error strings.
pub fn validate_schema(path: &Path) -> Vec<String> {
    let content = match std::fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) => return vec![format!("cannot read file: {e}")],
    };
    let content = content.trim();
    if content.is_empty() {
        return vec!["file is empty".into()];
    }

    let val: Value = match serde_json::from_str(content) {
        Ok(v) => v,
        Err(_) => return vec!["invalid JSON".into()],
    };

    let mut errors = Vec::new();

    if val["version"].is_null() {
        errors.push("missing version".into());
    }
    if val["project"].is_null() {
        errors.push("missing project".into());
    }
    if !val["tasks"].is_array() {
        errors.push("tasks must be array".into());
        return errors;
    }

    let valid_statuses = ["pending", "in_progress", "completed", "cancelled"];
    // t-2322 (ADR-065): "epic" (hierarchy node markers, t-2312) and
    // "initiative" (13 stray pre-migration survivors) are valid task types
    // this standalone validator predates.
    let valid_types = ["phase", "milestone", "task", "subtask", "epic", "initiative"];

    if let Some(tasks) = val["tasks"].as_array() {
        for t in tasks {
            let id = t["id"].as_str().unwrap_or("?");
            if t["id"].is_null() {
                errors.push("task missing id".into());
            }
            if t["subject"].is_null() {
                errors.push(format!("task {id} missing subject"));
            }
            if t["status"].is_null() {
                errors.push(format!("task {id} missing status"));
            } else if let Some(s) = t["status"].as_str() {
                // t-2379 (ADR-065): an epic node's status validates against
                // a different vocabulary than an ordinary task's, mirroring
                // set_field()'s status branch (t-2313).
                let is_valid = if t["type"].as_str() == Some("epic") {
                    validate_epic_status(s).is_ok()
                } else {
                    valid_statuses.contains(&s)
                };
                if !is_valid {
                    errors.push(format!("task {id}: invalid status {s}"));
                }
            }
            if t["type"].is_null() {
                errors.push(format!("task {id} missing type"));
            } else if let Some(tp) = t["type"].as_str() {
                if !valid_types.contains(&tp) {
                    errors.push(format!("task {id}: invalid type {tp}"));
                }
            }
            if !t["tags"].is_null() {
                if !t["tags"].is_array() {
                    errors.push(format!("task {id}: tags must be array"));
                } else if let Some(tags) = t["tags"].as_array() {
                    if tags.iter().any(|v| !v.is_string()) {
                        errors.push(format!("task {id}: tags items must be strings"));
                    }
                }
            }
            if !t["context"].is_null() && !t["context"].is_string() {
                errors.push(format!("task {id}: context must be string"));
            }
            if !t["isc"].is_null() {
                if !t["isc"].is_array() {
                    errors.push(format!("task {id}: isc must be array"));
                } else if let Some(items) = t["isc"].as_array() {
                    if items.iter().any(|v| !v.is_string()) {
                        errors.push(format!("task {id}: isc items must be strings"));
                    }
                }
            }
            // t-2742: validate_schema() predates validate_work_type/validate_kind
            // (t-1960/t-2739's single-field write-path validators) and never
            // picked them up — whole-file validation missed drift they'd catch
            // on `set`. Reuse the same validators so the two paths can't diverge.
            if let Some(wt) = t["work_type"].as_str() {
                if let Err(e) = validate_work_type(wt) {
                    errors.push(format!("task {id}: {e}"));
                }
            }
            if let Some(k) = t["kind"].as_str() {
                if let Err(e) = validate_kind(k) {
                    errors.push(format!("task {id}: {e}"));
                }
            }
        }
    }

    errors
}

/// Validate a priority value. Accepts P0/P1/P2/P3 plus "null"/"" (clear). Rejects legacy
/// high/medium/low and any other string. Canonical enum is P[0-3] only — see t-1344.
pub fn validate_priority(value: &str) -> Result<(), String> {
    match value {
        "P0" | "P1" | "P2" | "P3" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid priority {other:?} — must be P0/P1/P2/P3 or null"
        )),
    }
}

/// Validate a status value. Accepts pending/in_progress/completed/cancelled plus "null"/""
/// (clear). Rejects synthetic display values like "done", "active", "blocked", "parked" — those
/// belong only in classify() output. See t-1345.
pub fn validate_status(value: &str) -> Result<(), String> {
    match value {
        "pending" | "in_progress" | "completed" | "cancelled" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid status {other:?} — must be pending/in_progress/completed/cancelled or null"
        )),
    }
}

/// Validate an epic node's `status` value (ADR-065). A DIFFERENT vocabulary
/// from `validate_status()`'s task lifecycle: active/next/parked/done/archived,
/// plus "null"/"" (clear). Only reached when the task being validated is
/// `type: "epic"` — see set_field's status branch and cmd_add; a non-epic
/// task's `status` field still validates against `validate_status()`. t-2313.
pub fn validate_epic_status(value: &str) -> Result<(), String> {
    match value {
        "active" | "next" | "parked" | "done" | "archived" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid epic status {other:?} — must be active/next/parked/done/archived or null"
        )),
    }
}

/// Validate a wave's `status` value (ADR-065 process-overlay slice, t-2315).
/// A wave's own vocabulary — distinct from both `validate_status()` (task)
/// and `validate_epic_status()` (epic node). The documented lifecycle is
/// queued → draining → shipped (backlog-v3-schema.md "Wave = Queue"), but
/// this validator does NOT enforce that ordering: no lifecycle-status
/// validator in this codebase enforces forward-only transitions (both
/// validate_status/validate_epic_status are pure membership checks), and the
/// drain/query logic that would give "ordering" real meaning is explicitly
/// out of scope for this slice.
pub fn validate_wave_status(value: &str) -> Result<(), String> {
    match value {
        "queued" | "draining" | "shipped" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid wave status {other:?} — must be queued/draining/shipped or null"
        )),
    }
}

pub fn validate_work_type(value: &str) -> Result<(), String> {
    match value {
        "implement" | "research" | "design" | "infra" | "chore" | "review" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid work_type {other:?} — must be implement/research/design/infra/chore/review or null"
        )),
    }
}

/// Validate a kind value (t-1960). Canonical list matches the CLI TaskKind enum;
/// used by every write path (CLI add/set, MCP add/set/batch) so they cannot drift.
pub fn validate_kind(value: &str) -> Result<(), String> {
    match value {
        "feature" | "fix" | "refactor" | "research" | "docs" | "design" | "ops" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid kind {other:?} — must be feature/fix/refactor/research/docs/design/ops or null"
        )),
    }
}

/// Validate a task node `type` value (t-2739). Canonical hierarchy vocabulary:
/// initiative/phase/milestone/task/subtask (task-convention.md) plus epic
/// nodes (ADR-065). Shared by every write path (CLI cmd_add, MCP backlog_add,
/// set_field) so they cannot drift — live data accumulated kind/work_type
/// values mistyped into `type` (feature/research/chore/ops) before this
/// validator existed.
pub fn validate_task_type(value: &str) -> Result<(), String> {
    match value {
        "task" | "subtask" | "phase" | "milestone" | "epic" | "initiative" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid type {other:?} — must be task/subtask/phase/milestone/epic/initiative or null"
        )),
    }
}

/// Validate an execution value (t-1982). Accepted: code, autonomous, null, "".
/// Shared by CLI set, MCP backlog_set, and MCP backlog_add so they cannot drift.
pub fn validate_execution(value: &str) -> Result<(), String> {
    match value {
        "code" | "autonomous" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid execution {other:?} — must be code/autonomous or null"
        )),
    }
}

/// t-2283: the value a new task's `ac_state` is stamped with. Shared by every
/// write path (CLI `cmd_add`, MCP `backlog_add`) so the stamp cannot drift.
pub const AC_STATE_DEFAULT: &str = "none";

/// Validate an ac_state value (t-2283, v3 forward-only slice). Accepts
/// none/proposed/approved plus "null"/"" (clear the key). Shared by every write
/// path so CLI and MCP cannot drift. Key *presence* marks a task as v3-managed;
/// this validator governs only the value once the key is being written.
pub fn validate_ac_state(value: &str) -> Result<(), String> {
    match value {
        "none" | "proposed" | "approved" | "null" | "" => Ok(()),
        other => Err(format!(
            "invalid ac_state {other:?} — must be none/proposed/approved or null"
        )),
    }
}

/// Rename the `initiative` key to `epic` on a single task object (t-1614 schema migration).
/// Preserves `level: "initiative"` and `type: "initiative"` values — only the KEY is renamed.
pub fn migrate_initiative_to_epic(mut task: Value) -> Value {
    if let Some(obj) = task.as_object_mut() {
        if let Some(val) = obj.remove("initiative") {
            obj.insert("epic".to_string(), val);
        }
    }
    task
}

/// Validate that tasks with effort M/L/XL have a non-empty context. See t-939 and tasks.spec.md.
pub fn validate_context_for_effort(effort: Option<&str>, context: Option<&str>) -> Result<(), String> {
    match effort {
        Some("M") | Some("L") | Some("XL") => {
            let has_context = context.map(|c| !c.trim().is_empty()).unwrap_or(false);
            if has_context {
                Ok(())
            } else {
                Err(format!(
                    "effort {:?} requires a non-empty context — add --context or include \"context\" in the JSON payload",
                    effort.unwrap()
                ))
            }
        }
        _ => Ok(()),
    }
}

/// Read the raw `status` field from a task — the canonical accessor used by
/// filter predicates AND aggregations. **Never use `classify()` for filtering**:
/// classify() emits synthetic display values (done/active/blocked/parked) that
/// are not in the raw enum and silently break --status filters. See t-1340/t-1346.
pub fn raw_status<'a>(task: &'a Value, default: &'a str) -> &'a str {
    task["status"].as_str().unwrap_or(default)
}

/// Fields retired from the task schema (ADR-065) that must never be written
/// via a write path that merges a raw JSON object directly onto a task
/// (rather than going through `set_field`'s exhaustive match, which already
/// hard-rejects them-by-omission via its `unknown field` catch-all). Single
/// source of truth: t-2310 hand-patched level/epic, then t-2325 had to
/// hand-patch stream separately with an independent `contains_key` check —
/// this constant plus `reject_retired_fields` (t-2385, ADR-067) generalizes
/// that so a future retirement is a one-line addition here instead of a new
/// call site.
///
/// SCOPE (ADR-067, t-2782): this list and `reject_retired_fields` are
/// **task-object-scoped** — they guard `.tasks[]` writes only. The `wip_limit`
/// entry retires the TASK/EPIC-level field (ADR-065 D4); the WAVE-level
/// `wip_limit` (ADR-079 §3, `set_wave_field`) is deliberate name reuse and
/// must never route through this guard. A future grep-shaped guard extension
/// must keep that scoping.
pub const RETIRED_FIELDS: &[&str] = &["level", "epic", "stream", "wip_limit"];

/// Reject a raw JSON object if it contains any retired field key. Exact key
/// match only — no substring matching, so e.g. `"epics"`/`"streaming"` pass
/// through untouched. Used by write paths that merge arbitrary JSON directly
/// (e.g. `cmd_add`'s `--json` ingestion), where `set_field`'s per-field match
/// doesn't apply. Names every retired field found, not just the first.
pub fn reject_retired_fields(obj: &serde_json::Map<String, Value>) -> Result<(), String> {
    let found: Vec<&str> = RETIRED_FIELDS
        .iter()
        .filter(|f| obj.contains_key(**f))
        .copied()
        .collect();
    if found.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "{} field(s) are retired (ADR-065) — level collapses into type, epic/stream are now hierarchy/tag concerns, wip_limit is retired (D4, 2026-08-12 — epics are unbounded, WIP control moves to waves); use --parent/tags instead",
            found.join(", ")
        ))
    }
}

/// Task fields whose canonical representation is a JSON array.
///
/// `acceptance_criteria` is deliberately absent: its items are prose and
/// legitimately contain commas, so comma-splitting them would corrupt the
/// payload. Only fields listed here are coerced.
pub const ARRAY_FIELDS: &[&str] = &["tags", "blocked_by", "isc"];

/// Coerce legacy comma-string values on [`ARRAY_FIELDS`] into real JSON arrays
/// (E2026-05-22-7).
///
/// Absent keys stay absent and nulls stay null — inventing keys here would
/// resurrect retired-field-style schema drift.
///
/// Shared by `set_field` and `cmd_add`'s `--json` ingestion so both write paths
/// normalize identically. `--json` merges arbitrary JSON straight onto the new
/// task, bypassing `set_field`'s per-field match, which is how comma-strings
/// used to survive to disk (t-2439).
pub fn normalize_array_fields(task: &mut Value) {
    for field in ARRAY_FIELDS {
        if let Some(s) = task.get(*field).and_then(|v| v.as_str()) {
            task[*field] = Value::Array(
                s.split(',')
                    .map(|t| t.trim())
                    .filter(|t| !t.is_empty())
                    .map(|t| Value::String(t.to_string()))
                    .collect(),
            );
        }
    }
}

/// Set a field on a task. Handles scalars, array append (+val)/remove (-val), and --append for text.
pub fn set_field(task: &mut Value, field: &str, value: &str, append: bool) -> Result<(), String> {
    match field {
        "tags" | "blocked_by" | "isc" => {
            // Auto-initialize isc if absent
            if field == "isc" && task[field].is_null() {
                task[field] = Value::Array(vec![]);
            }
            // Coerce legacy comma-string format to array (E2026-05-22-7)
            normalize_array_fields(task);
            let arr = task[field].as_array_mut()
                .ok_or_else(|| format!("{field} is not an array"))?;
            if let Some(stripped) = value.strip_prefix('+') {
                let v = Value::String(stripped.to_string());
                if !arr.contains(&v) { arr.push(v); }
            } else if let Some(stripped) = value.strip_prefix('-') {
                arr.retain(|v| v.as_str() != Some(stripped));
            } else {
                return Err(format!("use +val or -val for array fields (got: {value})"));
            }
            Ok(())
        }
        "acceptance_criteria" => {
            if task[field].is_null() {
                task[field] = Value::Array(vec![]);
            }
            if let Some(stripped) = value.strip_prefix('+') {
                let arr = task[field].as_array_mut()
                    .ok_or_else(|| format!("{field} is not an array"))?;
                let v = Value::String(stripped.to_string());
                if !arr.contains(&v) { arr.push(v); }
            } else if let Some(stripped) = value.strip_prefix('-') {
                let arr = task[field].as_array_mut()
                    .ok_or_else(|| format!("{field} is not an array"))?;
                arr.retain(|v| v.as_str() != Some(stripped));
            } else {
                let parsed: Value = serde_json::from_str(value)
                    .map_err(|_| format!("acceptance_criteria must be a JSON array or use +item/-item (got: {value})"))?;
                if !parsed.is_array() {
                    return Err(format!("acceptance_criteria must be a JSON array or use +item/-item (got: {value})"));
                }
                task[field] = parsed;
            }
            // t-2815 (ADR-079 §1 content-binding): approval binds to content —
            // any successful AC write on an approved task drops it back to
            // proposed, all three sub-paths above. Without this a loop could
            // obtain approval then reshape the contract while staying drainable
            // (the ADR-076-D2 moving-target class). approve_ac writes the field
            // directly, not through here, so promotion never un-approves itself.
            if task["ac_state"].as_str() == Some("approved") {
                task["ac_state"] = Value::String("proposed".into());
            }
            Ok(())
        }
        "context" | "notes" | "description" => {
            if append {
                let existing = task[field].as_str().unwrap_or("").to_string();
                let new_val = if existing.is_empty() {
                    value.to_string()
                } else {
                    format!("{existing}\n{value}")
                };
                task[field] = Value::String(new_val);
            } else {
                task[field] = Value::String(value.to_string());
            }
            Ok(())
        }
        "agent_config" | "agent_result" => {
            if value == "null" {
                task[field] = Value::Null;
            } else {
                let parsed: Value = serde_json::from_str(value)
                    .map_err(|e| format!("{field} must be a JSON object or \"null\": {e}"))?;
                if !parsed.is_object() {
                    return Err(format!("{field} must be a JSON object or \"null\""));
                }
                task[field] = parsed;
            }
            Ok(())
        }
        "priority" | "effort" | "status" | "type" | "strategy"
        | "build_step" | "execution" | "branch" | "subject" | "parent"
        | "started" | "completed" | "created" | "github_issue"
        | "work_type" | "kind" | "spawn" | "spawn_strategy" | "ac_state" => {
            if field == "priority" {
                validate_priority(value)?;
            }
            if field == "ac_state" {
                validate_ac_state(value)?;
                // t-2815 (ADR-079 §1): "approved" is reachable only through the
                // approve verb — a generic set with empty criteria would make the
                // verb's precondition decorative. none/proposed/null stay settable.
                if value == "approved" {
                    return Err(
                        "ac_state \"approved\" cannot be set directly — use \
                         `brana backlog ac <id> approve` (CLI) or backlog_ac_approve (MCP)"
                            .into(),
                    );
                }
            }
            if field == "status" {
                // ADR-065: an epic node's status validates against a
                // different vocabulary than an ordinary task's (t-2313).
                if task["type"].as_str() == Some("epic") {
                    validate_epic_status(value)?;
                } else {
                    validate_status(value)?;
                }
            }
            if field == "work_type" {
                validate_work_type(value)?;
            }
            if field == "kind" {
                validate_kind(value)?;
            }
            if field == "type" {
                validate_task_type(value)?;
            }
            if field == "execution" {
                validate_execution(value)?;
            }
            if value == "null" {
                task[field] = Value::Null;
            } else {
                task[field] = Value::String(value.to_string());
            }
            if field == "status" {
                crate::tasks::ack_status_write(task, value);
            }
            Ok(())
        }
        _ => Err(format!("unknown field: {field}")),
    }
}

/// Set a field on a wave object (ADR-065, t-2315). Waves are not tasks — a
/// separate, smaller field surface than `set_field()`'s task whitelist:
/// name/selector/contract/gate/status only. No array append/remove syntax
/// (no array-typed wave field exists in this minimal slice) and no
/// referential check on `gate` — nothing in this slice resolves or enforces
/// gates (that's the intent-CLI's job, deferred), and no other reference
/// field in this codebase (`parent`, `blocked_by`) is existence-checked at
/// write time either, so `gate` follows the same precedent.
pub fn set_wave_field(wave: &mut Value, field: &str, value: &str) -> Result<(), String> {
    match field {
        "status" => {
            validate_wave_status(value)?;
            if value == "null" {
                wave[field] = Value::Null;
            } else {
                wave[field] = Value::String(value.to_string());
            }
            Ok(())
        }
        // t-2782 (ADR-079 §3): the wave's WIP bound — nullable non-negative
        // integer, null = unbounded (the default until an operator opts in).
        // First non-string wave field: stored as a JSON number so the loop's
        // pull-step comparison (t-2813) can never be defeated by a "3" string.
        // 0 is legal (pause pulling). Enforcement lives at the loop's pull
        // step only — never here, never at drain, never at task start.
        "wip_limit" => {
            if value == "null" {
                wave[field] = Value::Null;
            } else {
                let n: u64 = value.parse().map_err(|_| {
                    format!("wip_limit must be a non-negative integer or null (got: {value})")
                })?;
                wave[field] = Value::Number(n.into());
            }
            Ok(())
        }
        // t-2782 (ADR-079 §3): selector/gate freeze while draining. Waves have
        // no log field, so a mid-drain edit would silently redirect what the
        // next pull cycle matches with zero audit trail. Requeue first — status
        // stays writable below precisely so the requeue path works.
        "selector" | "gate" => {
            if wave["status"].as_str() == Some("draining") {
                return Err(format!(
                    "wave is draining — {field} edits would silently redirect the next \
                     pull cycle; requeue first (set status queued), then edit {field}"
                ));
            }
            if value == "null" {
                wave[field] = Value::Null;
            } else {
                wave[field] = Value::String(value.to_string());
            }
            Ok(())
        }
        "name" | "contract" => {
            if value == "null" {
                wave[field] = Value::Null;
            } else {
                wave[field] = Value::String(value.to_string());
            }
            Ok(())
        }
        _ => Err(format!("unknown wave field: {field}")),
    }
}

/// Apply multiple field updates to a task atomically: either every field
/// applies, or the task is left untouched and all field errors are returned.
/// Fields are applied in caller-supplied order (t-1958).
pub fn set_fields_atomic(
    task: &mut Value,
    fields: &[(String, String)],
    append: bool,
) -> Result<serde_json::Map<String, Value>, Vec<String>> {
    let snapshot = task.clone();
    let mut updated = serde_json::Map::new();
    let mut errors = Vec::new();

    for (field, value) in fields {
        match set_field(task, field, value, append) {
            Ok(()) => {
                updated.insert(field.clone(), task[field.as_str()].clone());
            }
            Err(e) => errors.push(format!("{field}: {e}")),
        }
    }

    if errors.is_empty() {
        Ok(updated)
    } else {
        *task = snapshot;
        Err(errors)
    }
}

/// Validate that a task can be run: must be pending and not blocked.
pub fn validate_task_runnable(task: &Value, all: &[Value]) -> Result<(), String> {
    let id = task["id"].as_str().unwrap_or("?");
    let status = task["status"].as_str().unwrap_or("");
    if status == "in_progress" {
        return Err(format!("{id} already in_progress"));
    }
    if status != "pending" {
        return Err(format!("{id} is {status}, not pending"));
    }
    if let Some(deps) = task["blocked_by"].as_array() {
        for dep in deps {
            if let Some(dep_id) = dep.as_str() {
                if let Some(bt) = all.iter().find(|t| t["id"].as_str() == Some(dep_id)) {
                    if bt["status"].as_str() != Some("completed") {
                        let bs = bt["status"].as_str().unwrap_or("?");
                        return Err(format!("{id} blocked by {dep_id} ({bs})"));
                    }
                }
            }
        }
    }
    Ok(())
}

// ── Agent management (agents.json) ───────────────────────────────────
