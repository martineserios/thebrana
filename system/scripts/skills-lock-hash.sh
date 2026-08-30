#!/usr/bin/env bash
# Computes the computedHash for a vendored skill directory, per ADR-084 §2:
# sha256 over every file under the directory, sorted by relative path,
# each entry contributing its relative-path bytes followed by its raw
# content bytes (no separators). A single-file skill (just "SKILL.md", no
# sub-files) reduces to sha256("SKILL.md" + content) — the pre-existing
# ADR-012 convention this generalizes. That reduction only holds for
# skills that are actually single-file on disk; a lock entry's existing
# computedHash is not assumed valid just because it predates this script —
# run this against it to find out (t-3239 found 9 that don't match).
#
# Usage: skills-lock-hash.sh <skill-dir>
# Prints the hex digest on stdout. Exit 1 if the directory has no files.
set -euo pipefail

skill_dir="${1:?usage: skills-lock-hash.sh <skill-dir>}"
[ -d "$skill_dir" ] || { echo "not a directory: $skill_dir" >&2; exit 1; }

# Single find pass, reused for both the emptiness check and the hash walk —
# a second independent `find` call here would be a TOCTOU gap (the file set
# could change between an empty-check pass and a separate hashing pass).
files=$(cd "$skill_dir" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
[ -n "$files" ] || { echo "no files under $skill_dir" >&2; exit 1; }

hash=$(
  cd "$skill_dir"
  while IFS= read -r f; do
    printf '%s' "$f"
    cat -- "$f"
  done <<< "$files" | sha256sum | awk '{print $1}'
)

echo "$hash"
