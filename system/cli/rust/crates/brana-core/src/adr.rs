//! ADR number reservation — flock-based, shared across git worktrees (t-3294).
//!
//! ADR authoring was previously fully manual (`ls docs/architecture/decisions/ | tail`),
//! with no serialization between concurrent sessions. Two independent sessions collided on
//! ADR-091 the same day (t-3290). A spike proved a shared `flock` alone is not enough: each
//! `git worktree` checkout has its own local, uncommitted copy of the tracked decisions
//! directory, so a directory scan under a correctly-shared lock still races — the lock
//! serializes *when* two sessions run, not *what they see*. The fix moves the counter into a
//! registry file at the shared session root ([`crate::util::find_session_root`], ADR-069
//! D0b — identical from every linked worktree) instead of scanning the per-worktree tracked
//! directory on every call.

use crate::util::{find_session_root, lock_sidecar_timeout, write_json_atomic, DEFAULT_LOCK_TIMEOUT};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize, Default)]
struct AdrRegistry {
    highest: u32,
}

fn registry_path(shared_root: &Path) -> PathBuf {
    shared_root.join(".claude/adr-registry.json")
}

/// Reserve the next ADR number. `decisions_dir` (the worktree-local, tracked
/// `docs/architecture/decisions/` directory) is read only to BOOTSTRAP the registry the
/// first time it's created; every reservation after that reads/writes the registry file,
/// never the directory, so a stale per-worktree view can't cause a collision.
///
/// The whole reserve-and-persist step runs under one lock (t-3290: a reservation that only
/// updated in-memory state before releasing the lock would leave the same gap the
/// directory-scan version had) and does no I/O beyond two small file operations — no
/// network, no subprocess — so it can't turn into the inherited-lock blast-radius problem
/// documented in `pattern_no-new-io-under-inherited-lock`.
pub fn reserve_next_adr_number(decisions_dir: &Path) -> Result<u32, String> {
    let shared_root =
        find_session_root().ok_or("could not resolve shared session root (git-common-dir)")?;
    reserve_next_adr_number_at(&shared_root, decisions_dir)
}

/// Testable variant of [`reserve_next_adr_number`] — takes the shared root directly instead
/// of resolving it via `find_session_root()`, which shells out to `git` and (via the
/// `CLAUDE_PROJECT_DIR` hint) would otherwise require racy global-env-var manipulation to
/// isolate concurrent tests from each other and from the real repo (see `git_common_root_in`
/// / `find_tasks_file_with_hint` for the same testable-variant convention elsewhere in this
/// module).
fn reserve_next_adr_number_at(shared_root: &Path, decisions_dir: &Path) -> Result<u32, String> {
    let reg_path = registry_path(shared_root);

    let _guard = lock_sidecar_timeout(&reg_path, DEFAULT_LOCK_TIMEOUT)?;

    let mut registry: AdrRegistry = if reg_path.exists() {
        let content =
            std::fs::read_to_string(&reg_path).map_err(|e| format!("read registry failed: {e}"))?;
        serde_json::from_str(&content).unwrap_or_default()
    } else {
        AdrRegistry {
            highest: highest_existing_adr_number(decisions_dir),
        }
    };

    registry.highest += 1;
    let next = registry.highest;
    write_json_atomic(&reg_path, &registry)?;

    Ok(next)
}

fn highest_existing_adr_number(decisions_dir: &Path) -> u32 {
    let Ok(entries) = std::fs::read_dir(decisions_dir) else {
        return 0;
    };
    entries
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().to_str().map(str::to_string))
        .filter_map(|name| {
            name.strip_prefix("ADR-")
                .and_then(|rest| rest.split(['-', '.']).next())
                .and_then(|n| n.parse::<u32>().ok())
        })
        .max()
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Barrier};

    fn isolated_root() -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().expect("tempdir");
        let root = dir.path().to_path_buf();
        (dir, root)
    }

    fn seed_decisions_dir(root: &Path, numbers: &[u32]) -> PathBuf {
        let dir = root.join("docs/architecture/decisions");
        std::fs::create_dir_all(&dir).unwrap();
        for n in numbers {
            std::fs::write(dir.join(format!("ADR-{n:03}-fake.md")), "").unwrap();
        }
        dir
    }

    #[test]
    fn bootstraps_from_highest_existing_file_on_first_call() {
        let (_guard, root) = isolated_root();
        let decisions = seed_decisions_dir(&root, &[89, 90, 91, 92]);

        let reserved =
            reserve_next_adr_number_at(&root, &decisions).expect("reserve should succeed");

        assert_eq!(reserved, 93, "first reservation after seed 92 should be 93");
    }

    #[test]
    fn second_call_reads_the_registry_not_the_stale_directory() {
        let (_guard, root) = isolated_root();
        let decisions = seed_decisions_dir(&root, &[92]);

        let first = reserve_next_adr_number_at(&root, &decisions).expect("first reserve");
        assert_eq!(first, 93);

        // Second reservation happens WITHOUT a new ADR-093 file ever landing in
        // `decisions` (simulating: the placeholder was written in a different worktree
        // and not yet merged/pulled here). If this read the directory again it would
        // still see max=92 and collide on 93.
        let second = reserve_next_adr_number_at(&root, &decisions).expect("second reserve");
        assert_eq!(second, 94, "must not re-derive 93 from the stale directory scan");
    }

    #[test]
    fn twenty_way_concurrent_reservation_has_no_collisions_or_gaps() {
        let (_guard, root) = isolated_root();
        let decisions = seed_decisions_dir(&root, &[92]);

        const N: usize = 20;
        let barrier = Arc::new(Barrier::new(N));
        let handles: Vec<_> = (0..N)
            .map(|_| {
                let root = root.clone();
                let decisions = decisions.clone();
                let barrier = Arc::clone(&barrier);
                std::thread::spawn(move || {
                    barrier.wait(); // maximize actual concurrent contention
                    reserve_next_adr_number_at(&root, &decisions).expect("reserve should not fail")
                })
            })
            .collect();

        let mut results: Vec<u32> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        results.sort_unstable();

        let expected: Vec<u32> = (93..=(92 + N as u32)).collect();
        assert_eq!(
            results, expected,
            "20 concurrent reservations must be exactly 93..=112 with no dupes or gaps"
        );
    }

    #[test]
    fn empty_decisions_dir_bootstraps_from_zero() {
        let (_guard, root) = isolated_root();
        let decisions = root.join("docs/architecture/decisions");
        std::fs::create_dir_all(&decisions).unwrap();

        let reserved =
            reserve_next_adr_number_at(&root, &decisions).expect("reserve should succeed");

        assert_eq!(reserved, 1);
    }
}
