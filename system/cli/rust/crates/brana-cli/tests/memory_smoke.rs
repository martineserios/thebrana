//! Integration tests for `brana memory write` and `brana memory index`.
//!
//! These tests encode the contract from ADR-038 as executable assertions.
//! They WILL FAIL until t-1468 (brana memory write) and t-1469 (brana memory
//! index) are implemented — that is intentional: they are the TDD spec.
//!
//! Contract under test (ADR-038):
//! - `feedback` + project scope → dated file at `{project_memory}/feedback_{slug}_{ts}.md`
//! - `project`  + project scope → upsert at `{project_memory}/project_{slug}.md`
//! - Two parallel writes to same feedback slug → two distinct dated files (no clobber)
//! - `brana memory index` → MEMORY.md in project memory dir lists newest dated file per slug
//! - Plain-slug file + newer dated file → index references the dated file
//!
//! Conventions (same as cli_smoke.rs):
//! - `env("HOME", tmp.path())` + `current_dir(project_dir)` for full filesystem isolation
//! - One assertion per test — failure output is more useful that way
//! - Never touch the real ~/.claude or repo state

use assert_cmd::Command;
use assert_fs::prelude::*;
use predicates::prelude::*;
use std::path::{Path, PathBuf};
use std::time::Duration;

fn brana() -> Command {
    Command::cargo_bin("brana").expect("binary should build")
}

/// Mirror of brana-core encode_path: replace `/` and `_` with `-`.
fn encode_path(p: &Path) -> String {
    p.to_string_lossy().replace('/', "-").replace('_', "-")
}

/// Resolve the project memory dir under a given fake HOME.
fn project_memory_dir(fake_home: &Path, project_dir: &Path) -> PathBuf {
    fake_home
        .join(".claude/projects")
        .join(encode_path(project_dir))
        .join("memory")
}

/// Resolve the global memory dir under a given fake HOME.
fn global_memory_dir(fake_home: &Path) -> PathBuf {
    fake_home.join(".claude/memory")
}

// ── Surface ──────────────────────────────────────────────────────────────

#[test]
fn memory_help_exits_zero() {
    brana()
        .args(["memory", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("write").and(predicate::str::contains("index")));
}

#[test]
fn memory_write_help_exits_zero() {
    brana()
        .args(["memory", "write", "--help"])
        .assert()
        .success()
        .stdout(
            predicate::str::contains("--type")
                .and(predicate::str::contains("--scope"))
                .and(predicate::str::contains("--slug"))
                .and(predicate::str::contains("--content")),
        );
}

#[test]
fn memory_write_invalid_type_fails_with_hint() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();
    brana()
        .args([
            "memory", "write",
            "--type", "nonsense",
            "--scope", "project",
            "--slug", "test",
            "--content", "hello",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .failure()
        .stderr(
            predicate::str::contains("invalid")
                .or(predicate::str::contains("feedback"))
                .or(predicate::str::contains("expected")),
        );
}

// ── Test 1: feedback + project scope → dated file created ────────────────

#[test]
fn memory_write_feedback_project_creates_file() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();

    brana()
        .args([
            "memory", "write",
            "--type", "feedback",
            "--scope", "project",
            "--slug", "tdd-no-exceptions",
            "--content", "always write the failing test before implementation",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let mem_dir = project_memory_dir(home.path(), project.path());
    let entries: Vec<_> = std::fs::read_dir(&mem_dir)
        .expect("memory dir should exist after write")
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(entries.len(), 1, "expected exactly one file in memory dir");
    let name = entries[0].file_name().to_string_lossy().to_string();
    assert!(
        name.starts_with("feedback_tdd-no-exceptions_"),
        "file should have feedback_slug_ prefix, got: {name}"
    );
    assert!(name.ends_with(".md"), "file should be a .md file, got: {name}");
}

#[test]
fn memory_write_feedback_project_file_has_timestamp_suffix() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();

    brana()
        .args([
            "memory", "write",
            "--type", "feedback",
            "--scope", "project",
            "--slug", "tdd-no-exceptions",
            "--content", "always write the failing test before implementation",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let mem_dir = project_memory_dir(home.path(), project.path());
    let name = std::fs::read_dir(&mem_dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .next()
        .unwrap()
        .file_name()
        .to_string_lossy()
        .to_string();

    // Expect: feedback_tdd-no-exceptions_YYYY-MM-DDTHH-MM-SS.md
    let ts_part = name
        .strip_prefix("feedback_tdd-no-exceptions_")
        .expect("prefix missing")
        .strip_suffix(".md")
        .expect("suffix missing");

    assert_eq!(ts_part.len(), 19, "timestamp should be 19 chars (YYYY-MM-DDTHH-MM-SS), got: {ts_part}");
    assert_eq!(&ts_part[4..5], "-", "position 4 should be '-'");
    assert_eq!(&ts_part[7..8], "-", "position 7 should be '-'");
    assert_eq!(&ts_part[10..11], "T", "position 10 should be 'T'");
    assert_eq!(&ts_part[13..14], "-", "position 13 should be '-'");
    assert_eq!(&ts_part[16..17], "-", "position 16 should be '-'");
}

#[test]
fn memory_write_feedback_project_file_contains_content() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();
    let content = "always write the failing test before implementation";

    brana()
        .args([
            "memory", "write",
            "--type", "feedback",
            "--scope", "project",
            "--slug", "tdd-no-exceptions",
            "--content", content,
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let mem_dir = project_memory_dir(home.path(), project.path());
    let path = std::fs::read_dir(&mem_dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .next()
        .unwrap()
        .path();
    let written = std::fs::read_to_string(&path).unwrap();
    assert!(
        written.contains(content),
        "file should contain the written content"
    );
}

// ── Test 2: project + project scope → upsert (not dated) ─────────────────

#[test]
fn memory_write_project_scope_creates_plain_slug_file() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();

    brana()
        .args([
            "memory", "write",
            "--type", "project",
            "--scope", "project",
            "--slug", "batrade-broker-role",
            "--content", "BATRADE is a facilitator broker, not contract issuer",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let mem_dir = project_memory_dir(home.path(), project.path());
    let expected = mem_dir.join("project_batrade-broker-role.md");
    assert!(expected.exists(), "expected plain-slug file at {expected:?}");
}

#[test]
fn memory_write_project_scope_upserts_on_second_write() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();
    let slug = "batrade-broker-role";
    let args_first = [
        "memory", "write",
        "--type", "project",
        "--scope", "project",
        "--slug", slug,
        "--content", "first content",
    ];
    let args_second = [
        "memory", "write",
        "--type", "project",
        "--scope", "project",
        "--slug", slug,
        "--content", "updated content — upsert",
    ];

    brana().args(args_first).env("HOME", home.path()).current_dir(project.path()).assert().success();
    brana().args(args_second).env("HOME", home.path()).current_dir(project.path()).assert().success();

    let mem_dir = project_memory_dir(home.path(), project.path());
    let entries: Vec<_> = std::fs::read_dir(&mem_dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(entries.len(), 1, "upsert should not create a second file");
    let written = std::fs::read_to_string(entries[0].path()).unwrap();
    assert!(
        written.contains("updated content"),
        "file should contain the updated content after upsert"
    );
}

// ── Test 3: two parallel writes → two distinct dated files ───────────────

#[test]
fn memory_write_feedback_two_writes_create_two_dated_files() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();

    brana()
        .args([
            "memory", "write",
            "--type", "feedback",
            "--scope", "project",
            "--slug", "deploy-merge-to-main",
            "--content", "session A learning",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    // Sleep 1s to guarantee distinct timestamps
    std::thread::sleep(Duration::from_secs(1));

    brana()
        .args([
            "memory", "write",
            "--type", "feedback",
            "--scope", "project",
            "--slug", "deploy-merge-to-main",
            "--content", "session B learning — should not clobber session A",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let mem_dir = project_memory_dir(home.path(), project.path());
    let entries: Vec<_> = std::fs::read_dir(&mem_dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(
        entries.len(),
        2,
        "two feedback writes to same slug should produce two dated files (no clobber)"
    );
    for entry in &entries {
        let name = entry.file_name().to_string_lossy().to_string();
        assert!(
            name.starts_with("feedback_deploy-merge-to-main_"),
            "both files should have the slug prefix, got: {name}"
        );
    }
}

// ── Test 4: brana memory index → MEMORY.md lists newest file per slug ────

#[test]
fn memory_index_generates_memory_md() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();

    // Pre-create two dated files for the same slug (simulate two sessions)
    let mem_dir = project_memory_dir(home.path(), project.path());
    std::fs::create_dir_all(&mem_dir).unwrap();
    std::fs::write(
        mem_dir.join("feedback_tdd-no-exceptions_2026-05-19T08-00-00.md"),
        "---\nslug: tdd-no-exceptions\n---\nOld learning.",
    )
    .unwrap();
    std::fs::write(
        mem_dir.join("feedback_tdd-no-exceptions_2026-05-19T14-00-00.md"),
        "---\nslug: tdd-no-exceptions\n---\nNewer learning.",
    )
    .unwrap();

    brana()
        .args(["memory", "index", "--scope", "project"])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let memory_md = mem_dir.join("MEMORY.md");
    assert!(memory_md.exists(), "MEMORY.md should be created by brana memory index");
    let content = std::fs::read_to_string(&memory_md).unwrap();
    assert!(
        content.contains("tdd-no-exceptions"),
        "MEMORY.md should contain the slug"
    );
    assert!(
        content.contains("2026-05-19T14-00-00"),
        "MEMORY.md should reference the newest dated file, not the older one"
    );
    assert!(
        !content.contains("2026-05-19T08-00-00"),
        "MEMORY.md should NOT reference the older dated file when a newer one exists for the same slug"
    );
}

#[test]
fn memory_index_lists_all_slugs() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();
    let mem_dir = project_memory_dir(home.path(), project.path());
    std::fs::create_dir_all(&mem_dir).unwrap();

    std::fs::write(
        mem_dir.join("feedback_tdd-no-exceptions_2026-05-19T14-00-00.md"),
        "TDD learning.",
    )
    .unwrap();
    std::fs::write(
        mem_dir.join("feedback_deploy-merge-to-main_2026-05-19T14-00-00.md"),
        "Deploy learning.",
    )
    .unwrap();
    std::fs::write(
        mem_dir.join("project_batrade-broker-role.md"),
        "Broker role.",
    )
    .unwrap();

    brana()
        .args(["memory", "index", "--scope", "project"])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let content = std::fs::read_to_string(mem_dir.join("MEMORY.md")).unwrap();
    assert!(content.contains("tdd-no-exceptions"), "MEMORY.md should list tdd-no-exceptions");
    assert!(content.contains("deploy-merge-to-main"), "MEMORY.md should list deploy-merge-to-main");
    assert!(content.contains("batrade-broker-role"), "MEMORY.md should list batrade-broker-role");
}

// ── Test 5: plain slug + newer dated file → index picks dated file ────────

#[test]
fn memory_index_prefers_dated_file_over_plain_slug() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();
    let mem_dir = project_memory_dir(home.path(), project.path());
    std::fs::create_dir_all(&mem_dir).unwrap();

    // Plain slug (legacy format, no timestamp)
    std::fs::write(
        mem_dir.join("feedback_tdd-no-exceptions.md"),
        "Old plain-slug file.",
    )
    .unwrap();
    // Dated file (newer)
    std::fs::write(
        mem_dir.join("feedback_tdd-no-exceptions_2026-05-19T14-00-00.md"),
        "Newer dated file.",
    )
    .unwrap();

    brana()
        .args(["memory", "index", "--scope", "project"])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let content = std::fs::read_to_string(mem_dir.join("MEMORY.md")).unwrap();
    assert!(
        content.contains("2026-05-19T14-00-00"),
        "MEMORY.md should reference the dated file when both plain-slug and dated exist for the same slug"
    );
}

// ── Global scope ──────────────────────────────────────────────────────────

#[test]
fn memory_write_feedback_global_scope_creates_file_in_global_dir() {
    let home = assert_fs::TempDir::new().unwrap();
    let project = assert_fs::TempDir::new().unwrap();

    brana()
        .args([
            "memory", "write",
            "--type", "feedback",
            "--scope", "global",
            "--slug", "use-uv-for-python",
            "--content", "always use uv run python, never python3 directly",
        ])
        .env("HOME", home.path())
        .current_dir(project.path())
        .assert()
        .success();

    let global_dir = global_memory_dir(home.path());
    let entries: Vec<_> = std::fs::read_dir(&global_dir)
        .expect("global memory dir should exist")
        .filter_map(|e| e.ok())
        .collect();
    assert_eq!(entries.len(), 1);
    let name = entries[0].file_name().to_string_lossy().to_string();
    assert!(
        name.starts_with("feedback_use-uv-for-python_"),
        "global feedback file should have dated prefix, got: {name}"
    );
}
