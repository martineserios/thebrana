use anyhow::Result;
use brana_core::search::{DocRef, FTS5Provider, HybridProvider, RufloProvider, SearchProvider};
use std::sync::Arc;

pub fn cmd_recall(query: &str, top_k: usize, json: bool, db: Option<String>) -> Result<()> {
    let db_path = db
        .map(std::path::PathBuf::from)
        .unwrap_or_else(brana_core::memory::fts_index_path);

    let fts5 = Arc::new(FTS5Provider::new(db_path)) as Arc<dyn brana_core::search::SearchProvider>;
    let ruflo = Arc::new(RufloProvider::new("knowledge")) as Arc<dyn brana_core::search::SearchProvider>;
    let provider = HybridProvider::new(fts5, ruflo);

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
