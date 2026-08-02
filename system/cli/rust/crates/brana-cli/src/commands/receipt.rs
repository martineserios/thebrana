//! `brana receipt mint|validate` — build receipts as executed evidence (t-2593, ADR-076).
//!
//! All pure logic lives in `brana_core::receipt`. This module is the I/O half: git
//! re-derivation, subprocess execution, and the on-disk store. Keeping the split means
//! the comparison never sees a repo handle.
//!
//! Spec: `docs/architecture/features/build-receipts.md`.

use anyhow::{anyhow, bail, Result};
use brana_core::receipt::{
    ac_digest, compare, parse_receipt, paths_digest, sha256_hex, to_canonical_json,
    validate_structure, DerivedFacts, Execution, GateResult, Outcome, Receipt, RepoBinding, SCHEMA,
};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Exit codes. Distinct per gate result so a hook can branch without parsing stdout.
pub const EXIT_SCOPE_CHANGED: i32 = 3;
pub const EXIT_INVALIDATED: i32 = 4;

/// Git's hook environment overrides path-based repo discovery, and `cd` does not protect
/// you (`pattern_git-hook-env-leaks-into-executed-tests`; live failure 2026-08-01, t-2501).
/// Both our own git calls and — critically — the command we execute must run with these
/// cleared, or a test with git fixtures operates on the real repository.
const GIT_ENV: [&str; 6] = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_COMMON_DIR",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
];

fn scrub(c: &mut Command) -> &mut Command {
    for k in GIT_ENV {
        c.env_remove(k);
    }
    c
}

fn git_in(dir: &Path, args: &[&str]) -> Result<String> {
    let out = scrub(Command::new("git").current_dir(dir).args(args)).output()?;
    if !out.status.success() {
        bail!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn git_ok(dir: &Path, args: &[&str]) -> bool {
    scrub(Command::new("git").current_dir(dir).args(args))
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn repo_root() -> Result<PathBuf> {
    let cwd = std::env::current_dir()?;
    Ok(PathBuf::from(git_in(&cwd, &["rev-parse", "--show-toplevel"])?))
}

/// The store lives under `--git-common-dir`, never `.git`: one authority shared across
/// linked worktrees, invisible to `git status`, never pushed.
fn store_dir(root: &Path) -> Result<PathBuf> {
    let common = git_in(root, &["rev-parse", "--git-common-dir"])?;
    let common = if Path::new(&common).is_absolute() {
        PathBuf::from(common)
    } else {
        root.join(common)
    };
    Ok(common.join("brana/receipts"))
}

fn receipt_path(root: &Path, task_id: &str) -> Result<PathBuf> {
    Ok(store_dir(root)?.join(format!("{task_id}.json")))
}

fn blob_path(root: &Path, task_id: &str, which: &str) -> Result<PathBuf> {
    Ok(store_dir(root)?.join(format!("{task_id}.{which}")))
}

/// Resolve tasks.json from the SCRUBBED repo root rather than through
/// `brana_core::util::find_tasks_file()`, which discovers via an unscrubbed
/// `git rev-parse --git-common-dir` and therefore follows a leaked `GIT_DIR` to a foreign
/// repository. Caught by `t16_leaked_git_dir_does_not_reach_the_executed_command`; the
/// general defect in `find_tasks_file()` is filed separately (t-2617).
fn tasks_file(root: &Path) -> Result<PathBuf> {
    let common = git_in(root, &["rev-parse", "--git-common-dir"])?;
    let common = if Path::new(&common).is_absolute() {
        PathBuf::from(common)
    } else {
        root.join(common)
    };
    // The main checkout's .claude/tasks.json is shared across linked worktrees.
    for candidate in [common.parent().map(|p| p.join(".claude/tasks.json")), Some(root.join(".claude/tasks.json"))]
        .into_iter()
        .flatten()
    {
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    bail!("tasks.json not found under {} — cannot derive ac_digest", root.display())
}

/// `AC:` lines from the task's `context`, verbatim, in file order.
fn task_ac_lines(root: &Path, task_id: &str) -> Result<Vec<String>> {
    let path = tasks_file(root)?;
    let tasks = brana_core::tasks::load_tasks(&path).map_err(|e| anyhow!(e))?;
    let task = tasks
        .tasks
        .iter()
        .find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| anyhow!("task {task_id} not found in {}", path.display()))?;
    let context = task["context"].as_str().unwrap_or("");
    Ok(context
        .lines()
        .map(str::trim)
        .filter(|l| l.starts_with("AC:"))
        .map(str::to_string)
        .collect())
}

/// Default integration branch: `dev`, falling back to `main`.
fn default_base(root: &Path) -> Result<String> {
    for candidate in ["dev", "main"] {
        if git_ok(root, &["rev-parse", "--verify", "--quiet", candidate]) {
            return Ok(candidate.to_string());
        }
    }
    bail!("no `dev` or `main` branch found — pass --base explicitly")
}

fn changed_paths(root: &Path, from: &str, to: &str) -> Result<Vec<String>> {
    let out = git_in(root, &["diff", "--name-only", &format!("{from}..{to}")])?;
    Ok(out.lines().filter(|l| !l.is_empty()).map(str::to_string).collect())
}

/// Tracked-file dirtiness. Untracked and gitignored files are deliberately ignored — the
/// receipt binds the tracked tree.
fn tracked_dirty(root: &Path) -> Result<bool> {
    Ok(!git_in(root, &["status", "--porcelain", "--untracked-files=no"])?.is_empty())
}

// ---------------------------------------------------------------------------- mint

pub fn cmd_mint(
    task_id: &str,
    command: Vec<String>,
    base: Option<String>,
    json: bool,
) -> Result<()> {
    let root = repo_root()?;
    let argv = if command.is_empty() {
        vec!["./validate.sh".to_string()]
    } else {
        command
    };

    // 1. A receipt over an unclean tree binds nothing.
    if tracked_dirty(&root)? {
        bail!("worktree has uncommitted tracked changes — commit or stash before minting");
    }

    // 2. Base is the MERGE-BASE, never the live branch ref. A live ref moves whenever
    //    another session merges, and paths_digest would then cover their changes too
    //    (spec H1; see pattern_soft-reset-onto-moved-ref-clobbers).
    let base_ref = match base {
        Some(b) => b,
        None => default_base(&root)?,
    };
    let base_commit = git_in(&root, &["merge-base", "HEAD", &base_ref])?;
    let base_tree = git_in(&root, &["rev-parse", &format!("{base_commit}^{{tree}}")])?;
    let candidate_commit = git_in(&root, &["rev-parse", "HEAD"])?;
    let candidate_tree = git_in(&root, &["rev-parse", "HEAD^{tree}"])?;

    // 3. Freeze the snapshot.
    let paths = changed_paths(&root, &base_commit, &candidate_commit)?;
    let p_digest = paths_digest(&paths);
    let a_digest = ac_digest(&task_ac_lines(&root, task_id)?);

    // Idempotency — content-bound, not a lock. Compare against the stored receipt itself.
    let path = receipt_path(&root, task_id)?;
    if path.exists() {
        let existing = parse_receipt(&std::fs::read_to_string(&path)?).map_err(|e| anyhow!(e))?;
        if existing.repo.candidate_commit == candidate_commit {
            if existing.execution.argv == argv {
                if json {
                    println!("{}", to_canonical_json(&existing));
                } else {
                    println!("receipt for {task_id} already minted at this candidate — no-op");
                }
                return Ok(());
            }
            bail!(
                "a receipt for {task_id} already exists at candidate {} with a different command \
                 ({:?} vs {:?}) — two commands cannot both attest the same candidate",
                &candidate_commit[..8.min(candidate_commit.len())],
                existing.execution.argv,
                argv
            );
        }
        // Different candidate: normal re-mint, supersede below.
    }

    // 4. Execute. No shell — argv is a vector, so nothing is word-split or glob-expanded.
    //    The git environment is scrubbed (H2) or a test with fixtures hijacks this repo.
    let started = std::time::Instant::now();
    let out = scrub(Command::new(&argv[0]).current_dir(&root).args(&argv[1..]))
        .output()
        .map_err(|e| anyhow!("failed to execute {:?}: {e}", argv))?;
    let duration_ms = started.elapsed().as_millis() as u64;
    let exit_code = out.status.code().unwrap_or(-1);

    // 5. Re-derive. If the command moved HEAD or touched tracked files, the tree that
    //    produced this output is not the tree we recorded — refuse rather than lie.
    if git_in(&root, &["rev-parse", "HEAD"])? != candidate_commit {
        bail!("the executed command moved HEAD — refusing to record a receipt over a tree it changed");
    }
    if tracked_dirty(&root)? {
        bail!("the executed command modified tracked files — refusing to record a receipt over a tree it changed");
    }

    // 6. Outcome is DERIVED. No input path reaches it (ADR-076 D1).
    let outcome = Outcome::from_exit_code(exit_code);

    let r = Receipt {
        ac_digest: a_digest,
        execution: Execution {
            argv: argv.clone(),
            cwd_rel: ".".to_string(),
            duration_ms,
            exit_code,
            output_bytes: (out.stdout.len() + out.stderr.len()) as u64,
            stderr_sha256: sha256_hex(&out.stderr),
            stdout_sha256: sha256_hex(&out.stdout),
        },
        minted_at: chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        outcome,
        repo: RepoBinding {
            base_commit,
            base_tree,
            candidate_commit,
            candidate_tree,
            paths_digest: p_digest,
        },
        schema: SCHEMA.to_string(),
        task_id: task_id.to_string(),
    };
    validate_structure(&r).map_err(|e| anyhow!("minted receipt failed its own shape check: {e:?}"))?;

    // 7. Persist. The output blobs are stored so `validate` can RE-HASH them — a hash with
    //    nothing to compare against is a claim, not evidence.
    std::fs::create_dir_all(store_dir(&root)?)?;
    write_atomic(&blob_path(&root, task_id, "stdout")?, &out.stdout)?;
    write_atomic(&blob_path(&root, task_id, "stderr")?, &out.stderr)?;
    write_atomic(&path, to_canonical_json(&r).as_bytes())?;

    if json {
        println!("{}", to_canonical_json(&r));
    } else {
        println!(
            "minted {task_id}: {} (exit {}, {}ms) over {}",
            match outcome {
                Outcome::Passed => "passed",
                Outcome::Failed => "failed",
            },
            exit_code,
            duration_ms,
            &r.repo.candidate_commit[..8.min(r.repo.candidate_commit.len())]
        );
    }
    Ok(())
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

// ------------------------------------------------------------------------- validate

pub fn cmd_validate(task_id: &str, at: Option<String>, json: bool) -> Result<()> {
    let root = repo_root()?;
    let path = receipt_path(&root, task_id)?;
    if !path.exists() {
        emit(task_id, GateResult::Invalidated, "no receipt", json);
        std::process::exit(EXIT_INVALIDATED);
    }

    let r = parse_receipt(&std::fs::read_to_string(&path)?).map_err(|e| anyhow!(e))?;
    if let Err(e) = validate_structure(&r) {
        emit(task_id, GateResult::Invalidated, &format!("{e:?}"), json);
        std::process::exit(EXIT_INVALIDATED);
    }

    let at = at.unwrap_or_else(|| "HEAD".to_string());
    let at_commit = git_in(&root, &["rev-parse", &at])?;

    // NOTE: paths are re-derived over base_commit..<at>. On a feature branch that is
    // exactly the task's diff. At a BATCH promotion (dev->main) it over-includes other
    // tasks' changes — the open design problem recorded on t-2594; the batch policy is
    // that task's to decide, not this command's.
    let derived_paths = changed_paths(&root, &r.repo.base_commit, &at_commit)?;

    let facts = DerivedFacts {
        candidate_reachable: git_ok(
            &root,
            &["merge-base", "--is-ancestor", &r.repo.candidate_commit, &at_commit],
        ),
        paths_digest: paths_digest(&derived_paths),
        ac_digest: ac_digest(&task_ac_lines(&root, task_id)?),
        stdout_sha256: std::fs::read(blob_path(&root, task_id, "stdout")?)
            .ok()
            .map(|b| sha256_hex(&b)),
        stderr_sha256: std::fs::read(blob_path(&root, task_id, "stderr")?)
            .ok()
            .map(|b| sha256_hex(&b)),
    };

    let verdict = compare(&r, &facts);

    // Re-check after deciding, or the gate is a TOCTOU: the tree can move between the
    // comparison and the merge it authorises.
    if verdict == GateResult::Allow {
        let again = changed_paths(&root, &r.repo.base_commit, &at_commit)?;
        if paths_digest(&again) != facts.paths_digest
            || git_in(&root, &["rev-parse", &at])? != at_commit
        {
            emit(task_id, GateResult::ScopeChanged, "tree moved during validation", json);
            std::process::exit(EXIT_SCOPE_CHANGED);
        }
    }

    let reason = match verdict {
        GateResult::Allow => "receipt binds this tree",
        GateResult::ScopeChanged => "candidate moved — route to recovery, not restart",
        GateResult::Invalidated => "approval is void",
    };
    emit(task_id, verdict, reason, json);
    match verdict {
        GateResult::Allow => Ok(()),
        GateResult::ScopeChanged => std::process::exit(EXIT_SCOPE_CHANGED),
        GateResult::Invalidated => std::process::exit(EXIT_INVALIDATED),
    }
}

fn emit(task_id: &str, verdict: GateResult, reason: &str, json: bool) {
    let label = match verdict {
        GateResult::Allow => "allow",
        GateResult::ScopeChanged => "scope-changed",
        GateResult::Invalidated => "invalidated",
    };
    if json {
        println!(
            "{}",
            serde_json::json!({"task_id": task_id, "result": label, "reason": reason})
        );
    } else {
        println!("{label}: {task_id} — {reason}");
    }
}
