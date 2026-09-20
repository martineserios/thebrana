//! Smoke tests for `brana backlog ideas` (t-1770). Always run against a temp
//! fixture via `--file`; never touches the real ledger.
use assert_cmd::Command;
use predicates::prelude::*;

fn brana() -> Command {
    Command::cargo_bin("brana").expect("binary should build")
}

fn fixture() -> (tempfile::TempDir, std::path::PathBuf) {
    let d = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(d.path().join("docs/ideas/drained")).unwrap();
    std::fs::create_dir_all(d.path().join(".claude")).unwrap();
    std::fs::write(d.path().join("docs/ideas/a.md"), "# A\n").unwrap();
    std::fs::write(d.path().join("docs/ideas/b.md"), "# B\n").unwrap();
    std::fs::write(d.path().join("docs/ideas/drained/old.md"), "# old\n").unwrap();
    let tf = d.path().join(".claude/tasks.json");
    std::fs::write(
        &tf,
        r#"{"version":"3","tasks":[
            {"id":"t-1","subject":"s","status":"pending","context":"see docs/ideas/a.md"},
            {"id":"t-2","subject":"s2","status":"pending","context":null}
        ]}"#,
    )
    .unwrap();
    (d, tf)
}

#[test]
fn ideas_lists_all_top_level_docs() {
    let (_d, tf) = fixture();
    brana()
        .args(["backlog", "ideas", "--file"])
        .arg(&tf)
        .assert()
        .success()
        .stdout(predicate::str::contains("docs/ideas/a.md"))
        .stdout(predicate::str::contains("docs/ideas/b.md"))
        .stdout(predicate::str::contains("old.md").not());
}

#[test]
fn ideas_unlinked_omits_referenced_docs() {
    let (_d, tf) = fixture();
    brana()
        .args(["backlog", "ideas", "--unlinked", "--file"])
        .arg(&tf)
        .assert()
        .success()
        .stdout(predicate::str::contains("docs/ideas/b.md"))
        .stdout(predicate::str::contains("docs/ideas/a.md").not());
}

#[test]
fn ideas_link_writes_both_sides_and_is_idempotent() {
    let (d, tf) = fixture();
    for _ in 0..2 {
        brana()
            .args(["backlog", "ideas", "--file"])
            .arg(&tf)
            .args(["link", "b.md", "t-2"])
            .assert()
            .success();
    }
    let doc = std::fs::read_to_string(d.path().join("docs/ideas/b.md")).unwrap();
    assert_eq!(doc.matches("t-2").count(), 1, "{doc}");
    let ledger = std::fs::read_to_string(&tf).unwrap();
    assert_eq!(ledger.matches("docs/ideas/b.md").count(), 1, "{ledger}");

    brana()
        .args(["backlog", "ideas", "--unlinked", "--file"])
        .arg(&tf)
        .assert()
        .success()
        .stdout(predicate::str::contains("b.md").not());
}

#[test]
fn ideas_link_unknown_task_fails() {
    let (_d, tf) = fixture();
    brana()
        .args(["backlog", "ideas", "--file"])
        .arg(&tf)
        .args(["link", "b.md", "t-999"])
        .assert()
        .failure();
}
