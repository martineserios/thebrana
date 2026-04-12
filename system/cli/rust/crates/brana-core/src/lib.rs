//! brana-core — shared business logic for task management, feeds, inbox, and files.
//!
//! This crate contains all domain logic used by both `brana-cli` (terminal) and
//! `brana-mcp` (MCP server). It has no CLI framework or protocol dependencies.

pub mod files;
pub mod knowledge_pipeline;
pub mod scheduler;
pub mod session;
pub mod sync;
pub mod tasks;
pub mod util;
