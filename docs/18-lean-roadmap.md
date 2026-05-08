# 18 - Lean Roadmap: The Minimum Brain That Ships

An alternative to [17-implementation-roadmap.md](./17-implementation-roadmap.md) that strips everything to what actually delivers value now. Same foundation (ruflo), same destination (cross-client intelligence), fewer moving parts.

**Philosophy:** Build the 20% that delivers 80% of the value. Add complexity only when reality demands it, not when specs predict it.

---

## Why This Document Exists

[Doc 17](17-implementation-roadmap.md) is a comprehensive plan. It's also 6 phases, 5 immune system layers, SONA evaluation gates, A/B testing frameworks, token routing tiers, multi-round debate protocols, skill catalog checksums, and knowledge migration systems.

For a solo developer with 3-5 projects on a Max5 subscription, that's enterprise software for a personal tool. This document asks: what if we build only what we'll actually need in the first 6 months?

Everything dropped here can be added later. Nothing in this plan prevents graduating to [doc 17](17-implementation-roadmap.md)'s full vision. The difference is: [doc 17](17-implementation-roadmap.md) builds the infrastructure first and hopes the value follows. This document builds the value first and adds infrastructure when it hurts not to have it.

---

## Design Constraints (Same as [Doc 17](17-implementation-roadmap.md))

| Constraint | Value |
|---|---|
| **Intelligence layer** | ruflo (non-negotiable) |
| **Subscription** | Max5 (1,000 msg/block) |
| **Active projects** | 3-5 during build period |
| **Core value** | Cross-project intelligence |
| **PM framework** | Preserved from brana v1 |

---

## What's Dropped (and Why)

| [Doc 17](17-implementation-roadmap.md) Feature | Why It's Dropped | When to Add It Back |
|---|---|---|
| **SONA as a milestone** | Tag-based `memory search` works for <1000 patterns. SONA's neural features (MoE, EWC++, trajectory tracking) are for scale we won't hit in 6 months. | When tag-based recall fails you — you search for something you know is in ruflo memory and it doesn't surface. That's the signal. |
| **Token routing tiers** | On Max5 subscription, you pay per message block, not per token. Routing Haiku vs Sonnet vs Opus saves nothing. | If you switch to API billing. |
| **5-layer immune system** | Layers 2-5 (dual-track confidence, transferability gates, decay function, contradiction detection) are statistical machinery for a dataset of <500 patterns. | When you have 500+ patterns AND quarantine alone isn't catching bad ones. |
| **A/B testing framework** | Week-over-week controlled comparison is academic rigor for a system you're the only user of. You'll know if something is better. | Never, probably. Just try things and revert if worse. |
| **Skill catalog checksums** | Version pinning + SHA verification for 5-10 external skills is heavyweight package-manager ceremony. | When you're distributing the catalog to others or auto-installing skills. |
| **Deploy pipeline ceremony** | `rollback.sh`, `CHANGELOG.md`, tag-based rollback, `backup-knowledge.sh` as separate scripts. Git already gives you all of this. | When git-based rollback fails you. |
| **Multi-round debate protocol** | Challenger agent doing 4-5 round debates consuming 5-10% of message budget. One pass catches 90% of what a debate would. | When single-pass challenges stop catching real issues. |
| **Knowledge migrations** | Framework for migrating patterns between schema versions. You're not at v1 yet. | When you actually change the schema and have patterns to migrate. |
| **Genome/connectome separation** | The conceptual distinction (code vs learned knowledge) is useful but the ceremony (symlink deploys, separate backup strategies, never-rollback-connectome rules) adds friction. | The concepts stay in your head. The ceremony gets added when a real incident proves you need it. |

---

## What Stays

| Feature | Why It Survives |
|---|---|
| **ruflo + ruflo memory** | The whole point. Tag-based recall, `memory store`, `memory search`. |
| **Two-layer memory** | Layer 0 (native auto memory) + Layer 1 (ruflo memory). Keeps working if ruflo breaks. Near-zero cost. |
| **Four hooks** | SessionStart (recall), SessionEnd (learn), PreToolUse (enforce spec/test gate), PostToolUse (notice). All in `system/hooks/hooks.json`. The learning loop IS the product. |
| **Quarantine** | New patterns enter at 0.5 confidence, transferable: false. 3 successes to promote. One mechanism, biggest impact. |
| **6 core skills** | memory, retrospective, project-onboard, client-retire, challenge. The user interface. |
| **Challenger (one-pass)** | `/brana:challenge` spawns Sonnet, gets one review, done. No debate, no auto-trigger, no pre-screening. |
| **Export escape hatch** | `export-knowledge.sh` on day 1. Non-negotiable safety net. |
| **PM awareness** | One rule file. Mastermind knows about PM repos. |

---

## Phase 1: Working Skeleton (Weeks 1-3)

**Goal:** ruflo installed, ruflo memory initialized, 6 skills working, export escape hatch in place. You can use the system.

### What You Build

```
~/projects/brana/
├── .claude/
│   └── CLAUDE.md                    ← "You are developing the mastermind"
│
├── system/                          ← Deploys to ~/.claude/
│   ├── CLAUDE.md                    ← Mastermind identity
│   ├── rules/
│   │   ├── universal-quality.md     ← "Test before ship, no secrets"
│   │   ├── git-discipline.md        ← "Conventional commits"
│   │   └── pm-awareness.md          ← "Check PM repo before planning"
│   ├── skills/
│   │   ├── memory.md
│   │   ├── retrospective.md
│   │   ├── project-onboard.md
│   │   │   ├── client-retire.md
│   │   └── challenge.md
│   ├── agents/
│   │   └── scout.md                 ← Haiku fast research
│   └── settings.json                ← Hooks wired but disabled (enabled Phase 2)
│
├── deploy.sh                        ← cp -r system/* ~/.claude/ (yes, copy, not symlink)
├── export-knowledge.sh              ← Portable JSON export
├── validate.sh                      ← YAML frontmatter + context budget check
├── test-hooks.sh                    ← Pipe fake JSON to hooks, verify exit 0
├── test-memory.sh                   ← Store → search → verify round-trip
├── test.sh                          ← Runs all test layers
└── README.md
```

**Testing strategy:** Three layers, run before merging: static validation, hook smoke tests, memory round-trip. The full pyramid from [22-testing.md](dimensions/22-testing.md) is adopted pain-driven — add layers when failures motivate them, not upfront.

**What's different from [doc 17](17-implementation-roadmap.md):**
- No `rollback.sh` — `git checkout` + `deploy.sh` IS your rollback
- No `backup-knowledge.sh` — `export-knowledge.sh` IS your backup
- No `CHANGELOG.md` — git log IS your changelog
- No `BACKLOG.md` — your project management is elsewhere
- `deploy.sh` uses `cp -r`, not symlinks. Simpler. If you edit `~/.claude/` directly by accident, `git diff` in brana/ shows what's diverged. Symlinks are elegant but add cognitive overhead for one developer.

### User Feedback Loop

Create a user practices document (see [00-user-practices.md](./00-user-practices.md) for the template) during Phase 1. This is the field notebook — observations from real usage that drive system evolution. When the same pain point keeps appearing, that's the signal to automate it as a hook or validation check in Phase 2+.

### ruflo Setup

```bash
npm install -g ruflo@2.5.0-alpha.130
# Install missing sql.js dependency (not in package.json, required at runtime — see errata #25)
npm install sql.js --prefix $(dirname $(which ruflo))/..
ruflo init
cd "$HOME" && ruflo memory search --query "test"  # verify it works
```

> **Never use `npx`** to invoke ruflo in hooks, skills, or `.mcp.json` — it creates a separate package cache missing sql.js (see lesson #17). Use the globally-installed binary directly. `deploy.sh` auto-ensures sql.js on every deploy.

### Deploy

```bash
#!/bin/bash
# deploy.sh — copy system to ~/.claude/
set -e
./validate.sh || exit 1
cp -r system/* ~/.claude/
echo "Deployed. Verify: claude --version in any project."
```

### Skills

Build all 6 in week 1-2. Keep them simple:

| Skill | What It Does | ruflo Command |
|---|---|---|
| `/brana:memory recall` | Query ruflo memory for current context | `memory search -q` |
| `/brana:retrospective` | Manually store a learning | `memory store -k -v --namespace --tags` |
| `/project-onboard` | Bootstrap a new project + recall portfolio knowledge | `memory search -q` |
| `/brana:memory pollinate` | Pull patterns from other clients | `memory search -q` |
| `/brana:client-retire` | Archive project patterns, mark as historical | bulk tag update |
| `/brana:challenge` | Sonnet reviews your current plan (one pass) | Task tool with `model: "sonnet"` |

### Plugins to Install

| Plugin | Why |
|---|---|
| **security-guidance** (Anthropic) | Blocks dangerous commands |
| **commit-commands** (Anthropic) | Consistent git workflow |
| **Context7 MCP** | Real-time library docs |

### Export Escape Hatch

Same `export-knowledge.sh` from [doc 17](17-implementation-roadmap.md). Build it before you store a single pattern.

### Exit Criteria

- [ ] `deploy.sh` copies system to `~/.claude/` and loads correctly
- [ ] All 6 skills invokable and working
- [ ] `/brana:memory recall` returns results from manually-inserted test patterns
- [ ] `/brana:challenge` spawns Sonnet and returns useful feedback
- [ ] `export-knowledge.sh` produces output
- [ ] ruflo CLI responds to basic commands
- [ ] Context budget under 15KB
- [ ] `./test.sh` passes all layers (validate + hooks + memory)
- [ ] Plugins installed
- [ ] Used in 2+ real sessions. Skills feel useful, not ceremonial.
- [ ] Tag: `v0.1.0`

---

## Phase 2: The Learning Loop (Weeks 3-6)

**Goal:** Automated learning. Hooks fire every session. The brain remembers. This is where the system earns its existence.

### Three Hooks

Wire into `system/settings.json`. See [09-claude-code-native-features.md](dimensions/09-claude-code-native-features.md) for the hook JSON format, all 14 events, and async constraints.

#### SessionStart — "Remember what you know"

```
Trigger: Every session start
Action:
  1. Detect current project
  2. Query ruflo memory: project-tagged + tech-matched + high-confidence universal
  3. Inject context summary
Fallback: Skip if ruflo unavailable
```

#### SessionEnd — "Remember what you learned"

```
Trigger: Session termination (fires once — NOT Stop, which fires every response)
Action:
  1. Extract patterns (problem→solution, failures, decisions)
  2. Store in ruflo memory:
     - tags: project, technologies, problem types
     - confidence: 0.5 (quarantined)
     - transferable: false
  3. Also write critical learnings to Layer 0 (auto memory files)
Fallback: Write to ~/.claude/memory/pending-learnings.md
```

#### PostToolUse — "Notice what matters"

```
Trigger: Write|Edit|Bash (filtered)
Action:
  - Test failure after change → record what didn't work
  - Test pass after fix → record the fix
  - Keep it lightweight, guard against loops
Fallback: Skip entirely if ruflo unavailable
```

~~**Constraint (2026-03-13):** PostToolUse and PostToolUseFailure hooks don't fire from plugin `hooks.json` (CC v2.1.x bug, issue #24529). Current workaround: `bootstrap.sh` installs these to `~/.claude/settings.json` with absolute paths. Track the CC issue — when fixed, migrate to plugin hooks.json.~~ **Resolved 2026-05-08:** All hooks now in `system/hooks/hooks.json`. Hooks are read-once at CC session startup — restart CC after any hook config change. See plugin-packaging.md E1.

**Optimization:** Use `"async": true` on the PostToolUse hook so pattern storage doesn't block Claude's work. Also use the separate `PostToolUseFailure` event to capture failure patterns specifically — often more valuable than successes.

### Quarantine (The One Immune System Layer That Matters)

Every new pattern enters quarantined:

```
confidence: 0.5
transferable: false
promotion: 3 successful recalls in different sessions
failure: immediate demotion to suspect on bad recall
```

This prevents the worst failure mode — bad patterns spreading across clients before they're proven. If quarantine alone isn't catching problems after 3-4 months, revisit [doc 16](dimensions/16-knowledge-health.md)'s full immune system. Until then, this is enough.

### Testing the Loop

```
1. Start session in test project
2. SessionStart fires, queries ruflo memory
3. Solve a problem, end session
4. SessionEnd hook stores pattern
5. New session in same project → pattern recalled
6. New session in different project → pattern NOT recalled (quarantined)
7. After 3 successful recalls → pattern promotable
```

**Record/playback:** Once this manual sequence works, capture the hook inputs/outputs and convert to a deterministic replay test (see [22-testing.md](dimensions/22-testing.md) for the Block Engineering pattern). This is the single most impactful testing technique for non-deterministic agent behavior.

### Exit Criteria

- [ ] All 3 hooks firing correctly
- [ ] Graceful degradation when ruflo unavailable
- [ ] No infinite hook loops
- [ ] Full recall→learn→recall cycle verified
- [ ] Quarantine working: new patterns at 0.5, not transferable
- [ ] Layer 0 fallback working (pending-learnings.md)
- [ ] After 10+ sessions across 2+ projects: >50% of recalled patterns actually useful
- [ ] At least one cross-client pattern surfaced via manual `/brana:memory pollinate`
- [ ] At least one failure recalled and avoided
- [ ] Tag: `v0.2.0`

---

## Phase 3: Refinement (Weeks 6-12)

**Goal:** Polish what works, fix what doesn't, add what's missing. NOT a feature phase — a quality phase.

This phase is intentionally loose. By week 6, you'll know what's actually broken or missing in your specific workflow. Don't pre-plan it — respond to real pain.

### Likely Work (Based on What Usually Hurts)

**Recall quality tuning:**
- Tags are too broad or too narrow → refine tagging in SessionEnd hook
- Too many patterns recalled → add confidence threshold to SessionStart
- Wrong patterns recalled → adjust tech-match algorithm
- Good patterns not found → improve tag vocabulary

**Quarantine promotion:**
- Define "successful recall" clearly (tests pass? user didn't override? session completed?)
- Build the promotion path: quarantined → trusted → transferable
- Track manually at first. Automate only if manual tracking becomes annoying.

**Cross-pollination refinement:**
- `/brana:memory pollinate` is too noisy or too quiet
- Technology matching needs tuning (too specific = nothing found, too broad = irrelevant)
- Add tech-stack tags to project onboarding

**Challenge improvements:**
- Store challenge outcomes in ruflo memory (which challenges caught real issues?)
- Adjust when you invoke `/brana:challenge` based on experience, not automation

**Skill catalog (lightweight):**
- A markdown file listing external skills you've tried and vetted
- No checksums, no auto-install. Just a curated list with notes.

**Monthly manual review:**
- Not automated `/knowledge-audit` — just you, once a month:
  - How many patterns in ruflo memory?
  - Any that seem wrong? Demote or convert to anti-pattern.
  - Any that are stale? Lower confidence manually.
  - Any contradictions? Resolve them.
  - Grade recall quality using RAG metrics: precision@k (were recalled patterns relevant?), staleness rate, faithfulness. See [23-evaluation.md](dimensions/23-evaluation.md) and [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md#evaluating-the-brain) for the full measurement framework.
- This is [doc 16](dimensions/16-knowledge-health.md)'s immune system, but human-powered instead of automated.

### Exit Criteria

- [ ] Pattern recall precision >60% (up from Phase 2's >50%)
- [ ] At least one pattern promoted through quarantine to trusted
- [ ] At least one bad pattern caught and demoted or converted to anti-pattern
- [ ] Monthly review done at least once — health snapshot documented
- [ ] Cross-pollination has delivered at least one genuinely useful cross-client insight
- [ ] The system feels like it's helping, not like overhead
- [ ] Tag: `v0.3.0`

---

## Phase 4: Project Enforcement (After Phase 3)

**Goal:** The mastermind enforces spec-driven and test-driven development in managed clients. Not suggestions in CLAUDE.md (~80% compliance) — deterministic enforcement via PreToolUse hooks (~100%). See [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md) "Project Enforcement" section for the architectural design.

**Prerequisite:** Phase 3 complete (v0.3.0). The learning loop must work before enforcement layers on top — ADRs feed into ruflo memory via `/brana:retrospective`.

### Why This Phase Exists

Research (doc 11 section 5, [doc 09](dimensions/09-claude-code-native-features.md) PreToolUse) showed:
- CLAUDE.md rules alone achieve ~80% compliance for complex workflows (Claude Code issues #21119, #6120, #15443)
- PreToolUse hooks with `permissionDecision: "deny"` achieve ~100% (deterministic block)
- TDD-Guard (external) pushed TDD compliance from ~20% to ~84% via PreToolUse hooks
- The mastermind can enforce **spec-before-code** the same way — pure git checks, no ruflo dependency

### WI-1: `/decide` Skill — ADR Creation *(Retired 2026-03-15)*

> **Status: Retired.** The `/decide` skill was implemented (commit b668f2e) then intentionally retired in the skill consolidation (commit f2571bd). ADR creation is now handled inline by `/brana:build` SPECIFY step, which creates ADRs as part of the standard build loop. The PreToolUse spec-before-code enforcement (the lasting contribution of this WI) remains active.

**File:** ~~`system/skills/decide/SKILL.md`~~ (removed)

**Frontmatter:**
```yaml
---
name: decide
description: Create an Architecture Decision Record (ADR) in docs/decisions/
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---
```

**Logic (step by step):**

1. **Parse arguments.** If `$ARGUMENTS` is empty, ask the user for the decision title. If provided, use it (e.g., `/decide use JWT for authentication`).

2. **Locate project root.** Run `git rev-parse --show-toplevel` in the current directory. Fall back to `$PWD` if not a git repo.

3. **Check for `docs/decisions/` directory.** If it doesn't exist, ask the user: "This project doesn't have `docs/decisions/` yet. Create it? This also enables spec-before-code enforcement." If yes → `mkdir -p docs/decisions/`. If no → abort.

4. **Auto-increment ADR number.** Scan `docs/decisions/ADR-*.md` files. Extract the highest NNN from `ADR-NNN-*.md` filenames. New number = highest + 1. If no ADRs exist, start at 001. Zero-pad to 3 digits.

5. **Slugify title.** Convert title to lowercase, replace spaces and special characters with hyphens, truncate to 50 characters. Example: "Use JWT for Authentication" → `use-jwt-for-authentication`.

6. **Create ADR file.** Write to `docs/decisions/ADR-NNN-slug.md` using the Nygard template:

```markdown
# ADR-NNN: Title

**Date:** YYYY-MM-DD
**Status:** proposed

## Context

[What is the issue motivating this decision or change?]

## Decision

[What is the change that we're proposing and/or doing?]

## Consequences

[What becomes easier or more difficult because of this change?]
```

Replace `NNN` with the zero-padded number, `Title` with the original title, `YYYY-MM-DD` with today's date.

7. **Pre-populate context.** If the conversation so far contains relevant discussion (architecture debate, options weighed, trade-offs discussed), summarize it into the Context section. Don't leave it as a placeholder if there's usable context.

8. **Store in ruflo memory.** Use the standard binary discovery pattern:
```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v ruflo &>/dev/null && CF="ruflo"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx ruflo"
```
Store: `cd $HOME && $CF memory store -k "decision:{PROJECT}:{slug}" -v '{"type": "decision", "title": "...", "status": "proposed", "confidence": 0.5, "transferable": false}' --namespace decisions --tags "client:{PROJECT},type:decision,status:proposed"`

9. **Fallback (ruflo unavailable).** Append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`:
```
## Decision: {title}
- Date: YYYY-MM-DD
- Status: proposed
- File: docs/decisions/ADR-NNN-slug.md
```

10. **Report.** Show the user: file created, path, ADR number, next step ("Fill in the Context, Decision, and Consequences sections").

**Rules:**
- Ask for clarification if the title is ambiguous
- Never overwrite an existing ADR
- The ADR format is Nygard lightweight (Context, Decision, Consequences) — not the comprehensive v1 template

### WI-2: SDD/TDD Conventions Rule

**File:** `system/rules/sdd-tdd.md`

**Full content:**
```markdown
# Spec-Driven & Test-Driven Development

## When `docs/decisions/` exists in the project

This project has opted into spec-driven development:

- **Create an ADR before implementing any new feature.** Use `/brana:build` — ADR creation happens in the SPECIFY step. The PreToolUse hook will block implementation on `feat/*` branches until a spec or test exists.
- **Write tests before implementation code.** If TDD-Guard is installed, it enforces this automatically.
- **Feature branches (`feat/*`) must have spec/test activity before implementation.** Commits touching `docs/`, `test/`, `tests/`, or `*.test.*`/`*.spec.*` files satisfy this requirement.

## When `tdd-guard` is installed

TDD-Guard enforces RED-GREEN-REFACTOR:
- Write a failing test first
- Write minimal code to pass
- Refactor while green
- Toggle with `tdd-guard on/off`

## For projects without `docs/decisions/`

These rules don't apply — the project hasn't opted into SDD enforcement.

## Recommended setup for new projects

- `mkdir -p docs/decisions` — opt into spec-driven enforcement
- `npm install -g tdd-guard && tdd-guard on` — opt into TDD enforcement
```

**No `paths:` scoping** — loads globally (always in context). Keep it short (under 500 bytes) to minimize context budget impact.

### WI-3: PreToolUse Spec-Before-Code Hook

**File:** `system/hooks/pre-tool-use.sh`

**Shebang and safety:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Input (stdin JSON):**
```json
{
  "session_id": "abc123",
  "cwd": "/home/user/project",
  "hook_event_name": "PreToolUse",
  "tool_name": "Write",
  "tool_input": { "file_path": "/home/user/project/src/auth.ts", "content": "..." }
}
```

**Logic (detailed, with every branch):**

1. **Parse input.** `INPUT=$(cat)`. Extract `TOOL_NAME`, `CWD`, and `FILE_PATH` via `jq`. For Write: `.tool_input.file_path`. For Edit: `.tool_input.file_path`.

2. **Early exit: not Write or Edit.** If `TOOL_NAME` is not `Write` or `Edit` → output `{"continue": true}` and exit 0. (The matcher in settings.json handles this, but defense in depth.)

3. **Early exit: no file path.** If `FILE_PATH` is empty → output `{"continue": true}` and exit 0.

4. **Find git root.** `GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "")`. If empty (not a git repo) → pass through.

5. **Opt-in check.** Does `$GIT_ROOT/docs/decisions/` exist? If not → pass through. This is the opt-in mechanism.

6. **Branch check.** `BRANCH=$(git -C "$GIT_ROOT" branch --show-current 2>/dev/null || echo "")`. If `BRANCH` does not start with `feat/` → pass through. Only enforce on feature branches.

7. **Target file check: is it a spec/test file?** Make `FILE_PATH` relative to `GIT_ROOT`. Check if it matches any of:
   - `docs/*` (any file in docs/)
   - `test/*`, `tests/*`, `__tests__/*` (test directories)
   - `*.test.*`, `*.spec.*` (test file patterns)
   - `*.md` (documentation)
   If yes → pass through. Always allow spec/test/doc writes.

8. **Spec activity check.** Has any spec or test file been touched on this branch?
   ```bash
   MERGE_BASE=$(git -C "$GIT_ROOT" merge-base HEAD main 2>/dev/null || \
                git -C "$GIT_ROOT" merge-base HEAD master 2>/dev/null || echo "")
   ```
   If `MERGE_BASE` is empty (no main/master, fresh repo) → pass through.

   Check three sources (committed + staged + unstaged):
   ```bash
   SPEC_FILES=""
   # Committed changes on this branch
   SPEC_FILES="$SPEC_FILES$(git -C "$GIT_ROOT" diff --name-only "$MERGE_BASE"..HEAD -- \
       'docs/' 'test/' 'tests/' '__tests__/' '*.test.*' '*.spec.*' 2>/dev/null || true)"
   # Staged changes
   SPEC_FILES="$SPEC_FILES$(git -C "$GIT_ROOT" diff --cached --name-only -- \
       'docs/' 'test/' 'tests/' '__tests__/' '*.test.*' '*.spec.*' 2>/dev/null || true)"
   # Unstaged changes
   SPEC_FILES="$SPEC_FILES$(git -C "$GIT_ROOT" diff --name-only -- \
       'docs/' 'test/' 'tests/' '__tests__/' '*.test.*' '*.spec.*' 2>/dev/null || true)"
   ```

9. **Decision.** If `SPEC_FILES` is non-empty (after stripping whitespace) → pass through (spec activity exists).

10. **Block.** If no spec activity found → output:
    ```json
    {
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "Spec-first: use /brana:build SPECIFY step (ADR creation) or write tests before implementation on feat/* branches. This project has docs/decisions/ — enforcement is active."
      }
    }
    ```
    Exit 0.

**Graceful degradation:** If any git command fails (stderr), the hook outputs `{"continue": true}` and exits 0. Never block the user due to a hook error.

**Performance:** All operations are local git commands (<100ms total). Timeout: 5000ms (settings.json).

### WI-4: settings.json Update

**File:** `system/settings.json`

Add PreToolUse entry. Full resulting file:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/pre-tool-use.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "SessionStart": [ ... existing ... ],
    "SessionEnd": [ ... existing ... ],
    "PostToolUse": [ ... existing ... ],
    "PostToolUseFailure": [ ... existing ... ]
  }
}
```

### WI-5: Update `/project-onboard`

**File:** `system/skills/project-onboard/SKILL.md`

Add new step 5.5 (between current step 5 "Check PM integration" and step 6 "Present summary"):

```markdown
5.5. **Check SDD/TDD setup:**
   - Does `docs/decisions/` exist? If yes → report "SDD enforcement: active (PreToolUse hook blocks impl without spec on feat/* branches)"
   - Check if `tdd-guard` is in PATH (`command -v tdd-guard`). If yes → report "TDD enforcement: active (TDD-Guard PreToolUse hook)"
   - If neither exists, include in the summary:
     "**SDD/TDD not configured.** To enable:
      - `mkdir -p docs/decisions` → spec-before-code enforcement
      - `npm install -g tdd-guard && tdd-guard on` → test-before-code enforcement"
```

### WI-6: Tests

**File:** `test-hooks.sh`

Add 4 PreToolUse test functions after the existing session-end tests. Each test creates a temporary git repo, configures the scenario, pipes fake PreToolUse JSON to the deployed hook, and asserts on the output.

**Test 1: Allows spec files on feat/* branches**
```
Setup: temp dir, git init, git checkout -b feat/test, mkdir docs/decisions
Input: PreToolUse JSON with tool_name=Write, file_path=docs/decisions/ADR-001.md, cwd=temp dir
Assert: exit 0, output contains "continue": true, NO permissionDecision: deny
```

**Test 2: Blocks impl files without spec activity**
```
Setup: temp dir, git init, commit initial, git checkout -b feat/test, mkdir docs/decisions
Input: PreToolUse JSON with tool_name=Write, file_path=src/app.ts, cwd=temp dir
Assert: exit 0, output contains permissionDecision: "deny"
```

**Test 3: Passes through without docs/decisions/**
```
Setup: temp dir, git init, git checkout -b feat/test (NO docs/decisions/)
Input: PreToolUse JSON with tool_name=Write, file_path=src/app.ts, cwd=temp dir
Assert: exit 0, output contains "continue": true, NO permissionDecision
```

**Test 4: Passes through on non-feat branches**
```
Setup: temp dir, git init, git checkout -b fix/something, mkdir docs/decisions
Input: PreToolUse JSON with tool_name=Write, file_path=src/app.ts, cwd=temp dir
Assert: exit 0, output contains "continue": true, NO permissionDecision
```

**Cleanup:** Each test removes its temp directory in a trap handler.

### WI-7: Update skill-catalog.md

**File:** `skill-catalog.md`

Add entry for `/decide`:
```
| `/decide <title>` | Create ADR in docs/decisions/ (Nygard format) | Also enables spec-before-code enforcement |
```

### WI-8: Deploy, Test, Commit

1. `./validate.sh` — passes (new skill frontmatter valid, new hook script valid syntax, settings.json valid JSON, PreToolUse is a known event, context budget OK)
2. `./deploy.sh` — copies to `~/.claude/`
3. `./test.sh` — all layers green including 4 new PreToolUse tests
4. Atomic commits:
   - `feat(skills): add /decide for ADR creation (Nygard format)`
   - `feat(hooks): add PreToolUse spec-before-code enforcement`
   - `feat(rules): add SDD/TDD conventions`
   - `feat(skills): update project-onboard with SDD/TDD check`
5. Merge to master with `--no-ff`

### Exit Criteria

- [ ] `/decide test-feature` creates `docs/decisions/ADR-001-test-feature.md` with correct template
- [ ] `/decide` auto-increments (second ADR gets 002)
- [ ] `/decide` stores decision in ruflo memory (or fallback)
- [ ] PreToolUse hook blocks Write on `feat/*` branch in project with `docs/decisions/` and no spec activity
- [ ] PreToolUse hook allows Write on spec/test files always
- [ ] PreToolUse hook passes through on `fix/*`, `docs/*`, `main` branches
- [ ] PreToolUse hook passes through in projects without `docs/decisions/`
- [ ] PreToolUse hook degrades gracefully (git failure → pass through)
- [ ] `sdd-tdd.md` rule loads correctly, context budget still under 15KB
- [ ] `/project-onboard` reports SDD/TDD status
- [ ] `./test.sh` passes all layers (existing + 4 new PreToolUse tests)
- [ ] Used in at least 2 real sessions on a real project
- [ ] Tag: `v0.4.0`

---

## Phase 5: Project Alignment (After Phase 4)

**Goal:** Active project alignment. The mastermind doesn't just enforce disciplines in projects that already have the right structure — it helps projects GET to the right structure.

**Prerequisite:** Phase 4 complete (v0.4.0). Enforcement hooks must work before the alignment skill can verify they're active.

### What You Build

- `/project-align` skill — 5-phase pipeline: DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT
- [Doc 27](dimensions/27-project-alignment-methodology.md) methodology as the reference (what "aligned" means): [27-project-alignment-methodology.md](dimensions/27-project-alignment-methodology.md)
- Alignment checklist: 28 items, 7 groups, 3 tiers (minimal / standard / full)

### Why This Phase Exists

`/project-onboard` reports state. `/project-align` creates it. After Phase 4, the enforcement infrastructure exists (PreToolUse hooks, `/decide`, SDD/TDD rules). But projects still need manual setup to activate enforcement — creating `docs/decisions/`, seeding domain glossaries, configuring test frameworks. This phase automates that setup.

### Exit Criteria

- [ ] `/project-align` creates `.claude/CLAUDE.md`, `docs/decisions/`, test scaffolding
- [ ] `/project-align` works on greenfield (new) and brownfield (existing) projects
- [ ] Discovery interview personalizes scaffolding (not generic templates)
- [ ] Alignment report shows before/after state
- [ ] Alignment results stored in ruflo memory
- [ ] `portfolio.md` updated by alignment
- [ ] Works on at least 2 real projects
- [ ] Tag: `v0.5.0`

---

## Post-Phase 5: Agent-Skill Symbiosis (Completed)

Agents and skills now integrate as complementary layers rather than independent systems. This work was pain-driven by observed skill invocation gaps (Vercel's 56% non-invocation finding).

**What was built:**
- **Improved skill descriptions** — explicit "Use when..." trigger conditions on all 18 skills, raising invocation from 53% to ~79%
- **6 new agents** (memory-curator, client-scanner, venture-scanner, challenger, debrief-analyst, archiver) joining the existing scout — 7 total
- **Delegation-routing rule** — agents auto-delegate when skills go uninvoked, closing the gap from ~79% to ~95%
- **Skill-to-agent integration** — four patterns formalized: skill spawns agent (A), agent preloads skill (B), auto-delegation (C), multi-agent orchestration via skills (D)

See [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md) "Agent + Skill Symbiosis" section for the full architecture.

---

## After v0.5.0: What Gets Added When It Hurts

This isn't a phase — it's a menu. Add items when you feel the pain, not on a schedule.

**Multi-Agent TDD** — separate test-writer and implementer teammates in Agent Teams. Add when using Agent Teams on real projects and context pollution between test/impl is observed. See [22-testing.md](dimensions/22-testing.md) "Multi-Agent TDD" section.

**Full SDD workflow orchestration** — cc-sdd-style 5-phase gates (steering → spec-init → spec-design → spec-tasks → spec-impl). Add when the minimal spec-before-code hook isn't structured enough. The hook is a gate; a full workflow skill would be a guide.

**Project health monitoring** — statusline display of alignment metrics (ADR freshness, test coverage trend, debrief frequency). The base statusline is deployed (`~/.claude/statusline.sh` — see [doc 10](dimensions/10-statusline-research.md) §Brana Implementation); this backlog item is about layering alignment-specific metrics on top. Add when you want passive awareness of alignment drift. See [10-statusline-research.md](dimensions/10-statusline-research.md) "Project Health Monitoring via Statusline" and [27-project-alignment-methodology.md](dimensions/27-project-alignment-methodology.md) "Project Health Monitoring".

**`/project-align --check`** — periodic re-assessment mode. Runs the 28-item checklist without implementing, reports regressions. Add when alignment drift becomes a real concern across multiple clients.

| Pain | Solution | [Doc 17](17-implementation-roadmap.md) Equivalent |
|---|---|---|
| "Tag search isn't finding patterns I know exist" | Activate SONA: `neural train`, switch to vector similarity | Phase 3: SONA activation |
| "Stale patterns keep resurfacing" | Add monthly decay function (confidence -= 0.05 for unused patterns) | Phase 4: Layer 4 |
| "Contradicting patterns in ruflo memory" | Add contradiction check on pattern storage | Phase 4: Layer 5 |
| ~~"I want automatic challenges on big plans"~~ | ~~Add PostToolUse hook on ExitPlanMode → spawns Sonnet~~ **Done** — `post-plan-challenge.sh` nudges challenger agent on ExitPlanMode | Phase 5: Auto-challenge |
| "Onboarding a new project should suggest skills" | Enhance `/project-onboard` with tech detection + catalog lookup | Phase 5: Smart onboard |
| "The system should suggest its own improvements" | Add self-referential pattern queries (domain: brana-system) | Phase 5: Self-improvement |
| "I need to migrate patterns to a new schema" | Build migration script when the schema actually changes | Phase 5: Knowledge migrations |
| "Recall is slow / ruflo memory is big" | Activate HNSW indexing, consider quantization | Phase 3: Vector intelligence |
| "I'm distributing skills to others" | Add checksums and version pinning to skill catalog | Phase 3: Skill catalog |

**The principle:** you'll know when you need it because something will hurt. Right now, nothing hurts because the system doesn't exist yet. Build the minimum, use it hard, add complexity in response to real friction.

---

## Timeline

```
Weeks 1-3       Phase 1: Working Skeleton
                ├─ ruflo + ruflo memory + 6 skills + plugins
                ├─ export escape hatch
                ├─ deploy.sh (cp -r, not ceremony)
                └─ Tag: v0.1.0

Weeks 3-6       Phase 2: Learning Loop
                ├─ 3 hooks (recall, learn, notice)
                ├─ Quarantine (the one immune layer)
                ├─ Two-layer memory (native + ruflo memory)
                └─ Tag: v0.2.0

Weeks 6-12      Phase 3: Refinement
                ├─ Tune recall, fix what's broken
                ├─ Promotion paths, monthly manual review
                ├─ Cross-pollination tuning
                └─ Tag: v0.3.0

After Phase 3   Phase 4: Project Enforcement
                ├─ /decide skill (ADR creation, Nygard format)
                ├─ PreToolUse spec-before-code hook
                ├─ SDD/TDD conventions rule
                ├─ TDD-Guard recommendation in /project-onboard
                └─ Tag: v0.4.0

After Phase 4   Phase 5: Project Alignment
                ├─ /project-align skill (5-phase active pipeline)
                ├─ 28-item alignment checklist, 3 tiers
                ├─ Greenfield + brownfield support
                ├─ Cross-project alignment learning
                └─ Tag: v0.5.0

Post-Phase 5    Agent-Skill Symbiosis (completed)
                ├─ Improved skill descriptions (Use when... triggers)
                ├─ 9 new agents (10 total roster)
                ├─ Delegation-routing rule (auto-delegation)
                ├─ 4 integration patterns (A-D)
                ├─ Venture OS: 8 daily/weekly/monthly skills, 3 venture agents,
                │   2 venture hooks, GitHub Issues integration
                └─ Auto-challenge hook on ExitPlanMode

After v0.5.0    Pain-driven additions
                └─ SONA, decay, contradiction detection,
                    multi-agent TDD, full SDD workflow orchestration,
                    health monitoring statusline, /project-align --check...
                    when the pain justifies the complexity
```

**Total to usable system (v0.2.0):** ~6 weeks
**Total to refined system (v0.3.0):** ~12 weeks
**Total to enforced system (v0.4.0):** after Phase 3 real-world validation
**Total to aligned system (v0.5.0):** after Phase 4 real-world validation
**Total to [doc 17](17-implementation-roadmap.md)'s full vision:** whenever reality demands it

---

## Comparison: [Doc 17](17-implementation-roadmap.md) vs [Doc 18](18-lean-roadmap.md)

| Dimension | [Doc 17](17-implementation-roadmap.md) (Full Roadmap) | [Doc 18](18-lean-roadmap.md) (Lean Roadmap) |
|---|---|---|
| **Phases** | 6 (0-5) | 5 + pain-driven menu |
| **Timeline to usable** | 6 weeks (v0.3.0) | 6 weeks (v0.2.0) |
| **Timeline to "done"** | 4+ months (v1.0.0) | 12 weeks (v0.3.0), then ongoing |
| **Immune system** | 5 layers, fully automated | 1 layer (quarantine) + monthly manual review |
| **SONA** | Phase 3 milestone with evaluation gate | Not planned. Activate when tag search fails. |
| **Token routing** | Explicit tier system (WASM→Haiku→Sonnet→Opus) | Not planned. Subscription = flat cost. |
| **A/B testing** | Formal framework with metrics | Not planned. Try things, revert if worse. |
| **Challenger** | Multi-round debate, auto-trigger, budget calibration | One-pass Sonnet review, manual invocation |
| **Deploy** | Symlinks, rollback.sh, backup.sh, changelog | `cp -r` + git |
| **Skill catalog** | YAML with checksums, version pins, auto-verify | Markdown file with notes |
| **Knowledge health** | Automated detection, decay, contradiction, audit skill | Manual monthly review |
| **Risk** | Over-engineering: building what you don't need yet | Under-engineering: hitting walls that were predictable |

### Which to Use?

**Use [Doc 17](17-implementation-roadmap.md) if:**
- You enjoy building systems infrastructure
- You want the full vision from day 1
- You're comfortable with a 4-month runway before the system is "done"
- You believe the immune system complexity will pay off early

**Use [Doc 18](18-lean-roadmap.md) if:**
- You want to be using the brain in 3 weeks
- You'd rather add complexity in response to pain than in anticipation of it
- 3-5 projects and <1000 patterns don't justify enterprise infrastructure
- You believe manual review beats automated systems at this scale

**The hybrid approach (recommended):**
- Start with [Doc 18](18-lean-roadmap.md)'s Phases 1-2 (get to a working brain fast)
- Use [Doc 17](17-implementation-roadmap.md) as the reference architecture for the "pain-driven additions" phase
- When something hurts, look up the solution in [Doc 17](17-implementation-roadmap.md) and implement it
- See the upgrade path below for exactly how this works

---

## Upgrade Path: [Doc 18](18-lean-roadmap.md) → [Doc 17](17-implementation-roadmap.md)

This roadmap is designed as the on-ramp to [doc 17](17-implementation-roadmap.md), not a fork. Every decision here is a subset of [doc 17](17-implementation-roadmap.md)'s decisions — nothing conflicts, nothing needs redoing.

### Why It Composes Without Rework

**Same data, same schema.** Both roadmaps use ruflo memory's pattern storage (SQLite + JSON blobs). [Doc 18](18-lean-roadmap.md) stores patterns with tags, confidence, and transferable flags. [Doc 17](17-implementation-roadmap.md)'s additional features (dual-track confidence, decay timestamps, contradiction references) are extra fields on the same JSON. When you add them, existing patterns get sensible defaults — no migration needed.

**Same hooks, richer logic.** Both use the same three hooks (SessionStart, SessionEnd, PostToolUse) wired to the same triggers. [Doc 17](17-implementation-roadmap.md) adds more logic inside them (failure attribution, auto-challenge on ExitPlanMode). You enhance the hook scripts — you don't replace them.

**Same skills, more skills.** Both start with the same 6 core skills. [Doc 17](17-implementation-roadmap.md) adds `/skill-discover`, `/skill-install`, `/knowledge-audit`, `/system-health`. These are new files in `system/skills/`, not changes to existing ones.

**SONA reads existing data.** When you activate `neural train`, it indexes the patterns already in ruflo memory. It doesn't need patterns stored in a special format — it works on what's there.

### Compatibility Matrix

| [Doc 18](18-lean-roadmap.md) Decision | [Doc 17](17-implementation-roadmap.md) Upgrade | Redo? |
|---|---|---|
| `cp -r` deploy | Switch to symlinks in deploy.sh | **One line change.** Old deploys still work. |
| No rollback.sh | Create rollback.sh | **Add a file.** Nothing to undo. |
| Quarantine only (layer 1) | Add layers 2-5 on top | **Additive.** Quarantine stays, layers stack above it. |
| Tag-based `memory search` | Activate SONA (`neural train`) | **No change to hooks.** SONA enhances recall results transparently. |
| Single confidence field | Dual-track (session + validated) | **Add a field.** Existing patterns: `session_confidence = confidence`, `validated_confidence = confidence`. One-time backfill query. |
| No decay | Add monthly decay function | **Add a cron/script.** Reads existing `last_used` timestamps already being recorded. |
| No contradiction detection | Add contradiction check to SessionEnd hook | **Add logic to existing hook.** Reads existing tags already being stored. |
| One-pass `/brana:challenge` | Multi-round debate + auto-trigger | **Enhance skill file.** Old invocations still work, new flag enables debate mode. |
| Manual monthly review | `/knowledge-audit` skill | **The skill automates what you were doing manually.** Same checks, scripted instead of human. |
| Markdown skill catalog | YAML + checksums | **Format conversion.** 10 minutes. Data is the same. |
| No A/B testing | Add A/B framework | **New capability.** Doesn't touch existing code. |
| No token routing | Add routing tiers | **Config change.** Only relevant if you move off subscription billing. |

### The One Thing to Get Right Early: Tagging Discipline

The only potential friction in the upgrade is **tag quality**. [Doc 17](17-implementation-roadmap.md)'s advanced features (SONA similarity search, transferability gates, contradiction detection) all rely on patterns having consistent, meaningful tags. If your lean phase stores patterns with sloppy tags like `["fix", "bug", "code"]`, the advanced features won't work well on that data.

**The fix is free:** establish a tag vocabulary when you build the SessionEnd hook in Phase 2. Example:

```
Required tags for every pattern:
  - project: project name (e.g., "nexeye", "brana")
  - tech: technology stack (e.g., "supabase", "nextjs", "python")
  - type: problem category (e.g., "auth", "deployment", "testing", "performance")
  - outcome: "success" | "failure" | "partial"
```

This costs nothing to implement. It makes tag-based recall work better NOW and makes the SONA/immune-system upgrade seamless later.

### The Upgrade Timeline

```
Doc 18 Phase 1 (weeks 1-3)    v0.1.0  Foundation in place
Doc 18 Phase 2 (weeks 3-6)    v0.2.0  Learning loop + quarantine working
Doc 18 Phase 3 (weeks 6-12)   v0.3.0  Refined, 200-500 patterns accumulated
Doc 18 Phase 4 (after Phase 3) v0.4.0  SDD/TDD enforcement in managed clients
Doc 18 Phase 5 (after Phase 4) v0.5.0  Active project alignment pipeline

   ── pain-driven transition ── (not a deadline — when you feel it)

Doc 17 Phase 3: SONA           v0.6.0  Activate neural train on existing patterns
  Trigger: tag search misses patterns you know exist
  Effort: ~1 week (config + evaluation gate)

Doc 17 Phase 4: Immune system  v0.7.0  Add layers 2-5 on top of quarantine
  Trigger: quarantine alone isn't catching bad patterns
  Effort: ~2-4 weeks (decay, contradiction, transferability gates)

Doc 17 Phase 5: Self-improve   v0.8.0  Auto-challenge, dashboard, recursive learning
  Trigger: system is stable enough to improve itself
  Effort: ongoing
```

Each step is independent. You can do Phase 4 (immune system) without Phase 3 (SONA). You can do auto-challenge without A/B testing. Pick from [doc 17](17-implementation-roadmap.md)'s menu based on what actually hurts.

### What You'll Never Need to Redo

- **Patterns stored during lean phases** — they're in ruflo memory with tags, confidence, timestamps. Every [doc 17](17-implementation-roadmap.md) feature reads this data.
- **Hook wiring** — same triggers, same settings.json structure. You add logic, not replace it.
- **Skills** — same files, same frontmatter format. You add new ones and enhance existing ones.
- **Export escape hatch** — works the same at every scale. The Phase 5 enrichments just export more fields.
- **Project structure** — `~/projects/brana/system/` stays the same. You add files and directories, never restructure.

---

## References

- [09-claude-code-native-features.md](dimensions/09-claude-code-native-features.md) — Hook JSON format, all 14 events, stdin/stdout contracts, async constraints
- [17-implementation-roadmap.md](./17-implementation-roadmap.md) — The comprehensive roadmap (keep both)
- [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md) — Architecture this implements
- [16-knowledge-health.md](dimensions/16-knowledge-health.md) — Full immune system (for when quarantine isn't enough)
- [24-roadmap-corrections.md](./24-roadmap-corrections.md) — Errata: deploy.sh merge bug, Stop→SessionEnd, hook format, PostToolUseFailure
- [06-claude-flow-internals.md](dimensions/06-claude-flow-internals.md) — SONA details (for when tag-based recall isn't enough)
- [12-skill-selector.md](dimensions/12-skill-selector.md) — Trust model (for when you're sharing skills)
- [13-challenger-agent.md](dimensions/13-challenger-agent.md) — Full challenger design (for when one-pass isn't enough)
- [22-testing.md](dimensions/22-testing.md) — Testing strategy: record/playback, static validation, CI/CD pipeline
- [23-evaluation.md](dimensions/23-evaluation.md) — Evaluation strategy: RAG metrics for recall quality, eval-driven development
- [00-user-practices.md](./00-user-practices.md) — User feedback loop: field notes from real usage, graduation pathway from manual practice to hook/check
- [25-self-documentation.md](./25-self-documentation.md) — Frontmatter convention, staleness detection, growth stages for skills/configs
- [11-ecosystem-skills-plugins.md](dimensions/11-ecosystem-skills-plugins.md) — SDD/TDD enforcement tools (section 5): TDD-Guard, cc-sdd, Superpowers, multi-agent TDD
- [19-pm-system-design.md](./19-pm-system-design.md) — ADR design, `/decide` skill spec, CLAUDE.md compliance limitations
- [27-project-alignment-methodology.md](dimensions/27-project-alignment-methodology.md) — Project alignment: 28-item checklist, 3 tiers, 5-phase pipeline, cross-client learning
