//! End-to-end smoke test for `brana backlog stacked-verdict` (t-2857, ADR-081).
//!
//! Post-build challenger gate flagged this as a promised-but-missing test: the spec's
//! Testing Strategy explicitly says the zero-writes boundary property should have a
//! `receipt_smoke.rs`-pattern integration test, not just the inline pure-function unit
//! tests (which can't exercise the real subprocess chain: ac-grade.sh, receipt validate,
//! and the tasks.json read path together). This closes that gap.
//!
//! Same fixture discipline as receipt_smoke.rs: throwaway git repo in a tempdir, GIT_*
//! env scrubbed (`pattern_git-hook-env-leaks-into-executed-tests`).

use assert_cmd::Command;
use std::path::Path;

const GIT_ENV: [&str; 6] = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_COMMON_DIR",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
];

fn git(dir: &Path, args: &[&str]) -> String {
    let mut c = std::process::Command::new("git");
    c.current_dir(dir).args(args);
    for k in GIT_ENV {
        c.env_remove(k);
    }
    let out = c.output().expect("git runs");
    assert!(out.status.success(), "git {args:?} failed: {}", String::from_utf8_lossy(&out.stderr));
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

/// A repo with `system/scripts/ac-grade.sh` (+ its two lib deps) copied in from THIS
/// source tree, so ac-grade.sh's own worktree/lib resolution works against a real,
/// self-contained fixture rather than requiring the real repo as a side dependency.
fn repo_with_ac_grade() -> tempfile::TempDir {
    let tmp = tempfile::TempDir::new().unwrap();
    let p = tmp.path();
    git(p, &["init", "-q", "-b", "dev"]);
    git(p, &["config", "user.email", "t@t"]);
    git(p, &["config", "user.name", "t"]);
    git(p, &["config", "commit.gpgsign", "false"]);

    // CARGO_MANIFEST_DIR = <repo>/system/cli/rust/crates/brana-cli — 5 levels up to <repo>.
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let real_repo_root = manifest.join("../../../../..").canonicalize().expect("repo root resolves");

    for (src_rel, dst_rel) in [
        ("system/scripts/ac-grade.sh", "system/scripts/ac-grade.sh"),
        ("system/scripts/lib/cmd-allowlist.sh", "system/scripts/lib/cmd-allowlist.sh"),
        ("system/hooks/lib/resolve-brana.sh", "system/hooks/lib/resolve-brana.sh"),
    ] {
        let src = real_repo_root.join(src_rel);
        let dst = p.join(dst_rel);
        std::fs::create_dir_all(dst.parent().unwrap()).unwrap();
        std::fs::copy(&src, &dst).unwrap_or_else(|e| panic!("copy {src:?} -> {dst:?}: {e}"));
    }

    std::fs::create_dir_all(p.join(".claude")).unwrap();
    std::fs::write(
        p.join(".claude/tasks.json"),
        serde_json::json!({
            "project": "fixture",
            "tasks": [{
                "id": "t-1", "subject": "fixture", "status": "in_progress", "type": "task",
                "tags": [], "blocked_by": [], "branch": "dev",
                "acceptance_criteria": ["file seed.md exists"],
                "notes": "Evaluator: PASS (2026-08-14), 1 criteria checked"
            }]
        })
        .to_string(),
    )
    .unwrap();
    std::fs::write(p.join("seed.md"), "seed\n").unwrap();
    git(p, &["add", "-A"]);
    git(p, &["commit", "-q", "-m", "base"]);
    tmp
}

fn brana(dir: &Path) -> Command {
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(dir);
    for k in GIT_ENV {
        cmd.env_remove(k);
    }
    // Point resolve-brana.sh (sourced by ac-grade.sh, a subprocess this same `brana`
    // spawns) at the just-compiled binary via its own env-inherited CLAUDE_PLUGIN_DATA
    // — deterministic regardless of the ambient dev session's own plugin env vars.
    let bin_dir = tempfile::tempdir().unwrap();
    let bin_path = bin_dir.path().join("brana");
    std::fs::copy(assert_cmd::cargo::cargo_bin("brana"), &bin_path).unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = std::fs::metadata(&bin_path).unwrap().permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&bin_path, perms).unwrap();
    }
    cmd.env("CLAUDE_PLUGIN_DATA", bin_dir.path());
    std::mem::forget(bin_dir); // keep the tempdir alive for the command's lifetime
    cmd
}

#[test]
fn stacked_verdict_never_writes_tasks_json() {
    let tmp = repo_with_ac_grade();
    let tasks_path = tmp.path().join(".claude/tasks.json");
    let before = std::fs::read_to_string(&tasks_path).unwrap();

    brana(tmp.path())
        .args(["backlog", "stacked-verdict", "t-1", "--json"])
        .assert()
        .success();

    let after = std::fs::read_to_string(&tasks_path).unwrap();
    assert_eq!(before, after, "stacked-verdict must never write tasks.json (gauge law)");
}

#[test]
fn stacked_verdict_renders_evidence_and_judged_from_real_subprocesses() {
    let tmp = repo_with_ac_grade();

    let out = brana(tmp.path())
        .args(["backlog", "stacked-verdict", "t-1", "--json"])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let v: serde_json::Value = serde_json::from_slice(&out).expect("valid JSON");

    assert_eq!(v["task_id"], "t-1");
    assert_eq!(v["grade"]["pass"], 1, "seed.md exists — H1 should grade pass");
    assert_eq!(v["judged"]["pass"], 1, "Evaluator: PASS note should count as judged-pass");
    assert!(v["graded"].is_array(), "evidence-links finding: graded[] detail must pass through, not just counts");
    assert_eq!(v["graded"].as_array().unwrap().len(), 1);
}
