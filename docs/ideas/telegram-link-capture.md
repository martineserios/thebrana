---
title: Telegram Link Capture
status: draft
created: 2026-07-22
---
# Telegram Link Capture

> Brainstormed 2026-07-22. Scope expanded mid-brainstorm to a full Cloudflare
> migration, went through a 3-worker challenger review, then was deliberately
> scaled back down to the minimal option once the proportionality question was
> asked directly. See "Considered and rejected" for the larger designs and why.

## Problem

Links found on WhatsApp are captured manually today: copy the link, open a terminal, paste it, and run `/brana:log` (or `/brana:log bulk` for a dump) to get it into brana's knowledge/event-log pipeline. Every link costs a context switch to a terminal session, and the whole flow requires being at a computer.

## Solution

Add URL-detection directly into `personal/bot.py`'s existing message handler — still polling, still on `oracle-hub`, no new platform, no new credential, no touch to journal capture or morning prompts.

```
[Phone: WhatsApp] --Share--> [TheBranaBot, Telegram — unchanged, still polling]
        ▼
[oracle-hub — bot.py]
        │ regex: URL in message?
        ├─ yes ──▶ append to link-queue.jsonl (atomic write: tmp + rename)
        └─ always ▶ journal/YYYY-MM-DD.md   (unchanged)

[oracle-hub — new cron, ~15-30 min, pure script, no LLM]
        │ for each new queue entry:
        │   1. normalize URL, check against personal repo's OWN
        │      tasks.json (already local — no separate dedup store needed)
        │   2. skip if duplicate, else:
        │        brana backlog add --subject "[link] {url}"
        │          --stream research --tags "link,auto-captured"
        │        append formatted line → event-log.md
        │   3. mark queue entry processed
        │   4. git commit + push (reuses sync-state.sh's auto-commit pattern)

[NEW: laptop-local systemd timer, every 15-30 min]
        │ git -C ~/enter_thebrana/personal pull --ff-only
        │ (confirmed: no such job exists today — see Research findings)
        ▼
Tasks + event-log entries already there, locally, next time you look.

[NEW: laptop-local timer, every few hours — closes the KNOWLEDGE gap]
        │ brana backlog query --stream research --tag link --status pending
        │ for each (capped batch, 3-5 per run):
        │   claude -p "/brana:research {url} --depth quick"
        ▼
[/brana:research: fetch → read → cross-reference → synthesize →
 persists findings to a dimension doc / ruflo `knowledge` namespace →
 marks the task done]
        ▼
Knowledge is actually extracted and persisted. Loop fully closed.

[Anti-staleness nudge — same oracle-hub cron]
        │ queue count/age over threshold?
        └─ yes → bot proactively messages you:
                  "3 links pending, 6d old" (reuses reminder-dispatch pattern)
```

### Why this and not the serverless version

Three tiers were considered, in increasing scope:

| Option | Touches | Effort | Risk | Solves the ask? |
|---|---|---|---|---|
| **A — this plan** | `bot.py` handler + a new oracle-hub cron | ~half a day | Near zero — additive, journal/prompts untouched | Yes, completely |
| B — scoped serverless | New dedicated bot + Cloudflare Worker, just for links | ~1 week | Low — zero blast radius on the existing bot | Yes, plus removes link-capture from a VM that's already OOM-reclaimed once |
| C — full migration | Journal + prompts + links, all moved to Cloudflare/GitHub API | Multi-week | Real — to daily-used journal data | Yes, but bundled with a second, much bigger Oracle→serverless project that was never actually asked for |

C was fully designed and passed through a 3-worker adversarial challenger review (see "Considered and rejected" below for what that review found) before the proportionality question was asked directly and the answer came back: build A. Two independent signals had already pointed this direction — the challenger's critical-lens reviewer raised the same "cheaper stopgap" question unprompted — before the direct ask confirmed it.

### A bonus of choosing the minimal option

Two of the three challenger-review CRITICAL findings against the Cloudflare design (see below) don't apply to this plan at all, not because they were fixed but because they were *artifacts of that architecture*:
- The dedup-fork bug existed because Cloudflare Workers KV was a separate store from `tasks.json`. Here, the cron already runs on the same box with the same local `tasks.json` — one dedup source, no fork possible.
- The owner-auth gap existed because moving to always-live webhook mode meant the existing `OWNER_CHAT_ID` gate had to be manually re-implemented and could be missed. Here, `bot.py` keeps polling exactly as it does today — whatever auth gate already protects it keeps protecting it, unchanged.

The one finding that still fully applies: **queue/processing going stale** (see Risks) — addressed by the anti-staleness nudge, unchanged from the original design.

## Research findings

- `/brana:log bulk` (`system/skills/log/SKILL.md`) already does dedup + URL detection + research-task creation — replicated deterministically (no LLM) here for the unattended path, same as in the original design.
- `personal/bot.py` (289 lines, verified) is a polling "dumb pipe" today — Telegram in, journal file out, no URL detection. `test_bot.py` exists but has only 2 near-tautological tests — real test coverage needs writing, not assuming.
- **Confirmed: no recurring local "pull the personal repo" job exists today.** `sync-state.sh pull` is a one-time cache↔repo restore for brana's own operational state, unrelated to a generic git fetch. None of the 24 active `brana-sched-*` laptop timers touch the `personal` repo. A new laptop-local timer is required regardless of which architecture tier is chosen.
- `/brana:research` is Sonnet-model, high-effort, multi-phase (fetch, cross-reference, synthesize) — the actual knowledge-extraction step, distinct from capture, and not something to run unattended without a cap (see Solution diagram: `--depth quick`, 3-5 per run).
- Personal WhatsApp automation has no simple bot API (Business API needs Meta provisioning) — irrelevant to this plan either way, since capture still goes through Telegram via Share/Forward.

## Risks

- **Queue goes stale — confirmed top risk (pre-mortem, still applies).** Same failure pattern already seen elsewhere in this system (dead `close-extraction` cron, unprocessed close-queue entries). **Mitigation:** anti-staleness nudge (queue count/age threshold → proactive bot message).
- Bot regression risk — touching `bot.py` risks breaking journal capture. **Mitigation:** URL-detection is strictly additive (existing journal-write path unchanged), atomic queue-file writes (tmp + rename, same pattern as brana's own state files), and real tests written first, not assumed from `test_bot.py`'s current thin coverage.
- Research-extraction quota cost — capped via `--depth quick` + small batch size (see Solution).

## Second-order effects

- Auto-detect + async capture → capture friction drops to ~zero → link volume may rise → the unattended task-creation step means backlog research-task volume could grow — worth a periodic prune/review pass on `stream: research` tasks.
- This plan doesn't touch Oracle's role in the system. The bigger "should Oracle be replaced by serverless" question (raised, designed, and shelved this session — see below) stays open and separate, to be revisited on its own merits if the VM's reliability actually becomes a recurring problem, not bundled into a link-capture feature.

## Considered and rejected (kept for the reasoning trail)

**Full serverless migration (Option C above)** — designed in full: Cloudflare Worker webhook replacing `bot.py`'s polling, journal writes via GitHub Contents API, morning prompts via Cloudflare Cron Triggers, Workers KV for link dedup, an oracle-hub processing cron, the same laptop-pull-timer and `/brana:research` extraction steps as this plan. Went through a 3-worker adversarial challenger review (convergent/systems/critical lenses):
- **HIGH confidence (3/3 workers):** a write-order bug — KV marked a link "seen" before its GitHub commit was confirmed, risking silent permanent data loss on any commit failure.
- **HIGH confidence (2/3 workers):** the Workers-KV dedup store was disjoint from `tasks.json`'s existing dedup — unseeded at cutover, every already-tracked link would read as new.
- **Single-source, severe:** the parity-test plan covered ~4 of `bot.py`'s 9 real behaviors, missing the `OWNER_CHAT_ID` owner-auth gate — a real security gap once the bot is always-live.
- Also flagged: 3 Oracle-only scheduler jobs sharing the same bot token, cutover-ordering risk (`setWebhook` vs. stopping polling), new credential rotation plan, no rollback runbook, timezone mismatch in the parallel-run test plan.

All of this is real, useful design work — it's just scoped to a different, bigger project (replacing Oracle with serverless infrastructure) than what was actually asked (stop copy-pasting links). Revisit as its own idea if/when Oracle's reliability becomes an actual recurring problem — the earlier cloud audit this session already has candidate workloads (t-1786 feed pipeline, t-581 transcribe) pointing the opposite direction (moving *more* onto Oracle), which would need reconciling with any future Oracle-exit plan.

**Separate dedicated bot + Cloudflare Worker just for links (Option B)** — a legitimate middle ground (zero blast radius on the existing bot, gets OOM-reclaim resilience for this feature specifically) but not chosen; Option A achieves the same practical outcome without any new platform, at lower effort.

**Fully headless-Claude automation (`claude -p` on oracle-hub running `/brana:log`'s full logic)** — rejected early: the only judgment `/brana:log` does (fuzzy dedup, confirm-before-task-creation) becomes deterministic rules for an unattended path anyway, so no LLM is needed for capture at all.

## Next steps

1. Write real tests (new coverage, not an extension of `test_bot.py`'s current 2 tests) for: URL detection, queue-append (atomic write), dedup-against-tasks.json logic — test-first
2. Extend `bot.py`'s message handler: URL regex → atomic append to `link-queue.jsonl`, additive to existing journal write
3. Build the oracle-hub cron: dedup vs. local `tasks.json` → `brana backlog add` + `event-log.md` append → mark processed → commit/push
4. Add the anti-staleness nudge (queue count/age check → proactive Telegram message)
5. Add the laptop-local systemd timer: `git -C ~/enter_thebrana/personal pull --ff-only`, every 15-30 min
6. Add the laptop-local `/brana:research` extraction timer: capped batch (3-5), `--depth quick`, every few hours
7. Update `personal/README.md` if the bot's described behavior changes materially
