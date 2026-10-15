//! The recall usage log (t-3517): `brana recall --bundle [--shadow]` appends an offered row,
//! `brana memory usage` writes outcomes and answers `--check` / `--report`. Fake HOME throughout.

use assert_cmd::Command;
use assert_fs::prelude::*;
use serde_json::Value;
use std::path::{Path, PathBuf};

const SENTINEL: &str = "zqxsentinelzq";

fn encode(p: &Path) -> String {
    p.to_string_lossy().replace(['/', '_'], "-")
}

fn write_note(dir: &Path, name: &str, desc: &str, body: &str) {
    let path = dir.join(name);
    std::fs::write(&path, format!("---\ndescription: {desc}\n---\n{body}")).unwrap();
    let t = std::time::SystemTime::now() - std::time::Duration::from_secs(60);
    std::fs::File::options().write(true).open(&path).unwrap().set_modified(t).unwrap();
}

struct Fx {
    home: assert_fs::TempDir,
    project: assert_fs::TempDir,
}

impl Fx {
    fn new() -> Self {
        let home = assert_fs::TempDir::new().unwrap();
        let project = assert_fs::TempDir::new().unwrap();
        let global = home.path().join(".claude/memory");
        let mine = home.path().join(".claude/projects").join(encode(project.path())).join("memory");
        std::fs::create_dir_all(&global).unwrap();
        std::fs::create_dir_all(&mine).unwrap();
        write_note(&global, "pattern_scraping-tips.md", "GISTONE global scraping tips", "scraping tips");
        write_note(&mine, "feedback_scraping-rules.md", "GISTTWO project scraping rules", "scraping rules");
        project
            .child("tasks.json")
            .write_str(&format!(
                r#"{{"project":"fx","tasks":[
                    {{"id":"t-1","subject":"improve scraping","tags":["scraping"],"status":"pending"}},
                    {{"id":"t-2","subject":"{SENTINEL} scraping","tags":[],"status":"pending"}}]}}"#
            ))
            .unwrap();
        let fx = Fx { home, project };
        fx.cmd().args(["memory", "reindex"]).assert().success();
        fx
    }

    fn cmd(&self) -> Command {
        let mut c = Command::cargo_bin("brana").unwrap();
        c.env("HOME", self.home.path())
            .env("CLAUDE_PROJECT_DIR", self.project.path())
            .env("BRANA_TASKS_FILE", self.project.path().join("tasks.json"))
            .env_remove("BRANA_SESSION_STORE_ROOT")
            .current_dir(self.project.path());
        c
    }

    fn log(&self) -> PathBuf {
        self.home
            .path()
            .join(".claude/projects")
            .join(encode(self.project.path()))
            .join("brana/recall-usage.jsonl")
    }

    fn rows(&self) -> Vec<Value> {
        std::fs::read_to_string(self.log())
            .unwrap_or_default()
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }

    fn bundle(&self, task: &str, shadow: bool) -> std::process::Output {
        let mut args = vec!["recall", "--bundle", task, "--json"];
        if shadow {
            args.push("--shadow");
        }
        self.cmd().args(args).output().unwrap()
    }

    fn usage(&self, args: &[&str]) -> std::process::Output {
        self.cmd().arg("memory").arg("usage").args(args).output().unwrap()
    }
}

#[test]
fn shadow_appends_one_offered_row_and_prints_nothing() {
    let fx = Fx::new();
    let out = fx.bundle("t-1", true);
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    assert!(out.stdout.is_empty(), "shadow prints nothing to the model: {:?}", String::from_utf8_lossy(&out.stdout));
    let rows = fx.rows();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["kind"], "offered");
    assert_eq!(rows[0]["shown"], false);
    assert_eq!(rows[0]["task"], "t-1");
    assert_eq!(rows[0]["legs"]["fts"], "ok");
    let refs: Vec<&str> = rows[0]["pointers"].as_array().unwrap().iter().map(|p| p["ref"].as_str().unwrap()).collect();
    assert!(refs.contains(&"pattern_scraping-tips"), "{refs:?}");
}

#[test]
fn rows_carry_ids_only_never_query_text_or_gists() {
    let fx = Fx::new();
    assert!(fx.bundle("t-2", true).status.success());
    let text = std::fs::read_to_string(fx.log()).unwrap();
    assert!(!text.contains(SENTINEL), "the task subject (the query) reached the log: {text}");
    assert!(!text.contains("GISTONE") && !text.contains("GISTTWO"), "a gist reached the log: {text}");
    let usage = fx.usage(&["t-2", "--no-answer"]);
    assert!(usage.status.success(), "{}", String::from_utf8_lossy(&usage.stderr));
    assert!(!std::fs::read_to_string(fx.log()).unwrap().contains(SENTINEL));
}

#[test]
fn a_shown_bundle_prints_and_logs_a_shown_row() {
    let fx = Fx::new();
    let out = fx.bundle("t-1", false);
    assert!(out.status.success());
    let printed: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(printed["shown"], true);
    let rows = fx.rows();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["shown"], true);
}

#[test]
fn a_degraded_bundle_still_logs_its_row_with_the_leg_marked() {
    let fx = Fx::new();
    // The fixture has no vector store, so that leg is `error`; the row says so.
    assert!(fx.bundle("t-1", true).status.success());
    assert_eq!(fx.rows()[0]["legs"]["vector"], "error");
}

#[test]
fn an_unknown_task_and_a_missing_index_still_log_an_empty_row_and_exit_zero() {
    let fx = Fx::new();
    let out = fx.bundle("t-404", true);
    assert!(out.status.success());
    let rows = fx.rows();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["pointers"].as_array().unwrap().len(), 0);
}

#[test]
fn the_log_is_private() {
    use std::os::unix::fs::PermissionsExt;
    let fx = Fx::new();
    assert!(fx.bundle("t-1", true).status.success());
    let mode = std::fs::metadata(fx.log()).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);
}

#[test]
fn plain_recall_writes_no_log() {
    let fx = Fx::new();
    let out = fx.cmd().args(["recall", "scraping", "--json"]).output().unwrap();
    assert!(out.status.success());
    assert!(!fx.log().exists());
}

#[test]
fn check_exits_zero_with_no_rows_and_for_a_shadow_row() {
    let fx = Fx::new();
    assert_eq!(fx.usage(&["t-1", "--check"]).status.code(), Some(0));
    assert!(fx.bundle("t-1", true).status.success());
    assert_eq!(fx.usage(&["t-1", "--check"]).status.code(), Some(0));
}

#[test]
fn check_exits_two_for_a_shown_unresolved_row_and_zero_after_the_outcome() {
    let fx = Fx::new();
    assert!(fx.bundle("t-1", false).status.success());
    let blocked = fx.usage(&["t-1", "--check"]);
    assert_eq!(blocked.status.code(), Some(2));
    let say = String::from_utf8_lossy(&blocked.stderr);
    assert!(say.contains("brana memory usage t-1"), "the message names the command to run: {say}");

    let done = fx.usage(&["t-1", "--used", "pattern_scraping-tips", "--ignored", "feedback_scraping-rules"]);
    assert!(done.status.success(), "{}", String::from_utf8_lossy(&done.stderr));
    assert_eq!(fx.usage(&["t-1", "--check"]).status.code(), Some(0));

    let rows = fx.rows();
    let outcome = rows.iter().find(|r| r["kind"] == "outcome").unwrap();
    assert_eq!(outcome["answer"], "given");
    assert_eq!(outcome["used"], serde_json::json!(["pattern_scraping-tips"]));
    assert_eq!(outcome["offered"], rows[0]["id"]);
    // No transcript exists in the fixture, so `opened` is unavailable rather than guessed.
    assert_eq!(outcome["opened"], "unavailable");
}

#[test]
fn an_outcome_for_a_note_the_bundle_never_offered_is_rejected_and_writes_nothing() {
    let fx = Fx::new();
    assert!(fx.bundle("t-1", false).status.success());
    let out = fx.usage(&["t-1", "--used", "pattern_not-offered"]);
    assert_eq!(out.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&out.stderr).contains("pattern_not-offered"));
    assert_eq!(fx.rows().len(), 1);
    assert_eq!(fx.usage(&["t-1", "--check"]).status.code(), Some(2));
}

#[test]
fn an_outcome_without_an_offered_row_is_an_error() {
    let fx = Fx::new();
    let out = fx.usage(&["t-1", "--no-answer"]);
    assert_eq!(out.status.code(), Some(1));
    assert!(!fx.log().exists());
}

#[test]
fn no_answer_conflicts_with_used_and_a_bare_call_needs_a_choice() {
    let fx = Fx::new();
    assert!(fx.bundle("t-1", false).status.success());
    assert_ne!(fx.usage(&["t-1", "--no-answer", "--used", "pattern_scraping-tips"]).status.code(), Some(0));
    assert_ne!(fx.usage(&["t-1"]).status.code(), Some(0), "an outcome needs --used/--ignored or --no-answer");
    assert_eq!(fx.rows().len(), 1);
}

#[test]
fn an_empty_used_list_is_a_given_answer_that_used_none() {
    let fx = Fx::new();
    assert!(fx.bundle("t-1", false).status.success());
    let out = fx.usage(&["t-1", "--used", ""]);
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let rows = fx.rows();
    let o = rows.iter().find(|r| r["kind"] == "outcome").unwrap();
    assert_eq!((o["answer"].as_str(), o["used"].as_array().map(Vec::len)), (Some("given"), Some(0)));
}

#[test]
fn report_counts_offered_rows_sizes_and_degraded_legs() {
    let fx = Fx::new();
    assert!(fx.bundle("t-1", true).status.success());
    assert!(fx.bundle("t-2", true).status.success());
    let out = fx.usage(&["--report", "--json"]);
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let r: Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(r["offered"], 2);
    assert_eq!(r["shadow"], 2);
    assert_eq!(r["shown"], 0);
    assert_eq!(r["legs_not_ok"]["vector:error"], 2);
    let human = fx.usage(&["--report"]);
    assert!(human.status.success());
    assert!(String::from_utf8_lossy(&human.stdout).contains("offered"));
}

#[test]
fn check_reads_a_log_left_under_the_legacy_project_folder_name() {
    // A project root with `_` encodes differently under the legacy scheme. A shown row written
    // there must still block.
    let home = assert_fs::TempDir::new().unwrap();
    let parent = assert_fs::TempDir::new().unwrap();
    let project = parent.path().join("my_proj");
    std::fs::create_dir_all(&project).unwrap();
    let legacy = home
        .path()
        .join(".claude/projects")
        .join(project.to_string_lossy().replace('/', "-"))
        .join("brana");
    std::fs::create_dir_all(&legacy).unwrap();
    std::fs::write(
        legacy.join("recall-usage.jsonl"),
        r#"{"v":1,"kind":"offered","id":"o-1","task":"t-9","ts":"2026-10-20T10:00:00Z","shown":true,"legs":{"fts":"ok","vector":"ok"},"elapsed_ms":1,"pointers":[]}"#.to_owned() + "\n",
    )
    .unwrap();
    let out = Command::cargo_bin("brana")
        .unwrap()
        .env("HOME", home.path())
        .env("CLAUDE_PROJECT_DIR", &project)
        .env_remove("BRANA_SESSION_STORE_ROOT")
        .current_dir(&project)
        .args(["memory", "usage", "t-9", "--check"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2), "{}", String::from_utf8_lossy(&out.stderr));
}
