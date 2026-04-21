#!/usr/bin/env bash
# Spec stub for reference.rs hooks.json traversal tests (t-1318).
# Actual unit tests live in the #[cfg(test)] block of:
#   system/cli/rust/crates/brana-cli/src/commands/reference.rs
#
# Run all Rust unit tests with:
#   cd system/cli/rust && cargo test -p brana-cli reference 2>&1
#
# Tests added:
#   - test_generate_hooks_configchange_nested_structure
#   - test_generate_hooks_empty_hooks_object
#   - test_generate_hooks_flat_structure_produces_no_rows
echo "Rust unit tests for hooks.json traversal are in reference.rs #[cfg(test)]"
echo "Run: cd system/cli/rust && cargo test -p brana-cli reference"
