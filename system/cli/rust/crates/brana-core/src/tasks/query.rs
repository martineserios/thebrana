use super::*;
use serde_json::Value;
use std::collections::{HashMap, HashSet};


/// True when `task` counts as finished for blocked_by-gate purposes: the
/// task-status terminal values (`completed`/`cancelled`) for ordinary tasks,
/// or the epic-status terminal values (`done`/`archived`, ADR-065) for
/// `type: "epic"` nodes. Without this, an epic `blocked_by` another epic
/// would never unblock — the gate check previously hardcoded the task
/// vocabulary and never recognized an epic's own terminal states (t-2313).
pub fn is_finished(task: &Value) -> bool {
    match task["status"].as_str() {
        Some("completed") | Some("cancelled") => true,
        Some("done") | Some("archived") => task["type"].as_str() == Some("epic"),
        _ => false,
    }
}

/// True when `blocker` satisfies a `blocked_by` entry that names it. Distinct
/// from `is_finished`: a task being *over* is not the same as it having
/// *delivered* what its dependents wait on. ADR-079 (amended 2026-08-23) /
/// ADR-086 §4: only `completed` resolves — `cancelled` never does, it has to
/// be removed from `blocked_by` explicitly (cancelling a parent never
/// auto-cancels children). Epic nodes resolve on their own terminal states
/// (`done`/`archived`, ADR-065).
pub fn resolves_blocker(blocker: &Value) -> bool {
    match blocker["status"].as_str() {
        Some("completed") => true,
        Some("done") | Some("archived") => blocker["type"].as_str() == Some("epic"),
        _ => false,
    }
}

/// The single `blocked_by` resolution point (t-3166): every consumer —
/// `classify` (→ `next`/`focus`/`blocked`/status/roadmap), `wave_pull_decision`
/// (t-3043), the MCP focus tool — asks this, so the loop and the human can
/// never disagree on what "unblocked" means. An id absent from `by_id` is
/// unmet, not ignored.
pub fn unmet_blockers<'a>(task: &'a Value, by_id: &HashMap<&str, &Value>) -> Vec<&'a str> {
    task["blocked_by"]
        .as_array()
        .map(|deps| {
            deps.iter()
                .filter_map(|d| d.as_str())
                .filter(|id| !by_id.get(id).map_or(false, |b| resolves_blocker(b)))
                .collect()
        })
        .unwrap_or_default()
}

/// Classify a task's effective status.
pub fn classify(task: &Value, all: &[Value]) -> &'static str {
    if is_finished(task) {
        return "done";
    }
    match task["status"].as_str().unwrap_or("") {
        "in_progress" => "active",
        _ => {
            if task["blocked_by"].as_array().map_or(false, |d| !d.is_empty()) {
                let by_id = super::wave::task_index(all);
                if !unmet_blockers(task, &by_id).is_empty() {
                    return "blocked";
                }
            }
            if task["tags"]
                .as_array()
                .map_or(false, |t| t.iter().any(|v| v.as_str() == Some("parked")))
            {
                return "parked";
            }
            "pending"
        }
    }
}

/// Free-text search across subject, description, context, notes.
pub fn text_match(task: &Value, needle: &str) -> bool {
    let n = needle.to_lowercase();
    ["subject", "description", "context", "notes"]
        .iter()
        .any(|f| {
            task[f]
                .as_str()
                .map_or(false, |v| v.to_lowercase().contains(&n))
        })
}

/// Match a `--tag` query token against a task's tag list. Tags are still
/// plain strings (`Vec<String>`) — `key:value` is a naming convention, not
/// a new storage shape (D8, backlog-v3 t-2311).
///
/// - Query contains `:` → exact string match only (`"layer:backend"` matches
///   only the literal tag `"layer:backend"`).
/// - Query has no `:` → matches the bare tag of that name (backward compat)
///   OR any tag `"<query>:*"` (any-value-for-key match) — so `--tag backend`
///   finds both a bare `"backend"` tag and a `"backend:api"` tag.
///
/// A stored tag is split on its FIRST `:` only, so a value containing more
/// colons (e.g. `"url:https://example.com"`) still parses as key=`"url"`.
pub fn tag_matches(task_tags: &[&str], query: &str) -> bool {
    if query.contains(':') {
        return task_tags.contains(&query);
    }
    task_tags.iter().any(|t| {
        *t == query || t.split_once(':').map(|(k, _)| k) == Some(query)
    })
}

/// AND/OR composition of `tag_matches()` over a list of tag queries (t-2326).
/// Shared by `cmd_query`'s multi-tag AND and `cmd_tags`'s --filter (AND) /
/// --any (OR), so both commands see the same key:value exact + key-only
/// bare-or-any-value semantics instead of `cmd_tags` doing its own plain
/// exact-match check.
pub fn tags_query_match(task_tags: &[&str], tag_list: &[&str], is_and: bool) -> bool {
    if is_and {
        tag_list.iter().all(|tag| tag_matches(task_tags, tag))
    } else {
        tag_list.iter().any(|tag| tag_matches(task_tags, tag))
    }
}

/// Assert that `active_epic` (if set) resolves to something real — either a
/// `type: "epic"` node task (post-migration, ADR-065) or a task still
/// carrying the flat `epic` tag with that value (pre-migration compat,
/// since t-2312's migration script has not been run against live data yet
/// as of this task). Returns an error naming the unresolved slug instead of
/// silently falling through to a no-boost, empty-partition state — closing
/// the gap the ADR's epic table calls out: "the pointer resolves to a real,
/// local epic node and errors otherwise." t-2281 already fixed the
/// project-vs-global resolution BUG (which config file wins); this closes
/// the separate "resolves to nothing at all" gap on top of that fix. t-2314.
pub fn assert_active_epic_resolves(all: &[Value], active_epic: &str) -> Result<(), String> {
    let node_exists = all.iter().any(|t| {
        t["type"].as_str() == Some("epic") && t["subject"].as_str() == Some(active_epic)
    });
    if node_exists {
        return Ok(());
    }
    let flat_tag_exists = all.iter().any(|t| t["epic"].as_str() == Some(active_epic));
    if flat_tag_exists {
        return Ok(());
    }
    Err(format!(
        "active_epic {active_epic:?} does not resolve to any epic node or task — pass --epic with a real epic slug, or start a task under that epic"
    ))
}

/// Session-scoped focus resolution (ADR-088, t-3196) — replaces the retired
/// shared `active_epic` config file. Resolution order:
/// 1. `explicit` (the `--epic` flag) always wins.
/// 2. Else, the epic of the most-recently-started `in_progress` task —
///    v2 schema (client/venture): its flat `epic` field directly; v3 schema
///    (thebrana): `resolve_epic_ancestor()`'s parent-chain walk. This
///    generalizes the fallback `statusline.sh` (lines 36-90) already
///    implements for its own epic badge into one reusable core function,
///    rather than parsing the current branch name — a 2-segment
///    `{work-type}/t-{NNN}-{desc}` branch (the client/venture convention)
///    has no epic segment to parse at all.
/// 3. No match (no in-progress task, or its epic doesn't resolve) → `None`,
///    non-fatal — unlike `assert_active_epic_resolves`, which is fail-loud
///    for an explicit `--epic` that didn't resolve.
pub fn resolve_focus_epic(explicit: Option<&str>, all: &[Value]) -> Option<String> {
    if let Some(e) = explicit {
        return Some(e.to_string());
    }

    fn numeric_id_suffix(task: &Value) -> u64 {
        task["id"]
            .as_str()
            .unwrap_or("")
            .rsplit('-')
            .next()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0)
    }

    let candidate = all
        .iter()
        .filter(|t| t["status"].as_str() == Some("in_progress"))
        .max_by(|a, b| {
            let started_a = a["started"].as_str().unwrap_or("");
            let started_b = b["started"].as_str().unwrap_or("");
            started_a
                .cmp(started_b)
                .then_with(|| numeric_id_suffix(a).cmp(&numeric_id_suffix(b)))
        })?;

    if let Some(epic) = candidate["epic"].as_str() {
        if !epic.is_empty() {
            return Some(epic.to_string());
        }
    }

    let by_id: HashMap<&str, &Value> = all
        .iter()
        .filter_map(|t| t["id"].as_str().map(|id| (id, t)))
        .collect();
    if let Some(slug) = resolve_epic_ancestor(candidate, &by_id) {
        Some(slug)
    } else {
        None
    }
}

/// Named filter criteria replacing the 10-positional-arg `filter_tasks` signature.
#[derive(Debug, Clone)]
pub struct TaskFilter<'a> {
    pub tag: Option<&'a str>,
    pub status: Option<&'a str>,
    pub priority: Option<&'a str>,
    pub effort: Option<&'a str>,
    pub search: Option<&'a str>,
    pub types: Vec<&'a str>,
    pub epic: Option<&'a str>,
    pub work_type: Option<&'a str>,
    /// t-2283: filter by `ac_state` (v3 forward-only slice). Matches only tasks
    /// whose `ac_state` key is PRESENT and equals this value; legacy tasks (key
    /// absent) never match.
    pub ac_state: Option<&'a str>,
    /// t-3244 (ADR-086 §3): filter by derived role (`derive_role`), never a
    /// stored field. A task deriving no role (the approved+parked+¬human gap)
    /// never matches any role filter.
    pub role: Option<super::role::Role>,
}

impl Default for TaskFilter<'_> {
    fn default() -> Self {
        TaskFilter {
            tag: None,
            status: None,
            priority: None,
            effort: None,
            search: None,
            types: vec!["task", "subtask"],
            epic: None,
            work_type: None,
            ac_state: None,
            role: None,
        }
    }
}

/// Returns true if `s` is a valid kebab-case slug: one or more lowercase
/// alphanumeric segments joined by single hyphens (no leading/trailing/
/// consecutive hyphens). Mirrors the bash regex `^[a-z0-9]+(-[a-z0-9]+)*$`
/// used by the shared `epic-ancestor-walk.md` procedure.
pub fn is_epic_slug(s: &str) -> bool {
    !s.is_empty()
        && s.split('-')
            .all(|seg| !seg.is_empty() && seg.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit()))
}

/// Resolve the nearest `type: "epic"` ancestor of `task` by walking its
/// `parent` chain against `by_id` (a full task-id → task lookup built from
/// `all`). Rust equivalent of the bash `resolve_epic_ancestor()` in
/// `system/skills/_shared/epic-ancestor-walk.md` (t-2375/t-2377) — the flat
/// `epic` field it replaces was retired by the backlog-v3 migration
/// (ADR-065, t-2284) and its write path is sealed (t-2310), so any epic
/// membership check must walk `parent` instead of reading `task.epic`.
/// Depth-capped at 10 hops (current epic nodes are always top-level, so real
/// chains resolve in 1-2 hops) and rejects non-slug epic subjects (t-2263
/// failure class — pre-v3 `in-NNN` markers retyped to `type:"epic"` but
/// still carrying full sentence subjects).
pub fn resolve_epic_ancestor(task: &Value, by_id: &HashMap<&str, &Value>) -> Option<String> {
    let mut cur = task["parent"].as_str();
    let mut depth = 0;
    while let Some(id) = cur {
        if depth >= 10 {
            break;
        }
        let t = *by_id.get(id)?;
        if t["type"].as_str() == Some("epic") {
            if let Some(subject) = t["subject"].as_str() {
                if is_epic_slug(subject) {
                    return Some(subject.to_string());
                }
            }
        }
        cur = t["parent"].as_str();
        depth += 1;
    }
    None
}

/// Filter tasks using a `TaskFilter` struct (preferred API).
pub fn filter_tasks_by<'a>(tasks: &'a [Value], all: &[Value], filter: &TaskFilter<'_>) -> Vec<&'a Value> {
    let by_id: HashMap<&str, &Value> = all
        .iter()
        .filter_map(|t| t["id"].as_str().map(|id| (id, t)))
        .collect();
    tasks
        .iter()
        .filter(|t| {
            let tt = t["type"].as_str().unwrap_or("task");
            if !filter.types.contains(&tt) {
                return false;
            }
            if let Some(s) = filter.status {
                let _ = all;
                if raw_status(t, "") != s {
                    return false;
                }
            }
            if let Some(tag) = filter.tag {
                let tags: Vec<&str> = t["tags"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                if !tag_matches(&tags, tag) {
                    return false;
                }
            }
            if let Some(p) = filter.priority {
                if t["priority"].as_str().unwrap_or("") != p {
                    return false;
                }
            }
            if let Some(e) = filter.effort {
                if t["effort"].as_str().unwrap_or("") != e {
                    return false;
                }
            }
            if let Some(q) = filter.search {
                if !text_match(t, q) {
                    return false;
                }
            }
            if let Some(init) = filter.epic {
                match resolve_epic_ancestor(t, &by_id) {
                    Some(slug) if slug == init => {}
                    _ => return false,
                }
            }
            if let Some(wt) = filter.work_type {
                if t["work_type"].as_str().unwrap_or("") != wt {
                    return false;
                }
            }
            if let Some(acs) = filter.ac_state {
                // t-2283: match only when the ac_state KEY is present and equals
                // `acs`. A legacy task (key absent) reads as Null → never matches.
                if t["ac_state"].as_str() != Some(acs) {
                    return false;
                }
            }
            if let Some(role) = filter.role {
                if super::role::derive_role(t) != Some(role) {
                    return false;
                }
            }
            true
        })
        .collect()
}

/// The recognized `type` values (matches CLI `TaskType`/ADR-065's `epic` node type).
pub const VALID_TASK_TYPES: &[&str] = &["task", "subtask", "phase", "milestone", "initiative", "epic"];

/// Parse and validate a comma-separated `--type`/`task_type` spec (t-3233).
/// The CLI's `--type` used to be a single-value `clap` enum, which could
/// never express more than one type at all — the query undercount fix's own
/// "pass --type task,subtask,phase,milestone,epic to include everything"
/// advice was unreachable until that arg became free text. Free text
/// reintroduces the exact silent-drop failure class this task fixes (a
/// typo'd type token would match nothing and return zero results with no
/// error) unless validated here — the single validator both `cmd_query`
/// (CLI) and `backlog_query` (MCP) call, so neither surface can regress
/// independently.
pub fn validate_task_types(spec: &str) -> Result<Vec<&str>, String> {
    let types: Vec<&str> = spec.split(',').map(str::trim).collect();
    for t in &types {
        if !VALID_TASK_TYPES.contains(t) {
            return Err(format!(
                "invalid --type value {t:?} — must be one of: {}",
                VALID_TASK_TYPES.join(", ")
            ));
        }
    }
    Ok(types)
}

/// Count of tasks in `all` whose `type` is not present in `used_types` — the
/// exact population `filter_tasks_by`'s default scope (`["task", "subtask"]`)
/// silently drops when a caller never passes an explicit type filter (t-3233).
/// That population carries the epic-only status vocabulary (`next`/`active`/
/// `archived`, ADR-065) a default-scoped query never surfaces at all — an
/// audit found `brana backlog query --output json` (no `--type`) returning
/// 2861 of 3111 tasks with no indication anything was excluded
/// (docs/research/2026-08-29-field-usage-audit.md). Pure counting function
/// over the whole file, independent of any other filter — callers decide
/// how/when to surface it (CLI: a stderr note; MCP: a result field) and only
/// when the type scope was NOT explicitly chosen by the caller. Never
/// changes what `filter_tasks_by` itself returns.
pub fn excluded_by_type_count(all: &[Value], used_types: &[&str]) -> usize {
    all.iter()
        .filter(|t| !used_types.contains(&t["type"].as_str().unwrap_or("task")))
        .count()
}

/// Filter tasks by multiple criteria (AND logic).
/// Thin wrapper around `filter_tasks_by` — prefer that for new call sites.
pub fn filter_tasks<'a>(
    tasks: &'a [Value],
    all: &[Value],
    tag: Option<&str>,
    status: Option<&str>,
    priority: Option<&str>,
    effort: Option<&str>,
    search: Option<&str>,
    types: &[&str],
    epic: Option<&str>,
    work_type: Option<&str>,
) -> Vec<&'a Value> {
    filter_tasks_by(tasks, all, &TaskFilter {
        tag,
        status,
        priority,
        effort,
        search,
        types: types.to_vec(),
        epic,
        work_type,
        ac_state: None,
        role: None,
    })
}

/// Walk the blocked-by dependency chain for a task with cycle detection.
///
/// Returns a list of (depth, task) pairs representing the blocking tree.
/// Only includes blockers that are not yet done.
pub fn blocked_chain<'a>(
    task_id: &str,
    all: &'a [Value],
    depth: usize,
    visited: &mut HashSet<String>,
) -> Vec<(usize, &'a Value)> {
    if visited.contains(task_id) {
        return vec![]; // cycle detected
    }
    visited.insert(task_id.to_string());

    let task = match all.iter().find(|t| t["id"].as_str() == Some(task_id)) {
        Some(t) => t,
        None => return vec![],
    };

    let mut chain = vec![(depth, task)];

    if let Some(deps) = task["blocked_by"].as_array() {
        for dep in deps {
            if let Some(dep_id) = dep.as_str() {
                let blocker = all.iter().find(|t| t["id"].as_str() == Some(dep_id));
                if let Some(b) = blocker {
                    // "not yet done" here means "still blocks" — a cancelled
                    // blocker is over but unresolved, so it stays in the tree.
                    if !resolves_blocker(b) {
                        chain.extend(blocked_chain(dep_id, all, depth + 1, visited));
                    }
                }
            }
        }
    }

    chain
}

/// Find tasks that have been pending longer than the given threshold.
///
/// Returns tasks sorted by created date (oldest first).
pub fn stale_tasks<'a>(tasks: &'a [Value], all: &'a [Value], threshold_days: i64) -> Vec<&'a Value> {
    let cutoff = (chrono::Local::now().date_naive() - chrono::Duration::days(threshold_days))
        .format("%Y-%m-%d")
        .to_string();

    let mut stale: Vec<&Value> = tasks.iter()
        .filter(|t| matches!(t["type"].as_str(), Some("task" | "subtask")))
        .filter(|t| classify(t, all) == "pending")
        .filter(|t| {
            let created = t["created"].as_str().unwrap_or("9999-99-99");
            created < cutoff.as_str()
        })
        .collect();

    stale.sort_by(|a, b| {
        let da = a["created"].as_str().unwrap_or("");
        let db = b["created"].as_str().unwrap_or("");
        da.cmp(db)
    });

    stale
}
