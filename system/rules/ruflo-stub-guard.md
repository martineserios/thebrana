---
paths: ["system/procedures/**", "system/skills/**"]
---
# Ruflo Stub Guard

Never use these ruflo commands as authoritative signals. They return hardcoded
or unimplemented output regardless of input:

| Command / Tool | Stub behavior | Safe alternative |
|---|---|---|
| `ruflo security-scan` / `mcp__ruflo__aidefence_scan`, `aidefence_is_safe`, `aidefence_has_pii`, `aidefence_analyze`, `aidefence_learn`, `aidefence_stats` | Whole `aidefence_*` family errors `Cannot find module @claude-flow/aidefence` — same thin-wrapper defect, not just `aidefence_scan` (t-2748, live-probed 2026-08-12). Package is 97KB unpacked — too small for a real classifier. | Manual code review; validate.sh; don't gate client-facing traffic on it. Build a narrow local PII regex layer if needed; treat injection mitigation as architectural (least-privilege, untrusted input), not a classifier problem |
| `mcp__ruflo__testgen_tdd_repair` | Dead export — defined and re-exported in `mcp-tools/index.js` but never imported/registered by the MCP server on either v3.34 (our pinned install) or v3.38.3; its bridged plugin (`ruflo-testgen/tdd-repair/tdd-repair.mjs`) doesn't ship in either version (t-2753, live-probed 2026-08-12). No sanctioned ruflo MCP execution path exists. | Native `/brana:build` TDD loop already covers its 3 claimed advantages (spawn, budget cap, test-verified repair) |
| `ruflo deploy` | No real implementation; always "succeeds" | `git merge main`; Vercel/Cloud Run deploy |
| Memory quantization output | Reports hardcoded 3.92× compression factor | Treat as display-only; never use in capacity calculations |
| `mcp__ruflo__agentdb_controllers`, `agentdb_semantic-route`, `agentdb_health`, `agentdb_hierarchical-store/recall/delete`, `agentdb_context-synthesize`, `agentdb_batch`, `agentdb_feedback`, `agentdb_session-start/-end`, `agentdb_consolidate` | Fail with `AgentDB bridge not available`. Root cause confirmed 2026-08-12 (t-2757): installed `@claude-flow/memory` double-exports `ControllerRegistry`, crashing the bridge on import — a packaging bug, fixed upstream (not in our pinned version), not a "v3.5 vs v3.6" split. **NOT all `agentdb_*` tools** — `graph-query`/`graph-pathfinder`/`causal-edge*` use a separate `graph-node` backend and work (t-2759, live-probed 2026-08-12); corrected from an earlier "all `agentdb_*`" overstatement. **UPDATE 2026-08-14 (t-2626): the dup-export is now patched locally** (`system/scripts/patch-ruflo-memory-dup-export.sh`, re-asserted by `ruflo-mcp.sh` at every MCP launch) — the bridge initializes and memory writes take the native better-sqlite3 WAL path (live-probed: bridgeStoreEntry STORED, failure reason null, 6/6 concurrent CLI stores landed). The agentdb_* rows above may now respond; re-probe before trusting them, this row predates the patch. | Use `mcp__ruflo__memory_search` / `memory_store` instead |
| `mcp__ruflo__agentdb_pattern-search`, `mcp__ruflo__agentdb_route` | Do NOT error — silently degrade to a fallback (substring match; hardcoded `confidence:0.5`) instead of the advertised ReasoningBank/semantic behavior. Worse than a stub because the output looks legitimate (t-2759, live-probed 2026-08-12). | `memory_search(namespace:"pattern")` for pattern lookup; do not trust `agentdb_route`'s recommendation |
| `mcp__ruflo__performance_metrics` | Self-labels `"_real": false` in its own payload. | `mcp__ruflo__performance_bottleneck` (same family, `"_real": true`, genuinely computed) |
| `mcp__ruflo__browser_check` | Checkbox interaction tool — checks/unchecks a DOM element via CSS selector; NOT a browser health check | Use `browser_open` + navigate + inspect result |
| `mcp__ruflo__guidance_recommend` | Genuinely scores the input task, but its recommended execution steps include forbidden/dead tools (`agent_spawn`, `terminal_execute`) — the recommender hasn't been updated for ADR-059/t-2755 routing rules (t-2759, live-probed 2026-08-12) | Cross-check any suggestion against `delegation-routing.md` before following it |
| `mcp__ruflo__task_summary` | Undercounts live state — reported `running:0` in the same session where `mcp__ruflo__task_list` showed a task with `status:"running"` (t-2759, live-probed 2026-08-12) | Use `mcp__ruflo__task_list` directly, not the summary rollup |
| `mcp__ruflo__hooks_model-route`, `hooks_model-outcome`, `hooks_model-stats` | Pure bookkeeping under subscription (no model call, ~3ms, 0 tokens) with 2 confirmed integrity defects: picked a model contradicting its own ranking (chose sonnet while alternatives ranked haiku highest and sonnet was never scored), and `model-stats.totalDecisions` doesn't sum against `routedByCounts` (t-2766, live-probed 2026-08-12). `costMultiplier` is a static table lookup, not measured spend. | Ignore the routed model recommendation; use `delegation-routing.md` step 4 for real routing decisions. `hooks_model-verify` is genuinely real (deterministic structural checks, no LLM) if called with `record:false` |

**Why:** Confirmed stubs via source audit (issue #1482) and live testing (t-1549,
2026-05-20). Trusting these outputs has caused false security confidence and
incorrect capacity estimates in prior sessions.

**Scope:** This rule applies whenever writing or reviewing procedures and skills
that might reference these tools. For hooks that call ruflo, add a `# STUB — do not trust`
comment next to any of the three patterns above.

## Real but miscalibrated (not stubs — output is computed, just wrong for this repo)

| Command / Tool | Miscalibration | Safe alternative |
|---|---|---|
| `mcp__ruflo__analyze_diff-risk`, `analyze_file-risk` | Genuinely computed local heuristic (path-regex + line-count buckets + status; no key/LLM/network) — scores differ sensibly for generic diffs. But the path table is generic-webapp shaped (`src/auth`, `core`, `.env`) and blind to thebrana's actual highest-blast-radius files: `system/hooks/session-start.sh` (+17 lines) scored 0/100 with zero reasons. No tunable config exposed (t-2761, live-probed 2026-08-12). `analyze_diff-reviewers` also returns generic role strings, not CODEOWNERS/git-blame — useless solo-repo. | Don't wire into build CLOSE or pr-reviewer. The actual desired signal (touching `system/hooks/`, `bootstrap.sh`, `system/cli/rust/crates/*/src/`) is ~5 lines of native `git diff --name-only` against a repo-specific path list — tunable, zero MCP round-trip |
