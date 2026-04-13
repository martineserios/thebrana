
# Reconcile

Unified maintenance command for the brana system. Four domains, one entry point.

| Domain | Scope flag | What it checks |
|--------|-----------|---------------|
| **Consistency** | `--scope consistency` | Spec docs vs `system/` implementation drift (default) |
| **Security** | `--scope security` | Secrets, permissions, MCP tax, dangerous settings, credential files, acquired skill safety |
| **Propagation** | `--scope propagation` | Pending errata cascade, reflection gaps, spec-graph consistency |
| **Knowledge** | `--scope knowledge` | Stale dimensions, event log bloat, ruflo noise (DECAY) |

`--scope all` runs every domain sequentially.

**Replaces:** `/brana:audit` (merged into security domain), invokes `/brana:maintain-specs` commands (propagation domain).

## Usage

```
/brana:reconcile                          — consistency (default, backward compatible)
/brana:reconcile --scope security         — security checks only
/brana:reconcile --scope propagation      — spec cascade + graph checks
/brana:reconcile --scope knowledge        — knowledge hygiene (DECAY)
/brana:reconcile --scope all              — run all domains
```

Parse `--scope` from `$ARGUMENTS`. If no `--scope` flag is present, default to `consistency`.

## When to use

- **consistency** — After `/brana:maintain-specs` cascades changes that affect implementation, after manually editing specs, periodically, or before a new `/build-phase`
- **security** — Before sharing config, after adding MCP servers, after installing acquired skills, or monthly
- **propagation** — After dimension doc edits, when errata accumulate, or as part of a full maintenance cycle
- **knowledge** — After bulk indexing, when ruflo memory is suspected stale, weekly as DECAY hygiene pass
- **all** — Full system health check

## Architecture

After the enter→thebrana merge (ADR-006), specs and implementation coexist in one repo:

```
thebrana/
├── docs/                      ← roadmap specs (00, 15, 17-19, 24, 25, 30, 39)
│   └── reflections/           ← reflection specs (08, 14, 29, 31, 32)
├── system/                    ← implementation (skills, hooks, rules, agents, config)
├── .claude/CLAUDE.md          ← identity + conventions
└── deploy.sh                  ← deployment

brana-knowledge/dimensions/    ← dimension docs (knowledge, cross-repo)
```

Most reconcile work is **intra-repo** (docs/ → system/). Dimension docs in brana-knowledge provide additional spec surface but rarely contain implementation-specific claims.

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register steps based on scope:

- **consistency:** ORIENT, ROUTE, SCAN-SPECS, SCAN-IMPL, DIFF, PRESENT, APPLY, LOG, REPORT
- **security:** ORIENT, ROUTE, SEC-SCAN, SEC-REPORT
- **propagation:** ORIENT, ROUTE, PROP-SCAN, PROP-APPLY, PROP-REPORT
- **knowledge:** ORIENT, ROUTE, KNOW-1, KNOW-2, KNOW-3, KNOW-REPORT
- **all:** ORIENT, ROUTE, then all domain steps sequentially

**Plan mode:** Enter plan mode for scanning steps (SCAN-SPECS, SCAN-IMPL, DIFF, SEC-SCAN, PROP-SCAN). Exit plan mode before presenting results.

## Process

### Step 0: Orient + Route

#### 0a: Route by scope

Parse `--scope` from `$ARGUMENTS`. Default: `consistency`.

| Scope | Jump to |
|-------|---------|
| `consistency` | Step 1 (Scan specs) |
| `security` | Security Domain |
| `propagation` | Propagation Domain |
| `knowledge` | Knowledge Domain (DECAY) |
| `all` | Run consistency → security → propagation → knowledge sequentially |

#### 0b: Locate paths

```bash
THEBRANA="$HOME/enter_thebrana/thebrana"
DOCS="$THEBRANA/docs"
REFLECTIONS="$THEBRANA/docs/reflections"
KNOWLEDGE="$HOME/enter_thebrana/brana-knowledge/dimensions"
```

Verify `$THEBRANA` exists. If `$KNOWLEDGE` doesn't exist, note it — dimension docs won't be scanned (acceptable; roadmap and reflection docs contain most implementation-specific claims).

#### 0b: Check working state

Run `git status` in thebrana. If there are uncommitted changes, warn the user:

> "thebrana has uncommitted changes. Reconcile will modify system/ files. Commit or stash first?"

Wait for confirmation before proceeding.

#### 0c: Create branch

Before any edits, create a worktree branch:

```bash
BRANCH="chore/reconcile-$(date +%Y%m%d)"
cd $THEBRANA && git worktree add "$THEBRANA/../thebrana-$BRANCH" -b "$BRANCH"
```

If a branch with that name already exists (second reconcile in one day), append a counter: `-2`, `-3`, etc.

### Step 1: Scan specs (the "should" state)

Read the spec surface — everything that describes what the implementation should look like. Spawn parallel scout agents to scan each area efficiently.

**Model routing for scanning agents:** Route agents by area complexity. Areas with many files (skills/, docs/) use `model: "sonnet"`. Areas with few files (config, CLAUDE.md, deploy.sh) use `model: "haiku"`. This optimizes cost without sacrificing quality on complex areas.

**Graph-scoped scanning:** If `docs/spec-graph.json` exists, read it. For each `system/` area being checked, find nodes whose `impl_files` contain files in that area. Only scan those docs — this replaces exhaustive scanning with targeted, graph-informed lookups.

**Fallback (no graph):** If `docs/spec-graph.json` doesn't exist, scan all files in `brana-knowledge/dimensions/`, `docs/reflections/`, and `docs/` root. This ensures new docs are always included without hardcoded number ranges.

| Spec area | Location | What to extract |
|-----------|----------|----------------|
| **Dimension docs** | `brana-knowledge/dimensions/` (all `.md` files) | Tool capabilities, integration patterns, behavioral expectations |
| **Reflection docs** | `docs/reflections/` (all `.md` files) | Architecture decisions, cross-cutting conventions, quality criteria |
| **Roadmap docs** | `docs/` (all `.md` files in root) | Implementation details, WI specs, known errata, self-doc expectations |
| **Feature docs (tech)** | `docs/architecture/features/` (all `.md` files) | Design decisions, code flow, key files, API surface claims |
| **Feature docs (user)** | `docs/guide/features/` (all `.md` files) | Usage instructions, options, examples, troubleshooting steps |
| **CLAUDE.md** | `.claude/CLAUDE.md` | Commands table, ecosystem roles, rules, memory conventions |
| **Project commands** | `.claude/commands/*.md` | Project-level command definitions |

For each area, extract **concrete claims about the implementation** — things like:
- "skill X should exist with description Y"
- "hook Z should call ruflo memory store"
- "rule W should enforce convention V"
- "CLAUDE.md should list agent table with these entries"
- "deploy.sh should handle sql.js dependency"
- "feature doc says key file is at path X with role Y" (from tech doc Key Files tables)
- "user guide says option Z has default W" (from user guide Options tables)

Ignore abstract analysis or research — only extract claims that can be verified against system/ files.

### Step 2: Scan implementation (the "is" state)

Scan `system/` and related implementation files, area by area:

| Area | Files to scan |
|------|--------------|
| **Skills** | `system/skills/*/SKILL.md` — name, description, allowed-tools, body content |
| **Hooks** | `system/hooks/*.sh` — what each hook does, what it calls |
| **Rules** | `system/rules/*.md` — rule names, content, directives |
| **Agents** | `system/agents/*.md` — agent names, models, descriptions |
| **Config** | `system/settings.json` + `~/.claude/settings.json` — hook wiring (split: plugin vs bootstrap), feature flags |
| **CLAUDE.md** | `system/CLAUDE.md` — identity, agents table, principles, portfolio |
| **Deploy** | `deploy.sh` — deployment steps, dependency handling |

For each file, extract the same kind of concrete claims: "skill build-phase exists with description '...'" , "hook session-start.sh calls memory search", etc.

**Implementation awareness notes** (prevents false positives):

- **Hook dual-wiring:** Hooks are split between `system/hooks/hooks.json` (plugin: PreToolUse, SessionStart, SessionEnd, SubagentStart, SubagentStop, TaskCompleted, StopFailure) and `~/.claude/settings.json` (bootstrap: PostToolUse, PostToolUseFailure — CC bug #24529 workaround). When verifying hook claims, check BOTH locations. A PostToolUse hook in settings.json is NOT missing from hooks.json — it's intentionally there.
- **Rust CLI:** The `brana` CLI is a compiled Rust binary at `system/cli/rust/`. Subcommands (backlog, session, handoff, skills, knowledge, transcribe, files, feed, inbox) are Rust code, not shell scripts. Don't flag CLI subcommands as "unimplemented" because there's no matching `.sh` file.
- **Plugin binary sync:** The brana binary is auto-synced to `${CLAUDE_PLUGIN_DATA}/brana` via SessionStart hook. Scripts resolve it via `system/hooks/lib/resolve-brana.sh`.

### Step 3: Diff — identify drift

Compare the "should" claims (Step 1) against the "is" claims (Step 2). Classify each discrepancy:

| Drift type | Description | Example |
|-----------|-------------|---------|
| **Missing** | Spec describes something that doesn't exist | "Spec says agent 'foo' should exist, but agents/ has no foo.md" |
| **Stale** | Implementation contradicts current specs | "Skill description says 'v2 API' but specs now say 'v3 API'" |
| **Incomplete** | Implementation exists but is missing parts the spec requires | "Hook exists but doesn't handle the fallback case spec requires" |
| **Extra** | Implementation has something specs don't mention | Not necessarily wrong — flag for review, don't auto-remove |

**Materiality filter.** Apply the same test proven in `/brana:maintain-specs`: "Would this drift lead to wrong behavior or a wrong implementation decision?" Discard cosmetic differences, minor wording variations, and enhancement suggestions. Only surface drift that matters.

### Step 4: Present drift report [INTERACTIVE — pause here for user approval]

Show the user a structured plan:

```markdown
## Drift Report

**Scanned:** [date]
**Spec surface:** [N] docs (roadmaps + reflections + dimensions)
**Implementation:** [N] files in system/

### Drift by Area

#### Skills ([N] findings)
| # | Type | Finding | Proposed Fix |
|---|------|---------|-------------|
| 1 | Stale | skill X description says "..." but spec now says "..." | Update SKILL.md frontmatter |
| 2 | Missing | spec describes skill Y but it doesn't exist | Create skill Y (note: requires /build-phase) |

#### Hooks ([N] findings)
| # | Type | Finding | Proposed Fix |
|---|------|---------|-------------|

#### Rules ([N] findings)
...

#### Agents ([N] findings)
...

#### Config ([N] findings)
...

#### CLAUDE.md ([N] findings)
...

#### Deploy ([N] findings)
...

### Summary
- **Total drift:** N findings across M areas
- **Auto-fixable:** N (text updates, config changes, metadata corrections)
- **Manual required:** N (new skills to build, architectural changes)

Apply all auto-fixable changes? [y/n]
```

**Wait for user approval.** The report is a proposal, not a commitment.

### Step 5: Apply changes

After approval, apply all auto-fixable changes in the worktree:

1. **Text updates** — Edit SKILL.md frontmatter, rule content, CLAUDE.md sections, hook comments.
2. **Config changes** — Update settings.json entries.
3. **Metadata corrections** — Fix agent descriptions, skill allowed-tools lists.

For each change:
- Use the Edit tool (not Write) to make targeted modifications
- Commit each logical group as a separate commit with conventional commit messages:
  ```
  chore(reconcile): update skill X description to match spec
  chore(reconcile): add missing fallback to session-start hook
  ```

**Do NOT auto-create new skills or make architectural changes.** For "Missing" drift that requires building something new, log it as a backlog item in doc 30 or flag it for `/build-phase`. The reconcile command fixes drift in existing files — it doesn't build new capabilities.

### Step 6: Log to doc 24

Append a reconcile entry to `docs/24-roadmap-corrections.md`:

```markdown
### Reconcile Run — [YYYY-MM-DD]

**Trigger:** [manual | post-maintain-specs | periodic]
**Drift found:** N findings across M areas
**Applied:** N auto-fixes
**Deferred:** N (requires manual build or /build-phase)

| # | Area | Type | Finding | Resolution |
|---|------|------|---------|-----------|
| 1 | Skills | Stale | skill X description outdated | Applied — updated SKILL.md |
| 2 | Hooks | Missing | fallback case not handled | Deferred — logged to doc 30 backlog |
```

Commit the doc 24 update alongside the other changes.

### Step 7: Store in memory

Store the reconcile run in ruflo for future reference:

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "reconcile:brana:$(date +%Y%m%d)" \
  -v "{\"type\": \"reconcile\", \"date\": \"$(date +%Y-%m-%d)\", \"drift_found\": N, \"applied\": N, \"deferred\": N, \"areas\": [\"skills\", \"hooks\", ...]}" \
  --namespace pattern \
  --tags "client:brana,type:reconcile" \
  --upsert
```

If ruflo is unavailable, append to `~/.claude/projects/*/memory/MEMORY.md`.

### Step 8: Report

```markdown
## Reconcile Complete

**Date:** YYYY-MM-DD
**Branch:** chore/reconcile-YYYYMMDD

### Applied
- [N] auto-fixes across [M] areas
- [list each fix, one line]

### Deferred
- [N] items requiring manual build
- [list each, with suggested next action]

### Commits
- `abc1234` chore(reconcile): [description]
- `def5678` chore(reconcile): [description]

### Merge & Deploy
To merge:
```
cd ~/enter_thebrana/thebrana
git merge --no-ff chore/reconcile-YYYYMMDD
git worktree remove ../thebrana-chore/reconcile-YYYYMMDD
git branch -d chore/reconcile-YYYYMMDD
```

To deploy:
```
cd ~/enter_thebrana/thebrana && ./deploy.sh
```

### Follow-up
- If deferred items exist: consider `/build-phase` or add to doc 30 backlog
```

**Do not auto-merge or auto-deploy.** Present the commands and let the user decide.

---

## Security Domain (`--scope security`)

6 checks absorbed from `/brana:audit`. Fast, zero dependencies.

### SEC-1: Secrets in config files

Scan CLAUDE.md, rules/, skill frontmatter, hook scripts, agent definitions for leaked secrets.

**Patterns** (14 regexes):
```
(sk|pk|api|key|token|secret|password|credential|auth)[-_]?[A-Za-z0-9]{16,}
(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}
AKIA[0-9A-Z]{16}
(xox[bpas]-[A-Za-z0-9-]{10,})
(sk-[A-Za-z0-9]{20,})
Bearer\s+[A-Za-z0-9\-._~+/]+=*
Basic\s+[A-Za-z0-9+/]+=+
-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----
(postgres|mysql|mongodb)://[^\s]+:[^\s]+@
(ANTHROPIC|OPENAI|STRIPE|GITHUB|AWS)_[A-Z_]*KEY[=:]\s*\S+
```

**Files:** `CLAUDE.md`, `.claude/CLAUDE.md`, `~/.claude/CLAUDE.md` (if --global), `~/.claude/rules/*.md`, `system/skills/*/SKILL.md`, `system/hooks/*.sh`, `system/agents/*.md`.

Report: file, line number, pattern matched. Redact values (first 4 chars + `***`).

### SEC-2: Hook permission escalation

```bash
grep -rn "chmod\|chown\|setfacl" system/hooks/*.sh
```

Flag: `chmod +x` outside `system/hooks/`, `chmod 777` anywhere, `chown` to root.

### SEC-3: MCP server count (token tax)

Count MCP servers in settings.json. Each adds 4-17K tokens/session. Flag if >5 servers active.

### SEC-4: Dangerous settings

Check `settings.json` for: `bypassPermissions: true`, `dangerouslyDisableSandbox: true`, `allowedTools: ["*"]`. Flag each with severity.

### SEC-5: Unencrypted credential files

```bash
find . -name ".env" -o -name "credentials.json" -o -name "*.pem" -o -name "*.key" 2>/dev/null
```

Flag any found outside `.gitignore`.

### SEC-6: Acquired skill safety

Scan `system/skills/` for skills not in the core set (compare against git-tracked skill list). For acquired skills, check: allowed-tools list for dangerous tools (Bash with no constraints), external URLs in skill body, hook registration.

### SEC-7: ADR-033 violations in `~/.claude.json`

**Automated:** `config-drift.sh` already checks this at every session start and surfaces violations in `DRIFT_CONTEXT`. If the session-start hook reported `[ADR-033]` warnings, they will appear here.

**Manual sweep:** If you want to inspect directly:
```bash
jq -r '
  (.mcpServers // {} | to_entries[] | select(.value.command // "" | test("npx|uvx")) | "top: \(.key): \(.value.command)"),
  (.projects // {} | to_entries[] | .key as $p | (.value.mcpServers // {}) | to_entries[] | select(.value.command // "" | test("npx|uvx")) | "project \($p): \(.key): \(.value.command)")
' ~/.claude.json
```

Fix: pin each flagged server to its installed binary path (see ADR-033).

### SEC-REPORT

Present findings grouped by severity (CRITICAL / WARNING / INFO). No auto-fix — security issues require human judgment.

---

## Propagation Domain (`--scope propagation`)

Cascade pending errata through the spec layer hierarchy. Invokes existing commands as building blocks.

### PROP-1: Check pending errata

Read `docs/24-roadmap-corrections.md`. Count entries with `status: pending`. If zero, skip propagation.

### PROP-2: Apply errata cascade

Invoke the apply-errata command flow:

```
Skill(skill="brana:apply-errata")
```

This cascades: dimension → reflection → roadmap, with gate checks between layers.

### PROP-3: Re-evaluate reflections

Invoke re-evaluate-reflections:

```
Skill(skill="brana:re-evaluate-reflections")
```

Cross-checks reflection docs against dimension docs for gaps, contradictions, missed findings.

### PROP-4: Spec-graph consistency

If `docs/spec-graph.json` exists:
1. Run `brana graph build` to regenerate
2. Compare output with existing graph
3. Flag new orphan nodes, broken edges, missing docs

### PROP-REPORT

Summary: errata applied, reflections updated, graph changes. Commit all propagation changes as one logical group.

---

## Knowledge Domain (`--scope knowledge`)

DECAY — weekly scan for staleness, noise, and bloat in the knowledge system (ADR-027, ADR-030).

**Step registry:** ORIENT, ROUTE, KNOW-1, KNOW-2, KNOW-3, KNOW-REPORT

### KNOW-1: Stale dimensions [INTERACTIVE if stale docs found]

Identify dimension docs that are old AND unused.

1. List all `.md` files in `$KNOWLEDGE` (`brana-knowledge/dimensions/`).
2. For each file, check frontmatter for `last_verified:` date. If absent, fall back to last git commit date:
   ```bash
   git -C "$KNOWLEDGE" log -1 --format=%ci -- "$file"
   ```
3. If age > 90 days, check ruflo for recent search hits:
   ```
   mcp__ruflo__memory_search(query: "{doc title from frontmatter or filename}", namespace: "knowledge", limit: 1)
   ```
   If the search returns a result with a recent timestamp (< 90 days), the doc is still in use — skip it.
4. Collect all docs that are > 90 days old AND have no recent ruflo hits into a `stale_dims` list.
5. If `stale_dims` is non-empty, present via AskUserQuestion (multiSelect):
   ```
   "N stale dimensions found (>90 days, no recent search hits).
   Select which to mark stale (adds `stale: true` to frontmatter) or dismiss:"
   ```
   Options: one per stale doc (filename + age), plus "Skip — take no action".
6. For each selected doc, add `stale: true` to its YAML frontmatter (or report only if the doc lives in brana-knowledge and the user prefers manual edits there).

### KNOW-2: Event log bloat [INTERACTIVE if >20 old entries]

Trim old event log entries with a digest summary.

1. Resolve the event log path:
   ```bash
   PROJECT_HASH=$(echo -n "$THEBRANA" | md5sum | cut -d' ' -f1)
   LOG="$HOME/.claude/projects/$PROJECT_HASH/memory/event-log.md"
   ```
   If the file doesn't exist, check `$HOME/.claude/projects/*/memory/event-log.md` via glob. If no log exists, skip KNOW-2.
2. Parse entries. Each entry starts with a date line (e.g., `## YYYY-MM-DD` or `- YYYY-MM-DD:`). Count entries older than 90 days.
3. If > 20 old entries:
   a. Build a digest: group old entries by theme/tag, produce a summary line per theme with count.
   b. Present via AskUserQuestion:
      ```
      "Event log has M entries older than 90 days. Archive to event-log-archive-YYYY.md and keep inline digest?"
      ```
      Options: "Archive + digest", "Skip".
   c. On approval: write old entries to `event-log-archive-{YYYY}.md` (same directory), replace them in the original log with the digest block:
      ```markdown
      ## Archived — YYYY
      > N entries archived to event-log-archive-YYYY.md
      > Themes: theme1 (X), theme2 (Y), ...
      ```
4. If <= 20 old entries, note count in report and move on.

### KNOW-3: Ruflo noise [INTERACTIVE if hard-decay candidates found]

Identify low-value pattern entries for soft or hard decay.

1. Search ruflo for pattern entries:
   ```
   mcp__ruflo__memory_search(query: "*", namespace: "pattern", limit: 50)
   ```
2. For each returned entry, extract `confidence` (from metadata/tags) and age (from `created_at` or date tags). Classify:
   - **Soft decay** (90–180 days old): note in report, no action taken. These are aging but not yet candidates for removal.
   - **Hard decay** (> 180 days old AND confidence < 0.3): candidate for deletion.
3. If hard-decay candidates exist, present via AskUserQuestion (multiSelect):
   ```
   "P ruflo pattern entries are >180 days old with low confidence (<0.3).
   Select entries to delete, or dismiss:"
   ```
   Options: one per candidate (key + age + confidence), plus "Skip — take no action".
4. For each selected entry, delete:
   ```
   mcp__ruflo__memory_delete(key: "{entry_key}", namespace: "pattern")
   ```
   If `memory_delete` is unavailable or fails, log the entry key for manual removal.

### KNOW-REPORT

Present a summary:

```markdown
## Knowledge Domain — DECAY Report

**Date:** YYYY-MM-DD

| Check | Result |
|-------|--------|
| KNOW-1: Stale dimensions | N stale found, M marked |
| KNOW-2: Event log bloat | N old entries, M archived |
| KNOW-3: Ruflo noise | N soft decay, P hard decay deleted |

### Actions Taken
- [list each action, one line]

### No Action Needed
- [list checks that passed clean]
```

Store the report in ruflo (if available):
```
mcp__ruflo__memory_store(key: "decay:brana:{YYYYMMDD}", value: "{JSON summary}", namespace: "pattern", tags: "client:brana,type:decay")
```
If ruflo is unavailable, append summary to `~/.claude/projects/*/memory/MEMORY.md`.

---

## Rules

- **Read before writing.** Always read a file before editing it. Never assume file contents from spec descriptions alone.
- **Materiality filter is strict.** Only surface drift that would cause wrong behavior or wrong implementation decisions. Cosmetic differences are not drift.
- **Never auto-create new capabilities.** Reconcile fixes existing files. New skills, hooks, or agents require `/build-phase` or explicit user instruction.
- **Never auto-delete.** "Extra" items that specs don't mention get flagged for review, not removed. The user decides.
- **One branch, atomic commits.** All reconcile work happens on a single worktree branch with one commit per logical fix.
- **Plan then apply.** Always show the full drift report and get approval before making any changes.
- **Ask for clarification whenever you need it.** If a spec claim is ambiguous, a drift finding is borderline, or the right fix is unclear — ask. Don't guess.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes. **Auto-advance through all non-interactive steps** (ORIENT → SCAN-SPECS → SCAN-IMPL → DIFF without pause). Only pause at steps marked [INTERACTIVE] or final REPORT.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:reconcile — {STEP}`
2. The `in_progress` task is your current step — resume from there
3. Check the worktree branch for commits already applied

---

## Field Notes

### 2026-04-09: Verify before wiring — check call chains first
When DIFF flags a script as "exists but not in hooks.json", grep sibling hook scripts before adding a hooks.json entry: `grep -r "script-name.sh" system/hooks/`. A script absent from hooks.json may already be called internally (e.g., config-drift.sh is called by session-start.sh line 157). Absence from hooks.json is necessary-but-not-sufficient evidence of a real gap.
Source: /brana:reconcile --scope consistency, 2026-04-09

### 2026-04-09: Exclude docs/archive from scan scope
Scan agents must exclude `docs/archive/**` and `docs/reflections/archive/**`. Stale archived content produces false positives — the archive copy of doc 14 said "13 rules" while the live doc already had "14 rules". Always include the full file path in findings so archive hits are obvious before fixes are applied.
Source: /brana:reconcile --scope consistency, 2026-04-09
