//! Integration smoke tests for the `brana-query` binary (t-3236).
//!
//! Its own `--types` flag defaulted to "task,subtask" and comma-split with
//! ZERO validation (unlike t-3233's fix on `brana backlog query` and MCP
//! `backlog_query`) — a typo'd `--types` value silently matched nothing and
//! returned zero results with no error. These tests lock in that a typo now
//! errors loudly instead.

use assert_cmd::Command;
use predicates::prelude::*;

fn brana_query() -> Command {
    Command::cargo_bin("brana-query").expect("binary should build")
}

const FIXTURE: &str = r#"{"tasks":[
    {"id":"t-1","type":"task","subject":"a"},
    {"id":"ph-1","type":"phase","subject":"b"}
]}"#;

#[test]
fn valid_types_spec_filters_normally() {
    brana_query()
        .args(["--types", "task,phase", "--count"])
        .write_stdin(FIXTURE)
        .assert()
        .success()
        .stdout(predicate::str::contains("2"));
}

#[test]
fn typo_in_types_spec_errors_loudly_instead_of_returning_zero() {
    // Before the fix: an unvalidated comma-split silently matched zero
    // types and printed "0" with exit code 0 — indistinguishable from a
    // legitimately empty result. Now it must fail loudly and name the typo.
    brana_query()
        .args(["--types", "taks", "--count"])
        .write_stdin(FIXTURE)
        .assert()
        .failure()
        .stderr(predicate::str::contains("taks"));
}
