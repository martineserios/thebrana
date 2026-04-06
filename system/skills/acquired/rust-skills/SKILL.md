---
name: rust-skills
group: utility
status: stable
allowed-tools: [Bash, Read, Write, Edit, Grep, Glob]
description: >
  Comprehensive Rust coding guidelines with 179 rules across 14 categories.
  Use when writing, reviewing, or refactoring Rust code. Covers ownership,
  error handling, async patterns, API design, memory optimization, performance,
  testing, and common anti-patterns. Invoke with /rust-skills.
license: MIT
metadata:
  author: leonardomso
  version: "1.0.0"
  sources:
    - Rust API Guidelines
    - Rust Performance Book
    - ripgrep, tokio, serde, polars codebases
---

# Rust Best Practices

Comprehensive guide for writing high-quality, idiomatic, and highly optimized Rust code. Contains 179 rules across 14 categories, prioritized by impact to guide LLMs in code generation and refactoring.

## When to Apply

Reference these guidelines when:
- Writing new Rust functions, structs, or modules
- Implementing error handling or async code
- Designing public APIs for libraries
- Reviewing code for ownership/borrowing issues
- Optimizing memory usage or reducing allocations
- Tuning performance for hot paths
- Refactoring existing Rust code

## Rule Categories by Priority

| Priority | Category | Impact | Prefix | Rules |
|----------|----------|--------|--------|-------|
| 1 | Ownership & Borrowing | CRITICAL | `own-` | 12 |
| 2 | Error Handling | CRITICAL | `err-` | 12 |
| 3 | Memory Optimization | CRITICAL | `mem-` | 15 |
| 4 | API Design | HIGH | `api-` | 15 |
| 5 | Async/Await | HIGH | `async-` | 15 |
| 6 | Compiler Optimization | HIGH | `opt-` | 12 |
| 7 | Naming Conventions | MEDIUM | `name-` | 16 |
| 8 | Type Safety | MEDIUM | `type-` | 10 |
| 9 | Testing | MEDIUM | `test-` | 13 |
| 10 | Documentation | MEDIUM | `doc-` | 11 |
| 11 | Performance Patterns | MEDIUM | `perf-` | 11 |
| 12 | Project Structure | LOW | `proj-` | 11 |
| 13 | Clippy & Linting | LOW | `lint-` | 11 |
| 14 | Anti-patterns | REFERENCE | `anti-` | 15 |

---

## Quick Reference

### 1. Ownership & Borrowing (CRITICAL)

- `\1` - Prefer `&T` borrowing over `.clone()`
- `\1` - Accept `&[T]` not `&Vec<T>`, `&str` not `&String`
- `\1` - Use `Cow<'a, T>` for conditional ownership
- `\1` - Use `Arc<T>` for thread-safe shared ownership
- `\1` - Use `Rc<T>` for single-threaded sharing
- `\1` - Use `RefCell<T>` for interior mutability (single-thread)
- `\1` - Use `Mutex<T>` for interior mutability (multi-thread)
- `\1` - Use `RwLock<T>` when reads dominate writes
- `\1` - Derive `Copy` for small, trivial types
- `\1` - Make `Clone` explicit, avoid implicit copies
- `\1` - Move large data instead of cloning
- `\1` - Rely on lifetime elision when possible

### 2. Error Handling (CRITICAL)

- `\1` - Use `thiserror` for library error types
- `\1` - Use `anyhow` for application error handling
- `\1` - Return `Result`, don't panic on expected errors
- `\1` - Add context with `.context()` or `.with_context()`
- `\1` - Never use `.unwrap()` in production code
- `\1` - Use `.expect()` only for programming errors
- `\1` - Use `?` operator for clean propagation
- `\1` - Use `#[from]` for automatic error conversion
- `\1` - Use `#[source]` to chain underlying errors
- `\1` - Error messages: lowercase, no trailing punctuation
- `\1` - Document errors with `# Errors` section
- `\1` - Create custom error types, not `Box<dyn Error>`

### 3. Memory Optimization (CRITICAL)

- `\1` - Use `with_capacity()` when size is known
- `\1` - Use `SmallVec` for usually-small collections
- `\1` - Use `ArrayVec` for bounded-size collections
- `\1` - Box large enum variants to reduce type size
- `\1` - Use `Box<[T]>` instead of `Vec<T>` when fixed
- `\1` - Use `ThinVec` for often-empty vectors
- `\1` - Use `clone_from()` to reuse allocations
- `\1` - Reuse collections with `clear()` in loops
- `\1` - Avoid `format!()` when string literals work
- `\1` - Use `write!()` instead of `format!()` 
- `\1` - Use arena allocators for batch allocations
- `\1` - Use zero-copy patterns with slices and `Bytes`
- `\1` - Use `CompactString` for small string optimization
- `\1` - Use smallest integer type that fits
- `\1` - Assert hot type sizes to prevent regressions

### 4. API Design (HIGH)

- `\1` - Use Builder pattern for complex construction
- `\1` - Add `#[must_use]` to builder types
- `\1` - Use newtypes for type-safe distinctions
- `\1` - Use typestate for compile-time state machines
- `\1` - Seal traits to prevent external implementations
- `\1` - Use extension traits to add methods to foreign types
- `\1` - Parse into validated types at boundaries
- `\1` - Accept `impl Into<T>` for flexible string inputs
- `\1` - Accept `impl AsRef<T>` for borrowed inputs
- `\1` - Add `#[must_use]` to `Result` returning functions
- `\1` - Use `#[non_exhaustive]` for future-proof enums/structs
- `\1` - Implement `From`, not `Into` (auto-derived)
- `\1` - Implement `Default` for sensible defaults
- `\1` - Implement `Debug`, `Clone`, `PartialEq` eagerly
- `\1` - Gate `Serialize`/`Deserialize` behind feature flag

### 5. Async/Await (HIGH)

- `\1` - Use Tokio for production async runtime
- `\1` - Never hold `Mutex`/`RwLock` across `.await`
- `\1` - Use `spawn_blocking` for CPU-intensive work
- `\1` - Use `tokio::fs` not `std::fs` in async code
- `\1` - Use `CancellationToken` for graceful shutdown
- `\1` - Use `tokio::join!` for parallel operations
- `\1` - Use `tokio::try_join!` for fallible parallel ops
- `\1` - Use `tokio::select!` for racing/timeouts
- `\1` - Use bounded channels for backpressure
- `\1` - Use `mpsc` for work queues
- `\1` - Use `broadcast` for pub/sub patterns
- `\1` - Use `watch` for latest-value sharing
- `\1` - Use `oneshot` for request/response
- `\1` - Use `JoinSet` for dynamic task groups
- `\1` - Clone data before await, release locks

### 6. Compiler Optimization (HIGH)

- `\1` - Use `#[inline]` for small hot functions
- `\1` - Use `#[inline(always)]` sparingly
- `\1` - Use `#[inline(never)]` for cold paths
- `\1` - Use `#[cold]` for error/unlikely paths
- `\1` - Use `likely()`/`unlikely()` for branch hints
- `\1` - Enable LTO in release builds
- `\1` - Use `codegen-units = 1` for max optimization
- `\1` - Use PGO for production builds
- `\1` - Set `target-cpu=native` for local builds
- `\1` - Use iterators to avoid bounds checks
- `\1` - Use portable SIMD for data-parallel ops
- `\1` - Design cache-friendly data layouts (SoA)

### 7. Naming Conventions (MEDIUM)

- `\1` - Use `UpperCamelCase` for types, traits, enums
- `\1` - Use `UpperCamelCase` for enum variants
- `\1` - Use `snake_case` for functions, methods, modules
- `\1` - Use `SCREAMING_SNAKE_CASE` for constants/statics
- `\1` - Use short lowercase lifetimes: `'a`, `'de`, `'src`
- `\1` - Use single uppercase for type params: `T`, `E`, `K`, `V`
- `\1` - `as_` prefix: free reference conversion
- `\1` - `to_` prefix: expensive conversion
- `\1` - `into_` prefix: ownership transfer
- `\1` - No `get_` prefix for simple getters
- `\1` - Use `is_`, `has_`, `can_` for boolean methods
- `\1` - Use `iter`/`iter_mut`/`into_iter` for iterators
- `\1` - Name iterator methods consistently
- `\1` - Iterator type names match method
- `\1` - Treat acronyms as words: `Uuid` not `UUID`
- `\1` - Crate names: no `-rs` suffix

### 8. Type Safety (MEDIUM)

- `\1` - Wrap IDs in newtypes: `UserId(u64)`
- `\1` - Newtypes for validated data: `Email`, `Url`
- `\1` - Use enums for mutually exclusive states
- `\1` - Use `Option<T>` for nullable values
- `\1` - Use `Result<T, E>` for fallible operations
- `\1` - Use `PhantomData<T>` for type-level markers
- `\1` - Use `!` type for functions that never return
- `\1` - Add trait bounds only where needed
- `\1` - Avoid stringly-typed APIs, use enums/newtypes
- `\1` - Use `#[repr(transparent)]` for FFI newtypes

### 9. Testing (MEDIUM)

- `\1` - Use `#[cfg(test)] mod tests { }`
- `\1` - Use `use super::*;` in test modules
- `\1` - Put integration tests in `tests/` directory
- `\1` - Use descriptive test names
- `\1` - Structure tests as arrange/act/assert
- `\1` - Use `proptest` for property-based testing
- `\1` - Use `mockall` for trait mocking
- `\1` - Use traits for dependencies to enable mocking
- `\1` - Use RAII pattern (Drop) for test cleanup
- `\1` - Use `#[tokio::test]` for async tests
- `\1` - Use `#[should_panic]` for panic tests
- `\1` - Use `criterion` for benchmarking
- `\1` - Keep doc examples as executable tests

### 10. Documentation (MEDIUM)

- `\1` - Document all public items with `///`
- `\1` - Use `//!` for module-level documentation
- `\1` - Include `# Examples` with runnable code
- `\1` - Include `# Errors` for fallible functions
- `\1` - Include `# Panics` for panicking functions
- `\1` - Include `# Safety` for unsafe functions
- `\1` - Use `?` in examples, not `.unwrap()`
- `\1` - Use `# ` prefix to hide example setup code
- `\1` - Use intra-doc links: `[Vec]`
- `\1` - Link related types and functions in docs
- `\1` - Fill `Cargo.toml` metadata

### 11. Performance Patterns (MEDIUM)

- `\1` - Prefer iterators over manual indexing
- `\1` - Keep iterators lazy, collect() only when needed
- `\1` - Don't `collect()` intermediate iterators
- `\1` - Use `entry()` API for map insert-or-update
- `\1` - Use `drain()` to reuse allocations
- `\1` - Use `extend()` for batch insertions
- `\1` - Avoid `chain()` in hot loops
- `\1` - Use `collect_into()` for reusing containers
- `\1` - Use `black_box()` in benchmarks
- `\1` - Optimize release profile settings
- `\1` - Profile before optimizing

### 12. Project Structure (LOW)

- `\1` - Keep `main.rs` minimal, logic in `lib.rs`
- `\1` - Organize modules by feature, not type
- `\1` - Keep small projects flat
- `\1` - Use `mod.rs` for multi-file modules
- `\1` - Use `pub(crate)` for internal APIs
- `\1` - Use `pub(super)` for parent-only visibility
- `\1` - Use `pub use` for clean public API
- `\1` - Create `prelude` module for common imports
- `\1` - Put multiple binaries in `src/bin/`
- `\1` - Use workspaces for large projects
- `\1` - Use workspace dependency inheritance

### 13. Clippy & Linting (LOW)

- `\1` - `#![deny(clippy::correctness)]`
- `\1` - `#![warn(clippy::suspicious)]`
- `\1` - `#![warn(clippy::style)]`
- `\1` - `#![warn(clippy::complexity)]`
- `\1` - `#![warn(clippy::perf)]`
- `\1` - Enable `clippy::pedantic` selectively
- `\1` - `#![warn(missing_docs)]`
- `\1` - `#![warn(clippy::undocumented_unsafe_blocks)]`
- `\1` - `#![warn(clippy::cargo)]` for published crates
- `\1` - Run `cargo fmt --check` in CI
- `\1` - Configure lints at workspace level

### 14. Anti-patterns (REFERENCE)

- `\1` - Don't use `.unwrap()` in production code
- `\1` - Don't use `.expect()` for recoverable errors
- `\1` - Don't clone when borrowing works
- `\1` - Don't hold locks across `.await`
- `\1` - Don't accept `&String` when `&str` works
- `\1` - Don't accept `&Vec<T>` when `&[T]` works
- `\1` - Don't use indexing when iterators work
- `\1` - Don't panic on expected/recoverable errors
- `\1` - Don't use empty `if let Err(_) = ...` blocks
- `\1` - Don't over-abstract with excessive generics
- `\1` - Don't optimize before profiling
- `\1` - Don't use `Box<dyn Trait>` when `impl Trait` works
- `\1` - Don't use `format!()` in hot paths
- `\1` - Don't `collect()` intermediate iterators
- `\1` - Don't use strings for structured data

---

## Recommended Cargo.toml Settings

```toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = true

[profile.bench]
inherits = "release"
debug = true
strip = false

[profile.dev]
opt-level = 0
debug = true

[profile.dev.package."*"]
opt-level = 3  # Optimize dependencies in dev
```

---

## How to Use

This skill provides rule identifiers for quick reference. When generating or reviewing Rust code:

1. **Check relevant category** based on task type
2. **Apply rules** with matching prefix
3. **Prioritize** CRITICAL > HIGH > MEDIUM > LOW
4. **Read rule files** in `rules/` for detailed examples

### Rule Application by Task

| Task | Primary Categories |
|------|-------------------|
| New function | `own-`, `err-`, `name-` |
| New struct/API | `api-`, `type-`, `doc-` |
| Async code | `async-`, `own-` |
| Error handling | `err-`, `api-` |
| Memory optimization | `mem-`, `own-`, `perf-` |
| Performance tuning | `opt-`, `mem-`, `perf-` |
| Code review | `anti-`, `lint-` |

---

## Sources

This skill synthesizes best practices from:
- [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- [Rust Performance Book](https://nnethercote.github.io/perf-book/)
- [Rust Design Patterns](https://rust-unofficial.github.io/patterns/)
- Production codebases: ripgrep, tokio, serde, polars, axum, deno
- Clippy lint documentation
- Community conventions (2024-2025)
