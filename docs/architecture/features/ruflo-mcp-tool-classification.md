---
title: Ruflo MCP Surface — Real/Theater/Broken Classification
status: active
produced_by: t-2759
depends_on: ADR-026-ruflo-mcp-backbone.md, ADR-059-multi-agent-substrate-selection.md
see_also: field-note_ruflo-agentic-layer-subscription-theater, system/rules/ruflo-stub-guard.md, system/rules/delegation-routing.md, project_gentle-ai-ruflo-comparison-adoption-candidates (2026-08-01/05 strategic-level comparison this audit tool-verifies)
created: 2026-08-12
---

# Ruflo MCP Surface — Real/Theater/Broken Classification

Umbrella whitelist/blacklist for the ~370 `mcp__ruflo__*` tools, produced under
**subscription-only** constraints (no `ANTHROPIC_API_KEY` in env), install v3.34.0.
Extends `field-note_ruflo-agentic-layer-subscription-theater` (June 2026 probe of the
agentic layer) and `system/rules/ruflo-stub-guard.md` from anecdote to a fuller
inventory, per t-2759.

**Prior art folded in, not re-derived:** `t-2757` (live re-verify of
`agentdb_hierarchical-store/recall` — confirmed BROKEN on our v3.34, root-caused to a
`ControllerRegistry` duplicate-ESM-export crash); the 2026-08-12 peer-session gap
analysis (`ruflo-gap-analysis.md` / `ruflo-upstream-extraction.md`, session `53e3ba7a`),
which source-audited upstream HEAD v3.38.0 and live-probed the agentic-theater tools;
and, at the strategic level, the earlier 2026-08-01/05 four-way comparison (gentle-ai /
ruflo / ruvnet-brain / thebrana — memory `project_gentle-ai-ruflo-comparison-adoption-candidates`),
whose call that "ruflo's durable value is the memory/embeddings layer, not the
orchestration layer Anthropic is natively absorbing" this audit now verifies tool by
tool rather than assumes.
This doc adds five parallel sessions of direct live probing (2026-08-12) across every
family prior work named but hadn't tested: `embeddings_*`, all of `agentdb_*`, memory
hygiene, `analyze_diff*`, `session_*`, `system_*`, `config_*`, `policy_*`, `guidance_*`,
`claims_*`, `performance_*`, all of `hooks_*` (representative sample), `coordination_*`
remainder, `task_*`/`workflow_*`, `swarm_health`/`pheromone_status`, `daa_*` remainder,
`neural_*` remainder, `ruvllm_*`, and the marketplace/ecosystem tail
(`github_*`, `transfer_*`, `metaharness_*`, `wasm_gallery_*`, `managed_agent_*`,
`http_fetch`).

**Classification legend:**
- **REAL+USEFUL** — computes something genuine we'd actually want; not already covered elsewhere.
- **REAL+REDUNDANT** — computes something genuine, but we already get it via `brana recall`, native tools, or another ruflo tool.
- **REAL+DORMANT** — genuine capability, correctly reports it has never been exercised (0 entries, not initialized) — not fake, just unused.
- **REAL+MISLEADING** — computes something genuine from input, but its output actively steers toward a forbidden or broken action.
- **DEGRADED** — the tool succeeds and returns *something*, but silently falls back to a weaker mode than advertised (e.g. claims "ReasoningBank BM25+semantic" and actually does a substring match) — worse than an error, because it looks like it worked.
- **BROKEN** — errors out, or two of its own endpoints contradict each other on identical data; usually the `ControllerRegistry` bridge crash (t-2757 root cause) or a missing optional npm dependency (`@ruvector/*`).
- **THEATER** — fabricated or hardcoded output regardless of input (confirmed by the June 2026 probe, the 2026-08-12 source audit, or directly live-probed here).
- **UNTESTED** — not called this session or by cited prior art; logged as a coverage gap, not silently assumed either way.
- **UNTESTED-SAFETY** — deliberately not called because doing so would mutate ruflo state, spend a real API call, or touch an external system out of band.

**Coverage note (no silent caps):** ~150 tools were directly live-probed across five
parallel sessions this session, ~15 more corroborated by cited prior sessions, ~15
already-established theater tools were not re-tested. The remaining ~100-130 tools
(mostly mutating/destructive siblings of tested read-only tools, plus
`federation_bbs_*`, most `metaharness_*` governance/training tools, `ruvllm_*`
mutators, and lifecycle-bound `hooks_*`) are **UNTESTED** — see §6's explicit list.

---

## 1. Verdict

Confirms and sharpens the June/August prior art: the **agentic coordination surface**
(`agent_*`, `hive-mind_*`, `swarm_*`, `coordination_*`, `daa_*`, `autopilot_*`,
`wasm_agent_*`) is bookkeeping/theater under subscription — live-probed directly for
`coordination_load_balance`/`_node`/`_topology`/`_metrics` and `daa_learning_status`/
`_performance_metrics` this session (§4, §5.5), confirming rather than merely inferring
the pattern for these specific tools. What's new here: the **AgentDB bridge** is broken
more broadly than just the hierarchical/temporal tools t-2757 checked — six more
`agentdb_*` tools fail with the identical `ControllerRegistry` error. But two `agentdb_*`
sub-families (`graph-*`/`causal-edge`, and `pattern-*`/`route` via a fallback path)
survive the same crash by using a different backend, so "agentdb is broken" is not a
safe blanket statement — it depends on which controller a given tool touches. The same
"real by family ≠ real by tool" pattern recurs everywhere: `performance_bottleneck` real
vs. `performance_metrics`/`performance_report` fake or self-contradictory in the same
family; `neural_predict` real vs. `neural_status`/`neural_patterns` fabricated-framing in
the same family; `task_list` real vs. `task_summary` contradicting it on identical data.
One actively dangerous finding: `guidance_recommend` genuinely computes a
task-appropriate score, then recommends forbidden tools (`agent_spawn`,
`terminal_execute`) as the execution path — real computation pointed at bad output.
Separately, several platform-layer tools (`claims_board`, `github_repo_analyze`,
`http_fetch`, `transfer_detect-pii`, `transfer_store-*`/`plugin-*`, `metaharness_score`/
`mcp_scan`, `hooks_intelligence_unified-stats`, `performance_bottleneck`) are genuinely
real and currently unused by any brana skill or rule.

---

## 2. AgentDB bridge — what's actually broken vs. what survives (directly probed 2026-08-12)

Root cause (t-2757): `memory-bridge.js` imports `ControllerRegistry` from
`@claude-flow/memory`, which double-exports the symbol on our v3.34 install — an ESM
crash. Confirmed to break every tool that routes through that one shared registry:

| Tool | Result | Evidence |
|---|---|---|
| `agentdb_health` | **BROKEN** | `{"available":false,"error":"AgentDB bridge not available"}` |
| `agentdb_context-synthesize` | **BROKEN** | `"AgentDB bridge not available. Use memory_store/memory_search instead."` |
| `agentdb_batch` | **BROKEN** | same error, on a throwaway insert |
| `agentdb_feedback` | **BROKEN** | same error |
| `agentdb_session-start` | **BROKEN** | same error |
| `agentdb_consolidate` | **BROKEN** | same error |
| `agentdb_session-end` | BROKEN (inferred — not called; would end a session that never started) | sibling of session-start |
| `agentdb_hierarchical-store/recall/delete` | **BROKEN** | t-2757 (same root cause) |
| `agentdb_controllers` | **BROKEN** | `ruflo-stub-guard.md` (same error) |
| `agentdb_semantic-route` | **BROKEN** | `ruflo-stub-guard.md` |

Two sub-families do **not** go through the broken registry and are genuinely real:

| Tool | Result | Evidence |
|---|---|---|
| `agentdb_graph-query` | **REAL, but not yet useful** | `backend:"sql-cosine"`, real `elapsedMs`, correctly returns empty for an unseeded node — machinery works. Per gap-analysis: graph *content* is junk (674/674 prior edges are trivial sequential `episode:N→N+1` links, similarity 0.0) — nothing produces meaningful edges yet. |
| `agentdb_graph-pathfinder` | **REAL, same caveat** | Honestly reports `"seedNodeId not present in graph_edges"` rather than fabricating a path. |
| `agentdb_causal-edge` | **REAL** | Wrote a throwaway test edge successfully: `{"success":true,"edgeId":"...","backend":"graph-node"}`. **Cleanup note: this audit left one throwaway edge (`audit-test:t-2759-a` → `audit-test:t-2759-b`, relation `audit-test-edge`) in the graph store — harmless but should be noted if the graph content is ever audited for real vs. test data.** |
| `agentdb_causal-edge-delete` / `agentdb_causal-node-delete` | UNTESTED (destructive, skipped) | inferred REAL — same graph-node backend as causal-edge |

And two more **degrade silently instead of erroring** — worse than `BROKEN`, because
nothing signals failure:

| Tool | Result | Evidence |
|---|---|---|
| `agentdb_pattern-search` | **DEGRADED** | `{"results":[],"controller":"memory-store-fallback","tier":"substring","note":"ReasoningBank controller unavailable; tier=substring from pattern namespace."}` — advertises "BM25+semantic hybrid," actually does substring matching. Already flagged in `ruflo-stub-guard.md`; **use `memory_search(namespace:"pattern")` instead.** |
| `agentdb_pattern-store` | **DEGRADED, but honest about it** | `{"success":true,"controller":"memory-store-fallback","note":"...Pattern persisted via memory_store."}` — writes land in the real memory store, just not the ReasoningBank tier the tool name implies. Functionally equivalent to `memory_store` with an extra label. **Cleanup note: this audit left one throwaway pattern (`patternId: pattern-1786543908541-h635tz`, type `audit-test`) in the memory store — harmless, not surfaced under `memory_list(namespace:"pattern")`'s top entries so its exact underlying key wasn't tracked down for removal.** |
| `agentdb_route` | **DEGRADED** | `{"route":"general","confidence":0.5,"agents":["coder"],"controller":"fallback"}` for a routing query about diff-classification — hardcoded confidence, generic answer regardless of input. Same failure shape as June's `daa_*`/`autopilot_*` heuristics-dressed-as-computation. |

**Action for `system/rules/ruflo-stub-guard.md`:** add `agentdb_context-synthesize`,
`agentdb_batch`, `agentdb_feedback`, `agentdb_session-start`, `agentdb_session-end`,
`agentdb_consolidate` to the BROKEN table (same bridge, same fix path as
`hierarchical-*`/`controllers`); add `agentdb_route` to the DEGRADED/stub table
alongside `pattern-search`.

---

## 3. Embeddings — real ONNX backend, mostly dormant features (directly probed)

| Tool | Result | Evidence |
|---|---|---|
| `embeddings_status` | **REAL** | Confirms `all-MiniLM-L6-v2`, 384-dim, ONNX backend, initialized 2026-02-25 |
| `embeddings_generate` | **REAL** | Genuine 384-dim vector, `norm≈1.0` (L2 normalized), varies with input text |
| `embeddings_compare` | **REAL+USEFUL** | Correct cosine similarity + interpretation ("very different") on two unrelated sentences |
| `embeddings_search` | REAL+REDUNDANT (inferred — same backend as `memory_search`) | UNTESTED directly |
| `embeddings_rabitq_status` | **REAL+DORMANT** | `{"available":false,"initialized":false,"vectorCount":0}` — RaBitQ quantized index has never been built on this install; honest, not fake |
| `embeddings_rabitq_build`/`search` | UNTESTED (build is a mutating trigger, skipped) | REAL infra, inferred unused |
| `embeddings_init` | UNTESTED (would reconfigure the live subsystem, skipped) | — |
| `embeddings_neural` | UNTESTED | `embeddings_status` shows `ruvector.enabled:false` — real optional feature, off |
| `embeddings_hyperbolic` | UNTESTED | `embeddings_status` shows `hyperbolic.enabled:true` — real feature, unused anywhere in brana |

**Verdict:** the embedding layer is real and already load-bearing (it's what `brana
recall` calls). Nothing new to adopt here beyond what's already wired — the RaBitQ/
hyperbolic/neural extensions are genuine but there's no evidence any brana workflow
would benefit from 32× quantized search or Poincaré-ball geometry at our current corpus
size (1111 entries).

---

## 4. Memory hygiene, diff analysis, and platform layer (directly probed)

| Tool | Result | Evidence |
|---|---|---|
| `memory_stats` / `memory_bridge_status` / `memory_detailed-stats` | **REAL** | Consistent live counts (1111 entries, 7 namespaces); `memory_detailed-stats` self-discloses `"note":"perf metrics are placeholders"` — structure real, perf numbers not |
| `memory_list` / `memory_retrieve` | **REAL** | Accurate enumeration; correctly returns `found:false` for a nonexistent key |
| `memory_search_unified` | **REAL+USEFUL** | Fans out across all 7 namespaces server-side with real scores in one call — not fully redundant with namespace-scoped `memory_search`/`brana recall`, since it's one round-trip for a cross-namespace sweep |
| `memory_export`/`cleanup`/`compress` | UNTESTED (mutating, skipped) | inferred REAL (same backend) |
| `memory_delete`/`import`/`import_claude`/`migrate` | UNTESTED (destructive) | — |
| `analyze_diff-stats` | **REAL** | Matched a real 3-commit git range exactly (15 files, 397/88 add/del) |
| `analyze_file-risk` | **REAL, but heuristic not "LLM-graded"** | Score varies deterministically with additions/deletions/status — the tool description says "LLM-graded change classification"; behavior is a deterministic formula, not an LLM call. Not fabricated, just overclaimed in its own description. |
| `analyze_diff`/`-classify`/`-reviewers`/`-risk` | REAL (inferred — same family/backend as `-stats`/`file-risk`) | UNTESTED directly |
| `session_current`/`session_list` | **REAL** | Honest empty state (`"No saved sessions"`) |
| `system_status` | **REAL, self-disclosing** | 3 of 4 components explicitly marked `"unknown — Health not measured, use system_health"` rather than faking a status |
| `system_health` | **REAL+USEFUL** | Genuinely differentiated per-component checks, real reason strings (`"Config file not found — run init"`) |
| `config_list` | **REAL** | Matched actual stored config (`memory.maxEntries`, `memory.persistInterval`) |
| `policy_status` | **REAL, dormant subsystem** | Reveals a real ADR-324 policy/receipt ledger already running in the background — `mode:"legacy"`, 346 receipts recorded, but 0 rules/budgets/approvals configured. Nothing enforces anything yet; this is infrastructure we've never turned on. |
| `guidance_quickref` | **REAL+REDUNDANT** | Accurate curated command list; we already have this via our own skill docs |
| `claims_board` | **REAL+USEFUL, currently unused** | Live board showed our own claim (`task:t-2759`) plus 5 other concurrently active session claims in real time (`t-1981`, `t-2321`, `t-1781`, `t-2622`, `t-2627`). Genuine cross-session WIP visibility that no brana skill surfaces today — directly relevant to t-2727's WIP-cap problem (concurrent sessions ARE observable via this tool, we just never look). |
| `mcp_status` | **REAL** | Trivial but accurate (live pid, transport) |
| `performance_metrics` | **THEATER, self-admitted** | Payload literally contains `"_real": false`; separately, its own latency/throughput sections return a full p50/p95/p99 breakdown despite `historySize:0` — nothing to compute a percentile from |
| `performance_bottleneck` | **REAL+USEFUL, self-admitted** | Payload contains `"_real": true`; genuinely computed CPU/mem/disk-io off the live process, cross-consistent with `system_metrics` from the same window. **Same family as `performance_metrics` but opposite trustworthiness — must check the `_real` field per-tool, never assume by family.** |
| `performance_report` | **BROKEN/UNRELIABLE** | Self-tags `"_real":true` but is internally inconsistent with `performance_metrics` for the same process seconds apart (`0.02 ops/s` vs `1250 ops/s`) — do not trust the `_real` flag as self-certification, cross-check independently |
| `performance_profile` | **REAL+USEFUL** | Hotspot breakdown measured over the actual requested duration, not templated |
| `performance_optimize` | **REAL, but a no-op** | Before/after numbers nearly identical, `applied:false` — only ever recommends, never optimizes. Confirms the CLI-level "reports success doing nothing" finding, though the MCP tool is at least honest about `applied:false` |
| `config_export` | **REAL+REDUNDANT** | Same data as `config_list`, reshaped |
| `coordination_load_balance`/`_node`/`_topology` | **THEATER** | `nodeCount:0`, empty node lists, static config blobs regardless of input — same bookkeeping-only pattern as `swarm_*`/`hive-mind_*`; extends the existing blanket blacklist (`delegation-routing.md` §1) with direct evidence rather than inference |
| `coordination_metrics` | **THEATER, self-disclosed** | `_note: "Real-time latency metrics not available — coordination is state-tracking only"` |
| `guidance_recommend` | **REAL, but actively misleading** | Dynamically scores task text (not templated), but its recommended execution steps include `agent_spawn`/`terminal_execute` — both forbidden (ADR-059 bookkeeping-only; `terminal_execute` denied in settings, t-2755). The recommender hasn't been updated for our routing rules — **do not follow its suggestions without cross-checking `delegation-routing.md`.** |
| `guidance_brain`/`_discover` | **REAL+USEFUL** | Live tool/skill registry matching this project's actual installed skills |
| `guidance_capabilities`/`_workflow` | **REAL+REDUNDANT** | Same registry data or a static generic template, not independently useful |
| `hooks_list` | **REAL** | Accurate live registry (26 active hooks) |
| `hooks_route` | **REAL+USEFUL** | Genuine HNSW-backed semantic routing — two different tasks got different routing (`semantic-native` vs `keyword` fallback), different confidences |
| `hooks_model-route` | **REAL+USEFUL** | Complexity scored differently (13% vs 40%) for two different tasks, with distinct reasoning strings — not static |
| `hooks_model-stats` | **REAL+USEFUL** | `totalDecisions` counter genuinely incremented across live `model-route` calls in the same session |
| `hooks_metrics` | **REAL, dormant** | Self-tags `_real:true`, honestly discloses "No metrics data collected yet" rather than fabricating numbers |
| `hooks_coverage-gaps`/`-route`/`-suggest` | **REAL+DORMANT** | Real query path, but nothing populates coverage data for this project — honestly empty (`totalGap:0`), not fabricated |
| `hooks_explain` | **REAL+REDUNDANT** | Genuinely computed factor breakdown, but materially overlaps `hooks_route`'s own reasoning output |
| `hooks_intelligence` (status query) | **REAL+DORMANT** | Honest all-zero activity counts across 12 subsystems — infrastructure present but fully inert in our usage |
| `hooks_intelligence_stats` | **REAL+USEFUL** | Cross-tool consistent — `modelRouter.totalDecisions` exactly matched the count of `hooks_model-route` calls made in the same session, proving live computation not a static counter |
| `hooks_intelligence_pattern-search` | **REAL+REDUNDANT** | Real HNSW hits over the actual pattern store, but a narrower wrapper around `memory_search(namespace:"pattern")` |
| `hooks_intelligence_attention` | **THEATER** | Identical `"(synthetic harness) pattern #1-5"` output at a flat weight of 0.2 for two unrelated queries; self-admits `_embeddingSource:"hash-fallback"` |
| `hooks_worker-list` | **REAL infra, 0% exercised** | 12 defined "smart triggers" (ultralearn/optimize/consolidate/audit/etc.), all show `0` active instances ever |
| `hooks_worker-status` | **REAL+DORMANT** | Consistent 0-workers empty state, matches `worker-list` |
| `hooks_worker-detect` | **REAL+REDUNDANT** | Correctly returned `detected:false, confidence:0` for a non-matching prompt (not hardcoded true), but feeds a dispatch path we don't use |
| `hooks_notify` | **REAL+REDUNDANT** | Real delivery record, but in-process only — no consumer in our workflow (we use native Task/Agent messaging) |
| `hooks_intelligence_unified-stats` | **REAL+USEFUL** | Explicitly reports `"memory-bridge (unreachable)"` — directly corroborates the same bridge break documented in §2, from a completely different tool. Good diagnostic for this exact bug class. |
| `hooks_codemod` / `hooks_model-verify` | REAL (already established, not re-tested) | prior gap-analysis |
| `hooks_init` | **UNTESTED-SAFETY — flag** | Schema writes `.claude/settings.json` with an optional force-overwrite; risks clobbering project hook config if called out-of-band, not tested |
| `hooks_build-agents`, `hooks_post-*`, `hooks_pre-*`, `hooks_session-*`, `hooks_task-completed`, `hooks_teammate-idle`, `hooks_transfer`, `hooks_pretrain`, `hooks_intelligence_pattern-store`/`_learn`/`-reset`/`_trajectory-*` | **UNTESTED-SAFETY** | Lifecycle-bound (fired by the harness at specific events) or mutate learning/trajectory state — out-of-band calls risk corrupting session/hook state, not tested |

**Verdict on `hooks_*`:** unlike `hive-mind_*`/`swarm_*`, this family is mostly real —
routing, verification, and stats tools genuinely compute from input and cross-check
consistently against each other (e.g. `hooks_intelligence_stats` mirrors live
`hooks_model-route` call counts). But "real" ≠ "useful": most of it is empty/inert
infrastructure we never populate (`coverage-*`, `worker-*`, intelligence status) or
redundant with a narrower/native equivalent already in use. One clear theater finding —
`hooks_intelligence_attention` — and one clear safety flag — `hooks_init` writes
`.claude/settings.json`.

---

## 5. Ruflo's own task/workflow engines vs. ours (directly probed — do not confuse with brana or native tooling)

`task_*` and `workflow_*` are ruflo's **own internal** persistence layers, entirely
separate from `.claude/tasks.json` (brana backlog) and from Claude Code's native
Workflow tool. Confusing the three is easy since the vocabulary overlaps.

| Tool | Result | Evidence |
|---|---|---|
| `task_create`/`task_list` | **REAL** | Created a throwaway task; it round-tripped through `task_list` with correct fields and timestamp |
| `task_status`/`update`/`assign`/`retry`/`complete` | REAL (corroborated via observed side effects — a prior probe task in `task_list` showed real cancel/progress state, not directly called by this session) | — |
| `task_summary` | **BROKEN — disagrees with `task_list`** | Reported `running:0` in the same session where `task_list` showed a task with `status:"running"`, 42% progress — the two endpoints contradict each other on identical underlying data. **`task_list` is real (it correctly reflects DB state); `task_summary`'s aggregation is the broken part. Never trust `task_summary` alone.** |
| `workflow_list`/`workflow_status` | **REAL, and negatively informative** | Surfaced a real prior workflow run (`probe-loop-workflow`) with genuine step detail: the `loop` step type is literally `status:"skipped"` (unimplemented), and the `task` step **fails** with `"task step step-2 requires config.agentId or workflow.variables.defaultAgentId"`. Directly confirms the gap-analysis finding that ruflo-native workflow `loop`/`task` steps are unimplemented/key-gated. **Do not build automation on ruflo-native `workflow_execute`/`workflow_run` beyond trivial `wait`-only steps — use our native Workflow tool instead.** |
| `workflow_template` (list) | **REAL+REDUNDANT** | Empty list, accurately reflects no saved templates |
| `workflow_create`/`execute`/`run` | UNTESTED (would kick off a real run) | given confirmed-broken `loop`/`task` steps, expect REAL-BUT-NON-FUNCTIONAL for anything past trivial |
| `workflow_validate`/`pause`/`resume`/`cancel`/`stop`/`delete` | UNTESTED | — |
| `swarm_health` | **REAL+REDUNDANT** | Correctly reports `status:"no_swarm", healthy:false` — accurate empty-state check, not fabricated. Doesn't change the existing `swarm_*` blacklist (nothing to report on since we never build swarms), just confirms the *health check itself* isn't lying. |
| `swarm_pheromone_status` | **REAL+REDUNDANT** | Correctly reports `active:false, reason:"no running pheromone-adaptive swarm"` |

---

## 5.5. `daa_*` remainder, `neural_*` remainder, `ruvllm_*` (directly probed)

`daa_*`'s core execution tools were already established as theater (field-note); these
are the two read-oriented siblings:

| Tool | Result | Evidence |
|---|---|---|
| `daa_learning_status` | **THEATER** | A stale test agent shows `successRate:1, adaptations:0` — perfect success with zero learning events, matching the already-confirmed fabricated-metrics pattern |
| `daa_performance_metrics` | **THEATER** | `avgLearningRate:0.1` is a flat constant regardless of `totalAdaptations:0` — not computed from any real signal |
| `neural_status` | **REAL embeddings, degenerate "training" stat** | `_realEmbeddings:true` (genuine ONNX backend); `avgAccuracy:1` for exactly one trivial stored pattern — consistent with `neural_train`'s known `accuracy = patternsStored>0 ? 1.0 : 0` formula. The embeddings underneath are real; the "accuracy"/"training" framing on top is not. |
| `neural_patterns` | **REAL+REDUNDANT** | Lists a real stored embedding pattern — genuine data, but it's `memory_store` output under "neural" branding |
| `neural_predict` | **REAL+USEFUL — standout of this cluster** | Genuine 384-dim MiniLM embedding + a computed, non-round cosine similarity (`0.0858`) via a real classifier head. `confidence:1` is a degenerate single-class softmax artifact (only one pattern in the DB), not fabrication. |
| `neural_compress`/`_optimize` | UNTESTED | not called this session |
| `ruvllm_status` | **REAL+REDUNDANT** | Accurately reports `wasm.available:false`, `trajectories:0` — correct empty/disabled state, not inflated |
| `ruvllm_chat_format` | **BROKEN — missing dependency** | Errors: `Cannot find package '@ruvector/ruvllm-wasm'` — not installed on this machine, not subscription-gating |
| `ruvllm_generate_config` | **BROKEN — missing dependency** | Same missing-package error, even though it's a pure JSON config builder — it eagerly loads the WASM module |
| `ruvllm_hnsw_route` | **REAL, honest error** | `"Router not found"` for an unconfigured router — correct behavior, full capability not judgeable without the excluded `hnsw_create` |

**Verdict:** `daa_*` remains uniformly theater end-to-end (execution tools already known,
now confirmed for the read-oriented siblings too). `neural_*` is split — the embedding
core is real, the "learning"/"accuracy" framing on top is fabricated, except
`neural_predict` which is genuinely computing something new (cosine similarity via a
real classifier). `ruvllm_*` is architecturally real (coordinator + graph backend both
report honest states) but two of four tools are hard-broken on this install from a
missing optional npm package — an environment gap, not a design flaw; re-verify if
`@ruvector/ruvllm-wasm` is ever installed.

---

## 6. Ecosystem tail — marketplace, GitHub, metaharness, session, wasm gallery (directly probed)

| Tool | Result | Evidence |
|---|---|---|
| `github_repo_analyze` | **REAL+USEFUL, self-admitted** | `"_real":true`; genuine GitHub-sourced metrics on thebrana itself (4055 commits, matches `git rev-list --count HEAD` exactly; 543 open issues, matches live `gh issue list`) — no explicit auth token needed, reused ambient git/gh credentials |
| `github_metrics` | **REAL+REDUNDANT** | Same commit count as `repo_analyze`, cross-verified against `git`/`gh` — real but duplicates tools already in daily use |
| `transfer_detect-pii` | **REAL+USEFUL** | Correctly found email+phone in a test string with real severity, and correctly did **not** flag a fake SSN pattern as PII — precise, not naive regex-everything. Candidate input for the gap-analysis's `RUFLO_MEMORY_SCAN_ON_WRITE` MemPoison use case. |
| `http_fetch` | **REAL, well-engineered — not a security concern** | Correctly blocked a private/link-local SSRF probe (`169.254.169.254`, the cloud-metadata address) by default with a clear `PRIVATE_ADDRESS` error, matching its documented ADR-164 allowlist (blocks `file://`/`ftp://`/RFC-1918/loopback/link-local by default, strips auth headers by default, hard timeout, response-size cap). A live GET to `api.github.com` also succeeded normally (real headers, real rate-limit data, 176ms). Revises the peer gap-analysis's cautious framing — this specific tool is safe as allowlisted; the real SSRF/supply-chain exposure named there is in the `browser_session_end`/`template_apply`/`cookie_use` `npx -y @claude-flow/cli@latest` shell-outs, a different tool family, not re-tested here. |
| `transfer_store-search`/`-featured`/`-trending` | **REAL+USEFUL** | Live query against a real, small pattern registry (`store-featured` returned a specific ed25519-signed entry, not filler); `-trending` returned the identical single result to `-featured` on this low-traffic registry (REAL+REDUNDANT relative to each other, not fake) |
| `transfer_plugin-search`/`-official`/`-featured` | **REAL+USEFUL** | Distinct, detailed plugin metadata including per-plugin security-audit records; `-featured` is the same set as `-official`, re-sorted (REAL+REDUNDANT relative to each other) |
| `transfer_store-download` | UNTESTED (would install something) | not called |
| `transfer_ipfs-resolve` | UNTESTED-SAFETY | no safe/known CID available to test |
| `metaharness_score` | **REAL+USEFUL** | Repo-specific 5-dimension scorecard (harnessFit 75, toolSafety 90, memoryUsefulness 44) with plausible, non-round numbers and a cost estimate — not a static template |
| `metaharness_mcp_scan` | **REAL+USEFUL** | Correctly reported `mcpEnabled:false` for a directory with no `.mcp/servers.json` policy file — accurate, not a hardcoded pass. Directly relevant to auditing the MCP surface itself. |
| `metaharness_audit_list` | **REAL+DORMANT** | Correctly returned empty (`totalInNamespace:0`) — no prior audits stored, not fabricated data |
| `metaharness_audit_trend` | UNTESTED-SAFETY | Needs two audit records to diff; none exist (confirmed empty by `audit_list`) |
| `metaharness_similarity` | UNTESTED-SAFETY | Needs two genome/score files; none prepared |
| `metaharness_evolve`/`_flywheel`/`_gepa`/`_learn`/`_redblue`/`_security_bench`/`_threat_model`/`_bench`/`_genome`/`_drift_from_history`/`_oia_audit` | **UNTESTED** | look like long/expensive/governance-sensitive runs by tool description — skipped rather than guessed at |
| `session_current` | **REAL+DORMANT** | `status:"none", error:"No saved sessions"` — real empty state, not fabricated |
| `session_list` | **REAL+DORMANT** | `{sessions:[], total:0}` — consistent empty state |
| `session_info` | UNTESTED-SAFETY | requires a `sessionId`; none exist to query |
| `managed_agent_list` | **REAL, key-gated by design** | Self-reports needing `ANTHROPIC_API_KEY`/Managed Agents beta — dead under subscription, same pattern as `agent_execute` |
| `managed_agent_status` | UNTESTED-SAFETY | requires a `sessionId`; list is empty/key-gated so nothing to query |
| `managed_agent_create`/`_prompt`/`_terminate` | **UNTESTED (key-gated by design)** | per prior art, real Anthropic HTTP call but hard key-gated under subscription — not called to avoid a real paid-API attempt |
| `wasm_gallery_list`/`_categories`/`_active`/`_config`/`_search`/`_list_by_category` | **BROKEN — missing dependency** | `ERR_MODULE_NOT_FOUND: @ruvector/rvagent-wasm` — optional npm package not installed on this install, not a design flaw. Re-verify if the package is ever installed. |
| `wasm_gallery_*` mutators (`add_custom`/`create`/`export`/`import`/`load_rvf`/`remove_custom`/`configure`) | UNTESTED | given the same missing-dependency error on every read path, expect the same BROKEN result — not independently confirmed |
| `federation_bbs_human_join`/`_publish`/`_register`/`_watch` | **UNTESTED-SAFETY** | Not called — would publish/register externally with a persistent identity. Schema descriptions (Ed25519 tokens, monotonic sequence, PII gating) read as a genuinely-designed real subsystem, not theater — but each documents an optional dependency that degrades to `{degraded:true}` when missing, so live behavior here is more likely BROKEN-by-missing-dep (same pattern as `wasm_gallery_*`) than fabricated. |
| `business_pod_validate` | **REAL, not applicable to this project** | Genuine JSON-schema validation (correctly rejected incomplete input with a specific field error) — real, but thebrana doesn't build ADR-164 business pods, no current use case |
| `business_pod_route_backend` | UNTESTED | not called |

**Remaining unclassified tail (~100-130 tools).** Not probed by this audit at all:
most `ruvllm_*` mutators (`hnsw_add`/`_create`, `microlora_*`, `sona_*`), most
`hooks_*` lifecycle/mutation tools (§4), `config_set`/`_import`/`_reset`,
`system_reset`, `policy_evaluate`, `embeddings_init`/`_neural`/`_hyperbolic`/`_rabitq_build`,
`memory_export`/`_cleanup`/`_compress`/`_delete`/`_import`/`_import_claude`/`_migrate`,
`agentdb_causal-edge-delete`/`_causal-node-delete`/`_hierarchical-delete`,
`workflow_create`/`_execute`/`_run`/`_validate`/`_pause`/`_resume`/`_cancel`/`_stop`/`_delete`,
`task_status`/`_update`/`_assign`/`_retry`/`_complete` (inferred real via side effects,
not directly called). Treat all of these as unclassified, not as theater-by-default or
real-by-default — the split seen everywhere else in this audit (e.g. `agentdb_graph-*`
real vs. `agentdb_context-synthesize` broken in the *same* family; `performance_bottleneck`
real vs. `performance_metrics` fake in the *same* family; `daa_learning_status` theater vs.
`neural_predict` real in adjacent families) shows family-level assumptions are unsafe.
Verify per-tool before depending on any of these.

---

## 7. Recommended routing updates

**Add to `system/rules/delegation-routing.md` §1 never-use list:**
- `agentdb_context-synthesize`, `agentdb_batch`, `agentdb_feedback`,
  `agentdb_session-start`/`-end`, `agentdb_consolidate` — same broken bridge as
  `hierarchical-*` (§2 above); use `memory_store`/`memory_search` instead.
- `agentdb_pattern-search`, `agentdb_route` — DEGRADED, not BROKEN: they return a
  plausible-looking answer from a fallback path instead of erroring. More dangerous
  than an outright failure. Use `memory_search(namespace:"pattern")` for pattern
  lookup; treat `agentdb_route`'s output as a coin flip, not a recommendation.
- `performance_metrics` and `performance_report` — the first self-labels `_real:false`
  and fabricates percentiles from zero history; the second self-labels `_real:true` but
  contradicts `performance_metrics` on the same live data. Use `performance_bottleneck`
  or `performance_profile` instead for this class of question (both genuinely computed,
  cross-consistent with `system_metrics`).
- `coordination_load_balance`/`_node`/`_topology`/`_metrics` — now directly live-probed
  (§4), confirmed to follow the exact same bookkeeping-only pattern as `coordination_orchestrate`/
  `_consensus`/`_sync`, which the existing blanket rule already forbids. No behavior
  change, just direct evidence closing the inference gap.
- `daa_learning_status`/`_performance_metrics` — now directly live-probed (§5.5),
  fabricated metrics confirmed for the read-oriented siblings, same as the
  already-forbidden `daa_*` execution tools.
- `task_summary` — undercounts/contradicts `task_list` on identical data; use
  `task_list` directly if ever reading ruflo's own (non-brana) task store.
- Ruflo-native `workflow_execute`/`workflow_run` for anything beyond a single `wait`
  step — the `loop` step type is unimplemented and the `task` step is key-gated; use
  the native Workflow tool.
- `guidance_recommend` — genuinely scores input but recommends forbidden tools
  (`agent_spawn`, `terminal_execute`) in its own output. Not a "never call" (the
  scoring itself is real), but never act on its suggested execution steps without
  cross-checking this file.
- `wasm_gallery_*` (all read paths) and `ruvllm_chat_format`/`ruvllm_generate_config` —
  hard-BROKEN on this install from missing optional npm packages
  (`@ruvector/rvagent-wasm`, `@ruvector/ruvllm-wasm`), not subscription-gating. Re-verify
  if those packages are ever installed; don't route through them until then.

**New real+useful candidates worth a sanctioning decision (not yet routed anywhere):**
- `claims_board` — cross-session WIP visibility; candidate input for t-2727's WIP-cap
  decision (concurrent sessions are already observable, just not surfaced).
- `hooks_intelligence_unified-stats` — good diagnostic for AgentDB-bridge-health
  drift; candidate for `brana doctor` or a periodic health check.
- `github_repo_analyze`, `transfer_detect-pii`, `http_fetch`,
  `memory_search_unified` — genuinely useful, no current call site. Low priority;
  file as adoption candidates only if a concrete use case appears (per
  work-preferences.md simplicity guidance — don't wire in speculative capability).
- `transfer_store-search`/`plugin-search`/`plugin-official` — real marketplace queries;
  only relevant if/when we resume evaluating third-party ruflo plugins (gap-analysis
  §5 already deferred that broader question).
- `metaharness_score`/`_mcp_scan` — real, repo-specific scoring; `_mcp_scan` in
  particular is directly on-topic for future re-runs of an audit like this one.
- `neural_predict` — the one genuinely computational tool in the `neural_*` family
  (real embeddings + a non-constant cosine similarity); no current use case, flag only.

**No change needed:** `testgen_tdd_repair` (already sanctioned), `browser_*` (already
real+useful), `hooks_codemod`/`hooks_model-verify` (already real, already cited in
gap-analysis), `terminal_execute` (already absent from the tool surface / denied in
settings, t-2755), `wasm_agent_prompt` (already blacklisted).

---

## 8. What this doc does not settle

- The long tail in §6 (~100-130 tools, explicitly listed there) remains unclassified.
  If a future task wants to use one of them, verify it live first — do not assume real
  or theater from this doc.
- Whether to activate the ADR-324 policy/receipt subsystem (`policy_*`) is a separate
  decision, not made here — flagging its existence and current idle state is in scope
  for an audit, adopting it is not.
- The graph-content-is-junk problem (`agentdb_graph-*`/`causal-edge` machinery is real
  but nothing produces meaningful edges) is unchanged from the gap-analysis finding — a
  producer would need to exist before a consumer is worth building; out of scope here.
- This audit's own probing left minor, disclosed pollution in ruflo's stores: one
  throwaway graph edge (`audit-test:t-2759-a`→`audit-test:t-2759-b`), one throwaway
  pattern (`patternId: pattern-1786543908541-h635tz`), and one throwaway `task_create`
  record. Harmless, but worth a cleanup pass if ruflo's stores are ever audited for
  real vs. test data.
