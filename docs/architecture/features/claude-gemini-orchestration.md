---
title: Claude-Gemini Orchestration — Failure-Mode Spec
status: active
created: 2026-05-24
source: adversarial-spike-2026-05-24
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
