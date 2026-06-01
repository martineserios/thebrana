#!/usr/bin/env bash
# verify-docs.sh — Periodic doc verification surface (t-441 prereq).
# Wraps validate.sh --assumptions-only and surfaces a random sample of
# assumption rows for manual semantic review.
# --scope claudemd: scan portfolio CLAUDE.md files for volatile-content violations.
# Spec: system/scripts/verify-docs.spec.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${BRANA_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
VALIDATE="$REPO_ROOT/validate.sh"
DOCS_DIR="$REPO_ROOT/docs"
PORTFOLIO_ROOT="${BRANA_PORTFOLIO_ROOT:-$(cd "$REPO_ROOT/.." && pwd)}"

# ── Args ───────────────────────────────────────────────────
SAMPLE=5
JSON=false
SEED="${RANDOM}${RANDOM}"
SCOPE="docs"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sample)  SAMPLE="$2"; shift 2 ;;
        --json)    JSON=true; shift ;;
        --seed)    SEED="$2"; shift 2 ;;
        --scope)   SCOPE="$2"; shift 2 ;;
        -h|--help)
            cat <<EOF
Usage: verify-docs.sh [--sample N] [--json] [--seed N] [--scope docs|claudemd]

  --sample N       Number of assumption rows to surface (default: 5)
  --json           Emit JSON output
  --seed N         RNG seed for reproducible sampling
  --scope docs     Run assumption-row structural check + sample (default)
  --scope claudemd Scan portfolio CLAUDE.md files for volatile-content violations
EOF
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

# ── CLAUDE.md portfolio scan (--scope claudemd) ────────────
run_claudemd_scan() {
    if [ ! -d "$PORTFOLIO_ROOT" ]; then
        echo "verify-docs: PORTFOLIO_ROOT not found at $PORTFOLIO_ROOT" >&2
        exit 2
    fi

    local -a viols_dated=() viols_pricing=() viols_tracker=()
    local total_files=0 f rel hit

    while IFS= read -r f; do
        total_files=$((total_files + 1))
        rel="${f#$PORTFOLIO_ROOT/}"

        # DATED_STATUS: lines with embedded 202X-MM-DD dates, excluding frontmatter key:value
        while IFS= read -r hit; do
            [ -n "$hit" ] && viols_dated+=("$rel|$hit")
        done < <(grep -nE '202[0-9]-[0-9]{2}-[0-9]{2}' "$f" \
                 | grep -vE '^[0-9]+:[[:space:]]*[a-z_]+:[[:space:]]' || true)

        # PRICING: $N/mes, ARS N/mes, USD N/mes
        while IFS= read -r hit; do
            [ -n "$hit" ] && viols_pricing+=("$rel|$hit")
        done < <(grep -nE '(\$[0-9]|ARS[[:space:]]+[0-9]|USD[[:space:]]+[0-9])[^/]*/mes' "$f" || true)

        # TRACKER_TABLE: table header lines with Status + work-tracker columns
        while IFS= read -r hit; do
            [ -n "$hit" ] && viols_tracker+=("$rel|$hit")
        done < <(grep -nE '^\|.*\bStatus\b.*\|' "$f" \
                 | grep -E '\b(Priority|Effort|Sprint|Assigned)\b' || true)

    done < <(find "$PORTFOLIO_ROOT" -name "CLAUDE.md" \
                  -not -path "*worktree*" 2>/dev/null | sort)

    local total_v=$(( ${#viols_dated[@]} + ${#viols_pricing[@]} + ${#viols_tracker[@]} ))

    if [ "$JSON" = true ]; then
        local dated_json="[]" pricing_json="[]" tracker_json="[]"
        [ ${#viols_dated[@]} -gt 0 ] && dated_json=$(
            printf '%s\n' "${viols_dated[@]}" | jq -R -s '
                split("\n") | map(select(length > 0)) | map(
                    . as $r | ($r | index("|")) as $i |
                    {file: $r[0:$i], match: $r[($i+1):]})' || true)
        [ ${#viols_pricing[@]} -gt 0 ] && pricing_json=$(
            printf '%s\n' "${viols_pricing[@]}" | jq -R -s '
                split("\n") | map(select(length > 0)) | map(
                    . as $r | ($r | index("|")) as $i |
                    {file: $r[0:$i], match: $r[($i+1):]})' || true)
        [ ${#viols_tracker[@]} -gt 0 ] && tracker_json=$(
            printf '%s\n' "${viols_tracker[@]}" | jq -R -s '
                split("\n") | map(select(length > 0)) | map(
                    . as $r | ($r | index("|")) as $i |
                    {file: $r[0:$i], match: $r[($i+1):]})' || true)
        jq -n \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --argjson files "$total_files" \
            --argjson total "$total_v" \
            --argjson dated "$dated_json" \
            --argjson pricing "$pricing_json" \
            --argjson tracker "$tracker_json" \
            '{
                timestamp: $ts,
                scope: "claudemd",
                files_scanned: $files,
                total_violations: $total,
                violations: {
                    DATED_STATUS: $dated,
                    PRICING: $pricing,
                    TRACKER_TABLE: $tracker
                }
            }'
    else
        echo "=== verify-docs --scope claudemd ==="
        echo ""
        printf "Scanned %d CLAUDE.md files\n" "$total_files"
        echo ""
        if [ "$total_v" -eq 0 ]; then
            echo "PASS — 0 volatile-content violations found."
        else
            printf "VIOLATIONS: %d total\n\n" "$total_v"
            local v file match
            if [ ${#viols_dated[@]} -gt 0 ]; then
                printf "DATED_STATUS (%d) — status lines with embedded dates:\n" "${#viols_dated[@]}"
                for v in "${viols_dated[@]}"; do
                    file="${v%%|*}"; match="${v#*|}"
                    printf "  %s:%s\n" "$file" "$match"
                done
                echo ""
            fi
            if [ ${#viols_pricing[@]} -gt 0 ]; then
                printf "PRICING (%d) — service cost lines:\n" "${#viols_pricing[@]}"
                for v in "${viols_pricing[@]}"; do
                    file="${v%%|*}"; match="${v#*|}"
                    printf "  %s:%s\n" "$file" "$match"
                done
                echo ""
            fi
            if [ ${#viols_tracker[@]} -gt 0 ]; then
                printf "TRACKER_TABLE (%d) — work-tracker table headers:\n" "${#viols_tracker[@]}"
                for v in "${viols_tracker[@]}"; do
                    file="${v%%|*}"; match="${v#*|}"
                    printf "  %s:%s\n" "$file" "$match"
                done
                echo ""
            fi
        fi
        echo "Action: remove volatile content from CLAUDE.md — move to portfolio.md or project docs."
    fi

    [ "$total_v" -eq 0 ] && return 0 || return 1
}

# ── Short-circuit for --scope claudemd ─────────────────────
if [ "$SCOPE" = "claudemd" ]; then
    run_claudemd_scan
    exit $?
fi

# ── Pre-flight ─────────────────────────────────────────────
if [ ! -f "$VALIDATE" ]; then
    echo "verify-docs: validate.sh not found at $VALIDATE" >&2
    exit 2
fi
if [ ! -d "$DOCS_DIR" ]; then
    echo "verify-docs: docs/ not found at $DOCS_DIR" >&2
    exit 2
fi

# ── Structural check (validate.sh Check 15) ───────────────
STRUCT_OUT=$(bash "$VALIDATE" --assumptions-only 2>&1) || true
STRUCT_CHECKED=$(echo "$STRUCT_OUT" | grep -oE '\(([0-9]+) checked\)' | grep -oE '[0-9]+' | head -1)
STRUCT_CHECKED="${STRUCT_CHECKED:-0}"
STRUCT_STALE=$(echo "$STRUCT_OUT" | grep -cE 'Stale assumption in' || true)
if [[ "$STRUCT_OUT" == *"Check 15: PASS"* ]]; then
    STRUCT_EXIT=0
else
    STRUCT_EXIT=1
fi

# ── Extract all assumption rows across docs/ ──────────────
# Reuses the perl pattern from validate.sh check_assumption_freshness.
# Output lines: doc|tier_source|tier|last_verified|claim
extract_rows() {
    local doc="$1"
    local rel="${doc#$REPO_ROOT/}"
    perl -e '
        my $doc = shift;
        my $rel = shift;
        open my $fh, "<", $doc or return;
        my $in_section = 0;
        my $tier_col;
        my $claim_col = 2;  # default: column 2 (after row number) is the claim
        my @rows;
        while (my $line = <$fh>) {
            $in_section = 1 if $line =~ /^##\s+Assumptions/;
            $in_section = 0 if $in_section && $line =~ /^##\s/ && $line !~ /^##\s+Assumptions/;
            next unless $in_section;
            if ($line =~ /^\|\s*\#\s*\|/ && $line =~ /Tier/i) {
                my @cols = split(/\|/, $line);
                for my $i (0..$#cols) {
                    $tier_col = $i if $cols[$i] =~ /\bTier\b/i;
                }
                next;
            }
            next if $line =~ /^\|[\s\-:]*\|/;
            if ($line =~ /^\|.*\|$/) {
                my $date_match;
                if ($line =~ /last.verified[:\s]*(\d{4}-\d{2}-\d{2})/i) {
                    $date_match = $1;
                } elsif ($line =~ /(\d{4}-\d{2}-\d{2})/) {
                    $date_match = $1;
                }
                next unless $date_match;
                my @cells = split(/\|/, $line);
                # cells[0] is empty (leading pipe), cells[1] is row number
                my $row_tier = "";
                if (defined $tier_col) {
                    $row_tier = $cells[$tier_col] // "";
                    $row_tier =~ s/^\s+|\s+$//g;
                    $row_tier = "" if $row_tier !~ /^(tech|architecture|methodology)$/;
                }
                my $claim = $cells[$claim_col] // "";
                $claim =~ s/^\s+|\s+$//g;
                $claim =~ s/\|/ /g;
                $claim = substr($claim, 0, 100);
                print "$rel|$row_tier|$date_match|$claim\n";
            }
        }
    ' "$doc" "$rel"
}

# Read doc-level confidence_tier
doc_tier_of() {
    local doc="$1"
    awk '
        /^---$/ { fm = !fm; next }
        fm && /^confidence_tier:/ { gsub(/^confidence_tier:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }
    ' "$doc" 2>/dev/null
}

ALL_ROWS=()
while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    DOC_TIER=$(doc_tier_of "$doc")
    DOC_TIER="${DOC_TIER:-tech}"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        # row format: rel|row_tier|date|claim
        # Resolve effective tier + source
        ROW_TIER="$(echo "$row" | awk -F'|' '{print $2}')"
        if [ -n "$ROW_TIER" ]; then
            EFF_TIER="$ROW_TIER"
            TIER_SRC="per-row"
        elif [ "$DOC_TIER" != "tech" ]; then
            EFF_TIER="$DOC_TIER"
            TIER_SRC="doc"
        else
            EFF_TIER="tech"
            TIER_SRC="default"
        fi
        REL="$(echo "$row" | awk -F'|' '{print $1}')"
        DATE="$(echo "$row" | awk -F'|' '{print $3}')"
        CLAIM="$(echo "$row" | awk -F'|' '{for(i=4;i<=NF;i++) printf "%s%s", $i, (i<NF?"|":"")}')"
        ALL_ROWS+=("${REL}|${EFF_TIER}|${TIER_SRC}|${DATE}|${CLAIM}")
    done < <(extract_rows "$doc")
done < <(find "$DOCS_DIR" -type f -name "*.md" 2>/dev/null)

TOTAL=${#ALL_ROWS[@]}

# ── Sample N rows deterministically by SEED ───────────────
sample_rows() {
    local n="$1"
    [ "$TOTAL" -eq 0 ] && return
    [ "$n" -gt "$TOTAL" ] && n="$TOTAL"
    # Use awk with srand for reproducibility — print indices, sort, take N
    printf '%s\n' "${ALL_ROWS[@]}" | awk -v seed="$SEED" -v n="$n" '
        BEGIN { srand(seed) }
        { print rand() "\t" $0 }
    ' | sort | head -n "$n" | cut -f2-
}

SAMPLE_LINES=()
while IFS= read -r line; do
    [ -n "$line" ] && SAMPLE_LINES+=("$line")
done < <(sample_rows "$SAMPLE")

# ── Render ─────────────────────────────────────────────────
render_text() {
    echo "=== verify-docs ==="
    echo ""
    if [ "$STRUCT_EXIT" -eq 0 ]; then
        echo "Structural (validate.sh Check 15): PASS — $STRUCT_CHECKED assumptions checked, $STRUCT_STALE stale"
    else
        echo "Structural (validate.sh Check 15): FAIL — $STRUCT_CHECKED checked, $STRUCT_STALE stale"
    fi
    echo ""
    echo "Sample of ${#SAMPLE_LINES[@]} assumptions for manual semantic review:"
    echo ""
    local i=1
    for line in "${SAMPLE_LINES[@]}"; do
        local doc tier src date claim
        doc=$(echo "$line"   | awk -F'|' '{print $1}')
        tier=$(echo "$line"  | awk -F'|' '{print $2}')
        src=$(echo "$line"   | awk -F'|' '{print $3}')
        date=$(echo "$line"  | awk -F'|' '{print $4}')
        claim=$(echo "$line" | awk -F'|' '{for(j=5;j<=NF;j++) printf "%s%s", $j, (j<NF?"|":"")}')
        echo "  [$i] $doc"
        echo "      tier: $tier ($src)"
        echo "      verified: $date"
        echo "      claim: \"$claim\""
        echo "      action: read claim, check current code, mark drift y/n"
        echo ""
        i=$((i + 1))
    done
    echo "Run quarterly. If >20% drift, file follow-up to unblock t-441."
}

render_json() {
    local samples_json="[]"
    if [ "${#SAMPLE_LINES[@]}" -gt 0 ]; then
        samples_json=$(printf '%s\n' "${SAMPLE_LINES[@]}" | jq -R -s 'split("\n") | map(select(length > 0)) | map(
            split("|") as $f | {
                doc: $f[0],
                tier: $f[1],
                tier_source: $f[2],
                last_verified: $f[3],
                claim: ($f[4:] | join("|"))
            }
        )')
    fi
    jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson struct_checked "$STRUCT_CHECKED" \
        --argjson struct_stale "$STRUCT_STALE" \
        --argjson struct_exit "$STRUCT_EXIT" \
        --argjson samples "$samples_json" \
        '{
            timestamp: $ts,
            structural: {
                checked: $struct_checked,
                stale: $struct_stale,
                exit: $struct_exit
            },
            sample: $samples
        }'
}

if [ "$JSON" = true ]; then
    render_json
else
    render_text
fi

exit "$STRUCT_EXIT"
