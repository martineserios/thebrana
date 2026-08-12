---
title: Ruflo MCP Surface — Real/Theater/Broken Classification
status: active
produced_by: t-2759
depends_on: ADR-026-ruflo-mcp-backbone.md, ADR-059-multi-agent-substrate-selection.md
see_also: field-note_ruflo-agentic-layer-subscription-theater, system/rules/ruflo-stub-guard.md, system/rules/delegation-routing.md
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
which source-audited upstream HEAD v3.38.0 and live-probed the agentic-theater tools.
This doc adds a session of direct live probing (2026-08-12) across families that prior
work named but hadn't tested: `embeddings_*`, most of `agentdb_*`, memory hygiene,
`analyze_diff*`, `session_*`, `system_*`, `config_*`, `policy_*`, `guidance_*`,
`claims_*`, `performance_*`, a `hooks_*` sample, `task_*`/`workflow_*`, and a handful of
ecosystem tools (`github_repo_analyze`, `transfer_detect-pii`, `http_fetch`,
`neural_status`).

**Classification legend:**
- **REAL+USEFUL** — computes something genuine we'd actually want; not already covered elsewhere.
- **REAL+REDUNDANT** — computes something genuine, but we already get it via `brana recall`, native tools, or another ruflo tool.
- **REAL+DORMANT** — genuine capability, correctly reports it has never been exercised (0 entries, not initialized) — not fake, just unused.
- **DEGRADED** — the tool succeeds and returns *something*, but silently falls back to a weaker mode than advertised (e.g. claims "ReasoningBank BM25+semantic" and actually does a substring match) — worse than an error, because it looks like it worked.
- **BROKEN** — errors out; usually the `ControllerRegistry` bridge crash (t-2757 root cause).
- **THEATER** — fabricated or hardcoded output regardless of input (confirmed elsewhere, June 2026 probe + 2026-08-12 source audit — not re-tested here).
- **UNTESTED** — not called this session or by cited prior art; logged as a coverage gap, not silently assumed either way.

**Coverage note (no silent caps):** ~50 tools were directly live-probed this session,
~15 more corroborated by cited prior sessions, ~15 already-established theater tools
were not re-tested. The remainder (`federation_bbs_*`, most `metaharness_*`,
`ruvllm_*`, `transfer_store-*/plugin-*`, `wasm_gallery_*` mutators,
`managed_agent_create/prompt/terminate`, most of `hooks_*`, most of `session_*` /
`config_*` mutators) is **UNTESTED** — see §6.

---

## 1. Verdict

Confirms and sharpens the June/August prior art: the **agentic coordination surface**
(`agent_*`, `hive-mind_*`, `swarm_*`, `coordination_*`, `daa_*`, `autopilot_*`,
`wasm_agent_*`) is bookkeeping/theater under subscription — no new evidence changes
this, not re-tested. What's new here: the **AgentDB bridge** is broken more broadly than
just the hierarchical/temporal tools t-2757 checked — six more `agentdb_*` tools fail
with the identical `ControllerRegistry` error. But two `agentdb_*` sub-families
(`graph-*`/`causal-edge`, and `pattern-*`/`route` via a fallback path) survive the same
crash by using a different backend, so "agentdb is broken" is not a safe blanket
statement — it depends on which controller a given tool touches. Separately, several
platform-layer tools (`claims_board`, `github_repo_analyze`, `http_fetch`,
`transfer_detect-pii`, `hooks_intelligence_unified-stats`, `performance_bottleneck`) are
genuinely real and currently unused by any brana skill or rule.

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
| `performance_metrics` | **THEATER, self-admitted** | Payload literally contains `"_real": false` |
| `performance_bottleneck` | **REAL+USEFUL, self-admitted** | Payload contains `"_real": true`; genuinely computed CPU/mem/disk-io off the live process. **Same family as `performance_metrics` but opposite trustworthiness — must check the `_real` field per-tool, never assume by family.** |
| `hooks_list` | **REAL** | Accurate live registry (26 active hooks) |
| `hooks_route` | **REAL+USEFUL** | Genuine HNSW-backed semantic routing, real latency, output varies meaningfully with task text |
| `hooks_worker-list` | **REAL infra, 0% exercised** | 12 defined "smart triggers" (ultralearn/optimize/consolidate/audit/etc.), all show `0` active instances ever |
| `hooks_intelligence_unified-stats` | **REAL+USEFUL** | Explicitly reports `"memory-bridge (unreachable)"` — directly corroborates the same bridge break documented in §2, from a completely different tool. Good diagnostic for this exact bug class. |
| `hooks_codemod` / `hooks_model-verify` | REAL (already established, not re-tested) | prior gap-analysis |
| Remaining ~34 `hooks_*` | **UNTESTED** | logged as coverage gap, not assumed either way — see §6 |

---

## 5. Ruflo's own task/workflow engines vs. ours (directly probed — do not confuse with brana or native tooling)

`task_*` and `workflow_*` are ruflo's **own internal** persistence layers, entirely
separate from `.claude/tasks.json` (brana backlog) and from Claude Code's native
Workflow tool. Confusing the three is easy since the vocabulary overlaps.

| Tool | Result | Evidence |
|---|---|---|
| `task_create`/`task_list` | **REAL** | Created a throwaway task; it round-tripped through `task_list` with correct fields and timestamp |
| `task_status`/`summary`/`update`/`assign`/`retry`/`complete` | REAL (corroborated via observed side effects — a prior probe task in `task_list` showed real cancel/progress state, not directly called by this session) | — |
| `workflow_list`/`workflow_status` | **REAL, and negatively informative** | Surfaced a real prior workflow run (`probe-loop-workflow`) with genuine step detail: the `loop` step type is literally `status:"skipped"` (unimplemented), and the `task` step **fails** with `"task step step-2 requires config.agentId or workflow.variables.defaultAgentId"`. Directly confirms the gap-analysis finding that ruflo-native workflow `loop`/`task` steps are unimplemented/key-gated. **Do not build automation on ruflo-native `workflow_execute`/`workflow_run` beyond trivial `wait`-only steps — use our native Workflow tool instead.** |
| `workflow_create`/`execute`/`run` | UNTESTED (would kick off a real run) | given confirmed-broken `loop`/`task` steps, expect REAL-BUT-NON-FUNCTIONAL for anything past trivial |
| `workflow_template`/`validate`/`pause`/`resume`/`cancel`/`stop`/`delete` | UNTESTED | — |

---

## 6. Ecosystem tail — sampled and untested (directly probed subset)

| Tool | Result | Evidence |
|---|---|---|
| `github_repo_analyze` | **REAL+USEFUL, self-admitted** | `"_real":true`; genuine GitHub-sourced metrics on thebrana itself (4055 commits, 29 branches, 3 contributors, 543 open issues) — no explicit auth token needed, reused ambient git/gh credentials |
| `transfer_detect-pii` | **REAL+USEFUL** | Correctly typed and located an email + phone in a test string with real severity; did not independently confirm SSN-pattern detection in this one sample (count:2 not 3) — worth a follow-up if this tool is adopted for the `RUFLO_MEMORY_SCAN_ON_WRITE` MemPoison use case from the gap-analysis |
| `http_fetch` | **REAL, well-engineered — not a security concern** | Correctly blocked a private/link-local SSRF probe (`169.254.169.254`, the cloud-metadata address) by default with a clear `PRIVATE_ADDRESS` error, matching its documented ADR-164 allowlist (blocks `file://`/`ftp://`/RFC-1918/loopback/link-local by default, strips auth headers by default, hard timeout, response-size cap). Revises the peer gap-analysis's cautious framing — this specific tool is safe as allowlisted; the real SSRF/supply-chain exposure named there is in the `browser_session_end`/`template_apply`/`cookie_use` `npx -y @claude-flow/cli@latest` shell-outs, a different tool family, not re-tested here. |
| `neural_status` | **REAL embeddings, degenerate "training" stat** | `"_realEmbeddings":true`; `avgAccuracy:1` for exactly 1 trivial stored pattern — consistent with the June field-note's `neural_train` finding (`accuracy = patternsStored>0 ? 1.0 : 0`). Underlying embeddings are genuinely real; "accuracy"/"training" framing on top of them is not. |
| `federation_bbs_*` | **UNTESTED** | would publish/register externally — no safe local probe exists |
| `transfer_store-*`/`plugin-*`/`ipfs-resolve` | **UNTESTED** | network calls to external registries, not exercised |
| `ruvllm_*` | **UNTESTED** | — |
| `metaharness_*` (most) | **UNTESTED** | several (`evolve`/`flywheel`/`gepa`/`redblue`/`security_bench`) look like long/expensive runs by description — skipped rather than guessed at |
| `managed_agent_create`/`prompt`/`terminate` | **UNTESTED (key-gated by design)** | per prior art, `managed_agent_*` execution is a real Anthropic HTTP call but hard key-gated under subscription — not called to avoid a real paid-API attempt |
| `wasm_gallery_*` mutators, `business_pod_*` | **UNTESTED** | — |

**This tail (~120-150 tools) was not probed.** Treat as unclassified, not as
theater-by-default or real-by-default — the split seen everywhere else in this audit
(e.g. `agentdb_graph-*` real vs. `agentdb_context-synthesize` broken in the *same*
family; `performance_bottleneck` real vs. `performance_metrics` fake in the *same*
family) shows family-level assumptions are unsafe. Verify per-tool before depending on
any of these.

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
- `performance_metrics` — self-labeled `_real:false`. Use `performance_bottleneck`
  instead for the same class of question (it's `_real:true` and genuinely computed).
- Ruflo-native `workflow_execute`/`workflow_run` for anything beyond a single `wait`
  step — the `loop` step type is unimplemented and the `task` step is key-gated; use
  the native Workflow tool.

**New real+useful candidates worth a sanctioning decision (not yet routed anywhere):**
- `claims_board` — cross-session WIP visibility; candidate input for t-2727's WIP-cap
  decision (concurrent sessions are already observable, just not surfaced).
- `hooks_intelligence_unified-stats` — good diagnostic for AgentDB-bridge-health
  drift; candidate for `brana doctor` or a periodic health check.
- `github_repo_analyze`, `transfer_detect-pii`, `http_fetch`,
  `memory_search_unified` — genuinely useful, no current call site. Low priority;
  file as adoption candidates only if a concrete use case appears (per
  work-preferences.md simplicity guidance — don't wire in speculative capability).

**No change needed:** `testgen_tdd_repair` (already sanctioned), `browser_*` (already
real+useful), `hooks_codemod`/`hooks_model-verify` (already real, already cited in
gap-analysis), `terminal_execute` (already absent from the tool surface / denied in
settings, t-2755), `wasm_agent_prompt` (already blacklisted).

---

## 8. What this doc does not settle

- The long tail in §6 (~120-150 tools) remains unclassified. If a future task wants to
  use one of them, verify it live first — do not assume real or theater from this doc.
- Whether to activate the ADR-324 policy/receipt subsystem (`policy_*`) is a separate
  decision, not made here — flagging its existence and current idle state is in scope
  for an audit, adopting it is not.
- The graph-content-is-junk problem (`agentdb_graph-*`/`causal-edge` machinery is real
  but nothing produces meaningful edges) is unchanged from the gap-analysis finding — a
  producer would need to exist before a consumer is worth building; out of scope here.
