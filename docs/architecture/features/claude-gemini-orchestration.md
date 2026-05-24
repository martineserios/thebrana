---
title: Claude-Gemini Orchestration — Feature Spec
status: active
created: 2026-05-24
depends_on: ADR-040, ADR-041
---

# Claude-Gemini Orchestration

> Claude orchestrates; Gemini (agy) executes as a stateless worker. Every result flows back
> through Claude into the brana system. See `brana-v2-compute-model.md` for the full stack.

## Layer Stack

```
LAYER A — Bash (scheduled sweeps, quick one-shots)
  agy -p "..." > system/scheduler/outputs/{ts}.md
  No version check, no timeout enforcement, no validation — caller owns these.
  Template: system/scheduler/templates/agy-sweep.sh.template

LAYER B — mcp__brana__agy_delegate (all skill-driven delegations)
  Version pin · 120s timeout · stdio isolation · output validation · /tmp/ cleanup
  Entry point: /brana:gemini "task" or /brana:gemini t-XXXX

LAYER C — /brana:gemini skill (full lifecycle)
  ROUTE → ENRICH → DELEGATE → APPLY → EXTRACT → PERSIST
  Procedure: system/procedures/gemini.md
```

## Task Type Taxonomy

### agy-eligible

| Type | Convention-sensitive | Notes |
|------|---------------------|-------|
| Research sweep | No | Atomic, read-only |
| Boilerplate generation | ⚠️ Yes | ENRICH required; ruflo abort if unavailable |
| Doc first draft | ⚠️ Yes | Pass explicit "why" context in task description |
| Conversion/translation | No | Deterministic output |
| Batch summarization | No | Parallel, repetitive |
| Test scaffolding | ⚠️ Yes | ENRICH required for codebase conventions |
| Competitive/market analysis | No | Research-heavy, brana-agnostic |

### Claude-native (never delegate)

| Type | Reason |
|------|--------|
| `system/` changes | Hook enforcement required |
| Git operations | Bypasses branch-guard, main-guard |
| `tasks.json` writes | Race condition risk (t-1507) |
| Architectural decisions | Requires in-session state + judgment |
| Multi-step stateful refactors | agy is stateless (no session ID) |
| Memory/session writes | brana system boundary |

## Routing Heuristic (4+1 Questions)

All four must be yes to delegate; convention gate (+1) adds a conditional abort:

1. **Atomic?** — one `agy -p` call, no mid-task state
2a. **System-isolated?** — no writes to `system/`, git, hooks, `tasks.json`
2b. **Context-enrichable?** — ENRICH can supply enough background
3. **Speed/token benefit?** — repetitive, fast, or token-heavy for Claude
+1. **Convention-sensitive?** — if yes: ruflo mandatory, abort if unavailable

## /tmp/ Invariant

Layer B output: `/tmp/agy-{suffix}-{ts_ms}.md` only. `agy_delegate.rs` hardcodes this.
Layer A sweeps: `system/scheduler/outputs/` only (survives reboot; `/brana:close` extracts).

Neither path can be overridden by callers. Claude reads from these paths and applies changes
via Write/Edit tools — CC hooks fire normally on every repo change.

## Version Pinning Discipline

`AGY_PINNED_VERSION = "1.0.1"` in `agy_delegate.rs`. Checked at every Layer B invocation.
Mismatch → hard error (not warning). Upgrade procedure: bump constant → re-run adversarial
spike → confirm output contract unchanged → commit. Never bump without re-running the spike.

## Cleanup Discipline

Both `/tmp/agy-prompt-{ts_ms}.md` and captured output are removed via Rust `Drop` guard
after the MCP tool returns. Timestamp suffix uses milliseconds to avoid collision on rapid
back-to-back calls. Layer A sweep files removed by `/brana:close` after EXTRACT.

---

# agy Failure-Mode Spec

> Empirical findings from adversarial spike run 2026-05-24.
> Gates `agy_delegate.rs` validator — do not modify without re-running spike.

## agy Version

Pinned: `1.0.1`  
Binary: `~/.local/bin/agy`  
Version flag: `agy --version` → stdout, exit 0.

## Failure Modes

| Failure | Exit code | Location | stdout pattern | Notes |
|---------|-----------|----------|----------------|-------|
| Empty/whitespace prompt | 0 | stdout | `Error: empty prompt. Usage: agy --print "..."` | Exit 0 despite error |
| Internal agy timeout | 0 | stdout | `Error: timed out waiting for response` | Fires after agy's own `--print-timeout` (5m default) |
| Invalid flag | 2 | stdout | `flags provided but not defined: -FLAG\nUsage of agy:...` | Exit 2 — only non-zero seen |
| Network / quota failure | unknown | unknown | Untested — our 120s outer timeout mitigates |
| Oversized prompt | 0 | stdout | agy explores FS then hits internal timeout | Degrades, does not crash |
| Happy path | 0 | stdout | Clean response content | stderr always empty |

## Validator Rules (in precedence order)

1. Exit code != 0 → `agy_nonzero_exit` error
2. stdout empty (after trim) → `agy_empty_output` error
3. stdout starts with `"Error: "` → `agy_error` error (covers empty prompt + internal timeout)
4. `tokio::time::timeout` fires before process exits → `agy_timeout` error
5. Otherwise → success, return trimmed stdout

## stdio Findings

- **stdout**: all output (both success and error messages) goes to stdout.
- **stderr**: always empty in every tested scenario. Captured for completeness but not signal-bearing.
- **MCP contract**: stdio must be `Stdio::null()` / `Stdio::piped()` — never inherited. MCP server communicates via inherited stdio; agy stdout bleeding into that pipe corrupts JSON-RPC.

## Prompt Injection

- Shell metacharacters in prompt string (e.g. `; rm -rf ...`) are passed to agy verbatim when using `Command::new("agy").arg("-p").arg(prompt)` — no shell involved, no injection risk at the Rust level.
- agy may interpret the injected text as instructions to Gemini and respond to it. Mitigation: Claude constructs all prompts; no raw user string interpolation.
