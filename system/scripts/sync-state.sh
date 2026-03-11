#!/usr/bin/env bash
set -euo pipefail

# sync-state.sh — Unified brana state sync (ADR-015)
#
# Subcommands:
#   push [--auto-commit]   — cache → repos (session-start hook, daily scheduler)
#   pull                   — repos → cache (new machine setup)
#   export [--auto-commit] — claude-flow patterns+decisions → repo JSON
#   import                 — repo JSON → claude-flow patterns+decisions
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
COMPANION_FILES=(
    "sessions.md"
    "session-handoff.md"
    "MEMORY-snapshot.md"
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

# ── export: claude-flow → repo ─────────────────────────────

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
        log "export skipped — claude-flow not available"
        return 1
    fi

    local export_file="$STATE_DIR/patterns-export.json"
    local tmp_file="/tmp/brana-patterns-export-$$.json"
    local changed=false

    # Export patterns namespace
    local patterns_json
    patterns_json=$(timeout 30 $CF memory search --query "" --namespace patterns --format json 2>/dev/null) || patterns_json="[]"

    # Export decisions namespace
    local decisions_json
    decisions_json=$(timeout 30 $CF memory search --query "" --namespace decisions --format json 2>/dev/null) || decisions_json="[]"

    # Combine into a single export file
    jq -n \
        --arg exported_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg cf_version "$($CF --version 2>/dev/null || echo unknown)" \
        --argjson patterns "$patterns_json" \
        --argjson decisions "$decisions_json" \
        '{
            exported_at: $exported_at,
            cf_version: $cf_version,
            namespaces: {
                patterns: $patterns,
                decisions: $decisions
            }
        }' > "$tmp_file" 2>/dev/null

    if [ -f "$tmp_file" ]; then
        local patterns_count decisions_count
        patterns_count=$(jq '.namespaces.patterns | length' "$tmp_file" 2>/dev/null) || patterns_count=0
        decisions_count=$(jq '.namespaces.decisions | length' "$tmp_file" 2>/dev/null) || decisions_count=0

        if [ ! -f "$export_file" ] || ! cmp -s "$tmp_file" "$export_file"; then
            mv "$tmp_file" "$export_file"
            changed=true
            log "exported: $patterns_count patterns, $decisions_count decisions"
        else
            rm -f "$tmp_file"
            log "export unchanged ($patterns_count patterns, $decisions_count decisions)"
        fi
    else
        log "export failed — could not generate JSON"
        return 1
    fi

    if [ "$changed" = true ] && [ "$auto_commit" = true ]; then
        auto_commit_state "sync: export claude-flow patterns and decisions"
    fi
}

# ── import: repo → claude-flow ─────────────────────────────

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
        log "import skipped — claude-flow not available"
        return 1
    fi

    local imported=0 failed=0

    # Import patterns
    local count
    count=$(jq '.namespaces.patterns | length' "$export_file" 2>/dev/null) || count=0
    for i in $(seq 0 $((count - 1))); do
        local key value tags
        key=$(jq -r ".namespaces.patterns[$i].key // empty" "$export_file" 2>/dev/null) || continue
        value=$(jq -c ".namespaces.patterns[$i].value // empty" "$export_file" 2>/dev/null) || continue
        tags=$(jq -r ".namespaces.patterns[$i].tags // empty" "$export_file" 2>/dev/null) || tags=""

        [ -z "$key" ] && continue

        if timeout 5 $CF memory store --upsert -k "$key" -v "$value" --namespace patterns --tags "$tags" 2>/dev/null; then
            ((imported++))
        else
            ((failed++))
        fi
    done

    # Import decisions
    count=$(jq '.namespaces.decisions | length' "$export_file" 2>/dev/null) || count=0
    for i in $(seq 0 $((count - 1))); do
        local key value tags
        key=$(jq -r ".namespaces.decisions[$i].key // empty" "$export_file" 2>/dev/null) || continue
        value=$(jq -c ".namespaces.decisions[$i].value // empty" "$export_file" 2>/dev/null) || continue
        tags=$(jq -r ".namespaces.decisions[$i].tags // empty" "$export_file" 2>/dev/null) || tags=""

        [ -z "$key" ] && continue

        if timeout 5 $CF memory store --upsert -k "$key" -v "$value" --namespace decisions --tags "$tags" 2>/dev/null; then
            ((imported++))
        else
            ((failed++))
        fi
    done

    log "import complete: $imported entries restored, $failed failed"
}

# ── snapshot: MEMORY.md for a specific project ─────────────

cmd_snapshot() {
    local project_dir="${1:-}"
    if [ -z "$project_dir" ]; then
        log "snapshot requires a project directory argument"
        return 1
    fi

    local project_name
    project_name=$(basename "$project_dir")

    local cc_dir
    cc_dir=$(find_cc_memory_dir "$project_name" 2>/dev/null) || true

    if [ -z "$cc_dir" ] || [ ! -f "$cc_dir/MEMORY.md" ]; then
        log "snapshot skipped — no MEMORY.md found for $project_name"
        return 0
    fi

    local repo_memory="$project_dir/.claude/memory"
    mkdir -p "$repo_memory"

    if sync_file "$cc_dir/MEMORY.md" "$repo_memory/MEMORY-snapshot.md"; then
        log "snapshot: MEMORY.md → $repo_memory/MEMORY-snapshot.md"
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
    push)   shift; cmd_push "$@" ;;
    pull)   shift; cmd_pull "$@" ;;
    export) shift; cmd_export "$@" ;;
    import) shift; cmd_import "$@" ;;
    snapshot) shift; cmd_snapshot "$@" ;;
    help|--help|-h)
        echo "Usage: sync-state.sh <push|pull|export|import|snapshot> [options]"
        echo ""
        echo "  push [--auto-commit]    Cache → repos (operational state + companion files)"
        echo "  pull                    Repos → cache (new machine restore)"
        echo "  export [--auto-commit]  Claude-flow patterns+decisions → repo JSON"
        echo "  import                  Repo JSON → claude-flow patterns+decisions"
        echo "  snapshot <project-dir>  MEMORY.md snapshot for a project"
        ;;
    *)
        echo "Unknown command: $1" >&2
        exit 1
        ;;
esac
