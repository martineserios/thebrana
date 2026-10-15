use anyhow::Result;
use brana_core::search::{DocRef, LegStatus, RecallScope, SearchProvider};
use brana_core::vector::RufloEmbedder;
use std::sync::Arc;

use crate::cli::RecallScopeArg;

pub fn cmd_recall(
    query: &str,
    top_k: usize,
    json: bool,
    db: Option<String>,
    scope: RecallScopeArg,
) -> Result<()> {
    let db_path = db
        .map(std::path::PathBuf::from)
        .unwrap_or_else(brana_core::memory::fts_index_path);

    // Local vector recall over the brana-owned store (t-2620) — replaces the broken ruflo
    // retrieval stack; ruflo remains only as query embedder. Curated memory files get
    // their own semantic list once `brana knowledge embed-memory` has filled it (t-3510);
    // before that the list is empty and recall is the old FTS + knowledge fusion.
    let provider = brana_core::vector::recall_provider(
        db_path,
        brana_core::vector::knowledge_db_path(),
        Arc::new(RufloEmbedder),
        match scope {
            RecallScopeArg::All => RecallScope::All,
            RecallScopeArg::Project => RecallScope::current_project(),
        },
    );

    let hits = provider.query(query, top_k);

    if json {
        println!("{}", serde_json::to_string(&hits)?);
        return Ok(());
    }

    if hits.is_empty() {
        println!("no matches for \"{query}\"");
        return Ok(());
    }

    for h in &hits {
        match &h.doc {
            DocRef::MemoryFile { slug, mtype, scope, .. } => {
                let mtype = if mtype.is_empty() { "?" } else { &mtype };
                println!("  [{mtype}] {slug} ({scope})  score={:.3}", h.rrf_score);
            }
            DocRef::KnowledgeEntry { key, namespace } => {
                println!("  [knowledge:{namespace}] {key}  score={:.3}", h.rrf_score);
            }
        }
        println!("    {}", h.snippet);
    }
    Ok(())
}

/// Time the freshness refresh may take before the bundle proceeds on a stale index.
const BUNDLE_REFRESH_BUDGET: std::time::Duration = std::time::Duration::from_millis(400);
/// Lock wait for the `unembedded` count.
const BUNDLE_UNEMBEDDED_WAIT: std::time::Duration = std::time::Duration::from_millis(200);

/// `brana recall --bundle <task-id>` (t-3537, ADR-099). Fails open: a missing task, tasks
/// file or index gives an empty bundle and exit 0; the reason is on stderr and in the legs.
pub fn cmd_recall_bundle(task_id: &str, json: bool, db: Option<String>, shadow: bool) -> Result<()> {
    use brana_core::recall_bundle::{BundleEnv, BundleTask, compute_bundle, format_human};

    // A task that cannot be found is no bundle worth logging: its row would be noise, and a
    // shown one would wait for an outcome nobody can give.
    let mut task_known = true;
    let task = load_bundle_task(task_id).unwrap_or_else(|why| {
        eprintln!("recall --bundle: {why}; returning an empty bundle");
        task_known = false;
        BundleTask { id: task_id.to_string(), subject: String::new(), tags: Vec::new() }
    });

    let fts_db = db.map(std::path::PathBuf::from).unwrap_or_else(brana_core::memory::fts_index_path);
    let knowledge_db = brana_core::vector::knowledge_db_path();
    let home = brana_core::util::home();
    let session_root = brana_core::util::find_session_root();
    let scope = RecallScope::project_in(&home, session_root.as_deref());
    let dirs: Vec<(String, std::path::PathBuf)> = scope
        .dirs()
        .unwrap_or(&[])
        .iter()
        .enumerate()
        .map(|(i, d)| ((if i == 0 { "global" } else { "project" }).to_string(), d.clone()))
        .collect();
    let provider = brana_core::vector::bundle_provider(&fts_db, &knowledge_db, Arc::new(RufloEmbedder), scope.clone());
    let env = BundleEnv {
        scope,
        project: session_root.as_deref().map(brana_core::util::encode_project_dir),
        dirs,
        knowledge_db,
        fts_db,
        provider: &provider,
        refresh_budget: BUNDLE_REFRESH_BUDGET,
        unembedded_wait: BUNDLE_UNEMBEDDED_WAIT,
    };

    let mut bundle = compute_bundle(&task, &env);
    bundle.shown = !shadow;
    if task_known {
        log_offered(&bundle, session_root.as_deref());
    }
    // Say which legs degraded (a healthy bundle is silent); the legs are also in the output.
    let degraded: Vec<String> = [("fts", bundle.legs.fts), ("vector", bundle.legs.vector)]
        .into_iter()
        .filter(|(_, st)| matches!(st, LegStatus::Timeout | LegStatus::Error))
        .map(|(name, st)| format!("{name}={}", st.as_str()))
        .collect();
    if !degraded.is_empty() {
        eprintln!("recall --bundle: degraded leg(s): {}", degraded.join(", "));
    }
    if shadow {
        return Ok(());
    }
    if json {
        println!("{}", serde_json::to_string(&bundle)?);
    } else {
        print!("{}", format_human(&bundle));
    }
    Ok(())
}

/// Append the bundle's offered row to the project's usage log (ADR-099 §5). Fail-open: a log
/// that cannot be written is said on stderr and never fails the build.
fn log_offered(bundle: &brana_core::recall_bundle::Bundle, session_root: Option<&std::path::Path>) {
    use brana_core::usage_log;
    let Some(root) = session_root else {
        eprintln!("recall --bundle: no project root; the offered row was not logged");
        return;
    };
    let session = super::time::resolve_newest_transcript()
        .and_then(|p| p.file_stem().map(|s| s.to_string_lossy().into_owned()));
    let freshness = serde_json::to_value(&bundle.freshness).unwrap_or(serde_json::Value::Null);
    let row = usage_log::offered_row(
        &usage_log::Offered {
            task: &bundle.task,
            shown: bundle.shown,
            fts: bundle.legs.fts.as_str(),
            vector: bundle.legs.vector.as_str(),
            elapsed_ms: bundle.elapsed_ms,
            pointers: &bundle.pointers,
            freshness,
            session: session.as_deref(),
        },
        chrono::Utc::now(),
    );
    let Some(row) = row else {
        eprintln!("recall --bundle: {:?} is not a task id; the offered row was not logged", bundle.task);
        return;
    };
    let [path, _] = usage_log::log_paths(&brana_core::util::session_store_root(), root);
    if let Err(e) = usage_log::append(&path, &row) {
        eprintln!("recall --bundle: could not log the offered row: {e}");
    }
}

/// The task's subject and tags from tasks.json (description, context and notes are never
/// read: the v1 query is subject + tags only).
fn load_bundle_task(task_id: &str) -> std::result::Result<brana_core::recall_bundle::BundleTask, String> {
    let tf = brana_core::util::find_tasks_file().ok_or("tasks.json not found")?;
    let data = brana_core::tasks::load_tasks(&tf)?;
    let t = data
        .tasks
        .iter()
        .find(|t| t["id"].as_str() == Some(task_id))
        .ok_or_else(|| format!("task {task_id} not found"))?;
    Ok(brana_core::recall_bundle::BundleTask {
        id: task_id.to_string(),
        subject: t["subject"].as_str().unwrap_or_default().to_string(),
        tags: t["tags"]
            .as_array()
            .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect())
            .unwrap_or_default(),
    })
}
