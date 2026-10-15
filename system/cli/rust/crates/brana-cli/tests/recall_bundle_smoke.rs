//! `brana recall --bundle <task-id>` (t-3537): end-to-end against a fake HOME.
//!
//! The fixture has no vector store, so the vector leg is `error` (it checks for the store before
//! it ever calls an embedder); the keyword leg and every stage run for real.

use assert_cmd::Command;
use assert_fs::prelude::*;
use predicates::prelude::*;
use std::path::Path;

fn brana() -> Command {
    Command::cargo_bin("brana").expect("binary should build")
}

/// Independent oracle for brana-core `util::encode_project_dir` (not a call into it).
fn encode(p: &Path) -> String {
    p.to_string_lossy().replace('/', "-").replace('_', "-")
}

struct Fx {
    home: assert_fs::TempDir,
    project: assert_fs::TempDir,
}

impl Fx {
    fn new() -> Self {
        let home = assert_fs::TempDir::new().unwrap();
        let project = assert_fs::TempDir::new().unwrap();
        let mem = |d: &Path| d.to_path_buf();
        let global = mem(home.path()).join(".claude/memory");
        let mine = home.path().join(".claude/projects").join(encode(project.path())).join("memory");
        let client = home.path().join(".claude/projects/-clients-acme/memory");
        for d in [&global, &mine, &client] {
            std::fs::create_dir_all(d).unwrap();
        }
        let note = |dir: &Path, name: &str, desc: &str, body: &str| {
            std::fs::write(dir.join(name), format!("---\ndescription: {desc}\n---\n{body}")).unwrap();
        };
        note(&global, "pattern_scraping-tips.md", "global scraping tips", "scraping tips");
        note(&mine, "feedback_scraping-rules.md", "project scraping rules", "scraping rules");
        note(&client, "pattern_acme-scraping.md", "ACME CONFIDENTIAL", "scraping scraping scraping");
        let tasks = project.child("tasks.json");
        tasks
            .write_str(r#"{"project":"fx","tasks":[{"id":"t-1","subject":"improve scraping","tags":["scraping"],"status":"pending"}]}"#)
            .unwrap();
        Fx { home, project }
    }

    fn cmd(&self) -> Command {
        let mut c = brana();
        c.env("HOME", self.home.path())
            .env("CLAUDE_PROJECT_DIR", self.project.path())
            .env("BRANA_TASKS_FILE", self.project.path().join("tasks.json"))
            .env_remove("BRANA_SESSION_STORE_ROOT")
            .current_dir(self.project.path());
        c
    }

    fn reindex(&self) {
        self.cmd().args(["memory", "reindex"]).assert().success();
    }
}

fn bundle_json(fx: &Fx, task: &str) -> serde_json::Value {
    let out = fx.cmd().args(["recall", "--bundle", task, "--json"]).output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    serde_json::from_slice(&out.stdout).unwrap_or_else(|e| panic!("not JSON ({e}): {}", String::from_utf8_lossy(&out.stdout)))
}

#[test]
fn bundle_prints_at_most_eight_pointers_and_no_other_clients_notes() {
    let fx = Fx::new();
    fx.reindex();
    let v = bundle_json(&fx, "t-1");
    let pointers = v["pointers"].as_array().unwrap();
    assert!(pointers.len() <= 8);
    let refs: Vec<&str> = pointers.iter().map(|p| p["ref"].as_str().unwrap()).collect();
    assert!(refs.contains(&"pattern_scraping-tips"), "{refs:?}");
    assert!(refs.contains(&"feedback_scraping-rules"), "{refs:?}");
    assert!(!refs.iter().any(|r| r.contains("acme")), "{refs:?}");
    assert!(!v.to_string().contains("ACME CONFIDENTIAL"));
}

#[test]
fn bundle_marks_the_legs_and_exits_zero_when_the_vector_store_is_missing() {
    let fx = Fx::new();
    fx.reindex();
    let v = bundle_json(&fx, "t-1");
    assert_eq!(v["legs"]["fts"], "ok");
    assert_eq!(v["legs"]["vector"], "error");
    assert_eq!(v["task"], "t-1");
    assert_eq!(v["shown"], true);
}

#[test]
fn bundle_refreshes_a_stale_index_before_querying() {
    let fx = Fx::new();
    fx.reindex();
    let mine = fx.home.path().join(".claude/projects").join(encode(fx.project.path())).join("memory");
    std::fs::write(mine.join("pattern_fresh-scraping.md"), "---\ndescription: written after the index\n---\nscraping").unwrap();
    let v = bundle_json(&fx, "t-1");
    let refs: Vec<&str> = v["pointers"].as_array().unwrap().iter().map(|p| p["ref"].as_str().unwrap()).collect();
    assert!(refs.contains(&"pattern_fresh-scraping"), "{refs:?}");
    assert_eq!(v["freshness"]["stale_notes"], 1);
}

#[test]
fn bundle_for_an_unknown_task_is_empty_and_exits_zero() {
    let fx = Fx::new();
    fx.reindex();
    let out = fx.cmd().args(["recall", "--bundle", "t-404", "--json"]).output().unwrap();
    assert!(out.status.success());
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(v["pointers"].as_array().unwrap().len(), 0);
    assert!(String::from_utf8_lossy(&out.stderr).contains("t-404"));
}

#[test]
fn bundle_without_an_index_is_empty_and_exits_zero() {
    let fx = Fx::new();
    let v = bundle_json(&fx, "t-1");
    assert_eq!(v["pointers"].as_array().unwrap().len(), 0);
    assert_eq!(v["legs"]["fts"], "error");
}

#[test]
fn human_format_groups_by_type() {
    let fx = Fx::new();
    fx.reindex();
    fx.cmd()
        .args(["recall", "--bundle", "t-1"])
        .assert()
        .success()
        .stdout(predicate::str::contains("t-1").and(predicate::str::contains("pattern")).and(predicate::str::contains("pattern_scraping-tips")));
}

#[test]
fn bundle_and_a_positional_query_are_mutually_exclusive() {
    let fx = Fx::new();
    fx.cmd().args(["recall", "some query", "--bundle", "t-1"]).assert().failure();
}

#[test]
fn recall_needs_a_query_or_a_bundle() {
    let fx = Fx::new();
    fx.cmd().args(["recall"]).assert().failure();
}

#[test]
fn plain_recall_output_is_unchanged() {
    let fx = Fx::new();
    fx.reindex();
    let out = fx.cmd().args(["recall", "scraping"]).output().unwrap();
    assert!(out.status.success());
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(
        text.lines().any(|l| l.starts_with("  [pattern] scraping-tips (global)  score=")),
        "plain recall format changed: {text}"
    );
}
