//! `brana backlog stacked-verdict` — compose the three evidence layers into
//! one line at a valve moment (t-2857, ADR-081).
//!
//! Deterministic (AC-grammar heuristics, via `ac-grade.sh`) + judged
//! (Evaluator:/Challenger: notes convention, ADR-081 D2) + executed (ADR-076
//! build receipts). Gauge law: reads and renders only — never writes any
//! task field. The pure composition logic (`parse_judged_verdicts`,
//! `grade_counts_from_json`, `compose_line`) is directly unit-tested with no
//! subprocess involved; `cmd_stacked_verdict` is the thin wrapper that shells
//! to `ac-grade.sh` and `brana receipt validate`.

use std::path::PathBuf;
use std::process::Command;

use anyhow::{Context, Result};
use serde_json::Value;

use brana_core::tasks;

use crate::util::find_tasks_file;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct JudgedCounts {
    pub pass: usize,
    pub fail: usize,
}

/// Parses `notes` for the Evaluator:/Challenger: convention (ADR-081 D2).
/// Most-recent-per-source wins (a repair-loop's later iteration supersedes
/// an earlier verdict). `PASS WITH GAPS` and `PROCEED WITH CHANGES` both
/// fold into judged-pass — matches challenger-gate.md's own blocking-rule
/// treatment (only `FAIL`/`RECONSIDER` blocks). No matching line for a
/// source → that source contributes nothing (not an error — many tasks skip
/// these gates by size/strategy).
pub fn parse_judged_verdicts(notes: &str) -> JudgedCounts {
    let mut evaluator: Option<bool> = None; // Some(true) = pass, Some(false) = fail
    let mut challenger: Option<bool> = None;

    for line in notes.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("Evaluator: ") {
            if rest.starts_with("PASS WITH GAPS") || rest.starts_with("PASS") {
                evaluator = Some(true);
            } else if rest.starts_with("FAIL") {
                evaluator = Some(false);
            }
        } else if let Some(rest) = line.strip_prefix("Challenger: ") {
            if rest.starts_with("PROCEED WITH CHANGES") || rest.starts_with("PROCEED") {
                challenger = Some(true);
            } else if rest.starts_with("RECONSIDER") {
                challenger = Some(false);
            }
        }
    }

    let mut counts = JudgedCounts::default();
    for v in [evaluator, challenger] {
        match v {
            Some(true) => counts.pass += 1,
            Some(false) => counts.fail += 1,
            None => {}
        }
    }
    counts
}

#[derive(Debug, Clone, Copy, Default)]
pub struct GradeCounts {
    pub pass: usize,
    pub fail: usize,
    pub unknown: usize,
}

/// Parses `ac-grade.sh --json`'s output shape:
/// `{"task_id":..., "graded":[...], "counts":{"pass":N,"fail":N,"unknown":N}}`.
/// A missing/malformed field defaults to 0 rather than erroring — a task
/// this can't fully parse still renders a partial bundle, never crashes the
/// approve/merge flow it's meant to inform.
pub fn grade_counts_from_json(v: &Value) -> GradeCounts {
    GradeCounts {
        pass: v["counts"]["pass"].as_u64().unwrap_or(0) as usize,
        fail: v["counts"]["fail"].as_u64().unwrap_or(0) as usize,
        unknown: v["counts"]["unknown"].as_u64().unwrap_or(0) as usize,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiptStatus {
    NoneMinted,
    Allow,
    ScopeChanged,
    Invalidated(String),
}

impl ReceiptStatus {
    fn render(&self) -> String {
        match self {
            ReceiptStatus::NoneMinted => "none minted".to_string(),
            ReceiptStatus::Allow => "allow".to_string(),
            ReceiptStatus::ScopeChanged => "scope-changed".to_string(),
            ReceiptStatus::Invalidated(reason) => format!("invalidated ({reason})"),
        }
    }
}

/// `brana receipt validate --json`'s output is `{"task_id":...,"result":"allow"
/// |"scope-changed"|"invalidated","reason":"..."}`, always on stdout regardless
/// of exit code. "no receipt" is reported as `invalidated` with that literal
/// reason string — distinguished here from a real invalidation.
pub fn receipt_status_from_json(v: &Value) -> ReceiptStatus {
    let result = v["result"].as_str().unwrap_or("");
    let reason = v["reason"].as_str().unwrap_or("").to_string();
    match result {
        "allow" => ReceiptStatus::Allow,
        "scope-changed" => ReceiptStatus::ScopeChanged,
        "invalidated" if reason == "no receipt" => ReceiptStatus::NoneMinted,
        "invalidated" => ReceiptStatus::Invalidated(reason),
        _ => ReceiptStatus::NoneMinted,
    }
}

/// Compose the one-line bundle. Pure — no I/O, directly testable.
/// `"{X}/{N} AC machine-green · {Y} judged-pass{detail} · {Z} needs-you · receipt: {R}"`
pub fn compose_line(grade: &GradeCounts, judged: JudgedCounts, receipt: &ReceiptStatus) -> String {
    let total = grade.pass + grade.fail + grade.unknown;
    let detail = if judged.pass > 0 { " (verdicts attached)" } else { "" };
    format!(
        "{}/{} AC machine-green · {} judged-pass{} · {} needs-you · receipt: {}",
        grade.pass,
        total,
        judged.pass,
        detail,
        grade.unknown,
        receipt.render()
    )
}

/// The thin wrapper: loads the task, shells to `ac-grade.sh` and `brana
/// receipt validate`, composes, prints. Zero writes — never calls
/// `tasks::save_tasks` or any mutating helper (gauge law, boundary-tested).
pub fn cmd_stacked_verdict(task_id: &str, json: bool, file: Option<PathBuf>) -> Result<()> {
    let bundle = compute_bundle(task_id, file)?;

    if json {
        println!(
            "{}",
            serde_json::json!({
                "task_id": task_id,
                "grade": {"pass": bundle.grade.pass, "fail": bundle.grade.fail, "unknown": bundle.grade.unknown},
                "judged": {"pass": bundle.judged.pass, "fail": bundle.judged.fail},
                "receipt": bundle.receipt.render(),
                "line": bundle.line,
            })
        );
    } else {
        println!("{}", bundle.line);
    }
    Ok(())
}

struct Bundle {
    grade: GradeCounts,
    judged: JudgedCounts,
    receipt: ReceiptStatus,
    line: String,
}

fn compute_bundle(task_id: &str, file: Option<PathBuf>) -> Result<Bundle> {
    let tf = match file {
        Some(f) => f,
        None => find_tasks_file().context("tasks.json not found")?,
    };
    let data = tasks::load_tasks(&tf).map_err(|e| anyhow::anyhow!("{e}"))?;
    let task = data
        .tasks
        .iter()
        .find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| anyhow::anyhow!("task {task_id} not found"))?;

    let notes = task["notes"].as_str().unwrap_or("");
    let judged = parse_judged_verdicts(notes);

    // repo_root for LOCATING ac-grade.sh must be the invoking process's own
    // checkout (`git rev-parse --show-toplevel` from cwd) — NOT derived from
    // tasks.json's path. tasks.json deliberately resolves via
    // `--git-common-dir` (shared across every worktree, by design — the
    // single source of truth for task state), which on a feature branch
    // points at the MAIN checkout. That checkout may not yet have this
    // branch's own system/scripts/ac-grade.sh, silently defeating the
    // grading call. Matches how ac-grade.sh's own worktree resolution and
    // `brana receipt validate`'s repo_root() already work: both assume the
    // invoking cwd IS the relevant checkout. Found via manual smoke test —
    // the unit tests below cover composition logic, not this subprocess
    // path-resolution mismatch, which only surfaces against a real repo.
    let repo_root = current_repo_root().unwrap_or_else(|| std::env::current_dir().unwrap_or_default());

    let grade = run_ac_grade(&repo_root, task_id)
        .map(|v| grade_counts_from_json(&v))
        .unwrap_or_default();

    let receipt = run_receipt_validate(task_id)
        .map(|v| receipt_status_from_json(&v))
        .unwrap_or(ReceiptStatus::NoneMinted);

    let line = compose_line(&grade, judged, &receipt);
    Ok(Bundle { grade, judged, receipt, line })
}

/// For `ac approve` (t-2872): render the bundle line, best-effort. `None` on
/// any failure (task not found, subprocess errors) — the caller must never
/// let this block or fail the actual approval; the gauge is informational
/// only, never a gate (gauge law, wave-pipeline.md §skeleton match).
pub fn render_bundle_line(task_id: &str, file: Option<PathBuf>) -> Option<String> {
    compute_bundle(task_id, file).ok().map(|b| b.line)
}

/// The invoking process's own checkout root — never derived from tasks.json's
/// path (see the comment at its call site above).
fn current_repo_root() -> Option<PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    let out = Command::new("git")
        .current_dir(&cwd)
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let s = String::from_utf8(out.stdout).ok()?;
    let trimmed = s.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(PathBuf::from(trimmed))
    }
}

fn run_ac_grade(repo_root: &std::path::Path, task_id: &str) -> Option<Value> {
    let script = repo_root.join("system/scripts/ac-grade.sh");
    if !script.exists() {
        return None;
    }
    let out = Command::new("bash")
        .arg(&script)
        .arg(task_id)
        .arg("--json")
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    serde_json::from_slice(&out.stdout).ok()
}

fn run_receipt_validate(task_id: &str) -> Option<Value> {
    let exe = std::env::current_exe().ok()?;
    // Exit codes 0/3/4 are all meaningful verdicts (allow/scope-changed/
    // invalidated) — status.success() alone would treat 3/4 as "no output",
    // discarding the JSON on stdout that receipt validate always emits
    // regardless of exit code.
    let out = Command::new(exe)
        .args(["receipt", "validate", task_id, "--json"])
        .output()
        .ok()?;
    serde_json::from_slice(&out.stdout).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── parse_judged_verdicts ────────────────────────────────────────────

    #[test]
    fn no_notes_zero_judged() {
        let c = parse_judged_verdicts("");
        assert_eq!(c, JudgedCounts { pass: 0, fail: 0 });
    }

    #[test]
    fn evaluator_pass_counts() {
        let c = parse_judged_verdicts("Evaluator: PASS (2026-08-14), 4 criteria checked");
        assert_eq!(c, JudgedCounts { pass: 1, fail: 0 });
    }

    #[test]
    fn evaluator_pass_with_gaps_folds_into_pass() {
        let c = parse_judged_verdicts("Evaluator: PASS WITH GAPS (2026-08-14), 4 criteria checked");
        assert_eq!(c, JudgedCounts { pass: 1, fail: 0 });
    }

    #[test]
    fn evaluator_fail_counts_as_fail() {
        let c = parse_judged_verdicts("Evaluator: FAIL (2026-08-14), 4 criteria checked");
        assert_eq!(c, JudgedCounts { pass: 0, fail: 1 });
    }

    #[test]
    fn challenger_proceed_counts() {
        let c = parse_judged_verdicts("Challenger: PROCEED (2026-08-14), 0 findings");
        assert_eq!(c, JudgedCounts { pass: 1, fail: 0 });
    }

    #[test]
    fn challenger_proceed_with_changes_folds_into_pass() {
        let c = parse_judged_verdicts("Challenger: PROCEED WITH CHANGES (2026-08-14), 2 findings, max severity 3");
        assert_eq!(c, JudgedCounts { pass: 1, fail: 0 });
    }

    #[test]
    fn challenger_reconsider_counts_as_fail() {
        let c = parse_judged_verdicts("Challenger: RECONSIDER (2026-08-14), 3 findings, max severity 4");
        assert_eq!(c, JudgedCounts { pass: 0, fail: 1 });
    }

    #[test]
    fn both_sources_combine() {
        let c = parse_judged_verdicts(
            "Evaluator: PASS (2026-08-14), 4 criteria checked\nChallenger: PROCEED (2026-08-14), 0 findings",
        );
        assert_eq!(c, JudgedCounts { pass: 2, fail: 0 });
    }

    #[test]
    fn most_recent_per_source_wins() {
        // Iteration 1 RECONSIDER, iteration 2 (after fixes) PROCEED — the later
        // line must win, not be double-counted or averaged.
        let c = parse_judged_verdicts(
            "Challenger: RECONSIDER (2026-08-14), 3 findings, max severity 4\nChallenger: PROCEED (2026-08-14), 0 findings",
        );
        assert_eq!(c, JudgedCounts { pass: 1, fail: 0 }, "later line supersedes the earlier one, not both counted");
    }

    #[test]
    fn unrelated_notes_text_ignored() {
        let c = parse_judged_verdicts("Retrospective: what surprised — a challenger review caught a real bug");
        assert_eq!(c, JudgedCounts { pass: 0, fail: 0 });
    }

    // ── grade_counts_from_json ───────────────────────────────────────────

    #[test]
    fn grade_counts_parses_full_shape() {
        let v = serde_json::json!({"task_id":"t-1","graded":[],"counts":{"pass":7,"fail":1,"unknown":2}});
        let c = grade_counts_from_json(&v);
        assert_eq!((c.pass, c.fail, c.unknown), (7, 1, 2));
    }

    #[test]
    fn grade_counts_defaults_on_missing_fields() {
        let v = serde_json::json!({});
        let c = grade_counts_from_json(&v);
        assert_eq!((c.pass, c.fail, c.unknown), (0, 0, 0));
    }

    // ── receipt_status_from_json ─────────────────────────────────────────

    #[test]
    fn receipt_allow() {
        let v = serde_json::json!({"task_id":"t-1","result":"allow","reason":"ok"});
        assert_eq!(receipt_status_from_json(&v), ReceiptStatus::Allow);
    }

    #[test]
    fn receipt_no_receipt_distinguished_from_real_invalidation() {
        let none = serde_json::json!({"task_id":"t-1","result":"invalidated","reason":"no receipt"});
        assert_eq!(receipt_status_from_json(&none), ReceiptStatus::NoneMinted);

        let tampered = serde_json::json!({"task_id":"t-1","result":"invalidated","reason":"stdout hash mismatch"});
        assert_eq!(
            receipt_status_from_json(&tampered),
            ReceiptStatus::Invalidated("stdout hash mismatch".to_string())
        );
    }

    #[test]
    fn receipt_scope_changed() {
        let v = serde_json::json!({"task_id":"t-1","result":"scope-changed","reason":"candidate moved"});
        assert_eq!(receipt_status_from_json(&v), ReceiptStatus::ScopeChanged);
    }

    // ── compose_line ──────────────────────────────────────────────────────

    #[test]
    fn compose_evidence_free_task() {
        let line = compose_line(&GradeCounts::default(), JudgedCounts::default(), &ReceiptStatus::NoneMinted);
        assert_eq!(line, "0/0 AC machine-green · 0 judged-pass · 0 needs-you · receipt: none minted");
    }

    #[test]
    fn compose_full_evidence() {
        let grade = GradeCounts { pass: 7, fail: 0, unknown: 2 };
        let judged = JudgedCounts { pass: 2, fail: 0 };
        let line = compose_line(&grade, judged, &ReceiptStatus::Allow);
        assert_eq!(
            line,
            "7/9 AC machine-green · 2 judged-pass (verdicts attached) · 2 needs-you · receipt: allow"
        );
    }

    #[test]
    fn compose_never_panics_on_zero_judged_with_evidence() {
        let grade = GradeCounts { pass: 3, fail: 1, unknown: 0 };
        let line = compose_line(&grade, JudgedCounts::default(), &ReceiptStatus::ScopeChanged);
        assert!(line.contains("0 judged-pass ·"), "no parenthetical when judged.pass == 0: {line}");
        assert!(!line.contains("verdicts attached"));
    }
}
