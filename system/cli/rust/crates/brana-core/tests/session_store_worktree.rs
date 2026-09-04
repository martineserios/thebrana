//! Session-store parity across git worktrees (ADR-069 D0b, t-2528 / t-2520).
//!
//! The store lives at `<store_root>/<encoded-project-root>/memory/`. If the project root
//! is resolved per-worktree, every linked worktree gets its own store and sees zero of the
//! main checkout's lanes — measured live 2026-07-28: `session read --all` returned 24 from
//! the main checkout and 0 from a linked worktree.
//!
//! These tests build a real temp repo with real `git worktree add` linked worktrees, and
//! inject the store root so nothing touches the operator's `~/.claude/projects` tree.

use brana_core::session::{lane_state_paths, resolve_memory_dir_in};
use brana_core::util::find_session_root_in;
use std::path::{Path, PathBuf};
use std::process::Command;

fn git(dir: &Path, args: &[&str]) {
    let mut cmd = Command::new("git");
    brana_core::util::scrub_git_env(&mut cmd);
    let out = cmd
        .current_dir(dir)
        .args(args)
        .output()
        .unwrap_or_else(|e| panic!("git {args:?} failed to spawn: {e}"));
    assert!(
        out.status.success(),
        "git {args:?} in {} failed: {}",
        dir.display(),
        String::from_utf8_lossy(&out.stderr)
    );
}

/// Create a committed repo at `root` and return its canonicalized path.
fn init_repo(root: &Path) -> PathBuf {
    std::fs::create_dir_all(root).unwrap();
    git(root, &["init", "-b", "main"]);
    git(root, &["config", "user.email", "test@example.invalid"]);
    git(root, &["config", "user.name", "test"]);
    git(root, &["config", "commit.gpgsign", "false"]);
    std::fs::write(root.join("README.md"), "seed\n").unwrap();
    git(root, &["add", "."]);
    git(root, &["commit", "-m", "seed", "--no-verify"]);
    root.canonicalize().unwrap()
}

fn add_worktree(main: &Path, path: &Path, branch: &str) -> PathBuf {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    git(
        main,
        &["worktree", "add", "-b", branch, path.to_str().unwrap()],
    );
    path.canonicalize().unwrap()
}

fn write_lane(store: &Path, root: &Path, file: &str, epic: Option<&str>) {
    let dir = resolve_memory_dir_in(store, root);
    std::fs::create_dir_all(&dir).unwrap();
    let epic_field = match epic {
        Some(e) => format!("\"{e}\""),
        None => "null".to_string(),
    };
    std::fs::write(
        dir.join(file),
        format!(
            r#"{{"version":1,"written_at":"2026-09-03T00:00:00Z","epic":{epic_field},"accomplished":[],"next":[]}}"#
        ),
    )
    .unwrap();
}

fn lane_names(store: &Path, root: &Path) -> Vec<String> {
    lane_state_paths(&resolve_memory_dir_in(store, root))
        .iter()
        .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
        .collect()
}

/// t-2528 (RED before t-2520): a linked worktree must enumerate the same lanes as the
/// main checkout, because both must resolve to the same store directory.
#[test]
fn session_store_enumerates_identically_from_main_checkout_and_worktree() {
    let tmp = tempfile::tempdir().unwrap();
    let store = tmp.path().join("store");
    let main = init_repo(&tmp.path().join("repo"));
    let lane = add_worktree(&main, &tmp.path().join("repo-lane"), "epic/feat/t-1-lane");

    let main_root = find_session_root_in(Some(&main)).expect("main checkout resolves a root");
    let lane_root = find_session_root_in(Some(&lane)).expect("worktree resolves a root");

    // One state written from the main checkout — the worktree must see it.
    write_lane(&store, &main_root, "session-state.json", None);

    assert_eq!(
        main_root,
        lane_root,
        "session store root must be identical from the main checkout ({}) and its linked \
         worktree ({}); per-worktree resolution splits the store",
        main.display(),
        lane.display()
    );
    assert_eq!(
        lane_names(&store, &main_root),
        lane_names(&store, &lane_root),
        "lane enumeration must be identical from main checkout and worktree"
    );
    assert_eq!(
        lane_names(&store, &lane_root),
        vec!["session-state.json".to_string()],
        "worktree must see the lane written from the main checkout"
    );
}

/// t-2520 AC: 5-8 concurrent worktree lanes all land in, and are visible from, one store.
#[test]
fn six_worktree_lanes_share_one_store_and_are_visible_from_every_lane() {
    let tmp = tempfile::tempdir().unwrap();
    let store = tmp.path().join("store");
    let main = init_repo(&tmp.path().join("repo"));

    let mut roots = vec![find_session_root_in(Some(&main)).expect("main root")];
    let mut expected = vec!["session-state.json".to_string()];
    write_lane(&store, &roots[0], "session-state.json", None);

    for i in 1..=6 {
        let slug = format!("lane{i}");
        let wt = add_worktree(
            &main,
            &tmp.path().join(format!("repo-{slug}")),
            &format!("{slug}/feat/t-{i}-work"),
        );
        let root = find_session_root_in(Some(&wt)).expect("worktree root");
        write_lane(&store, &root, &format!("session-state-{slug}.json"), Some(&slug));
        expected.push(format!("session-state-{slug}.json"));
        roots.push(root);
    }

    expected.sort();
    for root in &roots {
        let mut got = lane_names(&store, root);
        got.sort();
        assert_eq!(
            got, expected,
            "every lane must enumerate all 7 states from the shared store"
        );
    }
}

/// t-2520 AC: a per-worktree store orphaned by the move to common-root keying must be
/// discoverable, not silently stranded. This is the shape of the real one in the wild:
/// `<canonical>-feat-t-798/memory/` holding a state file whose worktree no longer exists.
#[test]
fn orphaned_per_worktree_store_is_discovered_as_a_legacy_lane() {
    use brana_core::session::{find_legacy_stores, LegacyStore};

    let tmp = tempfile::tempdir().unwrap();
    let store = tmp.path().join("store");
    let main = init_repo(&tmp.path().join("repo"));

    // Canonical store — must never be reported as its own orphan.
    write_lane(&store, &main, "session-state.json", None);

    // Orphan: the encoded dir of a worktree that has since been removed.
    let ghost = main.parent().unwrap().join("repo-feat-t-798");
    write_lane(&store, &ghost, "session-state.json", None);

    // A sibling store with no state files at all is not a lane and must be skipped.
    std::fs::create_dir_all(resolve_memory_dir_in(&store, &main.parent().unwrap().join("repo-empty")))
        .unwrap();

    let found = find_legacy_stores(&store, &main);
    assert_eq!(
        found,
        vec![LegacyStore {
            slug: "feat-t-798".to_string(),
            memory_dir: resolve_memory_dir_in(&store, &ghost),
        }],
        "the orphaned per-worktree store must be surfaced, and only it"
    );
}

/// t-3278: an empty canonical root must match nothing. When the project root resolved to
/// the empty path (relative `.git` from the main checkout, left unresolved), the prefix
/// collapsed to a bare `-` and every store on the machine — 13,000+ of them, from
/// unrelated projects — came back as a `legacy:` lane.
#[test]
fn empty_project_root_discovers_no_legacy_stores() {
    use brana_core::session::find_legacy_stores;

    let tmp = tempfile::tempdir().unwrap();
    let store = tmp.path().join("store");
    write_lane(&store, Path::new("/some/unrelated/project"), "session-state.json", None);
    write_lane(&store, Path::new("/tmp/.tmpXYZ"), "session-state.json", None);

    assert!(
        find_legacy_stores(&store, Path::new("")).is_empty(),
        "an empty canonical root must not be treated as a prefix of every store"
    );
}

/// A live linked worktree that already wrote state under the old per-worktree keying is
/// the same orphan case — it must surface too, and the canonical store must be unaffected.
#[test]
fn live_worktree_orphan_surfaces_without_polluting_the_canonical_store() {
    use brana_core::session::find_legacy_stores;

    let tmp = tempfile::tempdir().unwrap();
    let store = tmp.path().join("store");
    let main = init_repo(&tmp.path().join("repo"));
    let lane = add_worktree(&main, &tmp.path().join("repo-old"), "old/feat/t-2-x");

    write_lane(&store, &main, "session-state.json", None);
    write_lane(&store, &lane, "session-state-old.json", Some("old"));

    let slugs: Vec<String> = find_legacy_stores(&store, &main)
        .into_iter()
        .map(|s| s.slug)
        .collect();
    assert_eq!(slugs, vec!["old".to_string()]);
    assert_eq!(
        lane_names(&store, &main),
        vec!["session-state.json".to_string()],
        "the canonical store must not absorb legacy files implicitly"
    );
}
