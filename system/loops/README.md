# Loops Library

A catalog of committed loop definitions — parallel to the skills library
(`system/skills/`). A loop is *trigger + committed prompt + a termination
check the agent can't game* (docs/guide/workflows/drain-loop.md's own
formula). This directory is the index; each entry's authority may live here
directly, or point at a procedure doc elsewhere (see Wrapper entries below).

Full contract (entry schema, queue types, pull-interface verbs, the
beat-record schema, proof-of-life bar): [docs/architecture/features/loops-library.md](../../docs/architecture/features/loops-library.md).

## Catalog

| Entry | Purpose | Autonomy | Proven |
|---|---|---|---|
| [pipeline-digest.md](pipeline-digest.md) | L0 gauge — reports branch/worktree/inbox drift, read-only | L0 | Live since t-2823 |
| [drain-loop.md](drain-loop.md) | Pump — drains a single tagged wave, pulls + builds one task at a time | L1 | 8-beat session (t-2813) + ongoing production use |
| [epic-drain.md](epic-drain.md) | Pump — graph-walking generalization of drain-loop over an epic's wave graph | L1 | Fixture rehearsal + 2 real beats (t-2845) |

## Frontmatter contract

Every entry declares:

```yaml
name: <loop-name>
cadence: <default pacing>       # or pacing: {active_delay, waiting_delay, empty_delay}
autonomy: L0-L3
supervised: true                # false is unreachable until ADR-062 lands
drains: []                      # queue references this loop pulls from
fills: []                       # queue references this loop writes to
spawns: []                      # other loops/runners this loop may launch
records: "<pointer string>"     # reference to the beat-record schema — never redefine it inline
```

Body: beat procedure, cheap no-op-fast preflight, explicit STOP conditions
(real signals — exit codes, error strings, never self-assessed confidence),
and a `## Denied verbs` section for any entry with `autonomy` above L0.

## Wrapper entries

`drain-loop.md` and `epic-drain.md` are thin — frontmatter plus a pointer to
the actual committed procedure doc under `docs/guide/workflows/`. That doc
stays the single source; the wrapper exists only so this directory is a
complete index without forking procedure content (loops-library contract,
§Boundaries). `pipeline-digest.md` is the opposite shape: it lives here in
full because it never had a separate home.

When writing a new entry, default to the full (non-wrapper) shape unless the
procedure already has a natural home elsewhere with its own review history.

## Running a loop

Arm any entry via `/loop`, pointing it at the entry file (or the doc it
wraps). Every beat emits one record, always — verbosity is a render toggle,
never an emit toggle (see the beat-record schema in the feature spec). An
entry is not "done" until it has real beats with emitted records — proof-of-life
scales with autonomy; see each entry's own evidence in the Proven column above.

## Validating an entry

```bash
python3 system/scripts/loops-lint.py system/loops/<entry>.md
```

Wired into `validate.sh` as Check 71. Checks: required frontmatter keys
present, `records:` is a reference not a redefinition, `## Denied verbs`
present for any entry above L0.
