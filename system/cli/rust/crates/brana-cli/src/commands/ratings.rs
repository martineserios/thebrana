//! Ratings command — dashboard for ~/.claude/ratings/ratings.jsonl signals

use std::fs;
use std::path::Path;

// ── Data types ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub struct RatingEntry {
    pub ts: String,
    pub session_id: String,
    pub signal: String,
    pub category: String,
    pub prompt: String,
}

#[derive(Debug, Default)]
pub struct RatingsSummary {
    pub total: usize,
    pub positive: usize,
    pub negative: usize,
    pub entries: Vec<RatingEntry>,
    pub failure_count: usize,
    pub failure_files: Vec<String>,
}

// ── Pure functions (testable) ─────────────────────────────────────────────────

/// Parse a single JSONL line into a RatingEntry.
pub fn parse_line(line: &str) -> Option<RatingEntry> {
    let v: serde_json::Value = serde_json::from_str(line.trim()).ok()?;
    let obj = v.as_object()?;
    Some(RatingEntry {
        ts: obj.get("ts")?.as_str().unwrap_or("").to_string(),
        session_id: obj.get("session_id")?.as_str().unwrap_or("").to_string(),
        signal: obj.get("signal")?.as_str().unwrap_or("").to_string(),
        category: obj.get("category")?.as_str().unwrap_or("").to_string(),
        prompt: obj.get("prompt")?.as_str().unwrap_or("").to_string(),
    })
}

/// Load all entries from a ratings.jsonl file path.
pub fn load_ratings(path: &Path) -> Vec<RatingEntry> {
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    content.lines().filter(|l| !l.trim().is_empty()).filter_map(parse_line).collect()
}

/// List failure files in a FAILURES directory, most recent first.
pub fn list_failures(dir: &Path) -> Vec<String> {
    if !dir.exists() {
        return Vec::new();
    }
    let mut files: Vec<String> = fs::read_dir(dir)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().is_file())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    files.sort_by(|a, b| b.cmp(a)); // most recent first (timestamp prefix)
    files
}

/// Build a summary from entries + failure list.
pub fn build_summary(entries: Vec<RatingEntry>, failure_files: Vec<String>) -> RatingsSummary {
    let positive = entries.iter().filter(|e| e.category == "positive").count();
    let negative = entries.iter().filter(|e| e.category == "negative").count();
    let failure_count = failure_files.len();
    RatingsSummary {
        total: entries.len(),
        positive,
        negative,
        entries,
        failure_count,
        failure_files,
    }
}

// ── Command handler ───────────────────────────────────────────────────────────

pub fn cmd_ratings(last: usize, json: bool) -> anyhow::Result<()> {
    let home = crate::util::home();
    let ratings_dir = home.join(".claude/ratings");
    let jsonl_path = ratings_dir.join("ratings.jsonl");
    let failures_dir = ratings_dir.join("FAILURES");

    let entries = load_ratings(&jsonl_path);
    let failure_files = list_failures(&failures_dir);
    let summary = build_summary(entries, failure_files);

    if json {
        print_json(&summary, last);
    } else {
        print_dashboard(&summary, last, &ratings_dir);
    }
    Ok(())
}

fn print_dashboard(s: &RatingsSummary, last: usize, ratings_dir: &Path) {
    println!("\n\x1b[1mbrana ratings\x1b[0m\n{}\n", "=".repeat(40));

    if s.total == 0 {
        println!("No signals recorded yet.\n");
        println!("Signals are captured automatically by signal-capture.sh when");
        println!("you give explicit ratings (e.g. '5/5', '3/10') or use sentiment");
        println!("phrases ('perfect', 'that's wrong').\n");
        println!("Storage: {}/ratings.jsonl\n", ratings_dir.display());
        return;
    }

    let pos_pct = if s.total > 0 { s.positive * 100 / s.total } else { 0 };
    let neg_pct = if s.total > 0 { s.negative * 100 / s.total } else { 0 };

    println!("Total signals:  {}", s.total);
    println!("  \x1b[32mPositive:\x1b[0m     {:>4}  ({pos_pct}%)", s.positive);
    println!("  \x1b[31mNegative:\x1b[0m     {:>4}  ({neg_pct}%)\n", s.negative);

    // Recent signals
    let recent: Vec<&RatingEntry> = s.entries.iter().rev().take(last).collect();
    if !recent.is_empty() {
        println!("Recent signals (last {}):", recent.len());
        for e in &recent {
            let col = if e.category == "positive" { "\x1b[32m" } else { "\x1b[31m" };
            let ts_short = e.ts.get(..16).unwrap_or(&e.ts);
            let prompt_short = if e.prompt.len() > 60 {
                format!("{}…", &e.prompt[..60])
            } else {
                e.prompt.clone()
            };
            println!("  {ts_short}  {col}{:<8}\x1b[0m  {:<20}  \"{prompt_short}\"",
                e.category, e.signal);
        }
        println!();
    }

    // FAILURES summary
    if s.failure_count > 0 {
        println!("Failures: {} file(s) in {}/FAILURES/", s.failure_count, ratings_dir.display());
        for f in s.failure_files.iter().take(3) {
            println!("  {f}");
        }
        if s.failure_count > 3 {
            println!("  … and {} more", s.failure_count - 3);
        }
        println!();
    } else {
        println!("Failures: none\n");
    }
}

fn print_json(s: &RatingsSummary, last: usize) {
    let recent: Vec<serde_json::Value> = s.entries.iter().rev().take(last).map(|e| {
        serde_json::json!({
            "ts": e.ts,
            "session_id": e.session_id,
            "signal": e.signal,
            "category": e.category,
            "prompt": e.prompt,
        })
    }).collect();

    let out = serde_json::json!({
        "total": s.total,
        "positive": s.positive,
        "negative": s.negative,
        "failure_count": s.failure_count,
        "recent": recent,
    });
    println!("{}", serde_json::to_string_pretty(&out).unwrap_or_default());
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use std::io::Write;
    use std::path::PathBuf;
    use tempfile::TempDir;

    fn write_file(dir: &TempDir, rel: &str, content: &str) -> PathBuf {
        let path = dir.path().join(rel);
        if let Some(p) = path.parent() { fs::create_dir_all(p).unwrap(); }
        File::create(&path).unwrap().write_all(content.as_bytes()).unwrap();
        path
    }

    // ── parse_line ────────────────────────────────────────────────────────────

    #[test]
    fn test_parse_line_valid() {
        let line = r#"{"ts":"2026-05-09T10:00:00Z","session_id":"abc","signal":"5/5","category":"positive","prompt":"5/5 great"}"#;
        let e = parse_line(line).unwrap();
        assert_eq!(e.ts, "2026-05-09T10:00:00Z");
        assert_eq!(e.category, "positive");
        assert_eq!(e.signal, "5/5");
        assert_eq!(e.prompt, "5/5 great");
    }

    #[test]
    fn test_parse_line_invalid_json() {
        assert!(parse_line("not json").is_none());
    }

    #[test]
    fn test_parse_line_empty() {
        assert!(parse_line("").is_none());
    }

    #[test]
    fn test_parse_line_missing_ts_field() {
        // ts is required — line without it returns None
        let line = r#"{"session_id":"x","signal":"s","category":"positive","prompt":"p"}"#;
        assert!(parse_line(line).is_none());
    }

    #[test]
    fn test_parse_line_negative_category() {
        let line = r#"{"ts":"2026-05-09T10:00:00Z","session_id":"abc","signal":"phrase-negative","category":"negative","prompt":"that's wrong"}"#;
        let e = parse_line(line).unwrap();
        assert_eq!(e.category, "negative");
    }

    // ── load_ratings ──────────────────────────────────────────────────────────

    #[test]
    fn test_load_ratings_missing_file() {
        let entries = load_ratings(Path::new("/nonexistent/path/ratings.jsonl"));
        assert!(entries.is_empty());
    }

    #[test]
    fn test_load_ratings_empty_file() {
        let tmp = TempDir::new().unwrap();
        let path = write_file(&tmp, "ratings.jsonl", "");
        let entries = load_ratings(&path);
        assert!(entries.is_empty());
    }

    #[test]
    fn test_load_ratings_single_entry() {
        let tmp = TempDir::new().unwrap();
        let line = r#"{"ts":"2026-05-09T10:00:00Z","session_id":"abc","signal":"5/5","category":"positive","prompt":"5/5"}"#;
        let path = write_file(&tmp, "ratings.jsonl", &format!("{line}\n"));
        let entries = load_ratings(&path);
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].category, "positive");
    }

    #[test]
    fn test_load_ratings_multiple_entries() {
        let tmp = TempDir::new().unwrap();
        let content = concat!(
            r#"{"ts":"2026-05-09T10:00:00Z","session_id":"a","signal":"5/5","category":"positive","prompt":"p"}"#, "\n",
            r#"{"ts":"2026-05-09T11:00:00Z","session_id":"b","signal":"phrase-negative","category":"negative","prompt":"q"}"#, "\n",
            r#"{"ts":"2026-05-09T12:00:00Z","session_id":"c","signal":"emoji-positive","category":"positive","prompt":"r"}"#, "\n",
        );
        let path = write_file(&tmp, "ratings.jsonl", content);
        let entries = load_ratings(&path);
        assert_eq!(entries.len(), 3);
    }

    #[test]
    fn test_load_ratings_skips_blank_lines() {
        let tmp = TempDir::new().unwrap();
        let content = concat!(
            r#"{"ts":"2026-05-09T10:00:00Z","session_id":"a","signal":"5/5","category":"positive","prompt":"p"}"#, "\n",
            "\n",
            "   \n",
            r#"{"ts":"2026-05-09T11:00:00Z","session_id":"b","signal":"2/5","category":"negative","prompt":"q"}"#, "\n",
        );
        let path = write_file(&tmp, "ratings.jsonl", content);
        let entries = load_ratings(&path);
        assert_eq!(entries.len(), 2);
    }

    // ── list_failures ─────────────────────────────────────────────────────────

    #[test]
    fn test_list_failures_missing_dir() {
        let files = list_failures(Path::new("/nonexistent/FAILURES"));
        assert!(files.is_empty());
    }

    #[test]
    fn test_list_failures_empty_dir() {
        let tmp = TempDir::new().unwrap();
        fs::create_dir_all(tmp.path().join("FAILURES")).unwrap();
        let files = list_failures(&tmp.path().join("FAILURES"));
        assert!(files.is_empty());
    }

    #[test]
    fn test_list_failures_returns_filenames() {
        let tmp = TempDir::new().unwrap();
        write_file(&tmp, "FAILURES/2026-05-09T10-00-00-abc.txt", "failure");
        write_file(&tmp, "FAILURES/2026-05-09T11-00-00-def.txt", "failure");
        let files = list_failures(&tmp.path().join("FAILURES"));
        assert_eq!(files.len(), 2);
    }

    #[test]
    fn test_list_failures_sorted_most_recent_first() {
        let tmp = TempDir::new().unwrap();
        write_file(&tmp, "FAILURES/2026-05-09T08-00-00-aaa.txt", "old");
        write_file(&tmp, "FAILURES/2026-05-09T12-00-00-zzz.txt", "new");
        let files = list_failures(&tmp.path().join("FAILURES"));
        assert_eq!(files.len(), 2);
        assert!(files[0] > files[1], "most recent should be first");
    }

    // ── build_summary ─────────────────────────────────────────────────────────

    #[test]
    fn test_build_summary_empty() {
        let s = build_summary(vec![], vec![]);
        assert_eq!(s.total, 0);
        assert_eq!(s.positive, 0);
        assert_eq!(s.negative, 0);
        assert_eq!(s.failure_count, 0);
    }

    #[test]
    fn test_build_summary_counts() {
        let entries = vec![
            RatingEntry { ts: "t".into(), session_id: "s".into(), signal: "5/5".into(), category: "positive".into(), prompt: "p".into() },
            RatingEntry { ts: "t".into(), session_id: "s".into(), signal: "phrase-negative".into(), category: "negative".into(), prompt: "q".into() },
            RatingEntry { ts: "t".into(), session_id: "s".into(), signal: "emoji-positive".into(), category: "positive".into(), prompt: "r".into() },
        ];
        let s = build_summary(entries, vec!["f1.txt".into(), "f2.txt".into()]);
        assert_eq!(s.total, 3);
        assert_eq!(s.positive, 2);
        assert_eq!(s.negative, 1);
        assert_eq!(s.failure_count, 2);
    }

    #[test]
    fn test_build_summary_unknown_category_not_counted() {
        let entries = vec![
            RatingEntry { ts: "t".into(), session_id: "s".into(), signal: "x".into(), category: "unknown".into(), prompt: "p".into() },
        ];
        let s = build_summary(entries, vec![]);
        assert_eq!(s.total, 1);
        assert_eq!(s.positive, 0);
        assert_eq!(s.negative, 0);
    }
}
