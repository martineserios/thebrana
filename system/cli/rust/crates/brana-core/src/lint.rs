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
pub fn lint_task(_task: &Value, _all_tasks: &[Value]) -> LintReport {
    unimplemented!("t-1981: red phase")
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
