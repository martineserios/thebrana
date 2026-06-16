//! brana-mcp — MCP server exposing backlog tools via Model Context Protocol.
//!
//! Runs as a stdio MCP server, started by Claude Code via .mcp.json.
//! All business logic comes from brana-core; this crate is a thin adapter.

mod tools;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let server = pmcp::Server::builder()
        .name("brana-mcp")
        .version(env!("CARGO_PKG_VERSION"))
        .tool("backlog_query", tools::backlog_query::build())
        .tool("backlog_get", tools::backlog_get::build())
        .tool("backlog_set", tools::backlog_set::build())
        .tool("backlog_batch", tools::backlog_batch::build())
        .tool("backlog_add", tools::backlog_add::build())
        .tool("backlog_search", tools::backlog_search::build())
        .tool("backlog_stats", tools::backlog_stats::build())
        .tool("backlog_burndown", tools::backlog_burndown::build())
        .tool("backlog_focus", tools::backlog_focus::build())
        .tool("backlog_stale", tools::backlog_stale::build())
        .tool("session_write", tools::session_write::build())
        .tool("session_read", tools::session_read::build())
        .tool("session_history", tools::session_history::build())
        .tool("memory_write", tools::memory_write::build())
        .tool("memory_index", tools::memory_index::build())
        .tool("agy_delegate", tools::agy_delegate::build())
        .tool("recall", tools::recall::build())
        .build()?;

    server.run_stdio().await?;
    Ok(())
}
