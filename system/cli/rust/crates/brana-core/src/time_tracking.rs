//! Time tracking — Metric 1: active effort (ADR-083, t-2919/t-2920).
//!
//! Pure logic only: turn-delta/idle-cap summation, many-sub-spans bracket rollup,
//! orphaned-bracket recovery, coverage-annotation shape. **Every function here is
//! zero-I/O** — transcript reading, atomic writes, locking, and git-common-dir/git-dir
//! resolution all live in the caller (`brana-cli`), mirroring `receipt.rs`'s pure/IO split.
//!
//! Spec: `docs/architecture/features/time-tracking-metric-1.md`.
//! t-2965 (this file): tests + stub signatures only — no real implementation (that's t-2922).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const IDLE_CAP_SECS: i64 = 15 * 60;

/// One line of `brana/time/<task_id>.jsonl`. Lenient, forward-compatible serde
/// (queue.rs-shaped: no `deny_unknown_fields`, every post-v1 field `#[serde(default)]`) —
/// bracket lines are discrete events, not a signed attestation, so `receipt.rs`'s heavier
/// hash-attestation convention is deliberately not used here.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum BracketLine {
    Start {
        version: u64,
        task_id: String,
        ts: DateTime<Utc>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        session_label: Option<String>,
    },
    Close {
        version: u64,
        task_id: String,
        ts: DateTime<Utc>,
        duration_capped_secs: i64,
        turn_count: u64,
        gaps_capped: u64,
        coverage: Coverage,
    },
}

/// Whether this bracket's duration reflects the whole task or only part of it
/// (v1 excludes subagent/fork fan-out from the sum — ADR-083).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Coverage {
    Full,
    Partial,
}

/// Result of summing turn-to-turn deltas over a transcript, with each delta capped at
/// [`IDLE_CAP_SECS`]. `gaps_capped` counts how many individual deltas were capped (not the
/// number of turns) — the coverage-annotation shape ADR-083 requires.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TurnDeltaSummary {
    pub capped_total_secs: i64,
    pub gaps_capped: u64,
    pub turn_count: u64,
}

/// Sum turn-to-turn deltas over an ordered list of per-turn timestamps, capping each
/// individual delta at `idle_cap_secs`. `timestamps` must already be sorted ascending —
/// this function does not sort (the caller reads them in transcript order).
pub fn turn_delta_summed(timestamps: &[DateTime<Utc>], idle_cap_secs: i64) -> TurnDeltaSummary {
    let turn_count = timestamps.len() as u64;
    if timestamps.len() < 2 {
        return TurnDeltaSummary {
            capped_total_secs: 0,
            gaps_capped: 0,
            turn_count,
        };
    }
    let mut capped_total_secs = 0i64;
    let mut gaps_capped = 0u64;
    for pair in timestamps.windows(2) {
        let delta = (pair[1] - pair[0]).num_seconds();
        if delta > idle_cap_secs {
            capped_total_secs += idle_cap_secs;
            gaps_capped += 1;
        } else {
            capped_total_secs += delta;
        }
    }
    TurnDeltaSummary {
        capped_total_secs,
        gaps_capped,
        turn_count,
    }
}

/// Many-sub-spans bracket rollup: sum every `Close` line's `duration_capped_secs` for a
/// single `task_id`, across however many `(Start, Close)` pairs were recorded — potentially
/// spanning many transcript files/sessions (ADR-083's bracket model). Orphaned `Start` lines
/// (no matching `Close` — crash/session-death mid-bracket) are the caller's concern to close
/// via [`close_orphaned_bracket`] before calling this; this function sums only closed brackets.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BracketRollup {
    pub total_capped_secs: i64,
    pub bracket_count: u64,
    /// `Coverage::Partial` if ANY summed bracket was partial — one partial bracket taints
    /// the whole task_id total, since a bare number with no annotation is exactly the
    /// "precision masquerading as accuracy" trap ADR-083 names.
    pub coverage: Coverage,
}

pub fn sum_brackets(lines: &[BracketLine]) -> BracketRollup {
    let mut total_capped_secs = 0i64;
    let mut bracket_count = 0u64;
    let mut coverage = Coverage::Full;
    for line in lines {
        if let BracketLine::Close {
            duration_capped_secs,
            coverage: line_coverage,
            ..
        } = line
        {
            total_capped_secs += duration_capped_secs;
            bracket_count += 1;
            if *line_coverage == Coverage::Partial {
                coverage = Coverage::Partial;
            }
        }
    }
    BracketRollup {
        total_capped_secs,
        bracket_count,
        coverage,
    }
}

/// Recover an orphaned `Start` (no matching `Close` — the session died mid-bracket).
/// ADR-083's fallback: the bracket's end is the transcript's own last real turn's
/// timestamp, never "now" and never an error.
///
pub fn close_orphaned_bracket(
    start: &BracketLine,
    transcript_timestamps: &[DateTime<Utc>],
) -> TurnDeltaSummary {
    let start_ts = match start {
        BracketLine::Start { ts, .. } => *ts,
        BracketLine::Close { ts, .. } => *ts,
    };
    let relevant: Vec<DateTime<Utc>> = transcript_timestamps
        .iter()
        .copied()
        .filter(|t| *t >= start_ts)
        .collect();
    turn_delta_summed(&relevant, IDLE_CAP_SECS)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn ts(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    // ── turn_delta_summed ────────────────────────────────────────────────────

    #[test]
    fn turn_delta_sums_sub_cap_gaps_uncapped() {
        // Three turns, gaps of 10s and 20s — both well under the 15-min cap, sum uncapped.
        let timestamps = vec![
            ts("2026-08-17T10:00:00Z"),
            ts("2026-08-17T10:00:10Z"),
            ts("2026-08-17T10:00:30Z"),
        ];
        let result = turn_delta_summed(&timestamps, IDLE_CAP_SECS);
        assert_eq!(result.capped_total_secs, 30);
        assert_eq!(result.gaps_capped, 0);
        assert_eq!(result.turn_count, 3);
    }

    #[test]
    fn turn_delta_caps_each_gap_individually() {
        // Two gaps, each 20 minutes (1200s) — each caps to 900s (15min), summed = 1800s,
        // not the naive 2400s. Regression fixture shape from docs/ideas/task-time-tracking.md's
        // own live-transcript numbers (a multi-hour gap must cap to 15min, not be excluded).
        let timestamps = vec![
            ts("2026-08-17T10:00:00Z"),
            ts("2026-08-17T10:20:00Z"), // +1200s -> capped to 900s
            ts("2026-08-17T10:40:00Z"), // +1200s -> capped to 900s
        ];
        let result = turn_delta_summed(&timestamps, IDLE_CAP_SECS);
        assert_eq!(result.capped_total_secs, 1800);
        assert_eq!(result.gaps_capped, 2);
    }

    #[test]
    fn turn_delta_overnight_gap_regression_fixture() {
        // docs/ideas/task-time-tracking.md's own validated numbers: a session spanning
        // 63.5h naive wall-clock (one huge overnight gap) sums to 0.51h (1836s) active
        // when turn-deltas are capped at 15min. Model here with two turns bracketing the
        // full 63.5h gap plus a handful of normal sub-cap turns totaling ~936s, so the
        // capped total is dominated by the one capped 900s gap, not naive span.
        let timestamps = vec![
            ts("2026-08-17T00:00:00Z"),
            ts("2026-08-19T15:30:00Z"), // +63.5h naive -> capped to 900s (15min)
            ts("2026-08-19T15:30:05Z"), // +5s, uncapped
        ];
        let result = turn_delta_summed(&timestamps, IDLE_CAP_SECS);
        assert_eq!(result.capped_total_secs, 905);
        assert_eq!(result.gaps_capped, 1);
        // Naive span would have been 63.5h = 228_600s -- assert we are nowhere near it.
        assert!(result.capped_total_secs < 1000);
    }

    #[test]
    fn turn_delta_empty_timestamps_is_zero() {
        let result = turn_delta_summed(&[], IDLE_CAP_SECS);
        assert_eq!(result.capped_total_secs, 0);
        assert_eq!(result.gaps_capped, 0);
        assert_eq!(result.turn_count, 0);
    }

    #[test]
    fn turn_delta_single_timestamp_is_zero() {
        let result = turn_delta_summed(&[ts("2026-08-17T10:00:00Z")], IDLE_CAP_SECS);
        assert_eq!(result.capped_total_secs, 0);
        assert_eq!(result.turn_count, 1);
    }

    // ── sum_brackets (many-sub-spans rollup) ────────────────────────────────

    #[test]
    fn sum_brackets_rolls_up_multiple_closed_brackets_same_task() {
        // Two (Start, Close) pairs for the same task_id, as if from two different
        // sessions/transcript files -- the many-sub-spans bracket model (ADR-083).
        let lines = vec![
            BracketLine::Start {
                version: 1,
                task_id: "t-9001".into(),
                ts: ts("2026-08-17T09:00:00Z"),
                session_label: None,
            },
            BracketLine::Close {
                version: 1,
                task_id: "t-9001".into(),
                ts: ts("2026-08-17T09:30:00Z"),
                duration_capped_secs: 1500,
                turn_count: 40,
                gaps_capped: 1,
                coverage: Coverage::Full,
            },
            BracketLine::Start {
                version: 1,
                task_id: "t-9001".into(),
                ts: ts("2026-08-18T14:00:00Z"),
                session_label: None,
            },
            BracketLine::Close {
                version: 1,
                task_id: "t-9001".into(),
                ts: ts("2026-08-18T14:10:00Z"),
                duration_capped_secs: 600,
                turn_count: 12,
                gaps_capped: 0,
                coverage: Coverage::Full,
            },
        ];
        let rollup = sum_brackets(&lines);
        assert_eq!(rollup.total_capped_secs, 2100);
        assert_eq!(rollup.bracket_count, 2);
        assert_eq!(rollup.coverage, Coverage::Full);
    }

    #[test]
    fn sum_brackets_any_partial_taints_whole_total() {
        let lines = vec![
            BracketLine::Start {
                version: 1,
                task_id: "t-9002".into(),
                ts: ts("2026-08-17T09:00:00Z"),
                session_label: None,
            },
            BracketLine::Close {
                version: 1,
                task_id: "t-9002".into(),
                ts: ts("2026-08-17T09:30:00Z"),
                duration_capped_secs: 1500,
                turn_count: 40,
                gaps_capped: 0,
                coverage: Coverage::Partial, // delegation-heavy — under-counted
            },
        ];
        let rollup = sum_brackets(&lines);
        assert_eq!(rollup.coverage, Coverage::Partial);
    }

    #[test]
    fn sum_brackets_empty_is_zero() {
        let rollup = sum_brackets(&[]);
        assert_eq!(rollup.total_capped_secs, 0);
        assert_eq!(rollup.bracket_count, 0);
    }

    // ── close_orphaned_bracket ───────────────────────────────────────────────

    #[test]
    fn orphaned_bracket_uses_last_turn_timestamp_not_now() {
        // A Start with no matching Close (session died mid-bracket). The transcript has
        // real turns after the Start; the recovered duration must be turn-delta-summed up
        // to the LAST transcript turn, not "now" (which would silently include however
        // long the crash/recovery took as "active" time -- wrong).
        let start = BracketLine::Start {
            version: 1,
            task_id: "t-9003".into(),
            ts: ts("2026-08-17T10:00:00Z"),
            session_label: None,
        };
        let transcript_timestamps = vec![
            ts("2026-08-17T10:00:00Z"),
            ts("2026-08-17T10:05:00Z"),
            ts("2026-08-17T10:12:00Z"), // last real turn -- session died here
        ];
        let recovered = close_orphaned_bracket(&start, &transcript_timestamps);
        // 5min + 7min = 720s, both sub-cap, no idle capping needed.
        assert_eq!(recovered.capped_total_secs, 720);
        assert_eq!(recovered.turn_count, 3);
    }

    #[test]
    fn orphaned_bracket_with_no_transcript_turns_after_start_is_zero() {
        let start = BracketLine::Start {
            version: 1,
            task_id: "t-9004".into(),
            ts: ts("2026-08-17T10:00:00Z"),
            session_label: None,
        };
        let recovered = close_orphaned_bracket(&start, &[ts("2026-08-17T10:00:00Z")]);
        assert_eq!(recovered.capped_total_secs, 0);
    }

    // ── BracketLine schema round-trip (queue.rs-shaped lenient serde) ───────

    #[test]
    fn bracket_line_start_round_trips_through_json() {
        let line = BracketLine::Start {
            version: 1,
            task_id: "t-9005".into(),
            ts: ts("2026-08-17T10:00:00Z"),
            session_label: Some("debug-label".into()),
        };
        let json = serde_json::to_string(&line).unwrap();
        let parsed: BracketLine = serde_json::from_str(&json).unwrap();
        assert_eq!(line, parsed);
        assert!(json.contains("\"kind\":\"start\""));
    }

    #[test]
    fn bracket_line_close_round_trips_through_json() {
        let line = BracketLine::Close {
            version: 1,
            task_id: "t-9006".into(),
            ts: ts("2026-08-17T10:30:00Z"),
            duration_capped_secs: 1800,
            turn_count: 50,
            gaps_capped: 2,
            coverage: Coverage::Partial,
        };
        let json = serde_json::to_string(&line).unwrap();
        let parsed: BracketLine = serde_json::from_str(&json).unwrap();
        assert_eq!(line, parsed);
        assert!(json.contains("\"coverage\":\"partial\""));
    }

    #[test]
    fn bracket_line_missing_session_label_deserializes_as_none() {
        // Lenient serde (queue.rs-shaped): an older Start line written before
        // session_label existed must still parse.
        let json = r#"{"kind":"start","version":1,"task_id":"t-9007","ts":"2026-08-17T10:00:00Z"}"#;
        let parsed: BracketLine = serde_json::from_str(json).unwrap();
        match parsed {
            BracketLine::Start { session_label, .. } => assert_eq!(session_label, None),
            _ => panic!("expected Start variant"),
        }
    }
}
