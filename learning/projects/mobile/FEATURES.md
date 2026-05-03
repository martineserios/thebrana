# Feature Slices

Each row maps a roadmap scenario to a feature folder in the real project.
Keep this table in sync as you work.

| Scenario | Feature slice | API endpoints | Permissions | Depends on |
|---|---|---|---|---|
| M1 — scaffold | `features/shell` | none | none | — |
| M2 — sensor sampling | `features/sampling` | none (local) | accelerometer, gyroscope, microphone, location | shell |
| M3 — background sampling | `features/sampling` (extended) | none | background execution | sampling |
| M4 — offline sync | `features/sync` | `POST /ingest/v1/readings` | network state | sampling |
| M5 — wallet | `features/wallet` | `GET /query/v1/balance/:addr` + RPC | none | shell |
| M6 — DAO voting | `features/dao` | `GET /query/v1/proposals`, RPC | none | wallet |
| M7 — observability | cross-cutting | (Sentry DSN) | none | all |
| M8 — release | cross-cutting | none | none | all |

## Dependency graph

```
shell ─┬─▶ sampling ─┬─▶ sync
       │             └─▶ background-extension
       ├─▶ wallet ────────▶ dao
       └─▶ observability (cross-cutting)
```

Ship in this order. Every slice must be independently testable — if a test
for `dao` requires real sampling, the dependency is wrong.
