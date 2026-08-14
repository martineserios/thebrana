use brana_core::search::{FTS5Provider, HybridProvider, SearchProvider};
use brana_core::vector::{RufloEmbedder, VectorProvider};
use pmcp::{RequestHandlerExtra, TypedTool};
use schemars::JsonSchema;
use serde::Deserialize;
use std::sync::Arc;

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(deny_unknown_fields)]
pub struct Input {
    /// Search query
    pub query: String,
    /// Maximum results to return
    #[serde(default = "default_top_k")]
    pub top_k: usize,
}

fn default_top_k() -> usize { 10 }

pub fn build() -> TypedTool<Input, impl Fn(Input, RequestHandlerExtra) -> std::pin::Pin<Box<dyn std::future::Future<Output = pmcp::Result<serde_json::Value>> + Send>> + Send + Sync> {
    TypedTool::new("recall", |input: Input, _extra| {
        Box::pin(async move {
            let db_path = brana_core::memory::fts_index_path();

            let query_str = input.query.clone();
            let hits = tokio::task::spawn_blocking(move || {
                let fts5 = Arc::new(FTS5Provider::new(db_path)) as Arc<dyn SearchProvider>;
                // Local vector recall (t-2620) — ruflo kept only as query embedder.
                let vectors = Arc::new(
                    VectorProvider::new(brana_core::vector::knowledge_db_path(), Arc::new(RufloEmbedder))
                        .with_threshold(0.25),
                ) as Arc<dyn SearchProvider>;
                let provider = HybridProvider::new(fts5, vectors);
                provider.query(&input.query, input.top_k)
            })
            .await
            .map_err(|e| pmcp::Error::validation(e.to_string()))?;

            Ok(serde_json::json!({
                "query": query_str,
                "count": hits.len(),
                "hits": hits,
            }))
        })
    })
    .with_description("Hybrid recall — parallel FTS5 + ruflo semantic search merged via RRF (ADR-058). Returns memory files and knowledge entries ranked by combined score.")
}
