# Wave Graph Emission (shared)

Plan-time wave-graph primitives (ADR-080 §2): one wave per milestone, gate chain
computed from cross-milestone `blocked_by` edges, and a mandatory emission-time
cycle check before WRITE. Used by both call sites that emit a wave graph from a
milestone structure — [`system/skills/backlog/phases/plan.md`](../backlog/phases/plan.md)
(WAVES step, between DEPS and PROPOSE) and
[`system/skills/build/phases/decompose-mode.md`](../build/phases/decompose-mode.md)
(WAVES step, epic-scoped `/brana:build decompose` trees) — so the naming and
cycle-check logic can't drift the way `resolve_branch_prefix`'s two independent
mappings did (t-2494).

**A wave's `gate` is a single wave id or null** — the gate chain is a functional
graph (out-degree ≤ 1 per node). Cycle detection therefore reduces to: walk each
node's gate chain; if the walk takes more steps than there are nodes without
hitting a dead end (null), some node was necessarily revisited (pigeonhole) — a
cycle exists. This is DFS-equivalent for this restricted graph shape (ADR-080 §2
calls it "cheap DFS") without needing bash to track a per-node visited set.

<!-- WAVE-GRAPH-EMIT-BLOCK -->
```bash
# wave_name_for_milestone <epic-slug> <ms-slug>
# Prints the wave name per ADR-080 §2.5: "<epic-slug>-<ms-slug>". Always exits 0.
wave_name_for_milestone() {
  local epic_slug="$1" ms_slug="$2"
  printf '%s-%s\n' "$epic_slug" "$ms_slug"
}

# wave_gate_chain_has_cycle
# Reads "id<TAB>gate" pairs from stdin, one wave per line (gate empty or the
# literal string "null" means ungated). Exit 0 + no output: the gate chain is
# acyclic. Exit 1 + a diagnostic line: at least one wave's gate chain cycles.
wave_gate_chain_has_cycle() {
  local -A gate_of=()
  local id gate n=0
  while IFS=$'\t' read -r id gate; do
    [ -z "$id" ] && continue
    [ "$gate" = "null" ] && gate=""
    gate_of["$id"]="$gate"
    n=$((n + 1))
  done

  local start cur steps
  for start in "${!gate_of[@]}"; do
    cur="$start"
    steps=0
    while [ -n "$cur" ]; do
      steps=$((steps + 1))
      if [ "$steps" -gt "$n" ]; then
        echo "cycle detected: gate chain from $start does not terminate within $n waves"
        return 1
      fi
      cur="${gate_of[$cur]:-}"
    done
  done
  return 0
}
```
<!-- /WAVE-GRAPH-EMIT-BLOCK -->

> The `WAVE-GRAPH-EMIT-BLOCK` markers above are load-bearing:
> `tests/procedures/test-wave-graph-emit.sh` extracts exactly that span and sources
> it, so the test always exercises the shipped source. Do not remove or rename
> them, and keep the fences inside the markers.

## Usage at each call site

1. Collect the milestone's children (or the emitted milestones in a fresh
   `/brana:build decompose` tree) and compute each wave's `gate`: if any task
   under milestone B is `blocked_by` a task under milestone A, wave-B's gate is
   `wave_name_for_milestone(epic_slug, A's slug)`; independent milestones get no
   gate. Multiple upstream milestones collapse to one gate (a wave gates on at
   most one other wave) — pick the milestone whose tasks are referenced by the
   most cross-milestone `blocked_by` edges, and name the tie-break choice in the
   PROPOSE display so the human can override it.
2. Before displaying the graph in PROPOSE, feed the full `id<TAB>gate` set through
   `wave_gate_chain_has_cycle`. A cycle is a hard stop — surface the diagnostic
   and require the milestone dependency edges to be fixed before proceeding; do
   not display or write a cyclic graph. This is the plan-time check ADR-080 §2
   requires so the runner's PREFLIGHT cycle-STOP (ADR-080 §3.1) is the last line
   of defense, not the first.
3. Only on human approval (the same PROPOSE/WRITE gesture as the task tree) create
   the wave objects, each `status: queued`:
   ```bash
   brana backlog wave add --name "<wave-name>" --selector "parent:<ms-id>" \
     --contract "<milestone definition-of-done>" [--gate <upstream-wave-name>]
   ```
