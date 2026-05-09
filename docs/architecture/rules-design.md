# Rules Design

> How to decide when to write a rule, how to scope it, and how to keep it lean. Rules are always-present directives in the LLM's context window — every token counts.

## What a Rule Is

A rule is a markdown file that CC loads into the system prompt. Claude reads it every session, on every turn. It is not checked procedurally — it is internalized as part of Claude's working context.

Rules are for **behavioral constraints**: always do X, never do Y, prefer A over B. They communicate intent once; Claude applies it everywhere without being reminded.

Rules are **not** for:
- Automated actions that must fire without LLM involvement → use a hook
- Multi-step workflows → use a skill or procedure
- Reference data (schemas, API shapes) → use a dimension doc
- Project-specific conventions for a single project → use `.claude/CLAUDE.md`

## Rules vs Hooks — The Core Decision

This is the most common design question. The answer depends on whether LLM involvement is required:

| Situation | Use |
|-----------|-----|
| "Always check for a spec before writing code" | **Rule** — LLM decides, directs itself |
| "Block Write to `system/` on main branch" | **Hook** — automated gate, no LLM needed |
| "Prefer `brana backlog` over reading tasks.json" | **Rule** — style preference, LLM needs to know |
| "Log every tool failure to JSONL" | **Hook** — side effect, fires regardless of LLM intent |
| "Run tests before marking a task done" | **Rule** + **Hook** — rule sets expectation, hook can enforce |

**Rule of thumb from `rules-over-hooks-for-gates.md`:** When tempted to write a PreToolUse hook to enforce a process step, ask: "could a rule communicate this just as effectively?" If yes, write the rule. Hooks add per-event overhead and pollute context on every tool call. Rules load once and apply without side effects.

## Scoping: always-load vs paths

Every rule must declare one of these in its YAML frontmatter. `validate.sh` rejects rules that declare neither.

### `always-load: true`

Loaded every session, every project, every tool call. Counts against the 28 KB always-loaded budget.

```markdown
---
always-load: true
---
# Git Discipline

Every change starts on a branch. Always. No exceptions.
```

Use for cross-cutting directives that must apply universally:
- Core quality standards (`universal-quality.md`)
- Git workflow (`git-discipline.md`)
- Development methodology (`sdd-tdd.md`)
- Agent delegation table (`delegation-routing.md`)

**Budget:** `validate.sh` sums the byte size of all `always-load: true` rules. Cap is 28 KB. If you hit the cap, CC's context budget tooling starts throttling context at 55%.

### `paths: ["pattern/**", ...]`

Loaded only when a file matching the pattern is in the working set. Does not count against the always-loaded budget.

```markdown
---
paths: ["system/hooks/**", "system/rules/**"]
---
# Rules Over Hooks for Behavioral Gates

Prefer a rule file over a hook for "always do X before Y" behavioral constraints.
```

Use for rules that only apply when working on specific parts of the codebase:
- Hook authoring conventions → `paths: ["system/hooks/**"]`
- Skill authoring conventions → `paths: ["system/skills/**"]`
- Test discipline for a language → `paths: ["**/*.test.ts", "**/*.spec.ts"]`

Path patterns use glob syntax. Multiple patterns are OR'd — the rule loads if any pattern matches.

**Most new rules should use `paths:`.** Always-loaded rules inflate the context budget for sessions where the rule is irrelevant.

### Declaring both

Allowed, but `paths:` has no effect when `always-load: true` is set. Useful as documentation of intended scope:

```markdown
---
always-load: true
paths: ["system/**"]          # documents primary audience, has no runtime effect
---
```

## Writing Style

Rules live in the context window on every turn. Every byte is a recurring cost. Write accordingly:

**Directives, not explanations.** Say what to do, not why:

```markdown
# Bad — too much explanation
Use the brana CLI for all task operations because reading tasks.json directly
is fragile, bypasses validation, and breaks when the schema changes.

# Good — directive + one-line why
Always use `brana backlog` commands for task operations. Never read tasks.json directly.
```

**Concrete over abstract.** Name the actual tool, path, or command:

```markdown
# Bad — vague
Prefer the CLI tool over direct file access.

# Good — specific
Use `brana backlog get <id>` to read tasks. Use `brana backlog set <id> <field> <value>` to update.
```

**Imperative mood.** "Always", "Never", "Prefer", "Use":

```markdown
Always create a worktree branch before editing system/hooks/, system/skills/, or system/procedures/.
Never commit directly to main from behavioral paths.
Prefer `git -C <path>` over `cd <path> && git` in hooks and scripts.
```

**Few-shot examples for non-obvious behavior.** Two or three concrete lines beat a paragraph of prose:

```markdown
# parallel-bash.md
Run independent bash commands in parallel, not sequentially.
```

versus:

```markdown
# parallel-bash.md
Run independent Bash commands in parallel — send them in a single message as separate tool calls.

Good: git status + git log (both independent reads)
Bad: git add && git commit (sequential dependency — one must succeed before the other)
Not parallel: reading file A then using its content to decide what to read next
```

**Cap at 50 lines.** If a rule is growing past 50 lines, it has become a procedure. Move it to `system/procedures/` or a skill.

## Common Patterns

### "Always before X" constraint

```markdown
---
always-load: true
---
# Spec-First

Before writing implementation code on a new feature or fix, answer:
1. Does a spec (ADR or task context) exist for this change?
2. Does at least one test exist for the behavior being added?

If no to either: write the spec or test first. No exceptions for "small" changes.
```

### "Never do X" hard rule

```markdown
---
always-load: true
---
# No-Attribution Commits

Never add Co-Authored-By, Signed-off-by, or any attribution trailer to git commits.
Never use `git commit --signoff`.
The no-attribution rule applies to all repos in this portfolio.
```

### "Prefer A over B" style preference

```markdown
---
paths: ["system/hooks/**", "*.sh"]
---
# Shell Safety in Hooks

Never use `set -e` in hook scripts — a single failing command would exit the script
without emitting JSON, blocking the session.

Use `|| true` after every command that might fail:
  INPUT=$(cat) || true
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty') || true
```

### Delegation routing table

The `delegation-routing.md` rule holds the agent trigger table. Add new rows here when you add a new agent with auto-delegation:

```markdown
| Trigger | Action |
|---------|--------|
| Starting work on familiar-looking problem | Spawn memory-curator |
| New client project, unfamiliar codebase | Spawn client-scanner |
| Plan or architecture decision forming | Spawn challenger |
```

## Validation

`validate.sh` checks:

- Frontmatter declares `always-load: true` or `paths:` (rejects neither)
- YAML is valid (no tabs, quoted strings)
- File is under 50 KB (hard limit; soft limit is much lower)
- `always-load: true` rules contribute to budget check (28 KB cap)
- No secrets in the file

```bash
./validate.sh
```

## Checklist

1. Decide: is LLM involvement required? If no → hook. If yes → rule.
2. Decide: is this truly universal? If yes → `always-load: true`. If no → `paths:`.
3. Write directives, not explanations. Under 50 lines.
4. Run `./validate.sh`
5. Test in a live session: does Claude apply it without being reminded?
6. After merging: check `docs/reference/rules.md` regenerates correctly

> `docs/reference/rules.md` is auto-generated by `brana reference generate`. Do not edit it manually.

## See Also

- [`system/rules/README.md`](../../system/rules/README.md) — authoring contract enforced by validate.sh
- [`extending-hooks.md`](extending-hooks.md) — hook authoring (the alternative to rules for automated gates)
- [`docs/reference/rules.md`](../reference/rules.md) — auto-generated index of all current rules
- [`context-budget.md`](context-budget.md) — 28 KB cap, compaction thresholds
