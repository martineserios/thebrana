#!/usr/bin/env bash
# Rebuild the embedded FTS5 memory index (replaces JSONL→bulk-index.mjs pipeline).
#
# Previously: Phase 1 (awk parse → JSONL) + Phase 2 (node bulk-index.mjs → ruflo SQLite)
# Now:        brana memory reindex → FTS5 SQLite at ~/.claude/memory/index.db
#
# The Rust implementation scans ~/.claude/projects/*/memory/ + ~/.claude/memory/
# directly — no intermediate file, no node dependency.
#
# Usage (unchanged for scheduler compatibility):
#   index-patterns.sh                 # full cross-project reindex
#   index-patterns.sh --project X     # accepted but ignored; always full scan
#   index-patterns.sh --cleanup       # accepted but ignored; always full rebuild

set -euo pipefail

exec brana memory reindex
