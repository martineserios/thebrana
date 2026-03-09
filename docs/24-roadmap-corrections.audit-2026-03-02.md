# Audit Report — 2026-03-02

First run of `/brana:memory review --audit` (t-039). Audited doc 14 (Architecture) and both CLAUDE.md files.

## Contradictions Found: 10 (fixed)

### C-001: Skill count stale — HIGH
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), line ~155
- **Claim:** "34 deployed skills"
- **Reality:** 35 skills (verified via `ls system/skills/ | wc -l`)
- **Fix applied:** updated to 35

### C-002: Dimension doc count stale (doc 14) — HIGH
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), line ~198
- **Claim:** "27 docs"
- **Reality:** 29 dimension docs (26 numbered + 3 topic docs; verified via `ls dimensions/*.md`)
- **Fix applied:** updated to 29

### C-003: Dimension doc count stale (CLAUDE.md) — HIGH
- **Location:** `.claude/CLAUDE.md`, line ~119
- **Claim:** "315 sections from 26 dimension docs"
- **Reality:** 29 dimension docs
- **Fix applied:** updated to 29; added non-numbered docs to doc architecture tree

### C-004: Hook types undercounted — MEDIUM
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), line ~225
- **Claim:** "Four hook types" (PreToolUse, SessionStart, SessionEnd, PostToolUse)
- **Reality:** Five hook types (PostToolUseFailure missing)
- **Fix applied:** updated to 5, added PostToolUseFailure

### C-005: skill-catalog.yaml ghost reference — MEDIUM
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), line ~48
- **Claim:** `skill-catalog.yaml` in directory tree
- **Reality:** file is `skill-catalog.md`
- **Fix applied:** corrected extension

### C-006: ~/.swarm/ ghost entries — MEDIUM
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), lines ~87-88
- **Claim:** `trajectories/` and `config.yaml` exist under `~/.swarm/`
- **Reality:** only `memory.db` and `hnsw.index` exist
- **Fix applied:** removed ghost entries, added hnsw.index

### C-007: Skills tree truncated with bad indentation — MEDIUM
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), lines ~43-47
- **Claim:** 4 skills shown with broken nesting
- **Fix applied:** fixed indentation, added "+30 more" ellipsis, total count annotation

### C-008: Scripts tree incomplete — LOW
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), lines ~60-64
- **Claim:** 4 scripts
- **Reality:** 6 scripts (missing index-knowledge.sh, generate-index.sh)
- **Fix applied:** added missing scripts

### C-009: Commands tree incomplete — LOW
- **Location:** [doc 14](reflections/14-mastermind-architecture.md), lines ~65-67
- **Claim:** 2 commands
- **Reality:** 7 commands
- **Fix applied:** added missing commands

### C-010: Reflection DAG mislabel — MEDIUM
- **Location:** `.claude/CLAUDE.md`, line ~40
- **Claim:** R5(29 Transfer)
- **Reality:** doc 29 is "Venture Management Reflection", not "Transfer"
- **Fix applied:** corrected to R5(29 Venture)

## Verified Assertions: 5

- Agent count: 10 (consistent across doc 14 and CLAUDE.md)
- Hook system design: 3 learning + 1 enforcement + 1 error recovery = 5 types
- Three-layer architecture: Identity / Intelligence / Context
- Workspace architecture: thebrana (unified) + brana-knowledge (KB)
- System deploy pipeline: system/ → deploy.sh → ~/.claude/

## Not Fixed (deferred)

- **Context-budget rule text in loaded CLAUDE.md** appears as 3-tier (70/85%) due to system context truncation. Actual source and deployed file both have 4-tier (55/70/85%). No drift — false positive.
- **ADR-002 numbering collision** (two different ADR-002 files noted in doc 14). Deferred to next ADR cleanup.
- **Embedded CLAUDE.md example** in doc 14 is intentionally illustrative, not a live mirror. Marked as acceptable.
