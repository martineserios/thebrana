# 19 - Project Management System: Research, Analysis, and Design

How to manage multiple projects from the mastermind system. Not a core function — an optional plugin that layers PM capabilities on top of development work. Informed by Tiago Forte's Second Brain, solo PM best practices, GitHub Projects v2, Claude Code patterns, and brana v1's existing PM framework.

---

## Design Intent

A PM component for a solo developer managing 3-5 projects simultaneously, integrated with Claude Code as the primary interface. The system should:

- Track work across all projects from a single view
- Bridge the gap between PM state and code state (issues → branches → PRs → merges)
- Minimize maintenance overhead (the PM system should not become a project itself)
- Work as a plugin — projects without PM enabled work fine without it

---

## Research Findings

### Tiago Forte — Second Brain / PARA / CODE

**What's relevant:**

| Concept | Value for Brana | Adaptation |
|---|---|---|
| **PARA categories** | Project/Area distinction separates finite work from ongoing responsibility | Already done in brana v1 (01_Projects vs 02_Areas). Keep the distinction but drop rigid folder hierarchy in favor of tags/metadata. |
| **Intermediate Packets** | Discrete, reusable work units (ADRs, runbooks, templates, code patterns) | Already done with feature folders and ADRs. This is the strongest overlap with existing practice. |
| **Slow Burns** | Background accumulation of research/ideas for future projects | Maps to ReasoningBank pattern accumulation. The learning loop IS a slow burn engine. |
| **Just-in-time organization** | Organize as a byproduct of work, not as a ritual | The v1 PM system has too much upfront ceremony. Reduce template overhead. |
| **CODE workflow** (Capture→Organize→Distill→Express) | The pipeline from raw input to actionable output | Capture = issue creation. Organize = labels + milestones. Distill = feature spec (only for large work). Express = code + PR. |

**What doesn't translate:**

- **Progressive Summarization** — designed for prose notes, not code or project tracking. Technical documentation needs to be accurate and complete, not progressively highlighted.
- **Resonance-based capture** — "save what feels interesting" works for knowledge work, not for project tasks. Tasks need a utility criterion ("will this move the project forward?"), not an interest criterion.
- **Rigid folder hierarchy** — PARA's four folders fight search-first workflows. Developers find flat markdown + powerful search outperforms elaborate hierarchies.
- **Cross-platform mirroring** — maintaining identical PARA structures across tools is impractical. One canonical location per data type.

**Key criticism:** The #1 failure mode of Second Brain is the **collector's fallacy** — capturing aggressively but never processing or using what's captured. The PM system must bias toward action over accumulation. Every captured item should have a clear "what do I do with this?" answer.

Sources:
- Forte Labs: [BASB Overview](https://fortelabs.com/blog/basboverview/), [PARA Method](https://fortelabs.com/blog/para/), [Progressive Summarization](https://fortelabs.com/blog/progressive-summarization-a-practical-technique-for-designing-discoverable-notes/)
- Stack Overflow Blog: [Two Heads Are Better Than One](https://stackoverflow.blog/2022/10/03/two-heads-are-better-than-one-what-second-brains-say-about-how-developers-work/)
- Criticism: [XDA Developers](https://www.xda-developers.com/building-second-brain-became-excuse-for-not-using-my-first-one/), [Nick Milo on Progressive Summarization](https://www.linkingyourthinking.com/ideaverse/the-potential-side-effects-of-progressive-summarization)

---

### Solo PM Best Practices

**Frameworks that scale down well:**

| Framework | Solo Fit | Key Takeaway |
|---|---|---|
| **Now/Next/Later** | Excellent | Simplest prioritization that works. No dates, no estimation. Items flow forward. |
| **GTD** (Getting Things Done) | Good (capture + weekly review) | Trusted inbox + weekly review are the valuable parts. Contexts (@computer) less useful when everything is computer. |
| **Personal Kanban** | Good (WIP limits) | Limit work-in-progress to 1 item. The WIP limit IS the value, not the board. |
| **Shape Up** (Basecamp) | Moderate (appetite concept) | "How much time is this worth?" beats "How long will it take?" 2-week cycles work solo. |
| **Interstitial Journaling** | Excellent | Timestamped notes as you work. Solves the "where was I?" problem when context-switching between projects. Most underrated technique. |

**What fails at solo scale:**

- Velocity tracking / burndown charts — measuring yourself against yourself with inconsistent story points is meaningless
- Sprint ceremonies — daily standups to yourself have zero value. Retrospective is the one worth keeping (biweekly).
- Story points — replace with t-shirt sizes (S/M/L) or appetite ("worth 1 day" / "worth 1 week")
- Jira-style heavyweight tracking — configuration overhead exceeds value
- Separate PM tools — every context switch to update a ticket breaks flow

**What works:**

- **Plain text / markdown in git** — zero external dependencies, always accessible, versionable
- **Weekly review** (30 min) — the single most impactful meta-project practice. Update status for each project, review backlogs, identify blockers, decide "Now" focus for next week.
- **Portfolio file** — one view across all projects with traffic-light status (green/yellow/red)
- **Decision logs** — lightweight ADRs for significant decisions, table format for minor ones
- **Ship log** — record what you shipped, not just what you planned. Fights "I'm not accomplishing anything" feeling.

**The "meta-project" pattern:**

Managing 3-5 projects requires a layer above individual project management:
- One portfolio file listing all projects with status + current focus
- Weekly review touching all projects
- Now/Next/Later prioritization across the portfolio
- Kill zombie projects: anything untouched for 4+ weeks either gets committed to or archived

Sources:
- [Pankaj Pipada: Markdown/Git Task Management](https://pankajpipada.com/posts/2024-08-13-taskmgmt-2/)
- [GTD in 15 Minutes](https://hamberg.no/gtd)
- [Shape Up — Basecamp](https://basecamp.com/shapeup/0.3-chapter-01)
- [Now-Next-Later Roadmap](https://www.prodpad.com/blog/invented-now-next-later-roadmap/)
- [Interstitial Journaling](https://medium.com/better-humans/replace-your-to-do-list-with-interstitial-journaling-to-increase-productivity-4e43109d15ef)
- [Solo Developer's Manifesto](https://github.com/fawazahmed0/the-solo-developers-manifesto)
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)

---

### Brana v1 PM System (Existing)

**Structure:** Code/PM repo separation via symlinks. Each project has a paired `-pm/` repo.

```
01_Projects/
├── palco/              ← Code
├── palco-pm/           ← PM (BACKLOG, features/, decisions/, architecture/)
├── nexeye_eyedetect/
├── nexeye_eyedetect-pm/
└── [40+ project pairs]
```

**Core components:**

| Component | Purpose | Status |
|---|---|---|
| `BACKLOG.md` | Single source of truth for all work (P0-P4 priorities) | Central, manual |
| `features/F-NNN-name/` | Feature folders with README, requirements, integration-plan | Template-driven |
| `decisions/ADR-NNN-*.md` | Architecture Decision Records (immutable) | Well-established |
| `planning/sprints/` | Sprint tracking with current-sprint.md | Lightweight |
| `architecture/` | System design docs, API specs, diagrams | Per-project |
| `roadmap.md` | 6-month strategic timeline with phases | Manual |
| `99_System/templates/` | Reusable templates for tasks, features, meetings, projects | Comprehensive |

**Feature lifecycle (SPARC):** Specification → Pseudocode → Architecture → Refinement → Completion

**Strengths:** Clean separation, progressive disclosure (summary → detail), template consistency, decision preservation, single source of truth.

**Documented weaknesses:** Manual maintenance, two-repo coordination overhead, no automation, template drift, heavy for small projects.

See [03-pm-framework.md](dimensions/03-pm-framework.md) for the full analysis.

---

### GitHub Projects v2 (Current Capabilities)

**Maturity:** Fully GA. Genuine PM surface, not just a Kanban board.

**Key features for solo developer:**

| Feature | What It Gives You |
|---|---|
| **Table/Board/Roadmap views** | Multiple perspectives on the same data |
| **Custom fields** | Priority (P0-P3), Phase (Now/Next/Later), Effort (S/M/L) — fully customizable |
| **Iterations** | Sprint/cycle tracking with configurable dates and breaks |
| **Sub-issues** | Up to 100 per parent, 8 levels deep, cross-repo |
| **Issue dependencies** | "Blocked by" / "Blocking" relationships (up to 50 per type) |
| **Issue types** | Bug, Feature, Task (customizable at org level) |
| **Cross-repo projects** | One project tracking issues from all 3-5 repos |
| **Built-in automations** | Auto-set status on close/merge, auto-add items from repos |
| **50K item limit** | More than enough for any scale |

**Full CLI access via `gh`:**

```bash
# Project management
gh project create/list/view/edit/close/delete
gh project field-create/field-list/field-delete
gh project item-add/item-create/item-edit/item-list/item-archive/item-delete
gh project link/unlink (repos to projects)

# Issue management
gh issue create/list/view/edit/close/reopen/comment
gh issue develop (create linked branch from issue)
gh issue status (show your assigned/mentioned issues)

# Everything else via escape hatch
gh api repos/{owner}/{repo}/milestones  (create/list milestones)
gh api graphql (sub-issues, dependencies)
```

**Limitations:**
- No time tracking (use Toggl if needed)
- No burndown charts or velocity metrics (not needed solo)
- Milestones are repo-scoped (can't span repos)
- Labels are repo-scoped (must duplicate across repos)
- Sub-issue CLI support requires extensions or `gh api graphql`
- No native recurring issues (use Actions to simulate)

**Verdict:** GitHub Projects v2 is sufficient for solo PM. The combination of Projects (cross-repo views) + Issues (sub-issues, dependencies) + Milestones (phase tracking) + `gh` CLI (full automation) covers 85-90% of needs.

Sources:
- [GitHub Docs: About Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects)
- [GitHub Docs: Sub-Issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)
- [GitHub Docs: Issue Dependencies](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies)
- [gh project CLI Manual](https://cli.github.com/manual/gh_project)
- [gh issue CLI Manual](https://cli.github.com/manual/gh_issue)

---

### Claude Code PM Patterns (Community)

**What people use today:**

| Pattern | How It Works | Maturity |
|---|---|---|
| **Native TaskCreate** | Persistent JSON tasks at `~/.claude/tasks/`. Supports dependencies (DAGs). Multi-session via `CLAUDE_CODE_TASK_LIST_ID`. | Production |
| **CLAUDE.md + ROADMAP.md** | ROADMAP.md with checkbox tracking, CLAUDE.md instructs Claude to check it first. | Production |
| **planning-with-files** skill | task_plan.md + findings.md + progress.md. Auto-recovers after `/clear`. | Production |
| **CCPM** | GitHub Issues as source of truth + git worktrees for parallel agent isolation. | Production |
| **claude-simone** | Directory-based task management + MCP server. | Production |
| **Hooks for PM** | SessionStart: inject sprint context. Stop: verify task completion. PostToolUse: detect git commits. | Stable |
| **Agent teams** | Team lead orchestrates, teammates execute with shared task list. | Experimental |

**Key lessons from the community:**

1. **PM state belongs on the filesystem**, not in AI memory. The old TodoWrite system lost everything on session end. Auto memory has a 200-line limit. Dynamic PM state (current tasks, sprint status, blockers) needs explicit files on disk.
2. **Single tasks.md with checkboxes fails** for concurrent agents — individual task files avoid edit conflicts.
3. **CLAUDE.md compliance is unreliable** for complex workflows. Use hooks for deterministic enforcement, CLAUDE.md for conventions.
4. **Separate PM tools (Jira, Asana) break flow.** The PM surface needs to be CLI-accessible, ideally within the same terminal Claude Code runs in.
5. **JSON feature lists** prevent agents from declaring victory too early (Anthropic's long-running agent harness pattern).

Sources:
- [CCPM](https://github.com/automazeio/ccpm)
- [planning-with-files](https://github.com/OthmanAdi/planning-with-files)
- [claude-simone](https://github.com/Helmi/claude-simone)
- [Ben Newton: Claude Code Roadmap Management](https://benenewton.com/blog/claude-code-roadmap-management)
- [Nick Tune: Minimalist Task Management](https://medium.com/nick-tune-tech-strategy-blog/minimalist-claude-code-task-management-workflow-7b7bdcbc4cc1)
- [Anthropic: Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)

---

### Branch Strategy

**Recommended model: GitHub Flow**

One long-lived branch (`main`). All tracked work happens in short-lived feature branches. Every branch goes through a PR. Direct push to main for trivial changes only.

**Why GitHub Flow for solo:**
- Simple enough to not slow you down
- Creates 1:1 mapping between issues and branches (PM integration)
- PRs serve as change documentation even without a reviewer
- Works natively with `gh` CLI and Claude Code
- Scales up if a collaborator joins

**Branch-to-task mapping:**

```
<type>/<issue-number>-<short-description>

Examples:
  feature/42-user-auth-flow
  fix/87-null-pointer-on-login
  chore/103-update-dependencies
  refactor/56-extract-service-layer
```

Rules: one branch per issue, one issue per branch, branch from main, delete after merge.

**The bridge command: `gh issue develop`**

```bash
gh issue develop 42 --checkout --name feature/42-user-auth
# Creates branch, links to issue, checks out locally
# PR created later will auto-link to issue #42
```

**Conventional commits + auto-changelog:**

```
<type>[scope]: <description>

Types: feat, fix, chore, refactor, docs, test
BREAKING CHANGE in footer triggers major version bump
```

[git-cliff](https://git-cliff.org/) parses conventional commits and generates changelogs automatically:
```bash
git cliff -o CHANGELOG.md          # Full changelog
git cliff --unreleased              # Current work
gh release create v1.2.0 --notes "$(git cliff --latest --strip header)"
```

**PR workflow for solo dev:**

Work tracked by an issue → branch + PR + auto-close:
```bash
gh issue develop 42 --checkout --name feature/42-user-auth
# ... work, commit ...
gh pr create --title "feat: add user auth" --body "Closes #42"
gh pr merge --squash --delete-branch
```

Trivial changes (typos, config, deps) → direct push to main. No issue, no branch, no PR.

**Branch protection (lightweight):**
- Require status checks to pass before merge (if CI exists)
- Prevent force pushes to main
- Auto-delete branches after merge
- Do NOT require PR approvals (you're solo)

**Milestones and releases:**
- Tags on main for releases (`v1.2.0`). Release branches only for hotfixing old versions.
- Milestones group issues into phases. When all milestone issues close, tag and release.
- `gh api repos/{owner}/{repo}/milestones` for milestone CRUD.

Sources:
- [GitHub Flow](https://docs.github.com/en/get-started/using-git/github-flow)
- [gh issue develop](https://cli.github.com/manual/gh_issue_develop)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [git-cliff](https://git-cliff.org/)
- [Claude Code: Common Workflows](https://code.claude.com/docs/en/common-workflows)

---

## Design Decisions

### 1. Source of Truth: GitHub Issues (with generated BACKLOG.md)

**Decision:** GitHub Issues is the source of truth for task tracking. BACKLOG.md becomes a generated cache — a skill or hook runs `gh issue list` and writes a formatted markdown summary that Claude can read in one shot during SessionStart.

**Rationale:**
- Issues gain: automation (auto-close on merge), cross-repo tracking, sub-issues, dependencies, branch linking via `gh issue develop`, CLI access
- BACKLOG.md gains: always-current (generated, not manually maintained), zero maintenance, readable by Claude in one Read call
- The v1 pain point (manual BACKLOG.md maintenance) is eliminated

**Trade-off accepted:** GitHub dependency. Offline work loses issue tracking. Acceptable because code already lives on GitHub.

### 2. PM Repo: Merged Into Code Repo

**Decision:** Kill the separate PM repo. Move `decisions/`, `architecture/`, and `features/` into the code repo under `docs/`.

```
project-root/
├── docs/
│   ├── decisions/        ← ADRs
│   ├── architecture/     ← Design docs
│   └── features/         ← Specs (large features only)
├── src/
└── ...
```

**Rationale:**
- With GitHub Issues handling tasks, the PM repo's remaining content is 15-20 files — not enough to justify a separate repo
- ADRs evolve with the code they describe — same repo, same history, same PRs
- Eliminates symlink coordination and two-repo maintenance overhead
- Claude reads `docs/decisions/` directly without symlink traversal

**What's preserved:** The conceptual separation (PM thinking vs code) through directory structure, not repo boundaries. The `99_System/templates/` directory stays in the brana system project (it's system-wide, not per-project).

### 3. Automation: Manual First (Pain-Driven)

**Decision:** Start with skills only (manual invocation). Add hooks when specific manual steps become painful.

**Progression:**

| When | What | Trigger |
|---|---|---|
| Day 1 | Skills only (`/start-task`, `/done`, `/project-status`, `/weekly-review`) | Default |
| Month 2-3 | SessionStart hook: read CONTEXT.md + show current issue | You're doing this manually every session |
| Month 3+ | Stop hook: auto-update CONTEXT.md | You keep forgetting to note where you left off |
| Later | PostToolUse hook: auto-comment on issue after commit | You want a progress trail on issues |

**Rationale:** Consistent with lean roadmap philosophy (doc 18). Hooks for deterministic behavior, skills for judgment-based behavior.

### 4. Branch Strategy: PRs for Tracked Work

**Decision:** GitHub Flow. PRs for anything with a GitHub Issue. Direct push to main for trivial changes (typos, config, deps).

**Rule:** If it has an issue number, it goes through `gh issue develop` → branch → PR → squash merge → auto-close. If it doesn't have an issue number, it's trivial enough to push directly.

**Encoded in CLAUDE.md:**
```markdown
## Branch Strategy
- Work with a GitHub Issue: `gh issue develop <N>` → branch → PR → squash merge
- Trivial changes (typos, config, deps): commit directly to main
- Branch naming: <type>/<issue-number>-<description>
- PR titles: conventional commit format (feat:, fix:, chore:)
- PR body must include "Closes #<issue-number>"
```

---

## System Design

### Task Decomposition (Earned Ceremony)

| Size | Tracked As | When to Use |
|---|---|---|
| **Small** (< 1 day) | GitHub Issue | Most work. One issue, one branch, one PR. |
| **Medium** (1-5 days) | Issue + sub-issues | When it needs breakdown. Parent issue for visibility, sub-issues for individual steps. |
| **Large** (1-2 weeks) | Milestone + issues + feature spec in `docs/features/` | Only for complex features requiring design upfront. Rare. |

No mandatory feature folders, SPARC phases, or sprint files for small/medium work. Ceremony scales with task size.

### Portfolio View

One cross-repo GitHub Project for all 3-5 repos.

**Custom fields:**
- Priority: P0, P1, P2, P3
- Phase: Now, Next, Later
- Effort: S, M, L

**Setup:**
```bash
gh project create --owner "@me" --title "Portfolio"
gh project field-create <N> --owner "@me" --name "Priority" --data-type "SINGLE_SELECT" --single-select-options "P0,P1,P2,P3"
gh project field-create <N> --owner "@me" --name "Phase" --data-type "SINGLE_SELECT" --single-select-options "Now,Next,Later"
gh project field-create <N> --owner "@me" --name "Effort" --data-type "SINGLE_SELECT" --single-select-options "S,M,L"
gh project link <N> --owner "@me" --repo "owner/project-a"
gh project link <N> --owner "@me" --repo "owner/project-b"
# ... for each repo
```

### Per-Project Context

Each code repo gets:

```
project-root/
├── docs/
│   ├── decisions/            ← ADRs (ADR-NNN-title.md)
│   ├── architecture/         ← Design docs
│   └── features/             ← Specs for Large items only
├── CONTEXT.md                ← Where I left off (updated by skill or hook)
├── .claude/
│   └── rules/
│       └── branch-strategy.md ← Git workflow conventions
└── ...
```

`CONTEXT.md` is the interstitial journal for the project — captures where you left off, what you were thinking, what's next. Updated manually via `/done` skill or automatically via Stop hook (later).

### Skills (The User Interface)

| Skill | What It Does | Implementation |
|---|---|---|
| `/project-status` | Portfolio view across all projects | `gh project item-list` → formatted markdown |
| `/start-task <issue>` | Load context, create branch, show issue details | `gh issue view` + `gh issue develop` + read CONTEXT.md |
| `/done` | Commit, create PR, update CONTEXT.md | Conventional commit + `gh pr create` with `Closes #N` |
| `/plan-feature <title>` | Create parent issue + sub-issues + feature spec | `gh issue create` + template in `docs/features/` |
| `/weekly-review` | Guided walkthrough: status each project, check stale issues, reprioritize | `gh issue list` per repo + `gh project item-list` |
| `/decide <title>` | Create ADR from template in `docs/decisions/` | Copy template, auto-increment number |
| `/sync-backlog` | Generate BACKLOG.md from GitHub Issues | `gh issue list` → formatted markdown |

### Hooks (Added Later, Pain-Driven)

| Hook | Event | PM Action |
|---|---|---|
| Context loader | SessionStart | Read CONTEXT.md + run `/sync-backlog` to show current state |
| Context saver | Stop | Update CONTEXT.md with session summary |
| Issue updater | PostToolUse (Bash, matching git commit) | Comment on linked issue with commit summary |

### Integration with Mastermind (docs 14, 17, 18)

The PM component is a **plugin**, not core:

- **Loads when:** A project has `docs/decisions/` or is linked to the GitHub Project
- **Doesn't load when:** Quick scripts, experiments, one-off repos
- **Connects to learning loop:** PM decisions (ADRs) are pattern-worthy. The Stop hook can extract "decision X was made because Y" and store it in ReasoningBank.
- **Connects to challenger:** `/brana:challenge` on plan mode can check "does this plan align with the current milestone's scope?"
- **Context budget:** PM skills load on demand (zero cost until invoked). CONTEXT.md is small (~500 bytes). PM awareness rule is one small file.

---

## Open Questions

1. **BACKLOG.md generation frequency.** Every SessionStart (always current, small latency cost) or on-demand via `/sync-backlog` (faster sessions, may be stale)?

2. **ADR format.** Keep the comprehensive v1 template (metadata, forces, options, comparison matrix, implementation plan) or simplify to the lightweight Michael Nygard format (Context, Decision, Consequences)?

3. **Where does CONTEXT.md live?** Project root (visible, easy to find) or `.claude/context/` (cleaner root directory)? Project root feels right — it's for humans too, not just Claude.

4. **Weekly review automation.** The `/weekly-review` skill walks through each project. Should it also generate a weekly summary file (a ship log) that accumulates over time? Useful for retrospectives but adds file maintenance.

5. **Template migration.** The `99_System/templates/` in brana v1 has comprehensive templates. Which survive in v2? ADR template yes. Feature template simplified. Task/meeting/person/project templates — probably not needed with GitHub Issues handling tasks.

---

## References

- [03-pm-framework.md](dimensions/03-pm-framework.md) — Brana v1 PM system description
- [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md) — System architecture (PM as plugin)
- [17-implementation-roadmap.md](./17-implementation-roadmap.md) — Full roadmap (PM integration in Phase 1)
- [18-lean-roadmap.md](./18-lean-roadmap.md) — Lean roadmap (PM awareness rule)
