# Epic Ancestor Walk (shared)

The flat `epic` field was retired by the backlog-v3 migration (ADR-065, t-2284) — tasks
are now re-parented under epic-node tasks (`type: "epic"`) instead. Any procedure that
used to read `task.epic` directly must instead walk the task's `parent` chain to the
nearest `type: "epic"` ancestor and use that ancestor's `subject` as the slug.

Used by: `system/skills/close/phases/session-state.md` (Tier 2a/2b epic detection, t-2375),
`system/skills/backlog/phases/start.md` (branch-name epic-slug, t-2375 repair).

<!-- EPIC-WALK-BLOCK -->
```bash
# Reads one field at a time via `brana backlog get --field`, which needs no jq
# (t-2487). The previous form fetched the whole object and piped it to jq: the
# command substitution exits 0 even on an unparseable payload, so a jq failure
# left type_val/cur empty, the loop fell out, and the function printed "" —
# byte-identical to the legitimate "no epic ancestor" answer. It failed OPEN.
# Strips the JSON quoting `--field` emits ("epic" -> epic, null -> null).
_epic_field() {
  local out
  out=$(brana backlog get "$1" --field "$2" 2>/dev/null) || return 1
  [ -z "$out" ] && return 1          # no output at all == lookup failure
  out=${out#\"}; out=${out%\"}
  [ "$out" = "null" ] && out=""
  printf '%s' "$out"
}

# Exit contract — three OUTCOMES, kept distinguishable (t-2487):
#   slug + exit 0   epic ancestor found
#   empty + exit 0  no epic ancestor (a real negative)
#   exit 1          lookup failed — caller must NOT treat this as "no epic"
resolve_epic_ancestor() {
  local cur="$1" depth=0 type_val subject
  while [ -n "$cur" ] && [ "$cur" != "null" ] && [ "$depth" -lt 10 ]; do
    type_val=$(_epic_field "$cur" type) || return 1
    if [ "$type_val" = "epic" ]; then
      subject=$(_epic_field "$cur" subject) || return 1
      # Reject non-slug subjects (t-2263 failure class): the 4 pre-v3 in-001..in-004
      # markers were retyped to type:"epic" but still carry full sentence subjects
      # ("Backlog UI — rich task views..."), not slugs. A garbled slug silently
      # accepted here would misroute session-state / branch names the same way a
      # stale/uncorroborated value did in t-2263 — reject and keep walking instead
      # (parent is usually null, so this degrades to empty, same as no epic found).
      if printf '%s' "$subject" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
        printf '%s\n' "$subject"
        return 0
      fi
    fi
    cur=$(_epic_field "$cur" parent) || return 1
    depth=$((depth + 1))
  done
  echo ""
  return 0
}
```
<!-- /EPIC-WALK-BLOCK -->

> The `EPIC-WALK-BLOCK` markers above are load-bearing: `tests/procedures/test-epic-ancestor-walk.sh`
> extracts exactly that span and sources it, so the test always exercises the shipped
> function. Do not remove or rename them, and keep the fences inside the markers.

Depth cap guards against a malformed/cyclic parent chain — current epic nodes are always
top-level (`parent: null`), so real chains resolve in 1-2 hops.

**Callers must check the exit status, not just the string.** Empty-at-exit-0 means "no
epic field was ever set" and is safe to treat as a benign negative. A non-zero exit means
the lookup itself broke (task missing, binary error) and the epic is *unknown* — routing
on it is the t-2263 clobber class, since `brana session write` keys handoffs by epic and
replaces rather than merges. Stop and surface the error instead of guessing:

```bash
if ! EPIC=$(resolve_epic_ancestor "$TASK_ID"); then
    echo "⚠ epic lookup failed for $TASK_ID — not routing on an unknown epic" >&2
    # abort, or fall back to an explicitly un-routed default; never silently continue
fi
```

Covered by `tests/procedures/test-epic-ancestor-walk.sh`, which extracts this very code
block so the test cannot drift from the shipped source.
