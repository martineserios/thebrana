# Session-Aware Loop Integration for Brana

> **Superseded by [Brana Operating Model](brana-operating-model.md).** This doc is preserved for historical context.

> **Watcher scope superseded by [ADR-050](../architecture/decisions/ADR-050-loop-request-protocol.md).** The auto-spawn and session-config layers (Phases 1–3 below) were reconsidered in 2026-06 and replaced with a minimal suggest-and-confirm protocol. See ADR-050 for the rationale and the implemented surfaces (build.md + close.md).

> Brainstormed 2026-03-30. Status: idea.

## Problem

Brana workflows are one-shot — skills execute and return, hooks fire once. Users must manually set up recurring checks (`/loop`) every session. No session awareness means useful watchers (test status, uncommitted changes, task sync) require manual invocation each time.

## Proposed solution

Three-layer loop integration:

1. **Auto-spawning session loops** — A `session-loops.json` config per project defines loops that start on session open and stop on session close. Session-start hook reads the config and spawns loops via CronCreate.
2. **Standalone `/brana:watch`** — A skill for ad-hoc brana-aware recurring checks with presets (test watcher, commit watcher, task sync, drift detector).
3. **Skill embedding (future)** — When CC opens CronCreate to skills, build → auto-start test watcher, review → auto-start drift watcher. Deferred until the platform constraint is lifted.

### Config example (`session-loops.json`)

```json
{
  "loops": [
    {
      "name": "uncommitted-changes",
      "interval": "10m",
      "prompt": "check git status and report any uncommitted changes",
      "silent": true
    },
    {
      "name": "test-watcher",
      "interval": "15m",
      "prompt": "run cargo test --quiet and report failures only",
      "silent": true,
      "when": "branch:feat/*"
    }
  ]
}
```

The `silent: true` flag means no output unless something needs attention. The `when` field allows conditional activation based on branch pattern, project type, or active skill.

## Research findings

- CronCreate is available within skill procedures (constraint dissolved — confirmed CC v2.1.87+, skill procedures run in main context, empirically tested 2026-06-09). See ADR-050 §Context.
- t-705 (loop provider) already exists in the backlog, blocked by t-703 (provider abstraction)
- Session hooks (start/end) are shipped and extensible — natural spawn/kill points
- No watch patterns exist in any brana skill — greenfield opportunity
- `/loop` validated in t-702 — CronCreate works, session-only, 7-day auto-expiry

## Risks

- **Invisible magic** → Mitigated by opt-in config file (`session-loops.json`). Users author it explicitly.
- ~~**CronCreate skill restriction** → Hooks-only now.~~ Constraint dissolved (see E2026-06-10-1 / ADR-050). Skill embedding is now unblocked.
- **Short session utility** → Value comes from usefulness per fire, not frequency. Even 1 fire is enough.
- **Loop noise** → Default to silent mode. Only surface output when something needs attention.
- **Config drift** → Config is per-project, version-controlled. No hidden global state.

## Phased rollout

### Phase 1 — Config + hooks
- Define `session-loops.json` schema
- Extend `session-start.sh` to read config, spawn loops via CronCreate
- Extend `session-end.sh` to clean up (CronDelete active loops)
- Ship with 2-3 default presets (uncommitted changes, test watcher)

### Phase 2 — `/brana:watch` skill
- Standalone skill for ad-hoc watches
- Brana-aware presets: test, commit, drift, task-sync
- Custom watch from user prompt
- Integrates with CronCreate, shows active watches

### Phase 3 — Skill embedding
- ~~Depends on CC opening CronCreate to skills~~ — constraint dissolved (E2026-06-10-1). Unblocked.
- `/brana:build` auto-starts test watcher on BUILD step
- `/brana:review` auto-starts drift watcher
- Skills declare loop specs in frontmatter, main context fulfills

## Next steps

1. Unblock t-703 (provider abstraction) → unblocks t-705 (loop provider)
2. Design `session-loops.json` schema
3. Prototype session-start hook loop spawning
4. Test with 2 default presets across a few sessions
