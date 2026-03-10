# ADR-013: Event Log — Single-File Capture Layer

**Date:** 2026-03-07
**Status:** accepted
**Task:** t-208

## Context

Information arrives constantly — WhatsApp links, phone call outcomes, meeting notes, tool discoveries, ideas. Currently this information either stays in WhatsApp (lost), gets manually triaged into tasks.json (slow), or goes directly to tasks (but not everything is actionable).

There's no **capture layer** between "something happened" and "here's a task to track." Events are raw material. Tasks are commitments. The system needs a place for raw material.

A challenger review (Opus adversarial) identified key risks in the initial three-scope, CWD-routed design:
- Overlap with MEMORY.md (learnings), /debrief (errata), /brana:pipeline (leads)
- CWD routing ambiguity (logging cross-client events from wrong directory)
- Entry type auto-detection is fragile keyword matching
- 41st skill — sprawl concern

## Decision

Build `/brana:log` as a single-file, tag-based event log with bulk paste support.

Key design choices:
- **Single global file** (`~/.claude/memory/event-log.md`) — one place to search, one place to read. Tags provide scope routing instead of per-project files.
- **Tags, not CWD** — `#somos`, `#brana`, `#personal` etc. No auto-detection, no ambiguity. Works from any directory.
- **No entry type auto-detection** — inline `#tags` replace fragile keyword matching. User applies `#call`, `#meeting`, `#idea` if they want.
- **URL task creation confirms** — shows "Found N new URLs. Create research tasks?" instead of silently creating. Avoids noise from reference links.
- **Append-only, chronological** — new entries go at the bottom of the current day's section. Cleaner git diffs than reverse-chronological.
- **Archival at 500 lines** — entries older than 90 days move to `event-log-archive-YYYY.md`.

What `/brana:log` is NOT:
- Not a replacement for `/brana:backlog add` (tasks are commitments, log entries are observations)
- Not a replacement for MEMORY.md (memory stores patterns, log stores events)
- Not a replacement for `/brana:pipeline` (pipeline tracks deals, log captures first contact)
- Not a calendar, reminder system, or analytics tool

The log is an **inbox** — fast capture first, classify later. Some entries get promoted to tasks via `/brana:log review` (v1.1). Most stay as searchable context.

## Consequences

- **Easier:** capturing information in the moment. One command, any context.
- **Easier:** WhatsApp dump triage. Bulk mode parses, deduplicates, confirms.
- **Harder:** nothing significant — complexity is contained in one SKILL.md file.
- **Risk:** log becomes unread graveyard. Mitigated by `/brana:log review` (v1.1) and the URL-to-task promotion flow.
