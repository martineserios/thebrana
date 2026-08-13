//! Wave drain: gate enforcement + minimal selector resolution (t-2775).
//!
//! Spec: docs/architecture/features/wave-gate-enforcement.md. ADR-079 §2
//! requires both functions be importable — `cmd_wave_drain` (one-shot CLI
//! report) and the future loop runner (t-2813, per-cycle polling) must call
//! the SAME resolver, never re-derive selector semantics from raw tasks.json.

use serde_json::Value;

use super::query::tag_matches;

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
