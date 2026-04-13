# Context Budget

CC's hard-coded context thresholds. Reference these constants when designing skills, hooks, or session management behavior.

Source: CC v2.1.89 leak analysis via Zain Hasan blog (ccunpacked.dev), 2026-04-08.

---

## Constants

```
effectiveWindow     = modelContextWindow − 20K  (reserve for compaction calls)
autocompact trigger = effectiveWindow − 13K
warning threshold   = effectiveWindow − 20K

session_memory init     = 8K tokens
session_memory refresh  = every 15K tokens
SM-Compact preserves    = 10K–40K tokens
SM-Compact min messages = 5 text-block messages
```

For 200K context (Claude Sonnet/Opus standard):
```
effectiveWindow     ≈ 180K
autocompact trigger ≈ 167K  (~93% full)
warning threshold   ≈ 160K  (~89% full)
```

For 1M context (current brana default):
```
effectiveWindow     ≈ 980K
autocompact trigger ≈ 967K
warning threshold   ≈ 960K
```

On 1M context, autocompact is rarely triggered in practice.

---

## Brana's Current Coverage

| Signal | Mechanism | Threshold |
|--------|-----------|-----------|
| Visual nudge | Statusline turns orange | 55% of context used |
| Close reminder | `/brana:close` (manual) | User-initiated |
| Autocompact | CC native | ~93% (model-dependent) |

The 55% statusline catches context growth well before CC's autocompact fires.

---

## Design Rule

**Invoke `/brana:close` before autocompact, not after.**

CC's own recommendation: context resets produce cleaner handoffs than mid-compaction state. Brana's close procedure extracts session state and writes a handoff note — if compaction fires during close, that work is lost.

Practical guidance: invoke `/brana:close` when the statusline hits orange (55%) on long sessions, or before any `/brana:build` run that could push context deep.

See [agent loop doc](../reflections/33-agent-loop.md) §Step 3 for where compaction fits in the execution model.
