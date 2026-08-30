---
name: two-axis-review
description: "Two-axis review: Standards vs Spec, unmerged."
keywords: [code-review, review, diff, standards, spec, two-axis, pr-review]
task_strategies: [review]
group: core
allowed-tools: [Read, Bash, Skill]
disable-model-invocation: true
status: experimental
vendored_from: mattpocock/skills@v1.2.3
---

# Two-Axis Review (adapter)

ADR-084 vendor+wrap pilot expansion (t-2834's pilot evaluated EXPAND, §7a; t-2835 unparked
under that same evaluation). Thin adapter, not a copy — the actual discipline lives in the
vendored organ, read fresh every invocation (no state to lose across compaction — steps 1-3
below are the whole procedure):

**Named `two-axis-review`, not `code-review`** — deliberately distinct from the vendored
skill's own upstream name, because a pre-existing, unrelated built-in `code-review` skill
already occupies that name in this environment (correctness-bug + cleanup review, `--fix`/
`--comment`/`--post` flags). Vendoring the upstream organ verbatim at
`.agents/skills/code-review/` (its `name:` frontmatter says `code-review`, per ADR-084 §2's
"lands verbatim") is unavoidable and correct — the collision is contained by giving *this*
adapter, the user/model-facing entry point, its own name, exactly as `diagnose-hard-bug`
already does for `diagnosing-bugs` (t-2834). Invoke the vendored organ directly only via this
adapter, never by typing `/code-review` and hoping for the Pocock skill.

1. **Read the vendored skill**: `Skill(skill: "code-review")` — `.claude/skills/code-review/SKILL.md`,
   verbatim upstream, pinned `v1.2.3`, tracked in `skills-lock.json`. Follow its 5-step
   process as written (pin fixed point → identify spec source → identify standards
   sources → spawn both sub-agents in parallel → aggregate under separate, never-merged
   `## Standards` / `## Spec` headings).
2. **While following it, remap the two inputs the upstream process expects the caller to
   supply:**

   **Spec source (upstream step 2)** → **NOT** `docs/agents/issue-tracker.md`. That file is
   the tracker *verb* map (ADR-086 §8: "create an issue" → `brana backlog add`, etc.) — it
   answers "which CLI verb does X", not "what did this diff ask for". The actual spec brief
   for the Spec sub-agent comes from **the originating task's own fields**:
   - Resolve the task id from the branch name (`{epic}/{type}/t-NNN-{slug}`, per this
     project's branch convention) or from whatever the user names explicitly.
   - Fetch the task (`backlog_get <t-NNN>`) and run
     `system/scripts/two-axis-spec-lookup.sh` against its JSON: `acceptance_criteria` wins
     if non-empty; otherwise `AC:`-prefixed lines in `context` (task-convention.md's "AC:
     prefix" convention); otherwise the script prints the literal `no spec available` and
     exits 2.
   - **Missing-spec case (AC4):** exit 2 from the lookup script means the Spec sub-agent is
     **skipped entirely** — the aggregated report says `## Spec\nno spec available` under
     that heading, exactly as upstream step 2 already specifies for its own "user says
     there isn't one" branch. Never fabricate AC to fill the gap, and never fail the whole
     review because one axis has nothing to check — the Standards axis still runs and
     reports normally.

   **Standards source (upstream step 3)** → brana's own documented conventions, not a
   `CODING_STANDARDS.md`/`CONTRIBUTING.md` file (neither exists here):
   - `system/rules/*.md` — the behavioural rules that bind all work regardless of
     language (`sdd-tdd.md`, `no-patches-root-cause.md`, `universal-quality.md`,
     `git-discipline.md`, `parallel-bash.md`, and any other rule file touching the diff's
     area).
   - Whichever language/domain skill applies to the diff (e.g. `brana:rust-skills` for
     Rust, `brana:bash-defensive-patterns` for shell) — pass its content inline to the
     Standards sub-agent the same way upstream expects a `CONTRIBUTING.md` to be pasted in.
   - **Plus** the upstream skill's own Fowler smell baseline (its step 3, verbatim,
     already ships in `.claude/skills/code-review/SKILL.md`) — pasted in full alongside the
     brana-rules text, per upstream's own instruction that "the sub-agent has no other
     access to it." The baseline is a floor, not a ceiling: brana rules can suppress a
     baseline smell where they explicitly endorse the pattern it would flag (upstream's own
     "the repo overrides" clause, step 3).
3. **Cross-skill references** → [redirect-check.md](redirect-check.md), the committed list;
   re-verify it against the vendored `SKILL.md` on every upstream bump (ADR-084 §1 pump).
   The only slash-ref upstream carries (`/setup-matt-pocock-skills`) never fires — see the
   redirect list for why.

## Scope boundary vs. `challenger` (system/agents/challenger.md)

**These two are not substitutes and never review the same artifact:**

- **`challenger`** (`system/agents/challenger.md`) is **pre-commitment**: it stress-tests a
  *plan, architecture decision, or approach* — text describing intended work — before any
  code is written or committed to. Its flavors (Pre-Mortem, Simplicity Challenge,
  Assumption Buster, Adversarial User) all operate on a proposal, not a diff. It has no
  concept of "the diff" at all — there usually isn't one yet.
- **`two-axis-review`** (this adapter) is **post-code**: it reviews an *actual diff* — code
  that already exists between a fixed point and `HEAD` — against two axes (does it follow
  documented standards, does it match what was asked for). It has no opinion on whether the
  underlying approach was architecturally sound; that question was `challenger`'s job,
  earlier, before this diff existed.

Concretely: run `challenger` on a design doc or backlog task's plan before implementation
starts; run `two-axis-review` on the resulting commits after implementation is done, before
merge. Neither one is a lighter or heavier version of the other — they gate different
moments, and a change can cleanly pass one while never having been subject to the other
(e.g. a small fix with no separate plan-review step still gets a `two-axis-review` before
merge; a killed spike gets a `challenger` pre-mortem and never reaches a diff at all).

## Record on completion or early exit

Append one line to `~/.claude/run-state/pocock-code-review.jsonl` via a single shell
redirect — `printf '%s\n' '{"task_id":...}' >> ~/.claude/run-state/pocock-code-review.jsonl`
— never read-then-rewrite-the-file; this is a cross-session shared log and a single `>>` of
one line (well under `PIPE_BUF`) is the only append form safe against concurrent sessions
racing on it. Fields: `{"task_id", "fixed_point", "spec_found", "standards_findings",
"spec_findings", "date"}` — the invocation evidence a future kill/expand-style evaluation of
this specific adapter would read, mirroring t-2834's own pre-registered proxies (ADR-084 §7).
