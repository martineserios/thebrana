//! Wave drain: gate enforcement + minimal selector resolution (t-2775).
//!
//! Spec: docs/architecture/features/wave-gate-enforcement.md. ADR-079 §2
//! requires both functions be importable — `cmd_wave_drain` (one-shot CLI
//! report) and the future loop runner (t-2813, per-cycle polling) must call
//! the SAME resolver, never re-derive selector semantics from raw tasks.json.

use serde_json::Value;
use std::path::Path;

use super::query::tag_matches;
use super::{load_raw, lock_tasks, save_tasks};

/// Gate check (the point of t-2775). A wave with a non-empty `gate` may only
/// drain once the gated wave's status is `shipped`.
///
/// - `gate` absent/null/empty → Ok (nothing to gate on).
/// - gate id not found in `all_waves` → Err, fail loud (broken reference —
///   never silently treated as "no gate").
/// - gated wave status != "shipped" → Err naming the blocking wave.
/// - gated wave shipped → Ok.
pub fn check_wave_gate(wave: &Value, all_waves: &[Value]) -> Result<(), String> {
    let gate = match wave["gate"].as_str() {
        Some(g) if !g.is_empty() => g,
        _ => return Ok(()),
    };
    let gated = all_waves
        .iter()
        .find(|w| w["id"].as_str() == Some(gate))
        .ok_or_else(|| format!("gate wave {gate} not found"))?;
    let status = gated["status"].as_str().unwrap_or("unknown");
    if status != "shipped" {
        let id = wave["id"].as_str().unwrap_or("?");
        return Err(format!(
            "wave {id} blocked: gate wave {gate} not shipped (status: {status})"
        ));
    }
    Ok(())
}

/// MVP selector resolution. Supports exactly one selector form: `tag:<name>`
/// — resolved as pending tasks whose tags match `<name>` via the shared
/// `tag_matches` semantics (key:value exact, bare key any-value). Any other
/// selector string is rejected with a clear MVP-only error, never silently
/// no-op'd or partially matched.
pub fn resolve_wave_selector<'a>(
    wave: &Value,
    tasks: &'a [Value],
) -> Result<Vec<&'a Value>, String> {
    let selector = wave["selector"].as_str().unwrap_or("").trim();
    let name = selector
        .strip_prefix("tag:")
        .filter(|n| !n.is_empty() && !n.contains(char::is_whitespace))
        .ok_or_else(|| {
            format!("selector form not supported — MVP only resolves tag:<name> (got: {selector:?})")
        })?;
    Ok(tasks
        .iter()
        .filter(|t| {
            t["status"].as_str() == Some("pending") && {
                let tags: Vec<&str> = t["tags"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                tag_matches(&tags, name)
            }
        })
        .collect())
}

/// t-2813 (ADR-079 §2/§3): what one pull cycle decided. `NoneEligible`'s
/// counts make matched-but-not-eligible visible — the ADR names that state
/// as expected, not a bug, so the runner can report it instead of guessing.
#[derive(Debug, PartialEq, Eq)]
pub enum PullDecision {
    /// One task was (or, in the pure decision fn, would be) set in_progress.
    Pulled { task_id: String },
    /// Live in_progress selector-matches ≥ wip_limit — skip this cycle.
    AtLimit { live: usize, limit: u64 },
    /// Selector matched, but nothing is pending ∧ approved ∧ ¬parked.
    NoneEligible { matched: usize, unapproved: usize, parked: usize },
}

/// t-2813: pure pull decision over in-memory state — the loop runner's whole
/// eligibility contract in one place (ADR-079 §2 filter + §3 WIP bound):
///
/// - wave must be `draining` (pull from anything else is a caller error);
/// - candidates = `resolve_wave_selector` (the shared resolver — pending
///   matches), then `ac_state:approved` and not tagged `parked` (ADR-078);
/// - live = in_progress selector-matches; `wip_limit` null/absent = unbounded,
///   0 = pause; at limit → `AtLimit` before any candidate is considered;
/// - first eligible in array order wins (deterministic, no priority logic —
///   that's the operator's job via ordering/waves, not the pump's).
pub fn wave_pull_decision(wave: &Value, tasks: &[Value]) -> Result<PullDecision, String> {
    let wid = wave["id"].as_str().unwrap_or("?");
    let status = wave["status"].as_str().unwrap_or("unknown");
    if status != "draining" {
        return Err(format!(
            "wave {wid} is {status}, not draining — only draining waves may be pulled from"
        ));
    }

    let matched = resolve_wave_selector(wave, tasks)?;

    // Live count: in_progress tasks matching the selector tag. The resolver
    // (pending-only) validated the selector form above, so the strip is safe.
    let name = wave["selector"].as_str().unwrap_or("").trim()
        .strip_prefix("tag:").unwrap_or("");
    let live = tasks
        .iter()
        .filter(|t| {
            t["status"].as_str() == Some("in_progress") && {
                let tags: Vec<&str> = t["tags"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                tag_matches(&tags, name)
            }
        })
        .count();

    let limit = match wave.get("wip_limit") {
        None | Some(Value::Null) => None,
        Some(v) => Some(v.as_u64().ok_or_else(|| {
            format!("wave {wid} has a non-integer wip_limit ({v}) — fix the wave before pulling")
        })?),
    };
    if let Some(l) = limit {
        if live as u64 >= l {
            return Ok(PullDecision::AtLimit { live, limit: l });
        }
    }

    let mut unapproved = 0;
    let mut parked = 0;
    let mut first: Option<String> = None;
    for t in &matched {
        if t["ac_state"].as_str() != Some("approved") {
            unapproved += 1;
            continue;
        }
        let is_parked = t["tags"]
            .as_array()
            .map(|a| a.iter().any(|v| v.as_str() == Some("parked")))
            .unwrap_or(false);
        if is_parked {
            parked += 1;
            continue;
        }
        if first.is_none() {
            first = Some(t["id"].as_str().unwrap_or("?").to_string());
        }
    }
    match first {
        Some(task_id) => Ok(PullDecision::Pulled { task_id }),
        None => Ok(PullDecision::NoneEligible {
            matched: matched.len(),
            unapproved,
            parked,
        }),
    }
}

/// t-2813 (ADR-079 §3): the atomic pull — ONE lock_tasks critical section:
/// lock → fresh read → decide (`wave_pull_decision` on the just-read state) →
/// write in_progress + started → save. Count-then-pull as two calls is the
/// named TOCTOU; everything here happens under the same lock. A non-pulling
/// decision (AtLimit/NoneEligible) writes nothing. Never sets `completed` on
/// tasks or `shipped` on waves — promotion stays human (no auto-ship).
pub fn pull_wave_task(path: &Path, wave_id: &str) -> Result<PullDecision, String> {
    let _lock = lock_tasks(path)?;
    let mut val = load_raw(path)?;

    let wave = val["waves"]
        .as_array()
        .and_then(|ws| ws.iter().find(|w| w["id"].as_str() == Some(wave_id)))
        .cloned()
        .ok_or_else(|| format!("wave {wave_id} not found"))?;
    let tasks_snapshot = val["tasks"].as_array().cloned().unwrap_or_default();

    let decision = wave_pull_decision(&wave, &tasks_snapshot)?;

    if let PullDecision::Pulled { task_id } = &decision {
        let tasks = val["tasks"].as_array_mut().ok_or("tasks is not an array")?;
        let task = tasks
            .iter_mut()
            .find(|t| t["id"].as_str() == Some(task_id.as_str()))
            .ok_or_else(|| format!("pulled task {task_id} vanished mid-pull"))?;
        task["status"] = Value::String("in_progress".into());
        task["started"] =
            Value::String(chrono::Local::now().format("%Y-%m-%d").to_string());
        val["last_modified"] = Value::String(chrono::Local::now().to_rfc3339());
        save_tasks(path, &val).map_err(|e| format!("wave pull write failed: {e}"))?;
    }
    Ok(decision)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn wave(gate: Option<&str>, selector: &str) -> Value {
        json!({"id": "wave-2", "name": "w", "selector": selector,
               "gate": gate, "status": "queued"})
    }

    // ── check_wave_gate ──────────────────────────────────────────────────

    #[test]
    fn gate_absent_allows() {
        let w = json!({"id": "wave-1", "selector": "tag:x", "status": "queued"});
        assert!(check_wave_gate(&w, &[]).is_ok());
    }

    #[test]
    fn gate_null_or_empty_allows() {
        assert!(check_wave_gate(&wave(None, "tag:x"), &[]).is_ok());
        let w = json!({"id": "wave-2", "selector": "tag:x", "gate": "", "status": "queued"});
        assert!(check_wave_gate(&w, &[]).is_ok());
    }

    #[test]
    fn gate_shipped_allows() {
        let gated = json!({"id": "wave-1", "status": "shipped"});
        assert!(check_wave_gate(&wave(Some("wave-1"), "tag:x"), &[gated]).is_ok());
    }

    #[test]
    fn gate_not_shipped_blocks_naming_blocking_wave() {
        for status in ["queued", "draining"] {
            let gated = json!({"id": "wave-1", "status": status});
            let err = check_wave_gate(&wave(Some("wave-1"), "tag:x"), &[gated]).unwrap_err();
            assert!(err.contains("wave-1"), "error must name the blocking wave: {err}");
            assert!(err.contains("not shipped"), "error must say why: {err}");
        }
    }

    #[test]
    fn gate_nonexistent_fails_loud() {
        let err = check_wave_gate(&wave(Some("wave-99"), "tag:x"), &[]).unwrap_err();
        assert!(err.contains("wave-99") && err.contains("not found"),
            "broken gate reference must fail loud, not act as no-gate: {err}");
    }

    // ── resolve_wave_selector ────────────────────────────────────────────

    fn task(id: &str, status: &str, tags: &[&str]) -> Value {
        json!({"id": id, "subject": format!("s-{id}"), "status": status, "tags": tags})
    }

    #[test]
    fn tag_selector_matches_only_pending_with_tag() {
        let tasks = vec![
            task("t-1", "pending", &["bugfix"]),
            task("t-2", "pending", &["other"]),
            task("t-3", "in_progress", &["bugfix"]),
            task("t-4", "completed", &["bugfix"]),
        ];
        let matched = resolve_wave_selector(&wave(None, "tag:bugfix"), &tasks).unwrap();
        let ids: Vec<_> = matched.iter().map(|t| t["id"].as_str().unwrap()).collect();
        assert_eq!(ids, vec!["t-1"], "only pending tasks with the tag match");
    }

    #[test]
    fn tag_selector_supports_key_value_tags() {
        // the design doc's own example: selector `tag:wave:v3-w1`
        let tasks = vec![
            task("t-1", "pending", &["wave:v3-w1"]),
            task("t-2", "pending", &["wave:v3-w2"]),
        ];
        let matched = resolve_wave_selector(&wave(None, "tag:wave:v3-w1"), &tasks).unwrap();
        assert_eq!(matched.len(), 1);
        assert_eq!(matched[0]["id"], "t-1");
    }

    #[test]
    fn tag_selector_empty_match_is_ok_not_error() {
        let matched = resolve_wave_selector(&wave(None, "tag:nothing"), &[]).unwrap();
        assert!(matched.is_empty());
    }

    #[test]
    fn non_tag_selector_rejected_with_mvp_error() {
        for sel in ["shape:mechanical ac_state:approved", "status:pending",
                    "drainable", "tag:", "tag:a b", ""] {
            let err = resolve_wave_selector(&wave(None, sel), &[]).unwrap_err();
            assert!(err.contains("MVP only resolves tag:<name>"),
                "selector {sel:?} must be rejected with the MVP-only error, got: {err}");
        }
    }

    #[test]
    fn string_typed_tags_skipped_not_crash() {
        // 84 legacy tasks store tags as a comma-joined string; read paths
        // use .as_array() and skip them — the resolver must do the same.
        let tasks = [json!({"id": "t-1", "status": "pending", "tags": "bugfix,old"})];
        let matched = resolve_wave_selector(&wave(None, "tag:bugfix"), &tasks).unwrap();
        assert!(matched.is_empty(), "string-typed tags are skipped, not parsed");
    }
}
