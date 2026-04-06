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

<!-- PROCEDURE_FILE: procedures/rust-skills.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/rust-skills.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/rust-skills.md`.
