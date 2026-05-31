
# /brana:gemini — Gemini Worker Delegation

Delegate a task to agy (the Gemini CLI worker). Claude orchestrates; Gemini executes as a
stateless worker. Every result flows back through Claude into the brana system.

## Usage

```
/brana:gemini "task description"   # inline task
/brana:gemini t-XXXX               # pull task from backlog
```

`--bg` (fire-and-continue) is out of scope for v1. Full lifecycle requires Claude present when
agy finishes. Use Layer A (Bash: `agy -p "..."`) for fire-and-forget sweeps.

## agy-Eligible Task Types

| Type | Notes |
|------|-------|
| Research sweep | Atomic, read-only, Gemini Flash speed |
| Boilerplate generation | ⚠️ Convention-sensitive — ruflo required |
| Doc first draft | ⚠️ Pass explicit "why" context in task description |
| Conversion/translation | Deterministic, speed matters |
| Batch summarization | Parallel, repetitive |
| Test scaffolding | ⚠️ Convention-sensitive — ruflo required |
| Competitive/market analysis | Research-heavy, brana-agnostic |

## Never Delegate (Claude-native)

`system/` changes · git operations · tasks.json writes · architectural decisions ·
multi-step stateful refactors · memory/session writes.

---

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__memory_store")

## ROUTE

**Validate the 4-question routing heuristic:**

1. **Atomic?** — completable in one `agy -p` call, no mid-task state
2a. **System-isolated?** — no writes to system/, git, hooks, tasks.json during execution
2b. **Context-enrichable?** — ENRICH can supply enough background for useful output
3. **Speed/token benefit?** — repetitive, fast, or token-heavy for Claude

If any answer is **no**, abort. Tell the user why and suggest the appropriate tool (Claude directly, /brana:build, /brana:research, etc.).

**Hard-block for convention-sensitive task types when ruflo is unavailable:**

Convention-sensitive types: boilerplate generation, test scaffolding, ADR draft.

```
ToolSearch query: "ruflo memory_search"
```

If no ruflo tools found and task type is convention-sensitive → abort:
> "ruflo required for convention-sensitive task (boilerplate/tests) — use Claude directly to
> preserve codebase conventions."

---

## ENRICH

Query ruflo to build context before delegating.

**Default (non-convention-sensitive tasks):**
```
mcp__ruflo__memory_search: { query: "{task}", namespace: "knowledge", limit: 3 }
mcp__ruflo__memory_search: { query: "{task}", namespace: "pattern", limit: 3 }
```
Run in parallel. Collect results.

**Convention-sensitive tasks (boilerplate, test scaffolding, ADR draft):** use `limit: 10`,
filter for `source:thebrana` entries. If zero `source:thebrana` entries returned, prompt:
> "ruflo returned only generic patterns for a convention-sensitive task — proceed anyway
> (risk of violating codebase conventions) or use Claude directly?"
> If user proceeds: note the risk in the PERSIST step.

Build the enriched context string from ruflo results (2–5 bullet points, one per finding).

---

## DELEGATE

Load the agy_delegate tool:

```
ToolSearch query: "select:mcp__brana__agy_delegate"
```

Call `mcp__brana__agy_delegate` with:
- `task`: the full task description (self-contained, no implicit session references)
- `context`: enriched ruflo findings (omit if empty)
- `output_format`: format instructions matching the task type

Wait for result. On error, report the structured error to the user and stop.

**Output format guidance by task type:**

| Type | output_format hint |
|------|--------------------|
| Research sweep | "Return structured markdown with sections: Summary, Key Findings, Caveats" |
| Boilerplate | "Return the complete file content only. No explanation." |
| Doc draft | "Return a markdown document. Use headers. Include a 'Why' section." |
| Batch summarization | "One bullet per item. Bullet = item ID + one sentence." |
| Competitive analysis | "Return a scorecard table: Criteria \| Vendor A \| Vendor B \| Winner" |

---

## APPLY

Process the agy output. Two paths:

**CONTEXT (default):** Output informs Claude's reasoning for the current session. No file
written to repo. Claude synthesizes the agy findings and presents them to the user.
Use for: research sweep, competitive analysis, batch summarization.

**ARTIFACT (explicit):** Task description includes a target path ("write to {path}" or
"generate {file}"). Claude uses its own Write/Edit tool to land the result. All CC hooks
fire normally. agy output never lands in the repo without Claude's explicit Write/Edit call.
Use for: boilerplate generation, doc draft, test scaffolding.

**Reference-response detection (before applying either path):** If the agy output is
< 150 words and contains a file path pattern (starts with `/`, contains `/tmp/`, or
contains `/brain/`), agy may have written the result to disk instead of returning it.
Read the referenced path with the Read tool and use that content as the actual output.
If the path does not exist or is unreadable, surface the error to the user — do not
silently proceed with the reference string as if it were the result.

Present the applied result to the user before proceeding to EXTRACT.

---

## EXTRACT

Score the agy output for scope and novelty (same rules as /brana:build and /brana:brainstorm):

- **SMALL** — single factual finding, narrow scope → auto-persist without prompting
- **MEDIUM** — multi-part finding or affects multiple files → prompt user to confirm persist
- **LARGE** — architectural impact or many new patterns → prompt + run /brana:challenge before
  persisting

Classify each finding into: pattern, knowledge, or decision.

---

## PERSIST

For each finding that clears EXTRACT:

1. **Task context** (if invoked with a task ID):
   ```
   mcp__brana__backlog_set: { task_id: "t-XXXX", field: "context", value: "agy findings: {summary}", append: true }
   ```

2. **ruflo pattern store** (for patterns and transferable knowledge):
   ```
   mcp__ruflo__memory_store: { content: "{finding}", tags: ["source:agy-delegation", "{task-type}", "{relevant-domain}"] }
   ```

3. **Session log** — note agy delegation in the session summary for /brana:close to capture:
   > "Delegated to agy: {task summary} → {outcome summary}"

---

## Rules

- **agy never writes to the repo.** All CC hooks fire on Claude's own Write/Edit calls.
- **agy never calls brana CLI.** Claude does all backlog/session writes.
- **Prompt invariant.** Claude constructs all prompts. No raw user string interpolation.
- **v1 is foreground-only.** For fire-and-forget, use `agy -p "..." > /tmp/...` directly (Layer A).
- **Convention-sensitive tasks need ruflo.** Hard-block without it.
- **EXTRACT and PERSIST are mandatory.** Not optional steps under time pressure.
