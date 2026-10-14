use anyhow::Result;
use brana_core::search::{DocRef, SearchProvider};
use brana_core::vector::RufloEmbedder;
use std::sync::Arc;

pub fn cmd_recall(query: &str, top_k: usize, json: bool, db: Option<String>) -> Result<()> {
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
