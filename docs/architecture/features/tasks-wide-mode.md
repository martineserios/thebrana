# Feature: Wide Display Mode for /brana:tasks

**Date:** 2026-03-03
**Status:** shipped

## Goal

Add `--wide` flag to `/brana:tasks` view commands that renders tasks as tabular rows with all metadata columns visible on one line — like `kubectl get pods -o wide`.

## Audience

Solo developer who wants full info density on wide terminals (120+ cols).

## Constraints

- Instruction-based skill (SKILL.md) — no code logic, just rendering instructions
- Must compose with existing themes (classic/emoji/minimal) — wide is orthogonal to theme
- Must not break default (non-wide) behavior
- Subject column gets truncated with `…` if it exceeds available space
- Null fields render as `—` (em-dash), never blank

## Scope (v1)

- `--wide` flag on: `status`, `portfolio`, `roadmap`, `next`, `tags --filter/--any`
- Fixed column order: `icon id subject status tags pri eff stream blocked_by started completed`
- Phases/milestones render as header rows (progress summary, no per-column detail)
- Tags show first 3, then `+N` if more
- Theme icons apply to the `icon` column (same icons as compact mode)
- Wide-mode template defined once in Display Themes section, referenced by name

## Deferred

- `--sort-by` column sorting
- `--columns` custom column selection
- `--no-header` for scripting
- Color/ANSI support

## Design

Single-file change to `system/skills/tasks/SKILL.md`. Three insertion points:
1. Display Themes section — wide-mode template definition with examples for all 3 themes
2. Commands list — `--wide` flag on supported commands
3. Each view command section — "If `--wide`, render using wide-mode template" clause

No ADR needed (cosmetic, single file, same rationale as tasks-theme-system).

## Learnings

- Hooks can revert individual file edits between tool calls. For multi-edit changes to a single file, apply all edits atomically via a script, not sequential Edit tool calls.
- The "render using X template" anchor pattern from the theme feature extends naturally to wide mode — each command section gets a conditional clause without restructuring.
- Wide mode completes the "compact/verbose density toggle" deferred from the theme feature.
