#!/usr/bin/env bash
# organ-record.sh <organ> <task_id> <caller> [event] — one JSON line per organ
# invocation, appended to ~/.claude/run-state/pocock-<organ>.jsonl.
#
# This is the call-site record ADR-084 §7's invocation proxy reads; until it
# exists the proxy is "unreadable, not zero" (ADR-097 D1). One `>>` of one short
# line (well under PIPE_BUF) is the only append form safe against concurrent
# sessions racing on the same log — never read-then-rewrite. t-3489 (ADR-097 P0).
#
# Portable: date -u with an explicit format, mkdir -p, printf; no flock.
set -uo pipefail

organ="${1:-}"
task_id="${2:-}"
caller="${3:-}"
event="${4:-entry}"
if [ -z "$organ" ] || [ -z "$task_id" ] || [ -z "$caller" ]; then
  echo "usage: organ-record.sh <organ> <task_id> <caller> [event]" >&2
  exit 2
fi

# keep the line valid JSON: these are identifiers, strip anything that is not
organ="${organ//[^A-Za-z0-9._-]/}"
task_id="${task_id//[^A-Za-z0-9._-]/}"
caller="${caller//[^A-Za-z0-9._:-]/}"
event="${event//[^A-Za-z0-9._-]/}"

dir="$HOME/.claude/run-state"
mkdir -p "$dir"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"organ":"%s","task_id":"%s","caller":"%s","event":"%s","ts":"%s"}\n' \
  "$organ" "$task_id" "$caller" "$event" "$ts" >> "$dir/pocock-$organ.jsonl"
