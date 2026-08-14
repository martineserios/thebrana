#!/usr/bin/env bash
# ac-lint.sh — classify an acceptance criterion as machine-checkable or prose.
#
# Canonical grammar: docs/architecture/ac-grammar.md (the 10 heuristics).
# This classifier MUST mirror the consumer's matching logic in
# system/hooks/goal-completion.sh — a criterion classifies "checkable"
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

# Shared H7/H10 allowlist + metachar guard — single owner is lib/cmd-allowlist.sh
# (ADR-081 D1, t-2868). Do not redefine CMD_ALLOWLIST_RE/allowlisted_command()
# here — that's the exact two-copies drift that let an injection bypass ship
# (t-2856 challenger finding).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cmd-allowlist.sh
source "${SCRIPT_DIR}/lib/cmd-allowlist.sh"

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
    allowlisted_command "$cmd" && checkable
fi

# ── Heuristic 8: git log checks ──────────────────────────────────────────────
grep -qiE "^changes to .+ committed$" <<<"$criterion" && checkable
grep -qiE '^commit message contains "' <<<"$criterion" && checkable

# ── Heuristic 9: validate.sh passes (full run) — mirrors goal-completion.sh ──
# (t-2856 drift fix: H9 shipped in the hook with t-2206 but was never mirrored here.)
if grep -qiE 'validate\.sh' <<<"$criterion" \
   && grep -qiE '(passes|exit 0|exit code 0)' <<<"$criterion" \
   && ! grep -qiE 'check [0-9]' <<<"$criterion"; then
    checkable
fi

# ── Heuristic 10: demoable: <command> — same allowlist as heuristic 7 ────────
# (t-2856) Non-allowlisted demoable commands are prose: the hook never executes
# them; the demo happens at a human sitting.
if grep -qiE '^demoable: .+' <<<"$criterion"; then
    cmd=$(sed 's/^[Dd]emoable: *//' <<<"$criterion")
    allowlisted_command "$cmd" && checkable
fi

# ── Fallback: unknown pattern → prose (manual sign-off) ──────────────────────
prose
