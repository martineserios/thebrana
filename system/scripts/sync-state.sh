#!/usr/bin/env bash
set -euo pipefail

# sync-state.sh — Unified brana state sync (ADR-015)
#
# Subcommands:
#   push [--auto-commit]   — cache → repos (session-start hook, daily scheduler)
#   pull                   — repos → cache (new machine setup)
#   export [--auto-commit] — ruflo patterns+decisions → repo JSON
#   import                 — repo JSON → ruflo patterns+decisions
#   snapshot <project-dir> — MEMORY.md snapshot for a specific project
#
# Design: unidirectional per subcommand. push always writes cache→repo.
# pull always writes repo→cache. No bidirectional "newer-wins" logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEBRANA_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$THEBRANA_ROOT/system/state"

# ── File mappings ──────────────────────────────────────────
# Global operational state: cache path → repo path
CACHE_PATHS=(
    "$HOME/.claude/memory/event-log.md"
    "$HOME/.claude/memory/portfolio.md"
    "$HOME/.claude/tasks-portfolio.json"
    "$HOME/.claude/tasks-config.json"
)
REPO_PATHS=(
    "$STATE_DIR/event-log.md"
    "$STATE_DIR/portfolio.md"
    "$STATE_DIR/tasks-portfolio.json"
    "$STATE_DIR/tasks-config.json"
)

# Companion files synced per-project
# Note: sessions.md, session-handoff.md, MEMORY-snapshot.md removed (t-614)
# These stay in auto memory only — no repo copies needed
COMPANION_FILES=(
    "event-log.md"
)

# ── Helpers ────────────────────────────────────────────────

log() { echo "[sync-state] $*" >&2; }

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

# Copy file only if source exists and differs from dest
sync_file() {
    local src="$1" dst="$2"
    if [ ! -f "$src" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
        cp "$src" "$dst"
        log "synced: $(basename "$src")"
        return 0
    fi
    return 1  # no change
}

# Find CC project memory dir for a given project name
find_cc_memory_dir() {
    local project_name="$1"
    for projdir in "$HOME"/.claude/projects/*/; do
        if [ -d "${projdir}memory" ]; then
            if grep -qi "$project_name" "${projdir}memory/MEMORY.md" 2>/dev/null; then
                echo "${projdir}memory"
                return 0
            fi
        fi
    done
    return 1
}

# Resolve ~/path to $HOME/path
resolve_path() {
    echo "${1/#\~/$HOME}"
}

# ── push: cache → repos ───────────────────────────────────

cmd_push() {
    local auto_commit=false
    if [[ "${1:-}" == "--auto-commit" ]]; then
        auto_commit=true
    fi

    ensure_state_dir
    local changed=false

    # Global files
    for i in "${!CACHE_PATHS[@]}"; do
        if sync_file "${CACHE_PATHS[$i]}" "${REPO_PATHS[$i]}"; then
            changed=true
        fi
    done

    # Companion files per project (via tasks-portfolio.json)
    local portfolio="$HOME/.claude/tasks-portfolio.json"
    if [ -f "$portfolio" ]; then
        local paths
        paths=$(jq -r '
            if .clients then
                [.clients[].projects[].path] | .[]
            elif .projects then
                [.projects[].path] | .[]
            else empty end
        ' "$portfolio" 2>/dev/null) || true

        for project_path in $paths; do
            local resolved
            resolved=$(resolve_path "$project_path")
            [ -d "$resolved" ] || continue

            local project_name
            project_name=$(basename "$resolved")
            local cc_dir
            cc_dir=$(find_cc_memory_dir "$project_name" 2>/dev/null) || continue

            local repo_memory="$resolved/.claude/memory"
            mkdir -p "$repo_memory"

            for companion in "${COMPANION_FILES[@]}"; do
                if [ -f "$cc_dir/$companion" ]; then
                    if sync_file "$cc_dir/$companion" "$repo_memory/$companion"; then
                        changed=true
                    fi
                fi
            done

            # .needs-backprop (ephemeral flag)
            if [ -f "$cc_dir/.needs-backprop" ]; then
                if sync_file "$cc_dir/.needs-backprop" "$repo_memory/.needs-backprop"; then
                    changed=true
                fi
            fi
        done
    fi

    if [ "$changed" = true ]; then
        log "push complete — files synced to repos"
        if [ "$auto_commit" = true ]; then
            auto_commit_state "sync: push operational state to repos"
        fi
    else
        log "push complete — no changes"
    fi
}

# ── pull: repos → cache ───────────────────────────────────

cmd_pull() {
    ensure_state_dir

    # Global files (reverse direction)
    for i in "${!CACHE_PATHS[@]}"; do
        if [ -f "${REPO_PATHS[$i]}" ]; then
            mkdir -p "$(dirname "${CACHE_PATHS[$i]}")"
            sync_file "${REPO_PATHS[$i]}" "${CACHE_PATHS[$i]}" || true
        fi
    done

    # Companion files per project
    local portfolio="$STATE_DIR/tasks-portfolio.json"
    [ -f "$portfolio" ] || portfolio="$HOME/.claude/tasks-portfolio.json"
    if [ -f "$portfolio" ]; then
        local paths
        paths=$(jq -r '
            if .clients then
                [.clients[].projects[].path] | .[]
            elif .projects then
                [.projects[].path] | .[]
            else empty end
        ' "$portfolio" 2>/dev/null) || true

        for project_path in $paths; do
            local resolved
            resolved=$(resolve_path "$project_path")
            [ -d "$resolved" ] || continue

            local project_name
            project_name=$(basename "$resolved")
            local cc_dir
            cc_dir=$(find_cc_memory_dir "$project_name" 2>/dev/null) || true

            # If CC dir doesn't exist yet, try to create it
            if [ -z "$cc_dir" ]; then
                log "no CC memory dir for $project_name — skipping companion pull"
                continue
            fi

            local repo_memory="$resolved/.claude/memory"
            for companion in "${COMPANION_FILES[@]}"; do
                if [ -f "$repo_memory/$companion" ]; then
                    sync_file "$repo_memory/$companion" "$cc_dir/$companion" || true
                fi
            done
        done
    fi

    log "pull complete — cache restored from repos"
}

# ── export: ruflo → repo ──────────────────────────────────

# Paginate all entries from a ruflo namespace via CLI memory list.
# Outputs a JSON array to stdout.
ruflo_list_all() {
    local ns="$1"
    local limit=100
    local offset=0
    local all_entries="[]"

    while true; do
        local page
        page=$(timeout 30 $CF memory list --namespace "$ns" --limit "$limit" --offset "$offset" --format json 2>/dev/null) || break

        # Extract entries array from response
        local entries
        entries=$(echo "$page" | jq -c '.entries // []' 2>/dev/null) || break

        local count
        count=$(echo "$entries" | jq 'length' 2>/dev/null) || count=0

        if [ "$count" -eq 0 ]; then
            break
        fi

        all_entries=$(jq -s '.[0] + .[1]' <(echo "$all_entries") <(echo "$entries") 2>/dev/null) || break
        offset=$((offset + limit))
    done

    echo "$all_entries"
}

cmd_export() {
    local auto_commit=false
    if [[ "${1:-}" == "--auto-commit" ]]; then
        auto_commit=true
    fi

    ensure_state_dir

    # Source cf-env.sh
    if [ -f "$SCRIPT_DIR/../hooks/lib/cf-env.sh" ]; then
        source "$SCRIPT_DIR/../hooks/lib/cf-env.sh"
    elif [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
        source "$HOME/.claude/scripts/cf-env.sh"
    fi

    if [ -z "${CF:-}" ]; then
        log "export skipped — ruflo not available"
        return 1
    fi

    local export_file="$STATE_DIR/patterns-export.json"
    local tmp_file="/tmp/brana-patterns-export-$$.json"
    local changed=false

    # Export all namespaces via paginated list
    local NAMESPACES=("pattern" "decisions" "knowledge" "skills")
    local ns_json="{}"

    for ns in "${NAMESPACES[@]}"; do
        local entries
        entries=$(ruflo_list_all "$ns")
        ns_json=$(echo "$ns_json" | jq --arg ns "$ns" --argjson entries "$entries" '.[$ns] = $entries' 2>/dev/null) || true
    done

    # Build final export
    jq -n \
        --arg exported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg cf_version "$($CF --version 2>/dev/null || echo unknown)" \
        --argjson namespaces "$ns_json" \
        '{
            exported_at: $exported_at,
            cf_version: $cf_version,
            namespaces: $namespaces
        }' > "$tmp_file" 2>/dev/null

    if [ -f "$tmp_file" ]; then
        local total=0
        for ns in "${NAMESPACES[@]}"; do
            local c
            c=$(jq --arg ns "$ns" '.namespaces[$ns] | length' "$tmp_file" 2>/dev/null) || c=0
            total=$((total + c))
        done

        if [ ! -f "$export_file" ] || ! cmp -s "$tmp_file" "$export_file"; then
            mv "$tmp_file" "$export_file"
            changed=true
            log "exported: $total entries across ${#NAMESPACES[@]} namespaces"
        else
            rm -f "$tmp_file"
            log "export unchanged ($total entries)"
        fi
    else
        log "export failed — could not generate JSON"
        return 1
    fi

    if [ "$changed" = true ] && [ "$auto_commit" = true ]; then
        auto_commit_state "sync: export ruflo memory"
    fi
}

# ── import: repo → ruflo ──────────────────────────────────

cmd_import() {
    local export_file="$STATE_DIR/patterns-export.json"
    if [ ! -f "$export_file" ]; then
        log "import skipped — no export file at $export_file"
        return 1
    fi

    # Source cf-env.sh
    if [ -f "$SCRIPT_DIR/../hooks/lib/cf-env.sh" ]; then
        source "$SCRIPT_DIR/../hooks/lib/cf-env.sh"
    elif [ -f "$HOME/.claude/scripts/cf-env.sh" ]; then
        source "$HOME/.claude/scripts/cf-env.sh"
    fi

    if [ -z "${CF:-}" ]; then
        log "import skipped — ruflo not available"
        return 1
    fi

    local imported=0 failed=0

    # Get all namespace names from export file
    local namespaces
    namespaces=$(jq -r '.namespaces | keys[]' "$export_file" 2>/dev/null) || namespaces=""

    for ns in $namespaces; do
        local count
        count=$(jq --arg ns "$ns" '.namespaces[$ns] | length' "$export_file" 2>/dev/null) || count=0
        log "importing $count entries from namespace: $ns"

        for i in $(seq 0 $((count - 1))); do
            local key value tags
            key=$(jq -r --arg ns "$ns" ".namespaces[\$ns][$i].key // empty" "$export_file" 2>/dev/null) || continue
            value=$(jq -c --arg ns "$ns" ".namespaces[\$ns][$i].content // .namespaces[\$ns][$i].value // empty" "$export_file" 2>/dev/null) || continue
            tags=$(jq -r --arg ns "$ns" ".namespaces[\$ns][$i].tags // empty" "$export_file" 2>/dev/null) || tags=""

            [ -z "$key" ] && continue

            if cd "$HOME" && timeout 5 $CF memory store --upsert -k "$key" -v "$value" --namespace "$ns" --tags "$tags" 2>/dev/null; then
                ((imported++)) || true
            else
                ((failed++)) || true
            fi
        done
    done

    log "import complete: $imported entries restored, $failed failed"
}

# ── restore: binary backup → memory.db ────────────────────

cmd_restore() {
    local backup_script="$SCRIPT_DIR/backup-memory.sh"
    if [ -f "$backup_script" ]; then
        exec "$backup_script" --restore "$@"
    else
        log "error — backup-memory.sh not found at $backup_script"
        return 1
    fi
}


# ── auto-commit helper ─────────────────────────────────────

auto_commit_state() {
    local msg="${1:-sync: state update}"

    # Only auto-commit in thebrana repo
    if ! git -C "$THEBRANA_ROOT" diff --quiet -- system/state/ 2>/dev/null; then
        git -C "$THEBRANA_ROOT" add system/state/ 2>/dev/null || true
        git -C "$THEBRANA_ROOT" commit -m "$msg" --no-verify 2>/dev/null || true
        log "auto-committed state changes"
    fi

    # Also commit companion file changes in client repos
    local portfolio="$HOME/.claude/tasks-portfolio.json"
    if [ -f "$portfolio" ]; then
        local paths
        paths=$(jq -r '
            if .clients then
                [.clients[].projects[].path] | .[]
            elif .projects then
                [.projects[].path] | .[]
            else empty end
        ' "$portfolio" 2>/dev/null) || true

        for project_path in $paths; do
            local resolved
            resolved=$(resolve_path "$project_path")
            [ -d "$resolved/.claude/memory" ] || continue

            if ! git -C "$resolved" diff --quiet -- .claude/memory/ 2>/dev/null; then
                git -C "$resolved" add .claude/memory/ 2>/dev/null || true
                git -C "$resolved" commit -m "$msg" --no-verify 2>/dev/null || true
                log "auto-committed companion files in $(basename "$resolved")"
            fi
        done
    fi
}

# ── Main ───────────────────────────────────────────────────

case "${1:-help}" in
    push)    shift; cmd_push "$@" ;;
    pull)    shift; cmd_pull "$@" ;;
    export)  shift; cmd_export "$@" ;;
    import)  shift; cmd_import "$@" ;;
    restore) shift; cmd_restore "$@" ;;
    help|--help|-h)
        echo "Usage: sync-state.sh <push|pull|export|import|restore> [options]"
        echo ""
        echo "  push [--auto-commit]              Cache → repos (operational state)"
        echo "  pull                              Repos → cache (new machine restore)"
        echo "  export [--auto-commit]            Ruflo memory → repo JSON (all namespaces)"
        echo "  import                            Repo JSON → ruflo memory"
        echo "  restore [--date YYYYMMDD]         Restore memory.db from binary backup"
        ;;
    *)
        echo "Unknown command: $1" >&2
        exit 1
        ;;
esac
