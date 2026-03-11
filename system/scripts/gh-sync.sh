#!/usr/bin/env bash
set -euo pipefail

# gh-sync.sh — Sync tasks.json with GitHub Issues (t-160)
#
# Subcommands:
#   create <task-id> <tasks-json-path>     — create issue, print issue # to stdout
#   close <issue-number>                   — close issue
#   update <task-id> <tasks-json-path>     — update labels/state from task fields
#   pull-context <issue-number>            — print last 5 comments (structured)
#   sync-all <tasks-json-path> [--dry-run] — bulk sync all non-completed tasks
#   prune-labels                           — remove orphaned sync labels
#
# Exit codes:
#   0 — success
#   1 — GitHub API error
#   2 — auth/CLI failure
#   3 — invalid arguments
#
# Config: reads github_sync from ~/.claude/tasks-config.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$HOME/.claude/tasks-config.json"

# ── Helpers ──────────────────────────────────────────────────

log()  { echo "[gh-sync] $*" >&2; }
warn() { echo "[gh-sync] WARNING: $*" >&2; }
die()  { echo "[gh-sync] ERROR: $*" >&2; exit "${2:-3}"; }

# Check gh CLI is installed and authenticated
check_auth() {
    if ! command -v gh &>/dev/null; then
        die "gh CLI not installed. Install: https://cli.github.com/" 2
    fi
    if ! gh auth status &>/dev/null 2>&1; then
        die "GitHub auth required. Run: gh auth login" 2
    fi
}

# Read config value via jq
config_get() {
    local key="$1"
    if [[ -f "$CONFIG_PATH" ]]; then
        jq -r "$key // empty" "$CONFIG_PATH" 2>/dev/null || echo ""
    fi
}

# Check if sync is enabled
sync_enabled() {
    local enabled
    enabled="$(config_get '.github_sync.enabled')"
    [[ "$enabled" == "true" ]]
}

# Get label config
labels_stream_enabled() { [[ "$(config_get '.github_sync.labels.stream')" == "true" ]]; }
labels_priority_enabled() { [[ "$(config_get '.github_sync.labels.priority')" == "true" ]]; }
labels_tag_count() { config_get '.github_sync.labels.tags // 2'; }

# Read task fields from tasks.json via jq
task_field() {
    local task_id="$1" field="$2" tasks_json="$3"
    jq -r --arg id "$task_id" \
        '.tasks[] | select(.id == $id) | .'"$field"' // empty' \
        "$tasks_json" 2>/dev/null || echo ""
}

# Build labels array for a task
build_labels() {
    local task_id="$1" tasks_json="$2"
    local labels=()

    if labels_stream_enabled; then
        local stream
        stream="$(task_field "$task_id" "stream" "$tasks_json")"
        [[ -n "$stream" ]] && labels+=("stream:$stream")
    fi

    if labels_priority_enabled; then
        local priority
        priority="$(task_field "$task_id" "priority" "$tasks_json")"
        [[ -n "$priority" ]] && labels+=("priority:$priority")
    fi

    local tag_count
    tag_count="$(labels_tag_count)"
    if [[ "$tag_count" -gt 0 ]]; then
        local tags_csv
        tags_csv="$(jq -r --arg id "$task_id" --argjson n "$tag_count" \
            '(.tasks[] | select(.id == $id) | .tags // [])[:$n] | map("tag:" + .) | join(",")' \
            "$tasks_json" 2>/dev/null || echo "")"
        if [[ -n "$tags_csv" ]]; then
            IFS=',' read -ra tag_arr <<< "$tags_csv"
            labels+=("${tag_arr[@]}")
        fi
    fi

    # Join with commas
    local IFS=','
    echo "${labels[*]}"
}

# Ensure labels exist in the repo, create if missing
# Uses --force flag which creates or updates (idempotent)
ensure_labels() {
    local labels_csv="$1"
    [[ -z "$labels_csv" ]] && return

    local color
    IFS=',' read -ra label_arr <<< "$labels_csv"
    for label in "${label_arr[@]}"; do
        case "$label" in
            stream:*)   color="0075ca" ;;  # blue
            priority:*) color="e11d48" ;;  # red
            tag:*)      color="6b7280" ;;  # gray
            *)          color="ededed" ;;  # default
        esac
        # --force: create if missing, update color if exists (idempotent)
        gh label create "$label" --color "$color" --force 2>/dev/null || true
    done
}

# Build issue body from task
build_body() {
    local task_id="$1" tasks_json="$2"
    local stream priority effort strategy execution description context

    stream="$(task_field "$task_id" "stream" "$tasks_json")"
    priority="$(task_field "$task_id" "priority" "$tasks_json")"
    effort="$(task_field "$task_id" "effort" "$tasks_json")"
    strategy="$(task_field "$task_id" "strategy" "$tasks_json")"
    execution="$(task_field "$task_id" "execution" "$tasks_json")"
    description="$(task_field "$task_id" "description" "$tasks_json")"
    context="$(task_field "$task_id" "context" "$tasks_json")"

    cat <<EOF
**Task:** ${task_id} | **Stream:** ${stream:-—} | **Priority:** ${priority:-—} | **Effort:** ${effort:-—}
**Strategy:** ${strategy:-—} | **Execution:** ${execution:-—}

---

${description:-No description.}
$(if [[ -n "$context" ]]; then echo -e "\n${context}"; fi)

---
*Synced from tasks.json by brana*
EOF
}

# ── Subcommands ──────────────────────────────────────────────

cmd_create() {
    local task_id="${1:-}" tasks_json="${2:-}"
    [[ -z "$task_id" || -z "$tasks_json" ]] && die "Usage: gh-sync.sh create <task-id> <tasks-json-path>"
    [[ -f "$tasks_json" ]] || die "tasks.json not found: $tasks_json"

    check_auth

    local subject
    subject="$(task_field "$task_id" "subject" "$tasks_json")"
    [[ -z "$subject" ]] && die "Task $task_id not found in $tasks_json"

    # Dedup: check if issue already exists by searching title
    local tmp_dedup existing
    tmp_dedup="$(mktemp)"
    gh issue list --search "Task: $task_id in:title" --json number > "$tmp_dedup" 2>/dev/null || true
    existing="$(jq -r '.[0].number // empty' "$tmp_dedup" 2>/dev/null || echo "")"
    rm -f "$tmp_dedup"
    if [[ -n "$existing" ]]; then
        log "Issue #$existing already exists for $task_id — skipping creation"
        echo "$existing"
        return 0
    fi

    local title="Task: $task_id — $subject"
    local body
    body="$(build_body "$task_id" "$tasks_json")"
    local labels
    labels="$(build_labels "$task_id" "$tasks_json")"

    # Ensure labels exist before creating issue
    if [[ -n "$labels" ]]; then
        ensure_labels "$labels"
    fi

    local issue_url
    if [[ -n "$labels" ]]; then
        issue_url="$(gh issue create --title "$title" --body "$body" --label "$labels" 2>&1)" || {
            warn "Failed to create issue for $task_id: $issue_url"
            return 1
        }
    else
        issue_url="$(gh issue create --title "$title" --body "$body" 2>&1)" || {
            warn "Failed to create issue for $task_id: $issue_url"
            return 1
        }
    fi

    # Extract issue number from URL (https://github.com/owner/repo/issues/42)
    local issue_number
    issue_number="$(echo "$issue_url" | grep -oP '/issues/\K[0-9]+' || echo "")"
    if [[ -z "$issue_number" ]]; then
        warn "Could not extract issue number from: $issue_url"
        return 1
    fi

    log "Created issue #$issue_number for $task_id"
    echo "$issue_number"
}

cmd_close() {
    local issue_number="${1:-}"
    [[ -z "$issue_number" ]] && die "Usage: gh-sync.sh close <issue-number>"

    check_auth

    # Check if issue exists and get state via temp file
    local tmp_state
    tmp_state="$(mktemp)"
    if ! gh issue view "$issue_number" --json state > "$tmp_state" 2>/dev/null; then
        rm -f "$tmp_state"
        warn "Issue #$issue_number not found (404). May have been deleted."
        return 1
    fi

    local state
    state="$(jq -r '.state' "$tmp_state" 2>/dev/null || echo "")"
    rm -f "$tmp_state"
    if [[ "$state" == "CLOSED" ]]; then
        log "Issue #$issue_number already closed"
        return 0
    fi

    gh issue close "$issue_number" 2>/dev/null || {
        warn "Failed to close issue #$issue_number"
        return 1
    }

    log "Closed issue #$issue_number"
}

cmd_update() {
    local task_id="${1:-}" tasks_json="${2:-}"
    [[ -z "$task_id" || -z "$tasks_json" ]] && die "Usage: gh-sync.sh update <task-id> <tasks-json-path>"
    [[ -f "$tasks_json" ]] || die "tasks.json not found: $tasks_json"

    check_auth

    local issue_number
    issue_number="$(task_field "$task_id" "github_issue" "$tasks_json")"
    [[ -z "$issue_number" ]] && die "Task $task_id has no github_issue set"

    # Check if issue still exists
    if ! gh issue view "$issue_number" --json number >/dev/null 2>&1; then
        warn "Issue #$issue_number not found (404) for $task_id. Clearing link."
        echo "DELETED"
        return 1
    fi

    # Update labels
    local labels
    labels="$(build_labels "$task_id" "$tasks_json")"

    if [[ -n "$labels" ]]; then
        ensure_labels "$labels"

        # Get current labels via temp file (gh --json pipes unreliably in some envs)
        local tmp_labels
        tmp_labels="$(mktemp)"
        gh issue view "$issue_number" --json labels > "$tmp_labels" 2>/dev/null || true

        # Remove old sync labels
        local old_sync_labels
        old_sync_labels="$(jq -r '[.labels[].name | select(test("^(stream:|priority:|tag:)"))] | join(",")' "$tmp_labels" 2>/dev/null || echo "")"
        rm -f "$tmp_labels"

        if [[ -n "$old_sync_labels" ]]; then
            gh issue edit "$issue_number" --remove-label "$old_sync_labels" >/dev/null 2>&1 || true
        fi

        # Add new labels
        gh issue edit "$issue_number" --add-label "$labels" >/dev/null 2>&1 || {
            warn "Failed to update labels on issue #$issue_number"
        }
    fi

    log "Updated issue #$issue_number for $task_id"
}

cmd_pull_context() {
    local issue_number="${1:-}"
    [[ -z "$issue_number" ]] && die "Usage: gh-sync.sh pull-context <issue-number>"

    check_auth

    # Get comments via temp file
    local tmp_comments
    tmp_comments="$(mktemp)"
    if ! gh issue view "$issue_number" --json comments > "$tmp_comments" 2>/dev/null; then
        rm -f "$tmp_comments"
        warn "Issue #$issue_number not found (404)"
        return 1
    fi

    # Extract last 5 comments, structured format
    local comments
    comments="$(jq -r '
        .comments | .[-5:] |
        map("--- @\(.author.login) on \(.createdAt[:10]) ---\n\(.body)") |
        join("\n\n")
    ' "$tmp_comments" 2>/dev/null || echo "")"
    rm -f "$tmp_comments"

    if [[ -z "$comments" || "$comments" == "null" ]]; then
        return 0
    fi

    # Truncate to 2000 chars
    echo "${comments:0:2000}"
}

cmd_sync_all() {
    local tasks_json="${1:-}"
    local dry_run=false
    local exclude_stream=""
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true ;;
            --exclude-stream) shift; exclude_stream="${1:-}" ;;
            *) ;;
        esac
        shift
    done

    [[ -z "$tasks_json" ]] && die "Usage: gh-sync.sh sync-all <tasks-json-path> [--dry-run]"
    [[ -f "$tasks_json" ]] || die "tasks.json not found: $tasks_json"

    check_auth

    local total_created=0 total_closed=0 total_updated=0 total_skipped=0 total_errors=0

    # Find tasks needing sync
    # 1. Non-completed tasks without github_issue → need creation
    local needs_create stream_filter=""
    if [[ -n "$exclude_stream" ]]; then
        stream_filter="| select(.stream != \"$exclude_stream\")"
    fi
    needs_create="$(jq -r --arg excl "$exclude_stream" '
        .tasks[] |
        select(.type == "task" or .type == "subtask" or .type == "phase" or .type == "milestone") |
        select(.status != "completed" and .status != "cancelled") |
        select(.github_issue == null or .github_issue == "") |
        if $excl != "" then select(.stream != $excl) else . end |
        .id
    ' "$tasks_json" 2>/dev/null || echo "")"

    # 2. Completed tasks with github_issue → may need closing
    local needs_close
    needs_close="$(jq -r '
        .tasks[] |
        select(.status == "completed" or .status == "cancelled") |
        select(.github_issue != null and .github_issue != "") |
        "\(.id)|\(.github_issue)"
    ' "$tasks_json" 2>/dev/null || echo "")"

    local create_count close_count
    create_count="$(echo "$needs_create" | grep -c . 2>/dev/null || echo 0)"
    close_count="$(echo "$needs_close" | grep -c . 2>/dev/null || echo 0)"

    log "Sync plan: ~$create_count to create, ~$close_count to close"
    if [[ "$create_count" -gt 10 ]]; then
        log "Estimated time: $((create_count * 2 + close_count))s"
    fi

    if $dry_run; then
        log "=== DRY RUN ==="
        if [[ -n "$needs_create" ]]; then
            log "Would create issues for:"
            echo "$needs_create" | while read -r tid; do
                [[ -z "$tid" ]] && continue
                local subj
                subj="$(task_field "$tid" "subject" "$tasks_json")"
                log "  + $tid: $subj"
            done
        fi
        if [[ -n "$needs_close" ]]; then
            log "Would close issues for:"
            echo "$needs_close" | while read -r line; do
                [[ -z "$line" ]] && continue
                local tid issue_num
                tid="${line%%|*}"
                issue_num="${line##*|}"
                log "  - $tid: issue #$issue_num"
            done
        fi
        return 0
    fi

    # Execute creates
    if [[ -n "$needs_create" ]]; then
        echo "$needs_create" | while read -r tid; do
            [[ -z "$tid" ]] && continue
            local result
            if result="$(cmd_create "$tid" "$tasks_json" 2>&1)"; then
                local issue_num
                issue_num="$(echo "$result" | tail -1)"
                if [[ "$issue_num" =~ ^[0-9]+$ ]]; then
                    # Write issue number back to tasks.json
                    local tmp
                    tmp="$(mktemp)"
                    jq --arg id "$tid" --argjson num "$issue_num" \
                        '(.tasks[] | select(.id == $id)).github_issue = $num' \
                        "$tasks_json" > "$tmp" && mv "$tmp" "$tasks_json"
                    total_created=$((total_created + 1))
                fi
            else
                warn "Failed to create issue for $tid"
                total_errors=$((total_errors + 1))
            fi
            sleep 0.1  # Rate limit courtesy
        done
    fi

    # Execute closes
    if [[ -n "$needs_close" ]]; then
        echo "$needs_close" | while read -r line; do
            [[ -z "$line" ]] && continue
            local issue_num="${line##*|}"
            if cmd_close "$issue_num" 2>&1; then
                total_closed=$((total_closed + 1))
            else
                total_errors=$((total_errors + 1))
            fi
            sleep 0.1
        done
    fi

    log "Sync complete: $total_created created, $total_closed closed, $total_errors errors"
}

cmd_prune_labels() {
    check_auth

    # List all repo labels matching sync prefixes
    local sync_labels
    sync_labels="$(gh label list --json name --jq '
        [.[] | select(.name | test("^(stream:|priority:|tag:)"))] | .[].name
    ' 2>/dev/null || echo "")"

    if [[ -z "$sync_labels" ]]; then
        log "No sync labels found to prune"
        return 0
    fi

    # For each sync label, check if any open issue uses it
    echo "$sync_labels" | while read -r label; do
        [[ -z "$label" ]] && continue
        local count
        count="$(gh issue list --label "$label" --state open --json number --jq 'length' 2>/dev/null || echo "0")"
        if [[ "$count" == "0" ]]; then
            log "Pruning unused label: $label"
            gh label delete "$label" --yes 2>/dev/null || warn "Failed to delete label: $label"
        fi
    done

    log "Label pruning complete"
}

# ── Main ─────────────────────────────────────────────────────

main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        create)       cmd_create "$@" ;;
        close)        cmd_close "$@" ;;
        update)       cmd_update "$@" ;;
        pull-context) cmd_pull_context "$@" ;;
        sync-all)     cmd_sync_all "$@" ;;
        prune-labels) cmd_prune_labels "$@" ;;
        "")
            die "Usage: gh-sync.sh <create|close|update|pull-context|sync-all|prune-labels> [args]"
            ;;
        *)
            die "Unknown command: $cmd"
            ;;
    esac
}

main "$@"
