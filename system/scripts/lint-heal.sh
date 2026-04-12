#!/usr/bin/env bash
# lint-heal.sh — Deterministic Lint+Heal L2 for brana Layer 2 memory
#
# Capabilities (all deterministic, zero LLM, zero token cost):
#   Pass 1: Dedup         — archive stale projects/ copies by name: frontmatter
#   Pass 2: Contradiction — grep directional keyword pairs across feedback/project files
#   Pass 3: Imputation    — fill missing name:/type:/description: frontmatter fields
#   Pass 4: Surfacing     — flag concepts ≥10 refs with no dedicated doc
#
# Layer 2 only. Never deletes — always archives.
# See: docs/architecture/features/lint-heal-deterministic.md
#
# Usage:
#   lint-heal.sh [--dry-run] [--verbose]
#   lint-heal.sh --help

set -euo pipefail

# ── Config ────────────────────────────────────────────────────
# LINT_HEAL_MEMORY_ROOT overrides $HOME/.claude/projects (used in tests)
MEMORY_ROOT="${LINT_HEAL_MEMORY_ROOT:-$HOME/.claude/projects}"
ARCHIVE_BASE="$HOME/.claude/memory/archive"
REPORT_FILE="$HOME/.claude/lint-heal-report.md"
LOCK_FILE="$HOME/.swarm/lint-heal.lock"
STATE_FILE="$HOME/.swarm/lint-heal-state.json"
TODAY=$(date +%Y-%m-%d)
ARCHIVE_DIR="$ARCHIVE_BASE/$TODAY"
SNAPSHOT_DIR="$HOME/.claude/memory/pre-lint-heal-$TODAY"

DRY_RUN=0
VERBOSE=0

# ── Args ──────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=1 ;;
        --verbose|-v) VERBOSE=1 ;;
        --help|-h)
            cat <<'EOF'
Usage: lint-heal.sh [--dry-run] [--verbose]

Deterministic L2 memory consolidation for brana. Layer 2 only.

Passes:
  1. Dedup         archive stale projects/ copies by name: frontmatter match
  2. Contradiction grep directional keyword pairs (feedback/project files only)
  3. Imputation    fill missing name:/type:/description: frontmatter fields
  4. Surfacing     flag concepts ≥10 refs across MEMORY.md with no dedicated doc

Options:
  --dry-run   Show all planned changes, write nothing
  --verbose   Extra debug logging
  --help      Show this help and exit

Environment:
  LINT_HEAL_DRY_RUN=1      same as --dry-run
  LINT_HEAL_VERBOSE=1      same as --verbose
  LINT_HEAL_MEMORY_ROOT=   override memory root (tests only)
EOF
            exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

[[ "${LINT_HEAL_DRY_RUN:-0}"  == "1" ]] && DRY_RUN=1
[[ "${LINT_HEAL_VERBOSE:-0}" == "1" ]] && VERBOSE=1

# ── Logging ───────────────────────────────────────────────────
log()     { echo "[lint-heal] $*" >&2; }
dbg()     { [[ $VERBOSE -eq 1 ]] && echo "[lint-heal:dbg] $*" >&2 || true; }
dry_log() { echo "[DRY-RUN] would: $*" >&2; }

# ── Layer 2 allow-list guard ──────────────────────────────────
# Refuse to write any path outside these prefixes.
# Uses $HOME (not ~) throughout — realpath -m does not expand ~.
assert_allowed() {
    local path="$1"
    local real_path
    real_path=$(realpath -m "$path")
    local -a allowed=(
        "$(realpath -m "$HOME/.claude/projects")"
        "$(realpath -m "$HOME/.claude/memory/archive")"
        "$(realpath -m "$HOME/.claude/memory/pre-lint-heal")"
        "$(realpath -m "$HOME/.claude/lint-heal-report.md")"
        "$(realpath -m "$HOME/.swarm/lint-heal-state.json")"
        "$(realpath -m "$HOME/.swarm/lint-heal.lock")"
    )
    # Also allow MEMORY_ROOT if it's been overridden (tests)
    if [[ "$MEMORY_ROOT" != "$HOME/.claude/projects" ]]; then
        allowed+=("$(realpath -m "$MEMORY_ROOT")")
        allowed+=("$(realpath -m "$HOME/.claude/memory")")
    fi
    for pfx in "${allowed[@]}"; do
        [[ "$real_path" == "$pfx"* ]] && return 0
    done
    echo "FATAL: write outside Layer 2 allow-list: $path" >&2
    exit 1
}

# ── Lock file (PID + stale detection) ────────────────────────
acquire_lock() {
    mkdir -p "$HOME/.swarm"
    if [[ -f "$LOCK_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            echo "lint-heal already running (PID $old_pid). Aborting." >&2
            exit 1
        fi
        dbg "Stale lock from PID ${old_pid:-unknown}, removing."
        rm -f "$LOCK_FILE"
    fi
    echo "$$" > "$LOCK_FILE"
}
release_lock() { rm -f "$LOCK_FILE" 2>/dev/null || true; }
trap release_lock EXIT

# ── Archive helper ────────────────────────────────────────────
# Archives src to ARCHIVE_DIR using flattened filename.
# Path separator: __ (double-underscore). Note: collision if any path
# segment itself contains __ — unlikely with current portfolio paths.
archive_file() {
    local src="$1"
    local rel="${src#$MEMORY_ROOT/}"
    # Fall back to stripping $HOME/.claude/projects/ if MEMORY_ROOT differs
    [[ "$rel" == "$src" ]] && rel="${src#$HOME/.claude/projects/}"
    local flat="${rel//\//__}"
    local dst="$ARCHIVE_DIR/$flat"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_log "archive $(basename "$src") → $ARCHIVE_DIR/$flat"
        return 0
    fi
    assert_allowed "$dst"
    mkdir -p "$ARCHIVE_DIR"
    cp "$src" "$dst"
    log "  archived: $flat"
}

# ── Rollback snapshot ─────────────────────────────────────────
take_snapshot() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_log "snapshot $MEMORY_ROOT → $SNAPSHOT_DIR"
        return 0
    fi
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        dbg "Snapshot for today exists, skipping: $SNAPSHOT_DIR"
        return 0
    fi
    assert_allowed "$SNAPSHOT_DIR"
    log "Taking rollback snapshot → $SNAPSHOT_DIR"
    cp -r "$MEMORY_ROOT" "$SNAPSHOT_DIR" 2>/dev/null \
        || log "Warning: snapshot failed (non-fatal, continuing)"
    # Prune snapshots older than 7 days
    find "$HOME/.claude/memory" -maxdepth 1 -name 'pre-lint-heal-*' -type d \
        -mtime +7 -exec rm -rf {} + 2>/dev/null || true
}

# ── State update ──────────────────────────────────────────────
update_state() {
    local ts
    ts=$(date +%s)
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dry_log "update $STATE_FILE: {last_run_ts: $ts, session_count_since_run: 0}"
        return 0
    fi
    assert_allowed "$STATE_FILE"
    mkdir -p "$(dirname "$STATE_FILE")"
    printf '{"last_run_ts": %d, "session_count_since_run": 0, "last_run_date": "%s"}\n' \
        "$ts" "$TODAY" > "$STATE_FILE"
}

# ══════════════════════════════════════════════════════════════
# PASS 1: Dedup
# Find files with same name: frontmatter across memory dirs.
# Stale rule: projects/* copy when clients/* has same name → archive projects/
# Tiebreak: archive less-recently-modified (stat -c %Y, Linux).
# ══════════════════════════════════════════════════════════════
pass_dedup() {
    log "Pass 1: Dedup"
    local idx
    idx=$(mktemp)
    local dups
    dups=$(mktemp)
    local count=0

    # Build name → path index (name TAB filepath)
    while IFS= read -r f; do
        [[ ! -f "$f" ]] && continue
        local name
        name=$(sed -n 's/^name:[[:space:]]*//p' "$f" 2>/dev/null | head -1 | tr -d '\r\n') || true
        [[ -z "$name" ]] && continue
        printf '%s\t%s\n' "$name" "$f"
    done < <(find "$MEMORY_ROOT" \( -name 'feedback_*.md' -o -name 'project_*.md' \) \
        -type f 2>/dev/null) > "$idx"

    # Group by name; output only names with ≥2 files (using SUBSEP=\034 as separator)
    sort "$idx" | awk -F'\t' '
    {
        if ($1 in files) files[$1] = files[$1] "\034" $2
        else files[$1] = $2
        counts[$1]++
    }
    END {
        for (n in counts) {
            if (counts[n] >= 2) print n "|" files[n]
        }
    }' > "$dups"

    while IFS='|' read -r name paths_str; do
        # Split on SUBSEP (\034)
        local -a paths=()
        local -a stale=()
        local -a canonical=()
        IFS=$'\034' read -ra paths <<< "$paths_str"

        for p in "${paths[@]}"; do
            [[ -z "$p" ]] && continue
            # Check if path is under a "projects/" subdir RELATIVE to MEMORY_ROOT
            local rel_p="${p#$MEMORY_ROOT/}"
            if [[ "$rel_p" == projects/* ]]; then
                stale+=("$p")
            else
                canonical+=("$p")
            fi
        done

        if [[ ${#canonical[@]} -gt 0 && ${#stale[@]} -gt 0 ]]; then
            # Archive stale (projects/) copies
            for s in "${stale[@]}"; do
                [[ -f "$s" ]] || continue
                log "  dedup '$name': archiving stale: $(basename "$s")"
                archive_file "$s"
                [[ "$DRY_RUN" -eq 0 ]] && rm -f "$s"
                count=$((count + 1))
            done

        elif [[ ${#paths[@]} -ge 2 ]]; then
            # All canonical: archive the least-recently-modified
            local oldest="" oldest_mtime=9999999999
            for p in "${paths[@]}"; do
                [[ -f "$p" ]] || continue
                local mtime
                mtime=$(stat -c '%Y' "$p" 2>/dev/null || echo 9999999999)
                if [[ "$mtime" -lt "$oldest_mtime" ]]; then
                    oldest_mtime=$mtime
                    oldest=$p
                fi
            done
            if [[ -n "${oldest:-}" && -f "$oldest" ]]; then
                log "  dedup '$name': archiving oldest (mtime $oldest_mtime): $(basename "$oldest")"
                archive_file "$oldest"
                [[ "$DRY_RUN" -eq 0 ]] && rm -f "$oldest"
                count=$((count + 1))
            fi
        fi
    done < "$dups"

    rm -f "$idx" "$dups"
    log "Pass 1 done: $count files archived"
    echo "$count"
}

# ══════════════════════════════════════════════════════════════
# PASS 2: Contradiction detection
# Scan feedback_*.md + project_*.md ONLY (MEMORY.md explicitly excluded).
# Concept slug: tokens after directional keyword, up to 4, hyphen-joined.
# Threshold: ≥2 distinct files per polarity before flagging.
# Surface only — no auto-fix.
# ══════════════════════════════════════════════════════════════

# Extract concept slug from a line containing a directional keyword.
# Outputs: concept_slug (or empty if none found)
_extract_concept_slug() {
    local line="$1"
    # awk: find keyword, take next ≤4 tokens, lowercase+hyphen-join, strip non-alnum
    echo "$line" | awk '
    # slug_of: take ≤4 fields starting at position start, stop at common prepositions.
    # Example: "always use uv run python" → "uv-run-python"
    #          "always use ruflo for memory" → "ruflo" (stops at "for")
    function slug_of(start,   i, n, w, s, sw) {
        split("for in at of when to a an the and or but with by from on if is are was be been", sw_arr)
        for (k in sw_arr) sw[sw_arr[k]] = 1
        n = (NF - start + 1 > 4) ? 4 : NF - start + 1
        s = ""
        for (i = 0; i < n; i++) {
            w = tolower($(start + i))
            gsub(/[^a-z0-9]/, "", w)
            if (sw[w]) break   # stop at stopword/preposition
            if (length(w) >= 2) s = (s == "") ? w : s "-" w
        }
        return s
    }
    {
        for (i = 1; i <= NF; i++) {
            w = tolower($i)
            gsub(/[^a-z]/, "", w)
            # "prefer X..." or "always use X..." (two-token keyword)
            if (w == "prefer" && i < NF) { print slug_of(i+1); next }
            if (w == "always" && i < NF && tolower($(i+1)) == "use") { print slug_of(i+2); next }
            # "avoid X..." or "never use X..." (two-token keyword)
            if (w == "avoid" && i < NF) { print slug_of(i+1); next }
            if (w == "never" && i < NF && tolower($(i+1)) == "use") { print slug_of(i+2); next }
        }
    }
    '
}

pass_contradiction() {
    log "Pass 2: Contradiction detection"
    local pos_file neg_file
    pos_file=$(mktemp)   # concept_slug TAB filepath
    neg_file=$(mktemp)

    while IFS= read -r f; do
        [[ ! -f "$f" ]] && continue
        while IFS= read -r line; do
            # Positive keywords
            if echo "$line" | grep -qiE "\b(prefer|always use)\b"; then
                local slug
                slug=$(_extract_concept_slug "$line")
                echo "$slug" | grep -qE "^(${CONTRADICTION_STOPWORDS})$" && slug=""
                [[ -n "$slug" ]] && printf '%s\t%s\n' "$slug" "$f" >> "$pos_file"
            fi
            # Negative keywords
            if echo "$line" | grep -qiE "\b(avoid|never use)\b"; then
                local slug
                slug=$(_extract_concept_slug "$line")
                echo "$slug" | grep -qE "^(${CONTRADICTION_STOPWORDS})$" && slug=""
                [[ -n "$slug" ]] && printf '%s\t%s\n' "$slug" "$f" >> "$neg_file"
            fi
        done < "$f"
    done < <(find "$MEMORY_ROOT" \( -name 'feedback_*.md' -o -name 'project_*.md' \) \
        -type f 2>/dev/null)

    # Find concepts in both sets with ≥2 distinct files per polarity
    # Sort + uniq to deduplicate (same concept + same file)
    local pos_counts neg_counts
    pos_counts=$(mktemp)
    neg_counts=$(mktemp)

    sort -u "$pos_file" | awk -F'\t' '{count[$1]++} END {for(c in count) print count[c], c}' \
        > "$pos_counts"
    sort -u "$neg_file" | awk -F'\t' '{count[$1]++} END {for(c in count) print count[c], c}' \
        > "$neg_counts"

    local findings=""
    local count=0

    # Join on concept slug, filter where both ≥2
    while read -r pos_count concept; do
        [[ "$pos_count" -lt 2 ]] && continue
        local neg_count
        neg_count=$(awk -v c="$concept" '$2 == c {print $1}' "$neg_counts" || echo "0")
        neg_count=${neg_count:-0}
        [[ "$neg_count" -lt 2 ]] && continue

        # Get representative filenames (avoid xargs for portability)
        local pos_files neg_files
        pos_files=$(grep -F "$concept" "$pos_file" | awk -F'\t' '{print $2}' | \
            while IFS= read -r f; do basename "$f"; done | head -2 | paste -sd ',' -)
        neg_files=$(grep -F "$concept" "$neg_file" | awk -F'\t' '{print $2}' | \
            while IFS= read -r f; do basename "$f"; done | head -2 | paste -sd ',' -)

        findings="${findings}- **${concept}**: positive in [${pos_files}], negative in [${neg_files}]"$'\n'
        count=$((count + 1))
    done < "$pos_counts"

    rm -f "$pos_file" "$neg_file" "$pos_counts" "$neg_counts"
    log "Pass 2 done: $count contradiction candidates"
    # Return via temp file to avoid subshell count issue
    printf '%d\n%s' "$count" "$findings"
}

# ══════════════════════════════════════════════════════════════
# PASS 3: Frontmatter imputation
# Fill missing name:/type:/description: in feedback_*.md / project_*.md
# that have a frontmatter block (--- delimiters). Files without --- are skipped.
# ══════════════════════════════════════════════════════════════
pass_imputation() {
    log "Pass 3: Frontmatter imputation"
    local count=0

    while IFS= read -r f; do
        [[ ! -f "$f" ]] && continue
        local base
        base=$(basename "$f" .md)

        # Check for frontmatter block (need ≥2 lines with ---)
        local fm_count
        fm_count=$(grep -c "^---$" "$f" 2>/dev/null || echo 0)
        [[ "$fm_count" -lt 2 ]] && continue

        local has_name has_type has_desc
        # Use grep -cm1 + head -1 to ensure single-line numeric output
        has_name=$(grep -cm1 "^name:" "$f" 2>/dev/null | head -1 || echo 0)
        has_type=$(grep -cm1 "^type:" "$f" 2>/dev/null | head -1 || echo 0)
        has_desc=$(grep -cm1 "^description:" "$f" 2>/dev/null | head -1 || echo 0)

        # Skip if all fields present
        [[ "$has_name" -gt 0 && "$has_type" -gt 0 && "$has_desc" -gt 0 ]] && continue

        # Derive imputed values
        local imputed_name imputed_type imputed_desc
        imputed_name="${base#feedback_}"
        imputed_name="${imputed_name#project_}"
        imputed_name="${imputed_name#reference_}"

        if [[ "$base" == feedback_* ]]; then
            imputed_type="feedback"
        elif [[ "$base" == project_* ]]; then
            imputed_type="project"
        else
            imputed_type="reference"
        fi

        # First non-empty content line after closing ---
        imputed_desc=$(awk '
            /^---$/ { if (fm++) body=1; next }
            body && NF { print; exit }
        ' "$f" 2>/dev/null | sed 's/[#*`_\[\]]//g; s/  */ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | \
            head -c 120 || echo "")

        if [[ "$DRY_RUN" -eq 1 ]]; then
            [[ "$has_name" -eq 0 ]]  && dry_log "impute name: '$imputed_name' in $(basename "$f")"
            [[ "$has_type" -eq 0 ]]  && dry_log "impute type: '$imputed_type' in $(basename "$f")"
            [[ "$has_desc" -eq 0 && -n "$imputed_desc" ]] && \
                dry_log "impute description: '${imputed_desc:0:40}...' in $(basename "$f")"
            continue
        fi

        assert_allowed "$f"
        local tmp_file="${f}.lint-heal-tmp"

        # Inject missing fields after the opening ---
        # awk injects right after the first ---, before existing fields
        awk \
            -v hn="$has_name"    -v iname="$imputed_name" \
            -v ht="$has_type"    -v itype="$imputed_type" \
            -v hd="$has_desc"    -v idesc="$imputed_desc" \
            '
            BEGIN { injected = 0 }
            /^---$/ && !injected {
                print
                if (hn + 0 == 0) print "name: " iname
                if (ht + 0 == 0) print "type: " itype
                if (hd + 0 == 0 && idesc != "") print "description: " idesc
                injected = 1
                next
            }
            { print }
            ' "$f" > "$tmp_file" 2>/dev/null && {
                mv "$tmp_file" "$f"
                count=$((count + 1))
                log "  imputed fields in: $(basename "$f")"
            } || {
                rm -f "$tmp_file"
                log "  Warning: imputation failed for $(basename "$f") (skipped)"
            }
    done < <(find "$MEMORY_ROOT" \( -name 'feedback_*.md' -o -name 'project_*.md' \) \
        -type f 2>/dev/null)

    log "Pass 3 done: $count files imputed"
    echo "$count"
}

# ══════════════════════════════════════════════════════════════
# PASS 4: Concept-reference surfacing
# Scan MEMORY.md files for words ≥8 chars with ≥10 occurrences.
# Slug-normalize and check against existing feedback/project/dimension docs.
# Surface undocumented concepts in report only.
# ══════════════════════════════════════════════════════════════

# Normalize a concept or filename slug: strip common prefixes, convert _ to -
normalize_slug() {
    echo "$1" | sed 's/^feedback_//; s/^project_//; s/^reference_//; s/_/-/g' | tr '[:upper:]' '[:lower:]'
}

# Stopwords for Pass 2 (contradiction detection): generic terms that produce false positives.
# These appear in many diverse feedback files without representing a real contradiction.
CONTRADICTION_STOPWORDS="production|directly|thebrana|commands"

CONCEPT_STOPWORDS="linkedin|category|martineserios|follow-up|session-start|architecture|reconcile|maintenance|detected|description|research|claude-code|projects|knowledge|feedback|available|completed|following|implement|important|parameter|configure|existing|expected|function|generate|identify|increase|multiple|possible|previous|provides|required|response|separate|specific|strategy|template|variable|whatever|whenever|wherever|workflow"

pass_surfacing() {
    log "Pass 4: Concept-reference surfacing"

    # Build slug set from existing docs (feedback_, project_, dimensions)
    local known_slugs
    known_slugs=$(mktemp)

    find "$MEMORY_ROOT" \( -name 'feedback_*.md' -o -name 'project_*.md' \
        -o -name 'reference_*.md' \) -type f 2>/dev/null | \
        xargs -I{} basename {} .md 2>/dev/null | \
        while read -r name; do normalize_slug "$name"; done > "$known_slugs"

    # Also add dimension doc slugs if the brana-knowledge dir exists
    local bk_dir="$HOME/enter_thebrana/brana-knowledge/dimensions"
    if [[ -d "$bk_dir" ]]; then
        find "$bk_dir" -name '*.md' -type f 2>/dev/null | \
            xargs -I{} basename {} .md 2>/dev/null | \
            while read -r name; do normalize_slug "$name"; done >> "$known_slugs"
    fi

    # Count word occurrences across all MEMORY.md files
    local word_counts
    word_counts=$(mktemp)

    find "$MEMORY_ROOT" -name 'MEMORY.md' -type f 2>/dev/null | \
        xargs grep -oh '\b[a-z][a-z_-]*[a-z]\b' 2>/dev/null | \
        grep -v -E "^($CONCEPT_STOPWORDS)$" | \
        awk 'length($0) >= 8' | \
        sort | uniq -c | sort -rn | \
        awk '$1 >= 10 {print $1, $2}' > "$word_counts"

    local concept_report=""
    local count=0

    while read -r ref_count word; do
        local slug
        slug=$(normalize_slug "$word")
        # Check if a doc exists with this slug (substring match after normalization)
        if grep -qF "$slug" "$known_slugs" 2>/dev/null; then
            dbg "  concept '$word' ($ref_count refs) — has dedicated doc, skipping"
            continue
        fi
        concept_report="${concept_report}- **${word}** (${ref_count} refs) — no dedicated doc"$'\n'
        count=$((count + 1))
    done < "$word_counts"

    rm -f "$known_slugs" "$word_counts"
    log "Pass 4 done: $count undocumented concepts"
    printf '%d\n%s' "$count" "$concept_report"
}

# ══════════════════════════════════════════════════════════════
# REPORT
# ══════════════════════════════════════════════════════════════
write_report() {
    local dedup_count="$1"
    local contra_output="$2"
    local imputed_count="$3"
    local surface_output="$4"

    local contra_count contra_findings surface_count surface_findings
    contra_count=$(echo "$contra_output" | head -1)
    contra_findings=$(echo "$contra_output" | tail -n +2)
    surface_count=$(echo "$surface_output" | head -1)
    surface_findings=$(echo "$surface_output" | tail -n +2)

    local dry_prefix=""
    [[ "$DRY_RUN" -eq 1 ]] && dry_prefix="[DRY-RUN] "

    local report
    report=$(cat <<EOF
# ${dry_prefix}Lint+Heal Report — $TODAY

> L2 deterministic pass. Zero LLM. Layer 2 only.
> Run \`brana memory audit\` to review and approve candidates.

## Summary

| Pass | Result |
|------|--------|
| Dedup (Pass 1) | $dedup_count files archived |
| Contradiction candidates (Pass 2) | $contra_count (surface only — review before acting) |
| Frontmatter imputed (Pass 3) | $imputed_count files |
| Undocumented concepts (Pass 4) | $surface_count |

## Contradiction Candidates

> Pairs where one file says "prefer X" and another says "avoid X" for the same
> concept slug, with ≥2 distinct files on each side.
> Review manually. Mark resolved: add \`contradiction: resolved\` to one file's frontmatter.

${contra_findings:-_No candidates found._}

## Undocumented Concepts (≥10 refs, no dedicated doc)

> Consider creating a \`feedback_*.md\` or dimension doc for high-ref concepts.

${surface_findings:-_None found._}

---
_Generated by lint-heal.sh on $TODAY._
_Rollback: \`cp -r ~/.claude/memory/pre-lint-heal-$TODAY/. ~/.claude/projects/\`_
EOF
)

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo ""
        echo "=== REPORT PREVIEW ==="
        echo "$report"
        echo "=== END PREVIEW ==="
    else
        assert_allowed "$REPORT_FILE"
        mkdir -p "$(dirname "$REPORT_FILE")"
        echo "$report" > "$REPORT_FILE"
        log "Report → $REPORT_FILE"
    fi
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════
main() {
    log "Starting Lint+Heal L2 $([ "$DRY_RUN" -eq 1 ] && echo "(DRY-RUN)" || true)"
    log "Memory root: $MEMORY_ROOT"

    acquire_lock
    take_snapshot

    local dedup_count contra_output imputed_count surface_output
    dedup_count=$(pass_dedup)
    contra_output=$(pass_contradiction)
    imputed_count=$(pass_imputation)
    surface_output=$(pass_surfacing)

    write_report "$dedup_count" "$contra_output" "$imputed_count" "$surface_output"
    update_state

    log "Done. Dedup=$dedup_count Imputed=$imputed_count"
    [[ "$DRY_RUN" -eq 0 ]] && log "Report: $REPORT_FILE"
}

main "$@"
