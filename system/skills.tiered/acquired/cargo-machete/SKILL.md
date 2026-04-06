---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
name: cargo-machete
group: utility
status: stable
description: |
  Detect unused dependencies in Rust projects for cleaner Cargo.toml files and faster builds.
  Use when auditing dependencies, optimizing build times, cleaning up Cargo.toml, or detecting bloat.
  Trigger terms: unused dependencies, cargo-machete, dependency audit, dependency cleanup, bloat detection, cargo-udeps.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

<!-- PROCEDURE_FILE: procedures/cargo-machete.md -->
This skill's full procedure is in a separate file for startup performance (ADR-034).
Read and execute `system/procedures/cargo-machete.md` from the plugin root directory.
If the path doesn't resolve, use Glob to find `**/procedures/cargo-machete.md`.
