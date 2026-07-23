# Epic Ancestor Walk (shared)

The flat `epic` field was retired by the backlog-v3 migration (ADR-065, t-2284) — tasks
are now re-parented under epic-node tasks (`type: "epic"`) instead. Any procedure that
used to read `task.epic` directly must instead walk the task's `parent` chain to the
nearest `type: "epic"` ancestor and use that ancestor's `subject` as the slug.

Used by: `system/skills/close/phases/session-state.md` (Tier 2a/2b epic detection, t-2375),
`system/skills/backlog/phases/start.md` (branch-name epic-slug, t-2375 repair).

```bash
resolve_epic_ancestor() {
  local cur="$1" depth=0 json type_val subject
  while [ -n "$cur" ] && [ "$cur" != "null" ] && [ "$depth" -lt 10 ]; do
    json=$(brana backlog get "$cur" 2>/dev/null) || { echo ""; return; }
    type_val=$(echo "$json" | jq -r '.type // empty')
    if [ "$type_val" = "epic" ]; then
      subject=$(echo "$json" | jq -r '.subject // empty')
      # Reject non-slug subjects (t-2263 failure class): the 4 pre-v3 in-001..in-004
      # markers were retyped to type:"epic" but still carry full sentence subjects
      # ("Backlog UI — rich task views..."), not slugs. A garbled slug silently
      # accepted here would misroute session-state / branch names the same way a
      # stale/uncorroborated value did in t-2263 — reject and keep walking instead
      # (parent is usually null, so this degrades to empty, same as no epic found).
      if echo "$subject" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
        echo "$subject"
        return
      fi
    fi
    cur=$(echo "$json" | jq -r '.parent // empty')
    depth=$((depth + 1))
  done
  echo ""
}
```

Depth cap guards against a malformed/cyclic parent chain — current epic nodes are always
top-level (`parent: null`), so real chains resolve in 1-2 hops. On failure (no epic
ancestor, or ancestor subject isn't a valid slug) the function prints an empty string —
callers must treat that the same as "no epic field was ever set," not as an error.
