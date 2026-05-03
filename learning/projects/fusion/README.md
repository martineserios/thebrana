# Fusion — SenseLedger Integration

This folder is where the four tracks meet. It is deliberately sparse at
the start — you only add files here when a track produces something that
belongs across boundaries.

See `learning/roadmaps/05-fusion-project.md` for the architectural spec
this folder implements.

## What lives here

```
fusion/
├── README.md                 ← you are here
├── architecture.md           ← copy of the spec + live deltas as you learn
├── contracts/                ← copies of data contracts (symlinks or copies)
├── deployments/              ← address books, rpc urls, cluster manifests references
└── runbook.md                ← "how to bring SenseLedger up from nothing"
```

## Start condition

Before you touch this folder, you should have at least:

- A running `kind` cluster with the ingest API stub (k8s scenario 1 — C1)
- A mobile app that can post readings (mobile scenario 4 — C2)

Until then, the per-track folders are enough.

## Integration checkpoints (from the spec)

Track your progress here — tick them as you hit them:

- [ ] **C1**: Ingest stub running on `kind`
- [ ] **C2**: Mobile posts readings successfully
- [ ] **C3**: Aggregates landing in Timescale
- [ ] **C4**: SenseToken live on Sepolia
- [ ] **C5**: Merkle-root claims working end-to-end
- [ ] **C6**: DAO proposal executed, changing backend behavior
- [ ] **C7**: Hardened, GitOps'd, observed

When you tick a box, write a short note below about what surprised you.

## Notes (append-only)

_empty — fill as you go_
