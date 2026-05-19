# Research: Native CC Tasks vs Ruflo Tasks for PM Use Cases

**Date:** 2026-05-19
**Strategy:** evaluate
**Sources checked:** 6 (official CC docs, GitHub issues, claudearchitect, claudefa.st, agentwiki, dev.to)
**Trigger:** Pre-ADR-002 update — evaluate whether findings change the decision or just the framing

---

## Contradictions with Internal Docs

### CONTRADICTION: ADR-002 claim about "Native Claude Code Tasks — session-scoped, metadata doesn't query"

- **Finding:** Anthropic shipped the new Tasks system (TaskCreate/TaskUpdate/TaskGet/TaskList) in CC v2.1.16 on **January 22, 2026** — before ADR-002 was written (February 18, 2026). The new Tasks system is file-based (`~/.claude/tasks/`), persistent across sessions, and supports cross-session coordination via `CLAUDE_CODE_TASK_LIST_ID`.
- **Internal:** ADR-002 labels this option as "session-scoped, metadata doesn't query" — language that accurately describes the OLD `TodoWrite`/`TodoRead` Todos system, not the new Tasks system.
- **Impact:** The ADR-002 framing is out of date. The **decision is still correct** — even the new Tasks system lacks the PM features brana needs (see Findings 1-2 below).
- **Action:** Update ADR-002 context section to distinguish "old Todos system" from "new Tasks system" and add a note that the evaluation is of the Tasks system, which still has the PM gaps listed.

---

## Findings

### [VERSION] Finding 1 — CC new Tasks system: cross-session + file-based, but still PM-insufficient — HIGH

- **Source:** Official CC docs — Todo Tracking, CC system prompts repo — TaskCreate
- **Old version:** Todos (TodoWrite/TodoRead) — in-memory, session-scoped
- **New version:** Tasks (TaskCreate/TaskUpdate/TaskGet/TaskList) — file-based, persistent — shipped CC v2.1.16 (Jan 22, 2026), default as of v2.1.142

| PM requirement | Native Tasks system | brana tasks.json |
|----------------|--------------------|--------------------|
| Cross-session persistence | YES (file-based) | YES (git-tracked) |
| Priority field | NO (metadata only, unqueryable) | YES (P0-P3) |
| Tags / streams | NO | YES |
| Parent-child hierarchy | NO (dependency edges only) | YES (phase > milestone > task) |
| Query by metadata | NO (TaskGet excludes metadata field) | YES (brana backlog query) |
| Effort scoring | NO | YES (S/M/L/XL) |
| GitHub issue linking | NO (unqueryable metadata) | YES (github_issue field) |
| Multi-agent coordination | YES | NO (not designed for this) |

**What CC Tasks does better than brana tasks.json:**
- Native UI integration — visible in CC sidebar
- Multi-agent coordination via `CLAUDE_CODE_TASK_LIST_ID`
- `blocks`/`blockedBy` dependency edges
- No custom hook enforcement needed
- Available to any CC agent/subagent without brana dependency

### [UPDATE] Finding 2 — TaskGet metadata gap: stored but not retrievable — HIGH

- **Source:** GitHub Issue #21356 — Expose metadata in TaskGet (closed as **not planned**)
- **Detail:** TaskCreate accepts an arbitrary `metadata` object. TaskGet does NOT return it — only `subject`, `description`, `status`, `blocks`, `blockedBy`. Workaround: read raw JSON from `~/.claude/tasks/<session-id>/1.json`. This confirms the "metadata doesn't query" limitation persists in the new system.

### [CONFIRMED-INTERNAL] Finding 3 — Ruflo tasks remain agent coordination, not PM — MEDIUM

- **Source:** Ruflo wiki — Agent Usage Guide, dev.to — Claude Flow is Dead, Long Live Ruflo
- **Detail:** Ruflo rebranded from claude-flow at v3.5.0 (Feb 2026). Queen/worker agent types, not feature/task hierarchy. Ruflo v3.6 (Apr 29, 2026) added agent federation. No PM capabilities added. ADR-002 claim holds verbatim.

### [NEW] Finding 4 — Native Task tools not available in all CC environments — MEDIUM

- **Source:** GitHub Issue #23874 — isTTY check disables Tasks in VSCode, Issue #23816
- **Detail:** TaskCreate/TaskList/TaskUpdate disabled in VSCode CC extension and some non-TTY automation contexts. brana uses CLI mode — unaffected. But reinforces that building PM infra on native Tasks has reliability risk for clients using VSCode extension.

### [NEW] Finding 5 — PM MCP ecosystem matured since ADR-002 — MEDIUM

- **Source:** awesome-mcp-servers, CCPM GitHub repo (automazeio/ccpm)
- **Detail:** CCPM launched post-ADR-002: a CC skill using GitHub Issues + Git worktrees for PM, bash scripts for deterministic operations. Philosophically close to brana's approach (git-native, CLI-first). Requires GitHub API token — doesn't fit brana's zero-external-dependency constraint, but worth noting for clients.

---

## Leverage Analysis

### What the new CC Tasks system offers that brana doesn't use:

1. **Multi-agent coordination** (`CLAUDE_CODE_TASK_LIST_ID`) — agents share a task list across sessions. Brana subagents currently operate blind to the main session's tasks.json. This is the highest-value untapped capability.

2. **Native CC sidebar visibility** — tasks show in CC UI without any brana scaffolding.

3. **`blocks`/`blockedBy` edges** — structured dependency graph between tasks. brana tasks.json has no first-class dependency edges.

4. **No hook enforcement overhead** — native tasks don't need PostToolUse jq validation.

### Hybrid pattern candidate:

Use native CC Tasks for **in-session agent coordination** (subagent task lists, inter-agent blocking), while keeping brana tasks.json for **PM-grade backlog** (priority, streams, hierarchy, effort, GitHub linking). The two layers are complementary, not competing.

This is analogous to the `brana session` (ephemeral) vs `brana memory` (persistent) split that already exists.

---

## Proposed Doc/ADR Updates

### 1. ADR-002 context section — update option 1:

**Current:**
```
1. Native Claude Code Tasks — metadata doesn't query, session-scoped, insufficient for hierarchy
```

**Proposed:**
```
1. Native CC Task tools (TaskCreate/TaskUpdate/TaskGet/TaskList, CC v2.1.16 Jan 2026) — file-based
   persistent storage, cross-session via CLAUDE_CODE_TASK_LIST_ID env var, but no priority field,
   no tags/streams, no parent-child hierarchy, and metadata stored but excluded from TaskGet
   (issue #21356, closed not planned). Multi-agent coordination is the one capability brana
   tasks.json does not cover. PM-grade backlog management: insufficient.
```

### 2. Doc 09 — add Tasks section:

```markdown
### Task Tools (CC v2.1.16+)

Four tools: TaskCreate, TaskUpdate, TaskGet, TaskList. Default as of v2.1.142.
- Subject + description + status (no priority/tags/streams natively)
- File-based: ~/.claude/tasks/ — persists across sessions
- Cross-session coordination via CLAUDE_CODE_TASK_LIST_ID env var
- Dependency edges (blocks/blockedBy) but no parent-child hierarchy
- metadata stored in TaskCreate but NOT returned by TaskGet (issue #21356, closed not planned)
- Not available in VSCode extension (isTTY bug, issue #23874)
- Replaces deprecated TodoWrite/TodoRead (still available via CLAUDE_CODE_ENABLE_TASKS=0)
- Best use: multi-agent subagent coordination. Not a replacement for brana tasks.json.
```

---

## New Sources Discovered

- CCPM (automazeio/ccpm) — type: GitHub repo/CC skill — trust: unvalidated
- claudearchitect.com — type: blog/docs — trust: promising — good CC-specific coverage
- claudelog.com — type: blog — trust: unvalidated

---

## Registry Updates Proposed

- Add to `research-sources.yaml`: claudearchitect.com (type: blog, trust: promising, relevance: [09])
- Update `last_checked` for doc 09 (CC native features): 2026-05-19
