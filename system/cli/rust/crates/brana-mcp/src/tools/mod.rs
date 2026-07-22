pub mod backlog_query;
pub mod backlog_get;
pub mod backlog_set;
pub mod backlog_batch;
pub mod backlog_add;
pub mod backlog_search;
pub mod backlog_stats;
pub mod backlog_burndown;
pub mod backlog_focus;
pub mod backlog_stale;
pub mod session_write;
pub mod session_read;
pub mod session_history;
pub mod memory_write;
pub mod memory_index;
pub mod agy_delegate;
pub mod recall;

#[cfg(test)]
mod dispatch_queue_tests;

/// Serializes cwd/`CLAUDE_PROJECT_DIR` mutation across ALL handler tests in this test
/// binary, not just within one file — Rust's test runner executes files' tests
/// concurrently on separate threads, and cwd/env are process-global, so a per-file lock
/// only serializes within that file and races against every other file's tests (t-2305:
/// surfaced as a genuine flake once a third cwd-mutating test file was added). Every
/// `Hermetic`-style fixture across `tools/` must hold this lock, not a private one.
#[cfg(test)]
pub(crate) static CWD_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
