#!/usr/bin/env bash
# Usage: memory-store.sh -k KEY -v VALUE [-n NAMESPACE] [-t TAGS]
# Wraps $CF memory store with auto-fallback to MEMORY.md append.

source "$(dirname "$0")/cf-env.sh"

KEY="" VALUE="" NAMESPACE="patterns" TAGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        -k) KEY="$2"; shift 2 ;;
        -v) VALUE="$2"; shift 2 ;;
        -n) NAMESPACE="$2"; shift 2 ;;
        -t) TAGS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ -z "$KEY" ] || [ -z "$VALUE" ]; then
    echo "Usage: memory-store.sh -k KEY -v VALUE [-n NAMESPACE] [-t TAGS]" >&2
    exit 1
fi

# Primary: claude-flow memory store
if [ -n "$CF" ]; then
    STORE_CMD="cd $HOME && $CF memory store -k \"$KEY\" -v '$VALUE' --namespace $NAMESPACE"
    [ -n "$TAGS" ] && STORE_CMD="$STORE_CMD --tags \"$TAGS\""
    eval "$STORE_CMD" 2>/dev/null && exit 0
fi

# Fallback: append to project MEMORY.md
for projdir in "$HOME"/.claude/projects/*/memory/; do
    if [ -d "$projdir" ]; then
        echo -e "\n## $KEY\n$VALUE\n- Namespace: $NAMESPACE\n- Tags: $TAGS\n- Date: $(date +%Y-%m-%d 2>/dev/null)" >> "${projdir}MEMORY.md"
        exit 0
    fi
done
