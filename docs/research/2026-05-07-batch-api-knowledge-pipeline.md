# Batch API Integration — Knowledge Pipeline Tier 1

**Task:** t-1229  
**Date:** 2026-05-07  
**Verdict:** Feasible. Low risk. 1–2 day implementation. Blocked only by `ANTHROPIC_API_KEY` env var.

---

## Current State

Tier 1 calls `call_claude_json()` which shells out to the `claude` CLI binary one URL at a time:

```
for each unprocessed URL:
    claude --print --output-format json "<tier1 prompt>"  # 60s timeout
    update state
```

- Sequential, blocking, ~2–5s per URL on a warm session
- No Anthropic API key in the Rust code — all auth goes through the CLI's session
- `ureq` is already in `brana-core`'s `Cargo.toml` — no new HTTP dep needed

---

## Batch API Facts

| Property | Value |
|---|---|
| Endpoint | `POST https://api.anthropic.com/v1/messages/batches` |
| Beta header | `anthropic-beta: message-batches-2024-09-24` |
| Max per batch | 100,000 requests / 256 MB |
| Processing window | Up to 24h; typical for <500 requests: minutes |
| Cost | 50% discount on both input and output tokens |
| Rate limits | Separate, more generous than standard API |
| Streaming | Not supported (irrelevant — current pipeline never streams) |

**Request shape:**
```json
{
  "requests": [
    {
      "custom_id": "url-abc123",
      "params": {
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 256,
        "messages": [{ "role": "user", "content": "<tier1 prompt>" }]
      }
    }
  ]
}
```

**Poll:** `GET /v1/messages/batches/{id}` → `processing_status: "in_progress" | "ended"`

**Results:** `GET /v1/messages/batches/{id}/results` → JSONL:
```json
{"custom_id": "url-abc123", "result": {"type": "succeeded", "message": {"content": [...]}}}
{"custom_id": "url-def456", "result": {"type": "errored", "error": {...}}}
```

---

## custom_id Strategy

URLs are too long for the 64-char limit. Two options:

**Option A (recommended):** SHA-256 of the URL, hex-encoded, truncated to 40 chars.
- Deterministic: same URL → same id across retries
- No collision in practice for typical pipeline sizes

**Option B:** Batch-local incrementing index (`"req-0"`, `"req-1"`, …), correlate via array position.
- Simpler but breaks if batch is resubmitted with a different URL order

Use Option A. Store the `url → custom_id` mapping in memory during the batch run (not persisted).

---

## Polling Pattern

Since `brana ops knowledge tier1` is a CLI command (blocking from user's perspective), polling is synchronous:

```
submit → store batch_id in PipelineState → poll with exponential backoff → retrieve results
```

**Backoff schedule:** 5s → 10s → 20s → 30s → 60s, then 60s intervals. Max configurable (default 300s for interactive, no limit for scheduler).

**Interrupt handling:** If the process is killed mid-poll, `pending_batch_id` in `PipelineState` persists. On next run, check for a pending batch before submitting a new one — retrieve its results if `ended`, re-poll if still `in_progress`.

---

## Architecture Changes

### New fields on `PipelineState`

```rust
pub struct PipelineState {
    // existing ...
    /// In-flight or completed Batch API request ID, if any.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_batch_id: Option<String>,
    /// Timestamp when pending_batch_id was submitted (ISO 8601).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub batch_submitted_at: Option<String>,
}
```

### New functions in `knowledge_pipeline.rs`

```rust
/// Build a tier1 batch request body for the given URL entries.
pub fn build_tier1_batch_body(
    entries: &[UrlEventEntry],
    dimension_slugs: &[String],
) -> serde_json::Value

/// Submit a tier1 batch to the Anthropic Batch API.
/// Returns the batch ID.
pub fn submit_tier1_batch(
    entries: &[UrlEventEntry],
    dimension_slugs: &[String],
    api_key: &str,
) -> Result<String>

/// Poll until the batch reaches `ended` status or timeout is exceeded.
pub fn poll_batch_until_done(
    batch_id: &str,
    api_key: &str,
    timeout: std::time::Duration,
) -> Result<()>

/// Retrieve and parse batch results. Returns (url, score, reason) triples.
pub fn retrieve_tier1_batch_results(
    batch_id: &str,
    api_key: &str,
    custom_id_to_url: &HashMap<String, String>,
) -> Result<Vec<Tier1Result>>
```

### `call_claude_json()` stays unchanged

Tier 2 and Tier 3 are lower volume and often interactive — keep on sequential CLI shell-out for now.

---

## Prompting — No Changes Needed

The current Tier 1 JSON prompt works identically in the Batch API. The model receives the same message; the only difference is delivery mechanism. No streaming loss because the current pipeline never uses streaming.

---

## API Key

The pipeline currently has no `ANTHROPIC_API_KEY` dependency (CLI shell-out bypasses it). Batch API requires direct HTTP with the key.

**Resolution:** Read `ANTHROPIC_API_KEY` from env (or `~/.config/brana/anthropic.env` as fallback). Document in CLAUDE.md. The `validate.sh` check for `ANTHROPIC_API_KEY` should warn if unset when the user runs `brana ops knowledge tier1`.

---

## Error Handling

| Error type | Handling |
|---|---|
| `errored` result for a URL | Log warning, mark URL as `Tier1Error` (new status), continue |
| Network error during submit | Bubble up, leave state clean (no partial batch_id written) |
| Network error during poll | Retry with backoff; batch_id persisted, safe to resume |
| Batch expired (>24h) | Detect via `processing_status: "ended"` + `request_counts.errored == total`; re-submit |
| API key missing | Pre-flight error before any network call |

---

## Cost Estimate

Tier 1 processes ~50–200 URLs per run. Each prompt is ~500 tokens input, response ~100 tokens.

| Scenario | Current cost (Haiku) | Batch cost | Saving |
|---|---|---|---|
| 50 URLs | $0.0032 | $0.0016 | $0.0016 |
| 200 URLs | $0.0128 | $0.0064 | $0.0064 |

Cost savings per run are small. The value is: (1) faster wall-clock time (all URLs scored in parallel, not serially), and (2) the 50% discount scales as the pipeline grows.

---

## Implementation Plan

1. **Spec stub** — `knowledge_pipeline_batch.spec.md` (this doc satisfies it)
2. **Failing tests** — batch body construction, custom_id hashing, result parsing
3. **Implementation** — `submit_tier1_batch`, `poll_batch_until_done`, `retrieve_tier1_batch_results`
4. **Wire into CLI** — `brana ops knowledge tier1` checks for pending batch, submits if none
5. **Docs** — update `inbox-to-dimensions-pipeline.md` §LLM-calls section

**Estimated effort:** M (1–2 days). No new crate dependencies.

---

## Verdict

Proceed. High feasibility, clean fit with existing state machine, no prompting changes, ureq already present. The single prerequisite is documenting `ANTHROPIC_API_KEY` as a required env var for the knowledge pipeline commands. Tracks to t-1225 for implementation.
