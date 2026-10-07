#!/usr/bin/env bash
# organ-record.sh <organ> <task_id> <caller> [event] — one JSON line per organ
# invocation, appended to ~/.claude/run-state/pocock-<organ>.jsonl.
#
# This is the call-site record ADR-084 §7's invocation proxy reads; until it
# exists the proxy is "unreadable, not zero" (ADR-097 D1). One `>>` printf of
# one short line to a regular file is atomic via O_APPEND — never
# read-then-rewrite, this log is shared by concurrent sessions.
#
# Exit contract: 2 = usage/invalid identifier (nothing written); 0 otherwise —
# INCLUDING when the write fails (HOME unset, unwritable, jail, CI). A log write
# is advisory and must never abort the calling skill; the failure goes to stderr.
# t-3489 (ADR-097 P0). Portable: date -u with explicit format, mkdir -p, printf.
set -uo pipefail

organ="${1:-}"
task_id="${2:-}"
caller="${3:-}"
event="${4:-entry}"
if [ -z "$organ" ] || [ -z "$task_id" ] || [ -z "$caller" ]; then
  echo "usage: organ-record.sh <organ> <task_id> <caller> [event]" >&2
  exit 2
fi

# identifiers only: strip anything else, cap length, reject what sanitises away
# (a stripped-to-empty organ would write pocock-.jsonl and pollute the proxy)
organ="${organ//[^A-Za-z0-9._-]/}"
task_id="${task_id//[^A-Za-z0-9._-]/}"
caller="${caller//[^A-Za-z0-9._:-]/}"
event="${event//[^A-Za-z0-9._-]/}"
for v in "$organ" "$task_id" "$caller" "$event"; do
  if [ -z "$v" ] || [ "${#v}" -gt 64 ]; then
    echo "organ-record.sh: identifier empty or longer than 64 chars after sanitising — nothing written" >&2
    exit 2
  fi
done

home="${HOME:-}"
if [ -z "$home" ]; then
  echo "organ-record.sh: HOME unset — record skipped (advisory)" >&2
  exit 0
fi
dir="$home/.claude/run-state"
if ! mkdir -p "$dir" 2>/dev/null || [ ! -w "$dir" ]; then
  echo "organ-record.sh: $dir not writable — record skipped (advisory)" >&2
  exit 0
fi
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ! printf '{"organ":"%s","task_id":"%s","caller":"%s","event":"%s","ts":"%s"}\n' \
  "$organ" "$task_id" "$caller" "$event" "$ts" >> "$dir/pocock-$organ.jsonl" 2>/dev/null; then
  echo "organ-record.sh: append to $dir/pocock-$organ.jsonl failed — record skipped (advisory)" >&2
fi
exit 0
