//! End-to-end smoke tests for `brana time` (t-2921/t-2922, ADR-083).
//!
//! Same fixture shape as `receipt_smoke.rs`: throwaway git repos in tempdirs, every git
//! and `brana` invocation runs with the git-env denylist scrubbed
//! (`pattern_git-hook-env-leaks-into-executed-tests`).
//!
//! t-2921 (this file): tests only, against a `todo!()`-stubbed `brana time` — every test
//! here is expected to fail red until t-2922 implements the real logic.

use assert_cmd::Command;
use std::path::{Path, PathBuf};

const GIT_ENV: [&str; 6] = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_COMMON_DIR",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
];

fn git(dir: &Path, args: &[&str]) -> std::process::Output {
    let mut c = std::process::Command::new("git");
    c.current_dir(dir).args(args);
    for k in GIT_ENV {
        c.env_remove(k);
    }
    c.output().expect("git runs")
}

fn git_ok(dir: &Path, args: &[&str]) -> String {
    let out = git(dir, args);
    assert!(
        out.status.success(),
        "git {args:?} failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn brana(dir: &Path) -> Command {
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(dir);
    for k in GIT_ENV {
        cmd.env_remove(k);
    }
    cmd
}

/// A bare-bones repo on `dev` with one commit — no tasks.json/AC needed for these tests.
fn repo() -> tempfile::TempDir {
    repo_named("time-smoke-")
}

/// Same fixture, with a caller-chosen tempdir prefix — lets a test control whether the
/// resolved project root contains `_` (relevant for `e1`, below: `encode_project_path`
/// vs. `encode_project_path_legacy` only actually differ when the path has one).
fn repo_named(prefix: &str) -> tempfile::TempDir {
    let tmp = tempfile::Builder::new().prefix(prefix).tempdir().unwrap();
    let p = tmp.path();
    git_ok(p, &["init", "-q", "-b", "dev"]);
    git_ok(p, &["config", "user.email", "t@t"]);
    git_ok(p, &["config", "user.name", "t"]);
    git_ok(p, &["config", "commit.gpgsign", "false"]);
    std::fs::write(p.join("seed.txt"), "seed\n").unwrap();
    git_ok(p, &["add", "-A"]);
    git_ok(p, &["commit", "-q", "-m", "base"]);
    tmp
}

/// Add a second worktree off `base`'s `dev` branch — a genuinely separate `--git-dir`
/// from `base`'s own, sharing the same `--git-common-dir`. Returns the worktree path.
///
/// `base.parent()` is `/tmp` itself (tempfile creates its tempdirs directly there), a
/// namespace shared across every test run — a fixed literal `name` (e.g. "wt2") landed
/// two different runs' worktrees on the same path and made `git worktree add` fail
/// against leftover state from a prior run (the linked worktree directory isn't owned
/// by either `base`'s or its own `tempfile::TempDir`, so nothing cleans it up on drop).
/// Suffixing with `base`'s own random tempdir name keeps every run's path unique.
fn add_worktree(base: &Path, name: &str, branch: &str) -> PathBuf {
    let unique = base.file_name().and_then(|n| n.to_str()).unwrap_or("wt");
    let wt_path = base.parent().unwrap().join(format!("{name}-{unique}"));
    git_ok(base, &[
        "worktree", "add", wt_path.to_str().unwrap(), "-b", branch,
    ]);
    wt_path
}

fn data_store_path(repo_root: &Path, task_id: &str) -> PathBuf {
    repo_root.join(".git/brana/time").join(format!("{task_id}.jsonl"))
}

/// Encode a project root the same way `session.rs::encode_path` does (spec's "which
/// transcript file" resolution): `/` and `_` both become `-`.
fn encode_project_path(project_root: &str) -> String {
    project_root.replace('/', "-").replace('_', "-")
}

/// Legacy CC encoding (`/` only, underscores preserved) — matches
/// `commands/time.rs::encode_project_path_legacy` / `commands/handoff.rs::encode_path_legacy`.
fn encode_project_path_legacy(project_root: &str) -> String {
    project_root.replace('/', "-")
}

/// Fabricate a Claude Code session transcript for `worktree_root`'s own resolved
/// project root (its `git rev-parse --show-toplevel`, which differs per worktree —
/// each worktree is its own "project" from the invoked CLI subprocess's point of
/// view) inside `home`'s `.claude/projects/` tree, so `time close` invoked with that
/// worktree as cwd has a resolvable transcript. Multiple worktrees can share one
/// `home` — each gets its own encoded subdirectory, never colliding.
fn add_fake_transcript(home: &Path, worktree_root: &Path) {
    let project_root = git_ok(worktree_root, &["rev-parse", "--show-toplevel"]);
    let encoded = encode_project_path(&project_root);
    let project_dir = home.join(".claude/projects").join(&encoded);
    std::fs::create_dir_all(&project_dir).unwrap();
    let lines = [
        r#"{"timestamp":"2026-08-17T10:00:00.000Z","type":"user"}"#,
        r#"{"timestamp":"2026-08-17T10:00:05.000Z","type":"assistant"}"#,
        r#"{"timestamp":"2026-08-17T10:00:12.000Z","type":"assistant"}"#,
    ];
    std::fs::write(project_dir.join("fake-session.jsonl"), lines.join("\n") + "\n").unwrap();
}

/// Same as [`add_fake_transcript`], but under the LEGACY encoding only (`/`-only,
/// underscores preserved) — for `e1`, which asserts the fallback path in
/// `commands/time.rs::resolve_newest_transcript` actually resolves a transcript when
/// only the legacy-encoded directory exists.
fn add_fake_transcript_legacy(home: &Path, worktree_root: &Path) {
    let project_root = git_ok(worktree_root, &["rev-parse", "--show-toplevel"]);
    let encoded = encode_project_path_legacy(&project_root);
    let project_dir = home.join(".claude/projects").join(&encoded);
    std::fs::create_dir_all(&project_dir).unwrap();
    let lines = [
        r#"{"timestamp":"2026-08-17T10:00:00.000Z","type":"user"}"#,
        r#"{"timestamp":"2026-08-17T10:00:05.000Z","type":"assistant"}"#,
    ];
    std::fs::write(project_dir.join("fake-session.jsonl"), lines.join("\n") + "\n").unwrap();
}

/// Rung-2 verify-stage catch (2026-08-17): every test whose `time close` call is
/// meant to succeed must run with `HOME` overridden to a tempdir containing a real
/// (fabricated) transcript — the original tests asserted `close` succeeds with no
/// transcript fixture anywhere, silently contradicting this spec's own "fail closed
/// on unresolvable transcript path" boundary.
fn brana_with_home(dir: &Path, home: &Path) -> Command {
    let mut cmd = brana(dir);
    cmd.env("HOME", home);
    cmd
}

// ---- Group A: serialized-bracket rejection, scoped per-worktree -----------------

#[test]
fn a1_second_start_in_same_worktree_is_rejected() {
    let tmp = repo();
    // First start should succeed (once implemented) and open the bracket.
    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();
    // A second start for a DIFFERENT task_id in the SAME worktree, while the first
    // bracket is still open, must be rejected — one open bracket per worktree.
    brana(tmp.path())
        .args(["time", "start", "t-2"])
        .assert()
        .failure();
}

/// Rung-2 concurrency-lock finder catch (2026-08-17): `a1` above is sequential — the
/// first call fully completes before the second is even constructed, so it cannot
/// distinguish a real TOCTOU-safe lock from a naive unlocked check-then-write. This
/// test fires two `time start` calls at the SAME worktree with no serialization
/// between them (a `Barrier` holds both threads until both are ready to launch their
/// subprocess), asserting exactly one succeeds — the actual invariant the per-worktree
/// lock exists to protect.
#[test]
fn a4_concurrent_starts_in_same_worktree_exactly_one_succeeds() {
    let tmp = repo();
    let root = tmp.path().to_path_buf();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(2));

    let handles: Vec<_> = ["t-race-a", "t-race-b"]
        .iter()
        .map(|task_id| {
            let root = root.clone();
            let barrier = barrier.clone();
            let task_id = task_id.to_string();
            std::thread::spawn(move || {
                barrier.wait();
                brana(&root).args(["time", "start", &task_id]).ok().is_ok()
            })
        })
        .collect();
    let successes: usize = handles.into_iter().map(|h| h.join().unwrap()).filter(|ok| *ok).count();
    assert_eq!(
        successes, 1,
        "expected exactly one concurrent `time start` to win the same-worktree lock"
    );
}

#[test]
fn a2_start_after_close_succeeds() {
    let tmp = repo();
    let home = tempfile::TempDir::new().unwrap();
    add_fake_transcript(home.path(), tmp.path());
    brana_with_home(tmp.path(), home.path()).args(["time", "start", "t-1"]).assert().success();
    brana_with_home(tmp.path(), home.path()).args(["time", "close", "t-1"]).assert().success();
    // Bracket closed -> a new start (even for a different task_id) must succeed.
    brana_with_home(tmp.path(), home.path()).args(["time", "start", "t-2"]).assert().success();
}

#[test]
fn a3_different_worktrees_different_task_ids_both_succeed_independently() {
    let tmp = repo();
    let wt = add_worktree(tmp.path(), "wt2", "feat/other");
    // Two different worktrees, two different task_ids, concurrently — must not block
    // each other. This is the redesign's whole point: --git-dir is worktree-unique.
    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();
    brana(&wt).args(["time", "start", "t-2"]).assert().success();
}

// ---- Group B: atomic concurrent-write stress test (queue.rs-shaped) -------------

#[test]
fn b1_concurrent_writers_distinct_task_ids_no_corruption() {
    let tmp = repo();
    let root = tmp.path().to_path_buf();
    let home = tempfile::TempDir::new().unwrap();
    let home_path = home.path().to_path_buf();
    let n = 6;
    // Pre-create all N worktrees (+ their transcript fixtures) SEQUENTIALLY first,
    // outside the timed region — `git worktree add`'s own internal repo-state locking
    // (rung-2 concurrency-lock finder, 2026-08-17) otherwise staggers thread start
    // times enough to reduce genuine overlap at the shared brana/time/ writes,
    // weakening this test's evidentiary value. A Barrier then holds all N threads
    // until every worktree exists and every thread is ready, so the actual
    // start+close calls fire as close to simultaneously as possible — that's the
    // thing under test, not worktree/fixture setup.
    let worktrees: Vec<PathBuf> = (0..n)
        .map(|i| {
            let wt = add_worktree(&root, &format!("wt-b{i}"), &format!("feat/b{i}"));
            add_fake_transcript(&home_path, &wt);
            wt
        })
        .collect();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(n));
    let handles: Vec<_> = worktrees
        .into_iter()
        .enumerate()
        .map(|(i, wt)| {
            let barrier = barrier.clone();
            let home_path = home_path.clone();
            std::thread::spawn(move || {
                let task_id = format!("t-b{i}");
                barrier.wait();
                brana_with_home(&wt, &home_path).args(["time", "start", &task_id]).assert().success();
                brana_with_home(&wt, &home_path).args(["time", "close", &task_id]).assert().success();
                task_id
            })
        })
        .collect();
    let task_ids: Vec<String> = handles.into_iter().map(|h| h.join().unwrap()).collect();

    // Every task_id's data file must exist, contain exactly one well-formed Start and
    // one well-formed Close line, with no interleaved/corrupted bytes from another
    // writer's concurrent append.
    for task_id in &task_ids {
        let path = data_store_path(&root, task_id);
        let content = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("missing data file for {task_id}: {e}"));
        let lines: Vec<&str> = content.lines().filter(|l| !l.trim().is_empty()).collect();
        assert_eq!(lines.len(), 2, "{task_id}: expected exactly 2 lines, got {lines:?}");
        for line in &lines {
            let _: serde_json::Value = serde_json::from_str(line)
                .unwrap_or_else(|e| panic!("{task_id}: corrupt JSONL line {line:?}: {e}"));
        }
    }
}

/// Rung-2 verify-stage catch (2026-08-17): `b1` above writes each concurrent thread
/// to a DISTINCT `task_id`'s own file — trivially safe regardless of write strategy,
/// since the writers never touch the same file. The many-sub-spans bracket model
/// (ADR-083) makes concurrent writers to the SAME `task_id` (same worktree, resumed
/// across sessions, or — the actual near-term case — this same test process racing
/// to append `Start`/`Close` pairs for one bracket) a real scenario the append shape
/// must survive. This test drives that directly at the pure-append layer: N threads
/// each append one well-formed, independently-serialized line to the SAME
/// `<task_id>.jsonl`, synchronized via `Barrier` so the writes genuinely race.
#[test]
fn b2_concurrent_writers_same_task_id_no_corruption() {
    let tmp = repo();
    let root = tmp.path().to_path_buf();
    let path = data_store_path(&root, "t-shared");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, "").unwrap();
    let n = 8;
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(n));
    let handles: Vec<_> = (0..n)
        .map(|i| {
            let path = path.clone();
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                // One pre-serialized buffer, ONE write_all call — the exact invariant
                // under test (verify-stage catch, iteration 2: the first draft did two
                // separate write_all calls per line, the same multi-syscall hazard
                // class as writeln!, just coarser).
                let mut line = serde_json::json!({
                    "version": 1, "kind": "note", "task_id": "t-shared", "writer": i
                })
                .to_string();
                line.push('\n');
                barrier.wait();
                use std::io::Write;
                let mut f = std::fs::OpenOptions::new().append(true).open(&path).unwrap();
                f.write_all(line.as_bytes()).unwrap();
            })
        })
        .collect();
    for h in handles {
        h.join().unwrap();
    }
    let content = std::fs::read_to_string(&path).unwrap();
    let lines: Vec<&str> = content.lines().filter(|l| !l.trim().is_empty()).collect();
    assert_eq!(lines.len(), n, "expected exactly {n} lines, got {}: {lines:?}", lines.len());
    for line in &lines {
        let _: serde_json::Value = serde_json::from_str(line)
            .unwrap_or_else(|e| panic!("corrupt/interleaved JSONL line {line:?}: {e}"));
    }
}

// ---- Group C: H2 git-env-leak test ------------------------------------------------

#[test]
fn c1_leaked_git_dir_does_not_relocate_the_data_store() {
    let tmp = repo();
    let foreign = tempfile::TempDir::new().unwrap();
    git_ok(foreign.path(), &["init", "-q", "-b", "main"]);

    // Simulate being invoked from a git hook, which exports GIT_DIR.
    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(tmp.path())
        .env("GIT_DIR", foreign.path().join(".git"))
        .args(["time", "start", "t-1"]);
    cmd.assert().success();

    // The bracket must land in tmp's own store, never the foreign repo's.
    assert!(
        data_store_path(tmp.path(), "t-1").exists(),
        "GIT_DIR leaked — data store not written to the correct (real) repo"
    );
    assert!(
        !foreign.path().join(".git/brana").exists(),
        "GIT_DIR leaked — the foreign repo was touched"
    );
}

#[test]
fn c2_leaked_git_dir_does_not_relocate_the_open_bracket_lock() {
    // Same hazard, but for the --git-dir-resolved lock file rather than the
    // --git-common-dir-resolved data store — the two resolve differently and both
    // need independent H2 coverage per the spec's Testing Strategy.
    let tmp = repo();
    let foreign = tempfile::TempDir::new().unwrap();
    git_ok(foreign.path(), &["init", "-q", "-b", "main"]);

    let mut cmd = Command::cargo_bin("brana").unwrap();
    cmd.current_dir(tmp.path())
        .env("GIT_DIR", foreign.path().join(".git"))
        .args(["time", "start", "t-1"]);
    cmd.assert().success();

    let real_lock = tmp.path().join(".git/brana-time-open-bracket.json");
    assert!(real_lock.exists(), "open-bracket lock not written to the correct repo");
}

// ---- Group D: corrupt-store-not-clobbered ----------------------------------------

/// Rung-2 design fix (2026-08-17): the data store is a blind `O_APPEND` log (see
/// spec Decision #2), not a read-modify-write document — appending a new line never
/// needs to parse or validate what's already in the file, so a pre-existing corrupt
/// line does NOT block a new bracket from opening (unlike `queue.rs`'s
/// `parse_before_write_never_clobbers_corrupt_store`, which applies to the
/// LOCK file's read-modify-write, not this file). What must hold: the append succeeds,
/// the corrupt prefix is never truncated/rewritten, and the new line is well-formed —
/// data-quality issues in old lines are an aggregation-time concern (a later,
/// unbuilt task), not a write-time one.
#[test]
fn d1_corrupt_data_store_does_not_block_append_and_is_never_truncated() {
    let tmp = repo();
    let path = data_store_path(tmp.path(), "t-1");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, "{not valid jsonl at all\n").unwrap();

    brana(tmp.path()).args(["time", "start", "t-1"]).assert().success();

    let content = std::fs::read_to_string(&path).unwrap();
    assert!(
        content.starts_with("{not valid jsonl at all\n"),
        "the pre-existing corrupt line was truncated or rewritten: {content:?}"
    );
    let appended: Vec<&str> = content
        .lines()
        .skip(1)
        .filter(|l| !l.trim().is_empty())
        .collect();
    assert_eq!(appended.len(), 1, "expected exactly one new line appended: {content:?}");
    let _: serde_json::Value = serde_json::from_str(appended[0])
        .unwrap_or_else(|e| panic!("appended line is not valid JSON: {e}"));
}

/// A lock file left behind by a crash (a `Start` that never got `Close`d — no OS
/// mechanism reclaims ordinary file content, unlike the transient `lock_sidecar`
/// flock which the kernel releases on process death). The next `time start`/`close`
/// in that worktree must produce a clean, named-cause outcome, not a silent hang or
/// an unrelated crash.
#[test]
fn d2_stale_open_bracket_lock_after_crash_is_handled_cleanly() {
    let tmp = repo();
    let home = tempfile::TempDir::new().unwrap();
    add_fake_transcript(home.path(), tmp.path());
    let project_root = git_ok(tmp.path(), &["rev-parse", "--show-toplevel"]);
    let encoded = encode_project_path(&project_root);
    let transcript_path = home
        .path()
        .join(".claude/projects")
        .join(&encoded)
        .join("fake-session.jsonl");

    let lock_path = tmp.path().join(".git/brana-time-open-bracket.json");
    std::fs::write(
        &lock_path,
        serde_json::json!({
            "task_id": "t-crashed",
            "opened_at": "2020-01-01T00:00:00Z",
            "transcript_path": transcript_path.to_string_lossy(),
        })
        .to_string(),
    )
    .unwrap();

    // A start for a DIFFERENT task_id must be refused — the stale lock still says a
    // bracket is open, exactly as if the crashed session were still running.
    brana_with_home(tmp.path(), home.path()).args(["time", "start", "t-1"]).assert().failure();

    // Closing the crashed task_id's own bracket must succeed (reads transcript_path
    // back from the lock, per spec's "snapshot, don't re-resolve") and clear the
    // lock, regardless of how long ago `opened_at` claims it was opened.
    brana_with_home(tmp.path(), home.path())
        .args(["time", "close", "t-crashed"])
        .assert()
        .success();
    assert!(!lock_path.exists(), "stale lock not cleared after closing its own task_id");
}

/// The Boundaries table's "Always: fail closed on an unresolvable transcript path".
/// START succeeds with a real transcript present (so it has something to snapshot
/// into the lock's `transcript_path`); the file is then deleted before CLOSE runs —
/// CLOSE must read the *recorded* path back (spec: "snapshot, don't re-resolve") and
/// fail when it's gone, not silently re-resolve a different transcript or succeed
/// with a zero/garbage duration.
#[test]
fn d3_close_with_deleted_recorded_transcript_fails_closed() {
    let tmp = repo();
    let home = tempfile::TempDir::new().unwrap();
    add_fake_transcript(home.path(), tmp.path());
    let project_root = git_ok(tmp.path(), &["rev-parse", "--show-toplevel"]);
    let encoded = encode_project_path(&project_root);
    let transcript_path = home.path().join(".claude/projects").join(&encoded).join("fake-session.jsonl");

    brana_with_home(tmp.path(), home.path()).args(["time", "start", "t-1"]).assert().success();
    std::fs::remove_file(&transcript_path).unwrap();
    brana_with_home(tmp.path(), home.path())
        .args(["time", "close", "t-1"])
        .assert()
        .failure();
}

/// Verify-stage catch, iteration 2 (2026-08-17): the redesign's headline claim —
/// "CLOSE reads the recorded `transcript_path`; a second session becoming
/// newest-mtime between START and CLOSE cannot redirect it" — had zero coverage.
/// This proves it directly, decoupled from real duration-computation values (nothing
/// is implemented yet): after START records the *valid* transcript's path, a second,
/// NEWER `.jsonl` is written into the same fake project directory with deliberately
/// unparseable content. If a future implementation regresses to "always re-resolve
/// newest mtime at CLOSE" (the exact mistake this design exists to prevent), it would
/// try to read the broken newer file and fail; reading the recorded (valid, older)
/// path succeeds regardless of what else exists in the directory.
#[test]
fn d4_close_reads_recorded_transcript_not_newest_mtime() {
    let tmp = repo();
    let home = tempfile::TempDir::new().unwrap();
    add_fake_transcript(home.path(), tmp.path());
    let project_root = git_ok(tmp.path(), &["rev-parse", "--show-toplevel"]);
    let encoded = encode_project_path(&project_root);
    let project_dir = home.path().join(".claude/projects").join(&encoded);

    brana_with_home(tmp.path(), home.path()).args(["time", "start", "t-1"]).assert().success();

    // A second, strictly-newer .jsonl with content that would fail to parse as a
    // transcript — if CLOSE mistakenly re-resolves "newest mtime" instead of reading
    // the path START recorded, it reaches this file and must fail; it doesn't.
    std::thread::sleep(std::time::Duration::from_millis(10));
    std::fs::write(project_dir.join("newer-but-broken-session.jsonl"), "not a transcript at all").unwrap();

    brana_with_home(tmp.path(), home.path())
        .args(["time", "close", "t-1"])
        .assert()
        .success();
}

// ---- Group E: legacy-encoding fallback (Challenger iteration-1 finding) ----------

/// Challenger iteration-1 finding (2026-08-18): `resolve_newest_transcript` added a
/// legacy-encoding fallback (`/`-only, underscores preserved) mirroring
/// `commands/handoff.rs`'s proven `encode_path`/`encode_path_legacy` pattern, but
/// nothing exercised the fallback branch itself — the repo fixture never produced a
/// project root containing `_`, so current- and legacy-encoded paths were always
/// identical in every other test. `repo_named` with an underscore-bearing prefix
/// forces them to differ; only the legacy-encoded directory gets a transcript, so
/// `time close` succeeding here is possible only via the fallback branch.
#[test]
fn e1_legacy_encoded_project_dir_transcript_still_resolves() {
    let tmp = repo_named("time_smoke_legacy_");
    let home = tempfile::TempDir::new().unwrap();
    add_fake_transcript_legacy(home.path(), tmp.path());

    // Sanity: this fixture's project root really does contain `_`, so current and
    // legacy encodings genuinely differ — otherwise this test would pass for the
    // wrong reason (both paths resolving to the same directory).
    let project_root = git_ok(tmp.path(), &["rev-parse", "--show-toplevel"]);
    assert_ne!(
        encode_project_path(&project_root),
        encode_project_path_legacy(&project_root),
        "fixture project root has no '_' — this test can't distinguish the fallback from the primary path"
    );

    brana_with_home(tmp.path(), home.path()).args(["time", "start", "t-1"]).assert().success();
    brana_with_home(tmp.path(), home.path())
        .args(["time", "close", "t-1"])
        .assert()
        .success();
}
