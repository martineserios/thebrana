#!/usr/bin/env bash
# Remedy registry for validate.sh findings (t-2630, ADR-077).
#
# Every check id validate.sh can report must resolve to HAS_REMEDY or
# NO_REMEDY:<reason> here — no third (silent) state. Completeness is enforced by
# tests/procedures/test-validate-remedy-registry-completeness.sh, not at runtime
# (an advisory tool must not crash on unrelated, pre-existing gaps).
#
# NO_REMEDY reasons (ADR-077 Decision #2), exactly one of:
#   judgment-required  — fixing it means guessing content/policy
#   not-fixable         — no deterministic target state exists
#   excluded-high-risk  — a fix could exist but is deliberately not automated (Decision #4)
#   deferred-wave2      — genuinely mechanical per the SPECIFY-phase catalog, just not
#                         wired in this v1 pilot (a real gap, not a judgment call —
#                         labeling it judgment-required would itself be misleading)
#
# Sourced by validate.sh AFTER $SCRIPT_DIR is set — reuses it rather than
# re-deriving, so there is exactly one BASH_SOURCE-anchored root in play.
# Never runs anything on its own.

# extract_check_ids FILE — print every "# Check N" id in FILE, one per line.
#
# Two independent hazards, both verified against the live validate.sh during SPECIFY:
#   1. A column-0-anchored regex misses real checks indented inside a conditional
#      block (e.g. Check 51, indented 4 spaces).
#   2. Widening to a leading-whitespace-tolerant regex alone ALSO matches fake ids from
#      Python-heredoc comments nested inside Check 18's embedded script (between
#      `<<'PYEOF'` and `PYEOF`) — those comments are themselves at column 0 inside the
#      heredoc body, so whitespace-tolerance alone doesn't exclude them.
# This function blanks out heredoc regions first (preserving line count, so line
# numbers in any future error message stay accurate), then matches with a
# leading-whitespace-tolerant regex.
extract_check_ids() {
    local file="$1"
    awk '
        /<<['\''"]?PYEOF['\''"]?[[:space:]]*$/ { in_heredoc = 1; print; next }
        in_heredoc && /^PYEOF[[:space:]]*$/ { in_heredoc = 0; print ""; next }
        in_heredoc { print ""; next }
        { print }
    ' "$file" | grep -oP '^\s*# Check \K[0-9]+[a-z]?'
}

# REMEDY_REGISTRY[check_id] = "HAS_REMEDY" | "NO_REMEDY:<reason> — <one-line detail>"
# Covers every id extract_check_ids() finds in validate.sh (75 as of 2026-08-05;
# tests/procedures/test-validate-remedy-registry-completeness.sh enforces this stays
# true as checks are added or removed).
declare -A REMEDY_REGISTRY=(
  [1]="NO_REMEDY:judgment-required — skill frontmatter content (missing file/invalid YAML/name mismatch) can't be inferred"
  [2]="NO_REMEDY:judgment-required — correct paths: glob or always-load status is a scoping decision"
  [2b]="NO_REMEDY:judgment-required — resolving overlapping always-load rules needs authored consolidation"
  [3]="NO_REMEDY:judgment-required — correct settings.json content unknowable from the parse error alone"
  [4]="NO_REMEDY:judgment-required — mixed: memory-scope default is mechanical but name/description gaps need authored content"
  [5]="NO_REMEDY:not-fixable — context budget has no deterministic 'what to cut' target"
  [5b]="NO_REMEDY:not-fixable — instruction density has no deterministic trim target"
  [6]="NO_REMEDY:judgment-required — must confirm true positive before redacting a possible secret"
  [6b]="NO_REMEDY:judgment-required — must confirm true positive before redacting a possible secret"
  [7]="NO_REMEDY:judgment-required — must decide which directory's skill name to change and to what"
  [8]="NO_REMEDY:judgment-required — no deterministic way to safely shrink file content"
  [8b]="NO_REMEDY:judgment-required — must know which AskUserQuestion option is actually recommended"
  [9]="NO_REMEDY:deferred-wave2 — mechanical sub-cases exist (chmod +x, shebang insert, deploy-copy sync) but not wired in v1"
  [9b]="NO_REMEDY:deferred-wave2 — mechanical (source the matching lib) but not wired in v1"
  [10]="NO_REMEDY:judgment-required — frontmatter/syntax-error content needs authoring; shebang-only slice is a minor exception"
  [11]="NO_REMEDY:judgment-required — syntax errors need a human; shebang-only slice is a minor exception"
  [12]="NO_REMEDY:judgment-required — a broken depends_on reference could be typo, rename, or a skill to create — no safe default"
  [13]="NO_REMEDY:deferred-wave2 — mechanical (rewrite the matched count) but not wired in v1"
  [14]="NO_REMEDY:judgment-required — no deterministic mapping of an orphan file to the right spec-graph node"
  [15]="NO_REMEDY:not-fixable — verifying an assumption is still true is inherently human judgment"
  [16]="NO_REMEDY:judgment-required — writing the actual changelog entry is content authoring"
  [17]="NO_REMEDY:deferred-wave2 — mechanical (flip status: active -> historic) but not wired in v1"
  [18]="NO_REMEDY:judgment-required — orphan/assumption-ref gaps need authored path updates or prose"
  [19]="NO_REMEDY:not-fixable — scale-trigger signal, not a bug with a target state"
  [20]="NO_REMEDY:not-fixable — scale-trigger signal, not a bug with a target state"
  [21]="NO_REMEDY:not-fixable — scale-trigger signal, not a bug with a target state"
  [22]="NO_REMEDY:not-fixable — scale-trigger signal, not a bug with a target state"
  [23]="NO_REMEDY:judgment-required — requires authoring specific procedure logic/prose"
  [24]="NO_REMEDY:judgment-required — need to know/create the correct pinned wrapper path per server"
  [25]="NO_REMEDY:judgment-required — no deterministic mapping from a bad string to the correct canonical priority; touches live backlog state"
  [26]="NO_REMEDY:judgment-required — wrong auto-mapping could mis-surface or hide real work"
  [27]="NO_REMEDY:judgment-required — exec replaces the shell process, silently dropping any cleanup logic after the backgrounded command"
  [28]="NO_REMEDY:deferred-wave2 — mechanical (python3 -> uv run prefix) but not wired in v1"
  [29]="HAS_REMEDY"
  [30]="NO_REMEDY:deferred-wave2 — mechanical (cd subshell wrap) but not wired in v1"
  [31]="NO_REMEDY:excluded-high-risk — the check's own over-cap branch already self-mutates (irreversible prune of unreviewed quarantine entries beyond git history) — no clean undo fits the registry's undo contract"
  [32]="NO_REMEDY:judgment-required — two valid fixes exist with different control-flow semantics; picking wrong one changes behavior"
  [33]="NO_REMEDY:judgment-required — can't invent domain-relevant keywords"
  [34]="NO_REMEDY:excluded-high-risk — mutates live scheduler outside the repo (ADR-077 Decision #4)"
  [35]="NO_REMEDY:judgment-required — field content (actual registered paths) can't be synthesized as empty"
  [36]="NO_REMEDY:deferred-wave2 — mechanical (prepend ruflo preamble boilerplate) but not wired in v1"
  [37]="NO_REMEDY:judgment-required — check only knows what's retired, not what the current correct string is"
  [38]="NO_REMEDY:judgment-required — requires re-running an adversarial spike before bumping the version constant — not automatable"
  [39]="NO_REMEDY:judgment-required — args->command isn't a pure syntax transform; needs the actual command string constructed"
  [40]="NO_REMEDY:judgment-required — needs actual descriptive copy, can't synthesize"
  [41]="NO_REMEDY:not-fixable — regression test; a failure needs an arbitrary code fix in feed-summarize.sh"
  [42]="HAS_REMEDY"
  [43]="NO_REMEDY:judgment-required — implementing a missing mode branch is code authoring"
  [44]="NO_REMEDY:deferred-wave2 — mechanical (text substitute LIGHT -> NANO) but not wired in v1"
  [45]="NO_REMEDY:deferred-wave2 — mechanical (append missing tool name to nearest ToolSearch) but not wired in v1"
  [46]="NO_REMEDY:not-fixable — compile errors need arbitrary code fixes"
  [47]="NO_REMEDY:excluded-high-risk — wrong JSON shape would reintroduce the exact silent-hook-failure class the check guards against (ADR-077 Decision #4)"
  [48]="NO_REMEDY:judgment-required — needs authored table content describing what the hook blocks"
  [48a]="NO_REMEDY:judgment-required — needs authored table content describing what the hook blocks"
  [48b]="NO_REMEDY:deferred-wave2 — mechanical (delete stale doc row) but not wired in v1"
  [49]="NO_REMEDY:judgment-required — a new inventory row needs a description of what the hook does"
  [50]="NO_REMEDY:judgment-required — deleting the field vs allowlisting it as intentional legacy is a real design decision"
  [51]="NO_REMEDY:judgment-required — correct replacement command string can't be synthesized from the violation alone"
  [52]="NO_REMEDY:judgment-required — needs real procedure content, not just a heading"
  [53]="NO_REMEDY:deferred-wave2 — mechanical for the wrong-form sub-case (rewrite stub path) but not wired in v1"
  [54]="NO_REMEDY:judgment-required — new procedure content authoring"
  [55]="NO_REMEDY:judgment-required — new procedure content authoring"
  [56]="NO_REMEDY:judgment-required — content edit must be inserted in correct surrounding context"
  [57]="NO_REMEDY:judgment-required — broken link target and emptied content both need human-authored fixes"
  [58]="NO_REMEDY:excluded-high-risk — mutates live scheduler outside the repo (ADR-077 Decision #4)"
  [59]="NO_REMEDY:excluded-high-risk — moves git worktrees outside the repo, could disrupt an in-progress session (ADR-077 Decision #4)"
  [60]="NO_REMEDY:deferred-wave2 — mechanical (append missing tool to allowed-tools) but not wired in v1"
  [61]="NO_REMEDY:not-fixable — a sandbox breach means a security-boundary code fix, inherently judgment-required and high-stakes"
  [62]="HAS_REMEDY"
  [63]="HAS_REMEDY"
  [64]="HAS_REMEDY"
  [65]="NO_REMEDY:not-fixable — regression test; needs an arbitrary code fix in statusline.sh"
  [66]="NO_REMEDY:not-fixable — regression test; needs an arbitrary code fix in statusline.sh"
  [67]="NO_REMEDY:deferred-wave2 — mechanical but medium-risk (repo-wide reference rewrite); not wired in v1"
  [68]="NO_REMEDY:not-fixable — explicit author intent — the check's own message states it never auto-corrects, by design"
)

# remedy_lookup CHECK_ID — print "HAS_REMEDY" or the NO_REMEDY reason (without the
# "NO_REMEDY:" prefix) for CHECK_ID. Prints nothing and returns 1 if CHECK_ID has no
# registry entry at all (should never happen for a real check id — that's what the
# completeness test guards against; --fix dispatch treats this as a hard error, not
# a silent no-op).
remedy_lookup() {
    local id="$1"
    local entry="${REMEDY_REGISTRY[$id]:-}"
    if [ -z "$entry" ]; then
        return 1
    fi
    printf '%s\n' "$entry"
    return 0
}
