# ADR-008: Smart /brana:tasks add — suggest-only pattern

**Date:** 2026-03-03
**Status:** proposed

## Context
`/brana:tasks add` currently accepts a description and asks for stream, milestone, and tags. It does not cross-reference existing tasks for dependencies, nor does it suggest tags, effort, or parent from the description. This led to orphaned tasks missing obvious dependencies (e.g., t-058 added without blocked_by t-045 until manually caught).

PM literature challenge (10 books, NLM-grounded) identified risks of over-automation: auto-priority violates strategic intent (Perri, Croll), keyword dependency detection creates false confidence (Fitzpatrick), and frictionless add worsens the build trap (Perri).

## Decision
Adopt a **suggest-only** pattern: the system suggests tags, effort, parent, and dependency candidates, but the user confirms each. Specifically:

1. **No auto-priority.** Priority is left null; user sets it manually as a strategic choice.
2. **Dependencies are candidates.** Cross-reference by tag overlap (2+ shared tags) and subject keyword match. Presented as "Possible dependency — confirm?" Never auto-committed.
3. **Build-trap detection.** Flag tasks with solution language but no outcome context. Optionally prompt for problem statement.
4. **Progressive automation.** Each suggestion step is independent and can be individually automated in future versions (ask → auto-if-confident → auto-always) without restructuring the flow.

## Consequences
- **Easier:** Adding well-connected tasks. Dependency gaps caught at creation time. Build-trap awareness.
- **Harder:** Nothing — suggest-only is additive. Existing `/brana:tasks add` behavior preserved for users who skip all suggestions.
- **Future:** Each suggestion step is an independent automation dial. ICE scoring, duplicate detection, discovery-stream routing can be added as new steps without changing existing ones.
