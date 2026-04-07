# Golden Path Snapshot Format

**Status:** Design (schema only, no tooling yet)
**Schema:** `golden-path-snapshot-schema.json` (same directory)

## What it is

A JSON format for recording what happened during a skill execution: which steps ran, what tools were called, what the user chose at decision points, and what files were touched.

## Why it exists

Skills are procedures, not code. There are no unit tests for them. When a skill changes, the only way to know if it still works is to run it and check manually. Golden path snapshots give us a baseline to diff against:

- **Regression detection.** Compare a new execution snapshot against a known-good one. If the step sequence or tool call pattern changed, flag it for review.
- **Skill validation.** After editing a procedure, run it and capture a snapshot. Diff against the previous snapshot to see exactly what changed.
- **Onboarding.** New contributors can read a snapshot to understand what a skill actually does at runtime, not just what the procedure says it should do.

## Structure overview

```
{
  schema_version: 1,
  skill:          { name, version, arguments },
  outcome:        "success" | "failure" | "partial",
  captured_at:    ISO 8601 timestamp,
  duration_ms:    total wall-clock time (optional),

  steps: [
    {
      name:         "PRE-FLIGHT",
      order:        0,
      outcome:      "success" | "failure" | "skipped",
      duration_ms:  optional,
      tool_calls:   [{ tool, params, success }],
      interactions: [{ question, options, selected }]
    }
  ],

  files_read:     ["/abs/path"],
  files_written:  ["/abs/path"],
  tasks:          { created: ["step-1"], completed: ["step-1"] },
  notes:          "free text"
}
```

## Design decisions

**Flat file lists, not per-step.** Files are often read in one step and used in another. Tracking per-step adds noise without value for diffing. The top-level lists answer the important question: "did this execution touch the same files?"

**Tool params are string-only.** Params are for identification ("which file was read?"), not replay. Large bodies and secrets are omitted. String values keep the format simple and diffable.

**Interactions separate from tool calls.** AskUserQuestion is conceptually different from a tool call. It represents a decision point where the user shaped the execution path. Separating them makes it easy to find all decision points in a snapshot.

**No input/output capture.** Tool outputs are large and noisy. The snapshot records what was called and whether it worked, not what it returned. Full traces belong in session logs.

## Diffing

Snapshots are designed for `diff` or `jq`-based comparison:

```bash
# Compare two snapshots
diff <(jq -S . baseline.json) <(jq -S . current.json)

# Extract just the step sequence
jq '[.steps[] | {name, outcome}]' snapshot.json

# List all tool calls across all steps
jq '[.steps[].tool_calls[]? | .tool]' snapshot.json

# Find all user decision points
jq '[.steps[].interactions[]? | {question, selected}]' snapshot.json
```

## Future work

- Capture tooling (hook or close-step that auto-generates a snapshot)
- Snapshot storage convention (per-skill directory)
- Automated diff in CI or reconcile
