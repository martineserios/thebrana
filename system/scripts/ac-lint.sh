#!/usr/bin/env bash
# ac-lint.sh — classify an acceptance criterion as machine-checkable or prose.
#
# Canonical grammar: docs/architecture/ac-grammar.md (the 8 heuristics).
# This classifier MUST mirror the consumer's matching logic in
# system/hooks/goal-completion.sh:59-206 — a criterion classifies "checkable"
# here iff goal-completion.sh would actually run a check for it (not UNKNOWN).
# Producer (/brana:backlog plan lint) uses this to warn when a generated
# criterion won't auto-complete. (t-2201; tests: system/hooks/tests/test-ac-lint.sh)
#
# Usage:   ac-lint.sh "<criterion>"
# Output:  stdout "checkable" + exit 0   → matches a heuristic (auto-completes)
#          stdout "prose"     + exit 1   → free-text (needs manual sign-off)

set -uo pipefail

criterion="${1:-}"

# Strip a leading "AC: " / "AC:" prefix (mirrors goal-completion.sh:55-57).
criterion="${criterion#AC: }"
criterion="${criterion#AC:}"
criterion="${criterion# }"

prose() { echo "prose"; exit 1; }
checkable() { echo "checkable"; exit 0; }

[ -z "$criterion" ] && prose

# ── Heuristic 1: file exists (path with a known extension) ───────────────────
if grep -qiE "exists$|^file .+ exists" <<<"$criterion"; then
    grep -qE '[a-zA-Z0-9_./-]+\.(sh|md|json|rs|py|ts|js|toml)' <<<"$criterion" && checkable
fi

# ── Heuristic 2: brana backlog get ... returns ... ───────────────────────────
grep -qiE "^brana backlog get .+ returns" <<<"$criterion" && checkable

# ── Heuristic 3: validate.sh Check N passes ──────────────────────────────────
grep -qiE "validate\.sh.*check [0-9]+" <<<"$criterion" && checkable

# ── Heuristic 4: hook {name}.sh exists ───────────────────────────────────────
grep -qiE "hook .+\.sh exists" <<<"$criterion" && checkable

# ── Heuristic 5: file {path} contains "{string}" — reject abs / traversal ────
if grep -qiE '^file .+ contains "' <<<"$criterion"; then
    path=$(grep -oE 'file [^ ]+' <<<"$criterion" | awk '{print $2}')
    if [ -n "$path" ] && ! grep -qE '^/|\.\.' <<<"$path"; then
        checkable
    fi
fi

# ── Heuristic 6: jq '{expr}' {file} returns "{value}" — reject abs / traversal ─
if grep -qiE "^jq '.+' .+ returns" <<<"$criterion"; then
    file=$(sed "s/jq '[^']*' //" <<<"$criterion" | grep -oE '[^ ]+' | head -1)
    if [ -n "$file" ] && ! grep -qE '^/|\.\.' <<<"$file"; then
        checkable
    fi
fi

# ── Heuristic 7: "{command}" passes — allowlist only ─────────────────────────
if grep -qiE '^"[^"]+" passes$' <<<"$criterion"; then
    cmd=$(grep -oE '"[^"]+"' <<<"$criterion" | head -1 | tr -d '"')
    grep -qE '^(cargo test|pytest|python -m pytest|bun test|npm test|yarn test|bash tests/|\./tests/)' <<<"$cmd" && checkable
fi

# ── Heuristic 8: git log checks ──────────────────────────────────────────────
grep -qiE "^changes to .+ committed$" <<<"$criterion" && checkable
grep -qiE '^commit message contains "' <<<"$criterion" && checkable

# ── Fallback: unknown pattern → prose (manual sign-off) ──────────────────────
prose
