//! Derived triage roles (ADR-086 §3, t-3160/T1): a pure, never-stored view
//! over `status`/`ac_state`/`tags` — the single owner of "what state is this
//! task in for pull/triage purposes" so the pump (`wave_pull_decision`) and a
//! human (`brana backlog query --role`) never disagree. ADR-078's lesson:
//! two stored signals for one state drift; this is derived-only and adds no
//! field. `backlog_set(field: "role")` is rejected the same way `epic` is.

use serde_json::Value;

use super::query::tag_matches;

/// The five triage roles from ADR-086 §3, plus the two terminal states the
/// same table lists (`claimed`/`resolved`) so every task has exactly one
/// well-defined answer to "what role am I" whenever a role applies at all.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    NeedsTriage,
    NeedsInfo,
    ReadyForAgent,
    ReadyForHuman,
    Wontfix,
    Claimed,
    Resolved,
}

impl Role {
    /// Kebab-case name — the vocabulary used by `role:<name>` selectors,
    /// `--role` query/filter, and `get` output. The single string<->Role
    /// boundary; nothing else may hand-roll this mapping.
    pub fn as_str(self) -> &'static str {
        match self {
            Role::NeedsTriage => "needs-triage",
            Role::NeedsInfo => "needs-info",
            Role::ReadyForAgent => "ready-for-agent",
            Role::ReadyForHuman => "ready-for-human",
            Role::Wontfix => "wontfix",
            Role::Claimed => "claimed",
            Role::Resolved => "resolved",
        }
    }

    /// Parse a role name. Unknown names are rejected (`None`), never
    /// silently coerced to a default role.
    pub fn parse(s: &str) -> Option<Role> {
        match s {
            "needs-triage" => Some(Role::NeedsTriage),
            "needs-info" => Some(Role::NeedsInfo),
            "ready-for-agent" => Some(Role::ReadyForAgent),
            "ready-for-human" => Some(Role::ReadyForHuman),
            "wontfix" => Some(Role::Wontfix),
            "claimed" => Some(Role::Claimed),
            "resolved" => Some(Role::Resolved),
            _ => None,
        }
    }
}

/// Derive `task`'s role per ADR-086 §3's table. Pure, no I/O. Returns `None`
/// when no role applies — a real, honest gap in the table (e.g. an
/// `ac_state:approved` task tagged `parked`: not ready-for-agent per the
/// `¬tag:parked` clause, not ready-for-human without `tag:human`, and not
/// needs-triage/needs-info since it's already approved) rather than forcing
/// the task into the nearest role.
pub fn derive_role(task: &Value) -> Option<Role> {
    match task["status"].as_str() {
        Some("in_progress") => return Some(Role::Claimed),
        Some("completed") => return Some(Role::Resolved),
        Some("cancelled") => return Some(Role::Wontfix),
        _ => {}
    }

    // Everything below is the `status:pending` (or unset/other-non-terminal)
    // branch. `ac_state` absent-or-null is first-class `needs-triage`, not an
    // edge case — t-3164's field audit found 58.1% of pending tasks (533/917)
    // carry no `ac_state` key at all.
    let tags: Vec<&str> = task["tags"]
        .as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
        .unwrap_or_default();
    let is_parked = tag_matches(&tags, "parked");
    let is_human = tag_matches(&tags, "human");

    match task["ac_state"].as_str() {
        None | Some("none") => Some(Role::NeedsTriage),
        Some("proposed") => Some(Role::NeedsInfo),
        Some("approved") => {
            if is_human {
                Some(Role::ReadyForHuman)
            } else if is_parked {
                None
            } else {
                Some(Role::ReadyForAgent)
            }
        }
        _ => None,
    }
}

/// Augment `task`'s JSON with its derived `role` (t-3244) for `get` output —
/// `role` is never a stored field, so it is added to a clone, never written
/// back to storage. `None` renders as JSON `null`, matching every other
/// absent-value field in `get` output.
pub fn task_with_derived_role(task: &Value) -> Value {
    let mut out = task.clone();
    out["role"] = match derive_role(task) {
        Some(r) => Value::String(r.as_str().to_string()),
        None => Value::Null,
    };
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn task(status: &str, ac_state: Option<&str>, tags: &[&str]) -> Value {
        let mut t = json!({
            "status": status,
            "tags": tags,
        });
        if let Some(ac) = ac_state {
            t["ac_state"] = json!(ac);
        }
        t
    }

    #[test]
    fn needs_triage_when_ac_state_key_absent() {
        // t-3164: 58.1% of pending tasks lack the key entirely — first-class,
        // not an edge case.
        let t = task("pending", None, &[]);
        assert_eq!(derive_role(&t), Some(Role::NeedsTriage));
    }

    #[test]
    fn needs_triage_when_ac_state_explicitly_none() {
        let t = task("pending", Some("none"), &[]);
        assert_eq!(derive_role(&t), Some(Role::NeedsTriage));
    }

    #[test]
    fn needs_info_when_ac_state_proposed() {
        let t = task("pending", Some("proposed"), &[]);
        assert_eq!(derive_role(&t), Some(Role::NeedsInfo));
    }

    #[test]
    fn ready_for_agent_when_approved_unparked_nonhuman() {
        let t = task("pending", Some("approved"), &[]);
        assert_eq!(derive_role(&t), Some(Role::ReadyForAgent));
    }

    #[test]
    fn ready_for_human_when_approved_and_tagged_human() {
        let t = task("pending", Some("approved"), &["human"]);
        assert_eq!(derive_role(&t), Some(Role::ReadyForHuman));
    }

    #[test]
    fn ready_for_human_wins_over_parked_when_both_tags_present() {
        // Table order: tag:human is checked before ¬tag:parked in the
        // ready-for-agent clause, so a human-tagged task never falls into the
        // no-role gap just because it's also parked.
        let t = task("pending", Some("approved"), &["human", "parked"]);
        assert_eq!(derive_role(&t), Some(Role::ReadyForHuman));
    }

    #[test]
    fn no_role_when_approved_parked_and_not_human() {
        // The real gap in ADR-086 §3's table: approved + parked + ¬human
        // matches none of the five named roles. Honest None, not a forced fit.
        let t = task("pending", Some("approved"), &["parked"]);
        assert_eq!(derive_role(&t), None);
    }

    #[test]
    fn no_role_when_ac_state_is_an_unrecognized_value() {
        let t = task("pending", Some("garbled"), &[]);
        assert_eq!(derive_role(&t), None);
    }

    #[test]
    fn claimed_when_in_progress_regardless_of_ac_state() {
        let t = task("in_progress", Some("approved"), &[]);
        assert_eq!(derive_role(&t), Some(Role::Claimed));
    }

    #[test]
    fn resolved_when_completed() {
        let t = task("completed", Some("approved"), &[]);
        assert_eq!(derive_role(&t), Some(Role::Resolved));
    }

    #[test]
    fn wontfix_when_cancelled() {
        let t = task("cancelled", None, &[]);
        assert_eq!(derive_role(&t), Some(Role::Wontfix));
    }

    #[test]
    fn wontfix_wins_over_ac_state_when_cancelled() {
        // Terminal status short-circuits before ac_state/tags are consulted.
        let t = task("cancelled", Some("proposed"), &["human"]);
        assert_eq!(derive_role(&t), Some(Role::Wontfix));
    }

    #[test]
    fn role_as_str_round_trips_through_parse() {
        for r in [
            Role::NeedsTriage,
            Role::NeedsInfo,
            Role::ReadyForAgent,
            Role::ReadyForHuman,
            Role::Wontfix,
            Role::Claimed,
            Role::Resolved,
        ] {
            assert_eq!(Role::parse(r.as_str()), Some(r));
        }
    }

    #[test]
    fn parse_rejects_unknown_role_name() {
        assert_eq!(Role::parse("bogus-role"), None);
        assert_eq!(Role::parse(""), None);
        assert_eq!(Role::parse("Ready-For-Agent"), None); // case-sensitive
    }

    #[test]
    fn task_with_derived_role_adds_role_key_without_mutating_input() {
        let t = task("pending", Some("approved"), &[]);
        let out = task_with_derived_role(&t);
        assert_eq!(out["role"], "ready-for-agent");
        assert!(t.get("role").is_none(), "original task must not be mutated");
    }

    #[test]
    fn task_with_derived_role_renders_none_as_json_null() {
        let t = task("pending", Some("approved"), &["parked"]);
        let out = task_with_derived_role(&t);
        assert_eq!(out["role"], serde_json::Value::Null);
    }

    #[test]
    fn task_with_derived_role_preserves_every_other_field() {
        let mut t = task("in_progress", Some("approved"), &["x"]);
        t["subject"] = json!("hello");
        let out = task_with_derived_role(&t);
        assert_eq!(out["subject"], "hello");
        assert_eq!(out["status"], "in_progress");
        assert_eq!(out["role"], "claimed");
    }
}
