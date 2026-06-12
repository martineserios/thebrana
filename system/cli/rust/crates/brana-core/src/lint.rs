//! Definition-of-ready lint for autonomous dispatch (t-1981).
//!
//! The factory foreman runs `brana backlog lint <id>` before dispatching a task
//! to an autonomous workflow. Checks the definition-of-ready from
//! docs/research/2026-06-11-loop-native-redesign.md Part 2, with heuristics
//! refined by the t-1991 rehearsal evidence. Read-only: never mutates tasks.

use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Serialize)]
pub struct LintCheck {
    pub name: String,
    pub pass: bool,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct LintReport {
    pub ready: bool,
    pub checks: Vec<LintCheck>,
    /// Non-gating advisories (t-1991 findings 2 and 3) — never affect `ready`.
    pub warnings: Vec<String>,
}

/// Run the four definition-of-ready checks against `task`.
///
/// `all_tasks` is needed to resolve `blocked_by` references (check 4).
pub fn lint_task(task: &Value, all_tasks: &[Value]) -> LintReport {
    let context = task["context"].as_str().unwrap_or("");
    let ac_lines: Vec<&str> = context.lines()
        .map(str::trim)
        .filter(|l| l.starts_with("AC:"))
        .collect();

    // Check 1 — at least one AC: line with a machine-verifiable token.
    let verifiable = ac_lines.iter().filter(|l| is_verifiable(l)).count();
    let check1 = LintCheck {
        name: "machine-verifiable-ac".into(),
        pass: verifiable >= 1,
        reason: if ac_lines.is_empty() {
            "no AC: lines in context".into()
        } else {
            format!("{verifiable} of {} AC line(s) machine-verifiable", ac_lines.len())
        },
    };

    // Check 2 — non-empty context beyond AC: lines.
    let non_ac: Vec<&str> = context.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with("AC:"))
        .collect();
    let check2 = LintCheck {
        name: "rich-context".into(),
        pass: !non_ac.is_empty(),
        reason: if non_ac.is_empty() {
            "no context beyond AC: lines (tasks-need-rich-context)".into()
        } else {
            format!("{} non-AC context line(s)", non_ac.len())
        },
    };

    // Check 3 — effort S or M; L/XL must be decomposed first.
    let effort = task["effort"].as_str().unwrap_or("");
    let check3 = LintCheck {
        name: "effort-s-or-m".into(),
        pass: matches!(effort, "S" | "M"),
        reason: if effort.is_empty() {
            "effort not set".into()
        } else {
            format!("effort is {effort}")
        },
    };

    // Check 4 — no open ambiguity: Q:/open Q: lines or unresolved blockers.
    let open_questions = context.lines()
        .map(str::trim)
        .filter(|l| {
            let lower = l.to_lowercase();
            lower.starts_with("q:") || lower.starts_with("open q:")
        })
        .count();
    let unresolved: Vec<&str> = task["blocked_by"].as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str())
            .filter(|id| !blocker_resolved(id, all_tasks))
            .collect())
        .unwrap_or_default();
    let check4 = LintCheck {
        name: "no-open-ambiguity".into(),
        pass: open_questions == 0 && unresolved.is_empty(),
        reason: match (open_questions, unresolved.is_empty()) {
            (0, true) => "no open questions or unresolved blockers".into(),
            (n, true) => format!("{n} open Q: line(s) in context"),
            (0, false) => format!("unresolved blocker(s): {}", unresolved.join(", ")),
            (n, false) => format!("{n} open Q: line(s); unresolved blocker(s): {}", unresolved.join(", ")),
        },
    };

    let checks = vec![check1, check2, check3, check4];
    let ready = checks.iter().all(|c| c.pass);
    let warnings = collect_warnings(task, &ac_lines);
    LintReport { ready, checks, warnings }
}

/// True if a blocker id resolves to a completed or cancelled task.
/// Conservative: an id we can't find counts as unresolved.
fn blocker_resolved(id: &str, all_tasks: &[Value]) -> bool {
    all_tasks.iter()
        .find(|t| t["id"].as_str() == Some(id))
        .map(|t| matches!(t["status"].as_str(), Some("completed" | "cancelled")))
        .unwrap_or(false)
}

/// v1 heuristic: an AC line is machine-verifiable if it names a command, exit
/// code, flag, test/assertion shape (t-1991 finding 1), exact-output verb, or
/// file condition. "works well" matches nothing and fails.
fn is_verifiable(line: &str) -> bool {
    let lower = line.to_lowercase();
    if lower.contains('`') || lower.contains("--") || lower.contains('/') {
        return true;
    }
    const TOKENS: &[&str] = &[
        "exit", "exits", "exit code",
        "cargo ", "npm ", "pytest", "brana ", "git ", "bash ", "validate.sh",
        "test", "assert", "coverage",
        "emits", "returns", "outputs", "prints",
        "file exists",
    ];
    if TOKENS.iter().any(|t| lower.contains(t)) {
        return true;
    }
    // File condition: any whitespace token with a dotted extension (e.g. lint.md).
    lower.split_whitespace().any(|w| {
        w.rsplit_once('.')
            .is_some_and(|(stem, ext)| !stem.is_empty()
                && (1..=4).contains(&ext.len())
                && ext.chars().all(|c| c.is_ascii_alphabetic()))
    })
}

/// Non-gating advisories from t-1991 rehearsal findings 2 and 3.
fn collect_warnings(task: &Value, ac_lines: &[&str]) -> Vec<String> {
    let mut warnings = Vec::new();

    // Finding 2 — AC implies an interface change not explicitly enumerated.
    const SURFACE: &[&str] = &["param", "field", "interface", "schema", "endpoint", "api", "input"];
    const CHANGE: &[&str] = &["add", "new", "change", "extend", "accept"];
    if ac_lines.iter().any(|l| {
        let lower = l.to_lowercase();
        SURFACE.iter().any(|s| lower.contains(s)) && CHANGE.iter().any(|c| lower.contains(c))
    }) {
        warnings.push("AC may imply an interface change — enumerate it explicitly in the description (t-1991 finding 2)".into());
    }

    // Finding 3 — compiled-language tasks: code-size effort != wall-clock effort.
    const COMPILED: &[&str] = &["rust", "cargo", "compile"];
    let tags_text = task["tags"].as_array()
        .map(|a| a.iter().filter_map(|v| v.as_str()).collect::<Vec<_>>().join(" "))
        .unwrap_or_default();
    let haystack = format!("{} {}", tags_text, task["description"].as_str().unwrap_or("")).to_lowercase();
    if COMPILED.iter().any(|t| haystack.contains(t)) {
        warnings.push("compiled-language task: build-cycle cost may exceed effort label (t-1991 finding 3)".into());
    }

    warnings
}

// ── tests ───────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn base_task(context: &str, effort: Option<&str>, blocked_by: Vec<&str>) -> Value {
        json!({
            "id": "t-900", "type": "task", "subject": "Sample task",
            "description": "A sample task for lint tests with enough detail.",
            "status": "pending", "effort": effort, "tags": [],
            "context": context, "blocked_by": blocked_by,
        })
    }

    fn check<'a>(report: &'a LintReport, name: &str) -> &'a LintCheck {
        report.checks.iter().find(|c| c.name == name)
            .unwrap_or_else(|| panic!("missing check {name}"))
    }

    const READY_CTX: &str = "Rich background notes about scope and constraints.\nAC: `cargo test` passes with new lint tests included\nAC: rejection path tested through the handler";

    #[test]
    fn ready_task_passes_all_four_checks() {
        let t = base_task(READY_CTX, Some("S"), vec![]);
        let r = lint_task(&t, &[t.clone()]);
        assert!(r.ready);
        assert_eq!(r.checks.len(), 4);
        assert!(r.checks.iter().all(|c| c.pass));
    }

    // ── check 1: machine-verifiable AC ──────────────────────────────────

    #[test]
    fn no_ac_lines_fails_check_one() {
        let t = base_task("Just prose context, no acceptance criteria.", Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(!r.ready);
        assert!(!check(&r, "machine-verifiable-ac").pass);
    }

    #[test]
    fn vague_ac_fails_check_one() {
        let t = base_task("Some context here.\nAC: works well\nAC: feels fast", Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(!check(&r, "machine-verifiable-ac").pass);
    }

    #[test]
    fn one_verifiable_ac_among_vague_passes_check_one() {
        let t = base_task("Some context here.\nAC: works well\nAC: `brana doctor` exits 0", Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(check(&r, "machine-verifiable-ac").pass);
    }

    #[test]
    fn verifiable_token_variants_pass_check_one() {
        // Each line shape from the heuristic: exit code, flag, command word,
        // test/assert/coverage shape (t-1991 finding 1), output verb, file path.
        for ac in [
            "AC: command exits 1 on invalid input",
            "AC: --json output is stable",
            "AC: cargo test passes",
            "AC: rejection path tested through the handler",
            "AC: assert coverage on the error branch",
            "AC: emits {ready: bool} on stdout",
            "AC: docs/reference/lint.md exists",
        ] {
            let ctx = format!("Plenty of rich context first.\n{ac}");
            let t = base_task(&ctx, Some("S"), vec![]);
            let r = lint_task(&t, &[]);
            assert!(check(&r, "machine-verifiable-ac").pass, "should pass: {ac}");
        }
    }

    // ── check 2: rich context beyond AC lines ───────────────────────────

    #[test]
    fn ac_only_context_fails_check_two() {
        let t = base_task("AC: `cargo test` passes", Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(!check(&r, "rich-context").pass);
    }

    #[test]
    fn empty_context_fails_checks_one_and_two() {
        let t = base_task("", Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(!check(&r, "machine-verifiable-ac").pass);
        assert!(!check(&r, "rich-context").pass);
    }

    // ── check 3: effort S or M ───────────────────────────────────────────

    #[test]
    fn effort_l_xl_or_missing_fails_check_three() {
        for effort in [Some("L"), Some("XL"), None] {
            let t = base_task(READY_CTX, effort, vec![]);
            let r = lint_task(&t, &[]);
            assert!(!check(&r, "effort-s-or-m").pass, "effort {effort:?} must fail");
            assert!(!r.ready);
        }
    }

    #[test]
    fn effort_m_passes_check_three() {
        let t = base_task(READY_CTX, Some("M"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(check(&r, "effort-s-or-m").pass);
    }

    // ── check 4: no open ambiguity ───────────────────────────────────────

    #[test]
    fn open_question_line_fails_check_four() {
        for marker in ["Q: which schema version?", "open Q: store location?"] {
            let ctx = format!("{READY_CTX}\n{marker}");
            let t = base_task(&ctx, Some("S"), vec![]);
            let r = lint_task(&t, &[]);
            assert!(!check(&r, "no-open-ambiguity").pass, "marker {marker} must fail");
        }
    }

    #[test]
    fn unresolved_blocker_fails_check_four() {
        let t = base_task(READY_CTX, Some("S"), vec!["t-100"]);
        let blocker = json!({"id": "t-100", "status": "pending"});
        let r = lint_task(&t, &[blocker]);
        assert!(!check(&r, "no-open-ambiguity").pass);
    }

    #[test]
    fn missing_blocker_reference_fails_check_four() {
        // Conservative: a blocker we can't resolve counts as unresolved.
        let t = base_task(READY_CTX, Some("S"), vec!["t-999"]);
        let r = lint_task(&t, &[]);
        assert!(!check(&r, "no-open-ambiguity").pass);
    }

    #[test]
    fn resolved_blockers_pass_check_four() {
        let t = base_task(READY_CTX, Some("S"), vec!["t-100", "t-101"]);
        let done = json!({"id": "t-100", "status": "completed"});
        let cancelled = json!({"id": "t-101", "status": "cancelled"});
        let r = lint_task(&t, &[done, cancelled]);
        assert!(check(&r, "no-open-ambiguity").pass);
    }

    // ── warnings (non-gating, t-1991 findings 2 + 3) ─────────────────────

    #[test]
    fn interface_change_ac_warns_but_stays_ready() {
        let ctx = format!("{READY_CTX}\nAC: backlog_add accepts a new execution param, rejection tested");
        let t = base_task(&ctx, Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(r.ready, "warnings must not gate readiness");
        assert!(r.warnings.iter().any(|w| w.contains("interface")), "warnings: {:?}", r.warnings);
    }

    #[test]
    fn compiled_language_task_warns_on_build_cycle_cost() {
        let mut t = base_task(READY_CTX, Some("S"), vec![]);
        t["tags"] = json!(["rust", "cli"]);
        let r = lint_task(&t, &[]);
        assert!(r.ready);
        assert!(r.warnings.iter().any(|w| w.contains("build-cycle")), "warnings: {:?}", r.warnings);
    }

    #[test]
    fn plain_ready_task_has_no_warnings() {
        let t = base_task(READY_CTX, Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        assert!(r.warnings.is_empty(), "warnings: {:?}", r.warnings);
    }

    // ── JSON shape (AC 3) ────────────────────────────────────────────────

    #[test]
    fn report_serializes_to_ac_schema() {
        let t = base_task(READY_CTX, Some("S"), vec![]);
        let r = lint_task(&t, &[]);
        let v: Value = serde_json::to_value(&r).unwrap();
        assert!(v["ready"].is_boolean());
        let checks = v["checks"].as_array().unwrap();
        assert_eq!(checks.len(), 4);
        for c in checks {
            assert!(c["name"].is_string());
            assert!(c["pass"].is_boolean());
            assert!(c["reason"].is_string());
        }
    }
}
