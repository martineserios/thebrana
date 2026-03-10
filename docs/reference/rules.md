# Rule Reference

Complete reference for all 12 brana rules. Rules are behavioral directives loaded from `system/rules/`. Each file covers one concern. Rules are human-authored and prescriptive -- they tell Claude what to always, never, or prefer doing.

## Rules by Concern

| Concern | Rules |
|---------|-------|
| **Development process** | sdd-tdd.md, universal-quality.md, git-discipline.md |
| **Work management** | task-convention.md, pm-awareness.md, delegation-routing.md |
| **Knowledge management** | memory-framework.md, research-discipline.md, self-improvement.md |
| **System behavior** | context-budget.md, work-preferences.md, doc-linking.md |

---

## Development Process

### sdd-tdd.md -- Test-First Development

**What it enforces:** Tests come before implementation code. Specs come before features.

**Key directives:**
- Write the test first, see it fail, then implement
- Bug fix: reproduce with a failing test before fixing
- Refactor: run existing tests before and after
- Never weaken a test assertion without investigating the code -- the test is right until proven otherwise
- No test framework or no testable logic: state this and proceed

**Enhanced enforcement** applies to projects with `docs/decisions/`:
- ADR before implementation on `feat/*` branches
- PreToolUse hook blocks implementation files until a spec or test exists
- Commits touching `docs/`, `test/`, `tests/`, or `*.test.*`/`*.spec.*` satisfy the gate

**Correct:**
```
1. git worktree add ../repo-feat-auth -b feat/t-015-jwt-auth
2. /decide JWT auth strategy  -> docs/decisions/ADR-005.md
3. Write failing test          -> tests/auth.test.ts
4. Implement                   -> src/auth.ts (hook allows it)
```

**Incorrect:**
- Writing implementation code before any test exists on a feat/* branch
- Weakening a test assertion because the code produces different output (investigate the code first)
- Skipping the ADR on a feature branch in a project with docs/decisions/

---

### universal-quality.md -- Quality Standards

**What it enforces:** Baseline code quality expectations across all projects.

**Key directives:**
- Test before committing: run relevant tests, or verify manually if no test suite
- Verify before done: confirm functionality, compare before/after behavior
- No secrets in code: never commit API keys, tokens, passwords, or `.env` files
- Handle errors explicitly: don't swallow exceptions or ignore return codes
- Prefer typed approaches where the language supports it
- Code review mindset: write as if someone else maintains it tomorrow
- Test assertion discipline: investigate code before weakening assertions

**Correct:**
- Running `npm test` before committing changes
- Using environment variables for API keys
- Adding a try/catch with specific error handling

**Incorrect:**
- Committing without running tests ("it's just a small change")
- Hardcoding a token in source code
- Using `catch (e) {}` with an empty handler

---

### git-discipline.md -- Git Discipline

**What it enforces:** Every change starts on a branch. Worktrees over checkout. Conventional commits.

**Key directives:**
- Never commit directly to `main` or `master`
- Create the branch before the first edit, not after
- One branch per logical unit of work
- Merge with `--no-ff` to preserve branch history
- Never force-push to main or master

**Branch naming:**

| Prefix | When |
|--------|------|
| `feat/` | New capability, roadmap phase |
| `fix/` | Something broken |
| `docs/` | Spec changes, research |
| `chore/` | Cleanup, maintenance, config |
| `refactor/` | Same behavior, better structure |
| `test/` | Adding or fixing tests |
| `perf/` | Performance improvement |

**Worktree preference:** Use `git worktree add ../repo-shortname -b prefix/name` instead of `git checkout`. Always use `git worktree remove` (never `rm -rf`). Remove worktrees after merge.

**Commit conventions:** `type(scope): description`. Atomic commits. Messages explain WHY, not what. `wip:` commits allowed on feature branches -- squash before merging.

**Branch lifecycle:** Features = days. Fixes = hours. Docs = one session.

**Correct:**
```
git worktree add ../thebrana-fix-deploy -b fix/session-end-hook
# ... make changes ...
git commit -m "fix(hooks): handle cancellation in session-end"
git checkout main && git merge --no-ff fix/session-end-hook
git worktree remove ../thebrana-fix-deploy && git branch -d fix/session-end-hook
```

**Incorrect:**
- Making edits directly on main
- Using `git checkout` to switch branches (use worktrees)
- Running `rm -rf` on a worktree directory
- Force-pushing to main

---

## Work Management

### task-convention.md -- Task Convention

**What it enforces:** Tasks.json is the source of truth for work tracking. Branch before work, task before branch.

**Key directives:**
- Before branching: read `.claude/tasks.json`, state what you found
- Task exists: use its branch convention, set `in_progress`
- No task: propose one before branching
- After completing: update task to `completed` with notes
- Reads are free, writes require confirmation, planning proposes tree then confirms

**Task schema fields:** id, subject, description, tags, status, stream, type, parent, order, priority, effort, execution, blocked_by, branch, github_issue, created, started, completed, notes, context, strategy, build_step.

**Branch mapping:**

| Stream | Prefix |
|--------|--------|
| roadmap | `feat/` |
| bugs | `fix/` |
| tech-debt | `refactor/` |
| docs | `docs/` |
| experiments | `experiment/` |
| research | `research/` |

Format: `{prefix}{id}-{slug}` (e.g., `feat/t-015-jwt-auth`).

**Code tasks:** `/brana:backlog pick` enters `/brana:build` automatically. `/brana:build` CLOSE step handles completion. `/brana:backlog done` is for manual/external tasks only.

---

### pm-awareness.md -- PM Awareness

**What it enforces:** Awareness of project management context before starting work.

**Key directives:**
- Check if a PM repo or GitHub Issues exist before planning significant work
- Check for relevant open issues before starting new work -- avoid duplicating effort
- Link commits to issues when applicable (`fixes #N`, `relates to #N`)
- For multi-session tasks, update issue comments with progress
- Don't create issues unless asked -- check existing ones first

---

### delegation-routing.md -- Delegation Routing

**What it enforces:** Automatic skill invocation and agent delegation based on situational triggers.

**Key directives:**
- Auto-delegate to agents WITHOUT being asked when the situation matches
- When a skill trigger matches, invoke the skill -- don't just suggest it
- If the user declines, don't repeat

**Routing table (key triggers):**

| Trigger | Action |
|---------|--------|
| Work starting | check tasks.json, then `/brana:build` |
| Planning new work | `/brana:backlog plan` or `add` |
| Session ending | `/brana:close` |
| Big decision | `/brana:challenge` |
| New project | `/brana:onboard` |
| Weekly review | `/brana:review` |
| Research topic | `/brana:research [topic]` |
| Monthly knowledge health | `/brana:memory review` |

**Priority:** If the user invokes a skill, use it. If they don't but the situation matches an agent, auto-delegate. Never both.

---

## Knowledge Management

### memory-framework.md -- Memory Framework

**What it enforces:** Separation between prescriptive rules and descriptive memory.

**Two types of persistent files:**

| Type | Author | Content | Location |
|------|--------|---------|----------|
| CLAUDE.md + rules/ | Human | Prescriptive ("always X", "never Y") | Project root, system/rules/ |
| MEMORY.md | Claude | Descriptive ("project uses X", "Y pattern worked") | ~/.claude/projects/ |

**Key directives:**
- MEMORY.md has a 200-line cap
- Never store behavioral directives in MEMORY.md -- move them to rules/ or CLAUDE.md
- Reference, don't cache: store pointers to project files, not the content itself

**Quick test before writing to MEMORY.md:**
1. Fact or rule? Facts -> MEMORY.md. Rules -> rules/.
2. Already in a project file? Store a pointer, not the content.

**Correct:** `TinyHomes | projects/tinyhomes/ | docs/decisions/, .claude/tasks.json`
**Incorrect:** `TinyHomes commission: 10% (8% host + 2% guest)` (stale the day it changes)

---

### research-discipline.md -- Research Discipline

**What it enforces:** Project docs come before external research. Context before content.

**Key directives (in order):**
1. Read project docs first -- grep/read the project's own documentation before any web search
2. Note what the docs decided -- vocabulary, constraints, decisions, open questions
3. Research externally from the doc foundation -- deepen, validate, discover
4. Cross-reference findings against doc decisions -- conflicts? extensions? answers?

**Key rule:** Never launch web research and doc reading in parallel. Web results without doc context produce generic findings instead of project-specific ones.

**Correct:**
```
1. Read CLAUDE.md and docs/decisions/ for the project
2. Note: project uses JWT, decided against session cookies (ADR-005)
3. WebSearch: "JWT refresh token rotation best practices 2026"
4. Cross-reference: findings confirm ADR-005 approach, add rotation detail
```

**Incorrect:**
- Running WebSearch immediately when starting research on a topic
- Reading docs and launching web searches in parallel

---

### self-improvement.md -- Self-Improvement

**What it enforces:** Automatic learning every session without explicit skill invocation.

**Triggers and actions:**

| Trigger | Action |
|---------|--------|
| On correction | Capture pattern in auto memory immediately (what went wrong, fix, prevention) |
| On session start | Read and apply MEMORY.md patterns without being told |
| On session end | Write learnings to auto memory (decisions, patterns, mistakes) |
| On failure | Stop. Reassess from scratch. Say so if the new approach differs from the plan. |
| On non-trivial work | Ask "is there a more elegant way?" before presenting |
| On repeated patterns | Propose a rule, hook, or convention change |

**Key distinction:** Self-improvement runs automatically. Skills (`/brana:retrospective`, `/brana:close`) go deeper when explicitly invoked.

---

## System Behavior

### context-budget.md -- Context Budget

**What it enforces:** Proactive context window management to prevent quality degradation.

**Thresholds:**

| Context usage | Action |
|---------------|--------|
| < 55% | Proceed normally |
| 55-70% (yellow) | Prefer summaries, avoid loading new large files, consider subagent delegation |
| 70-85% | `/compact` before the next expensive operation |
| > 85% | Delegate to a fresh subagent |

**Key insight:** Context accuracy degrades gradually as the window fills (context rot), not at a cliff. Earlier intervention = better output quality.

**Expensive operations to watch:**
- WebFetch: 50-100K tokens/call. Prefer WebSearch (~1K).
- 5+ file edits: write a Python script instead of individual Read+Edit
- Scouts: write to temp files, return 2-line summaries
- MCP servers: 4-17K tokens each

**Edit precision:**
- Include 3+ surrounding lines in old_string for reliable matching
- Files under 50 LOC: prefer Write over Edit
- Sequence: Read A -> Edit A -> Read B -> Edit B (never batch edits without prior reads)

---

### work-preferences.md -- Work Preferences

**What it enforces:** Operational style preferences for how work is executed.

**Key directives:**
- **Parallelism:** Spawn sub-agents and work in parallel whenever possible. Maximize concurrency for independent tasks.
- **Subagent strategy:** Deploy subagents frequently to preserve main context. One focus per subagent.
- **Plan before building:** Activate plan mode for non-trivial tasks (3+ steps or architectural choices). Plan verification phases, not just development.
- **Autonomous execution:** Fix bugs directly. Don't ask for procedural guidance on debugging. Resolve failing CI/tests independently.
- **Simplicity:** No over-engineering, no unnecessary abstraction. Fewer lines beats more lines.
- **Automation through usage:** New capabilities embed as steps in existing commands, not standalone commands nobody remembers.

**Anti-pattern:** Creating useful capabilities as standalone commands nobody remembers to run.

---

### doc-linking.md -- Doc Linking

**What it enforces:** Consistent cross-document reference format.

**The rule:** Use `[doc NN](relative-path.md)` -- never bare "doc NN". Relative paths from the source file. Dimensions via `dimensions/NN-name.md`.

**Correct:** `See [doc 14](../docs/reflections/14-mastermind-architecture.md) for details.`
**Incorrect:** `See doc 14 for details.`
