<!-- backlog phase: Display themes + task-line/wide-mode templates (status, roadmap, next, tags rendering) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Display Themes

All rendering sections below use the **task-line template** to determine icons,
progress bars, and decorations. Resolve the active theme before rendering:

1. If `--theme <name>` flag is on the command, use it
2. Else read `~/.claude/tasks-config.json` → `{"theme": "<name>"}`
3. Else default to `classic`

### Task-line template

```
classic:   {icon} {id}  {subject}  {detail}
           ✓ done  ← active  → pending  · blocked  · parked
           bars: ████░░░░  {done}/{total}

emoji:     {icon} {id}  {subject}  {detail}
           ✅ done  🔨 active  🔲 pending  🔒 blocked  💤 parked
           bars: ████░░░░  {done}/{total}
           project header: 📋 {name}
           status --all header: boxed ╭╮╰╯ with 📊
           priority high: ⚡high
           blocked ref: ⛓ {id}
           health dots: 🟢 done  🟡 active  🔴 blocked

minimal:   {icon} {id}  {subject}  {detail}
           ● done  ◐ active  ○ pending  ⊘ blocked  ◌ parked
           bars: ━━━━╍╍╍╍  {done}/{total}
           blocked ref: ← {id}
```

### Wide mode (`--wide`)

Any view command (`status`, `roadmap`, `next`, `tags --filter`) accepts `--wide`.
Wide mode renders tasks as **tabular rows** with all metadata visible on one line — like `kubectl get pods -o wide`.
Wide mode composes with any theme (icons come from the active theme).

**Wide-mode template:**

```
Columns:  {icon} {id}  {subject}  {status}  {tags}  {pri}  {eff}  {stream}  {project}  {blocked_by}  {started}  {completed}

Header row (always shown):
  ID       Subject                         Status    Tags              Pri  Eff  Stream   Project      Blocked     Started     Done

Task rows (classic icons):
  ✓ t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  → t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  · t-009  Write auth tests                blocked   auth              P1   M    roadmap  t-008       —           —

Task rows (emoji icons):
  ✅ t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  🔲 t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  🔒 t-009  Write auth tests                blocked   auth              ⛓ t-008

Task rows (minimal icons):
  ● t-007  Design auth flow                done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
  ○ t-008  Implement JWT middleware         pending   auth, quick-win   P1   S    roadmap  —           —           —
  ⊘ t-009  Write auth tests                blocked   auth              P1   M    roadmap  ← t-008     —           —
```

**Rules:**
- `subject` gets remaining width after fixed columns; truncate with `…` if too long
- `tags` shows first 3 comma-separated, then `+N` if more
- Null fields render as `—` (em-dash), never blank
- `project` column: in cross-client views (`--all`), shows `client/project` for multi-project clients, client slug for single-project. In single-project views, shows project slug from tasks.json root or `—`
- Phases/milestones render as **section headers** (bold subject + progress bar, no per-column detail):
  ```
  ph-002  Phase 2: API Foundation                                        ████░░░░ 3/8
    ✓ t-007  Design auth flow              done      auth              P1   S    roadmap  —           2026-02-10  2026-02-12
    → t-008  Implement JWT middleware       pending   auth, quick-win   P1   S    roadmap  —           —           —
  ```
- Without `--wide`, all views use the compact tree layout (unchanged default behavior)

### Tree connectors (all themes)

Hierarchy views (status, roadmap) use box-drawing characters when not in `--wide` mode:

```
├── child (has siblings after)
└── child (last sibling)
│   continuation line
```

---

