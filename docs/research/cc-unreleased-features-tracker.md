# CC Unreleased Features Tracker

> Quarterly review cadence — check during `/brana:review monthly`.
> Last reviewed: 2026-04-10 (initial).

Feature flags compiled to `false` in CC v2.1.89 (the published build at leak time).
Source quality: `[VERIFIED]` = primary source quoting leaked code; `[REPORTED]` = secondary reporting; `[CONCEPTUAL]` = community reimplementation.

---

## Legend

| Column | Meaning |
|--------|---------|
| **What it does** | Current understanding (with source quality) |
| **Ship signal** | Known shipping timeline or absence |
| **Brana equivalent** | Existing or planned brana capability |
| **Decision** | MATCH / CEDE / MONITOR / WAIT |

---

## Memory & Knowledge

### Kairos — Always-on background memory daemon

| Field | Value |
|-------|-------|
| **What it does** | "Always-on background memory daemon for Claude Code. Keeps context coherent between sessions. Runs in background, processes tasks, integrates memories when user is not actively using CC." **[REPORTED — DeepLearning.ai, Roger Wong]** |
| **Flag** | Compiled to `false` in v2.1.89 |
| **Ship signal** | None. No Anthropic announcement as of 2026-04-10. |
| **Brana equivalent** | `lint-heal.sh` + session-start gate + scheduler (t-1075, shipped 2026-04-10). Covers dedup, contradiction detection, reference surfacing. |
| **Decision** | **MATCH** — brana shipped its equivalent before CC flipped the flag. Moat: cross-project memory + ruflo semantic search. When CC ships Kairos, align brana session state with CC's 8-section schema (t-1074). |

### autoDream — Memory consolidation inside Kairos

| Field | Value |
|-------|-------|
| **What it does** | "Merges duplicate memories, eliminates contradictions, resolves speculations, prunes memory to make stored data more suitable for action." Logic layer *inside* Kairos. **[REPORTED]** |
| **Flag** | Same flag as Kairos (part of the same daemon) |
| **Ship signal** | Ships with Kairos. |
| **Brana equivalent** | `lint-heal.sh` LINT (grep contradiction detection) + HEAL (merge + archive). `/brana:memory audit` surfaces report. (t-1075, shipped 2026-04-10) |
| **Decision** | **MATCH** — already shipped at L2 (deterministic). L3 (LLM-adjudicated) planned as future enhancement. |

---

## Agent Orchestration

### Coordinator Mode — Parallel agents in separate worktrees

| Field | Value |
|-------|-------|
| **What it does** | "Spawns parallel agents in separate git worktrees." Enables concurrent task execution with isolation. **[REPORTED]** |
| **Flag** | `false` in v2.1.89 |
| **Ship signal** | None. |
| **Brana equivalent** | `git worktree` + Agent tool with `isolation: "worktree"`. `/brana:backlog execute` routes tasks to subagents. Manual coordination, not a daemon. |
| **Decision** | **MATCH** — brana has the primitives. Gap: no auto-spawning based on task dependency graph. If CC ships Coordinator Mode, evaluate whether brana should wire `backlog execute` to the same pattern. |

### UltraPlan — 30-min Opus execution windows

| Field | Value |
|-------|-------|
| **What it does** | "Subagent that runs 30-min execution windows on Opus-class models. Cloud-offloaded resource-intensive work." **[REPORTED]** |
| **Flag** | `false` in v2.1.89 |
| **Ship signal** | None. Would require Anthropic to expose long-run async API. |
| **Brana equivalent** | None. Subagents via Agent tool have no time-window or resource-class concept. |
| **Decision** | **MONITOR** — not a brana domain decision until CC ships. If UltraPlan ships, evaluate whether `/brana:build` long-running tasks should route there. |

---

## Runtime & Interface

### Daemon Mode — Background sessions via tmux

| Field | Value |
|-------|-------|
| **What it does** | "Runs Claude Code sessions in the background via tmux. User can detach and reattach." **[REPORTED]** |
| **Flag** | `false` in v2.1.89 |
| **Ship signal** | None. |
| **Brana equivalent** | None directly. `brana:scheduler` + cron scripts run scheduled jobs without user presence, but don't expose a reattachable session. |
| **Decision** | **MONITOR** — niche use case for brana's current workflow. Revisit if CC ships and user demand appears. |

### Remote Bridge — Phone control for running sessions

| Field | Value |
|-------|-------|
| **What it does** | "Phone control for running CC sessions." **[REPORTED]** |
| **Flag** | `false` in v2.1.89 |
| **Ship signal** | None. |
| **Brana equivalent** | None. Telegram bot exists for personal project but not wired to brana. |
| **Decision** | **CEDE** — not brana's domain. If CC ships it, use it directly. |

### Voice Mode — STT/TTS interface

| Field | Value |
|-------|-------|
| **What it does** | "Speech-to-text / text-to-speech interface for CC." **[REPORTED]** |
| **Flag** | `false` in v2.1.89 |
| **Ship signal** | None. |
| **Brana equivalent** | `brana transcribe` (whisper.cpp, one-shot audio→text). Not interactive STT. |
| **Decision** | **CEDE** — if CC ships Voice Mode, brana wraps it for intake (`inbox/` voice notes → `brana transcribe` remains as pre-CC fallback). No brana-native STT roadmap. |

---

## Persona & Engagement

### Buddy — Tamagotchi-style persona

| Field | Value |
|-------|-------|
| **What it does** | "Tamagotchi-style pet behavior, `/buddy` slash command, user engagement commentary." **[REPORTED — Roger Wong]** |
| **Flag** | `false` in v2.1.89 |
| **Ship signal** | None. Experimental UX feature. |
| **Brana equivalent** | None. Brana's register is professional/operational, not gamified. |
| **Decision** | **CEDE** — not brana's design language. If CC ships `/buddy`, it's opt-in from user. No brana action. |

---

## Internal Models

### Capybara — Internal Claude 4.6 variant

| Field | Value |
|-------|-------|
| **What it does** | Internal variant of Claude 4.6. Likely a fine-tune or capability experiment. **[REPORTED]** |
| **Ship signal** | Unknown. May surface as a public model name or remain internal. |
| **Brana equivalent** | N/A — model routing handled by per-agent `model:` frontmatter. |
| **Decision** | **MONITOR** — if Capybara ships as a public model ID, evaluate whether any brana agent should route to it (challenger, debrief-analyst). |

### Numbat — Unreleased model

| Field | Value |
|-------|-------|
| **What it does** | Unreleased Anthropic model. No details available. **[REPORTED]** |
| **Ship signal** | Unknown. |
| **Brana equivalent** | N/A |
| **Decision** | **MONITOR** — same as Capybara. Evaluate on public release. |

---

## Compaction Modes (unreleased)

These are feature flags inside the context compaction system, not full features. Lower stakes than the above.

| Feature | Description | Decision |
|---------|-------------|----------|
| `HISTORY_SNIP` | Content-clear old tool results | MONITOR — CC may expose as setting |
| `CACHED_MICROCOMPACT` | Cache-edit microcompaction | MONITOR |
| `CONTEXT_COLLAPSE` | Model-side compression, suppresses proactive autocompact | MONITOR |
| `REACTIVE_COMPACT` | Compact only on 413 errors | MONITOR |

Source: **[VERIFIED — Zain Hasan]** — these were in the published build but disabled.

---

## Decision Summary

| Feature | Decision | Brana Status |
|---------|----------|-------------|
| Kairos | MATCH | Shipped (lint-heal, t-1075) |
| autoDream | MATCH | Shipped (lint-heal L2, t-1075) |
| Coordinator Mode | MATCH | Primitives exist; no auto-coordinator |
| UltraPlan | MONITOR | — |
| Daemon Mode | MONITOR | — |
| Remote Bridge | CEDE | — |
| Voice Mode | CEDE | brana transcribe as pre-CC fallback |
| Buddy | CEDE | — |
| Capybara | MONITOR | Model ID watch |
| Numbat | MONITOR | Model ID watch |

---

## Review Log

| Date | Reviewer | Changes |
|------|----------|---------|
| 2026-04-10 | Martin + Claude | Initial doc. Kairos/autoDream equivalent shipped same day (t-1075). |

---

## Sources

- [CC Source Leak — DeepLearning.ai](https://www.deeplearning.ai/the-batch/claude-codes-source-code-leaked-exposing-potential-future-features-kairos-and-autodream/) — primary for feature list **[REPORTED]**
- [Inside Claude Code Architecture — Zain Hasan](https://zainhas.github.io/blog/2026/inside-claude-code-architecture/) — compaction flags **[VERIFIED]**
- [Claude Code Unpacked — Roger Wong](https://rogerwong.me/2026/04/claude-code-source-leak) — Buddy detail **[REPORTED]**
- `docs/research/2026-04-08-claude-code-leak-analysis.md` — brana's consolidated analysis (§1.11, §5 Opp 7, §6)
