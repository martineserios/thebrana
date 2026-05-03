# Learning — Four Tracks, One Project

> Intermediate-level training across Kubernetes, Data Engineering, Mobile Development, and Blockchain/Ethereum, threaded together by a single fusion project.

## Why this exists

Learning four technologies in isolation produces four collections of tutorials and zero working systems. This folder flips that: you train each skill by building **one** real, integrated project that genuinely needs all four. Every roadmap ends at the same place — a slice of the fusion project you can deploy, run, and point at.

## The fusion project: SenseLedger

A decentralized community environmental sensor network.

- **Citizens** install a mobile app, opt in to contribute passive readings from their phone sensors (sound pressure, motion, approximate location, air-quality from paired BLE sensors).
- **A data engineering pipeline** ingests, validates, deduplicates, aggregates, and serves time-series data.
- **A Kubernetes cluster** hosts the ingestion API, the stream processor, TimescaleDB, observability, and the wallet bridge.
- **Ethereum smart contracts** issue a `SENSE` ERC-20 reward token for verified contributions, mint a `Station` NFT per registered device, and run a DAO that votes on quality thresholds and reward rates.

Each topic has a clear, load-bearing job. None of them are decoration.

```
 ┌─────────────┐   readings    ┌──────────────┐   validated   ┌───────────────┐
 │  Mobile app │ ─────────────▶│  Ingest API  │──────────────▶│ Stream worker │
 │ (Flutter /  │               │  (FastAPI    │               │ (validation,  │
 │  React Nat) │◀── token bal ─│   on k8s)    │               │  enrichment)  │
 └─────┬───────┘               └──────┬───────┘               └──────┬────────┘
       │                              │                              │
       │ wallet, DAO votes            │ audit events                 ▼
       │                              │                      ┌──────────────┐
       ▼                              ▼                      │ TimescaleDB  │
 ┌────────────┐              ┌─────────────────┐             │  (on k8s)    │
 │ Ethereum   │◀── attest ───│  Wallet bridge  │             └──────┬───────┘
 │ (Sepolia)  │              │  (signed merkle │                    │
 │ SenseToken │              │   roots per 1h) │                    ▼
 │ StationNFT │              └─────────────────┘             ┌──────────────┐
 │ SenseDAO   │                                              │   Query API  │
 └────────────┘                                              └──────────────┘
```

## What's in here

```
learning/
├── README.md               ← you are here
├── roadmaps/               ← per-topic training paths (goals, scenarios, milestones)
│   ├── 01-kubernetes.md
│   ├── 02-data-engineering.md
│   ├── 03-mobile-development.md
│   ├── 04-blockchain-ethereum.md
│   └── 05-fusion-project.md
└── projects/               ← hands-on scaffolds you actually work in
    ├── kubernetes/         ← kind cluster + manifests + scenarios
    ├── data-engineering/   ← docker-compose + batch / streaming / lakehouse scenarios
    ├── mobile/             ← mobile starter (framework choice made in roadmap)
    ├── blockchain/         ← hardhat workspace with SENSE token, Station NFT, DAO
    └── fusion/             ← the integrating project (architecture + wiring notes)
```

## How to use it

The 4 topic roadmaps are parallel tracks — you can move on all of them at once, or alternate week by week. The one hard rule: **every learning milestone ships something into `projects/fusion/`**. If it doesn't wire back into SenseLedger, it's a tutorial, not a milestone.

Suggested rhythm (adapt to taste):

| Week | Focus | Output into fusion |
|------|-------|--------------------|
| 1–2 | k8s foundations + local cluster | `kind` cluster running ingest API stub |
| 3–4 | Data eng batch scenario | Parquet → DuckDB query API over a day of readings |
| 5–6 | Mobile onboarding + sensor sampling | App posts readings to the k8s-hosted ingest API |
| 7–8 | Blockchain core contracts | `SenseToken.sol` + `StationNFT.sol` deployed to Sepolia, app reads balance |
| 9–10 | Streaming scenario + wallet bridge | Kafka/Redpanda → merkle roots → on-chain attestation |
| 11–12 | DAO voting + mobile DAO UI | Threshold changes flow from DAO vote → k8s config → validation |

Don't treat the weeks as deadlines — treat them as a DAG of deliverables. The dependencies are what matter.

## Level and assumptions

**Mixed / intermediate** — comfortable with Docker, a backend language or two, basic SQL, git, and the shell. These roadmaps skip fundamentals and go straight to practical patterns, production concerns, and architectural tradeoffs.

What they assume you already know, or will skim elsewhere:

- **k8s**: what a container is, what an image is, `docker compose up`
- **Data**: basic SQL, what a dataframe is, what ETL means at all
- **Mobile**: at least one mobile app installed on your own phone
- **Blockchain**: what a public/private keypair is, you've seen a block explorer

## Tracking in the backlog

Each track has a milestone in the brana backlog under the `personal` stream, with sub-tasks per phase. Use `/brana:backlog` to see current focus, or filter by tag:

```
backlog_query { tags: ["learning"] }
backlog_query { tags: ["learning", "kubernetes"] }
backlog_focus { stream: "personal" }
```

Parent epic: `ph-014` — *Learn four tracks via SenseLedger*.

## Non-goals

- Not a tutorial curriculum. Roadmaps point at *what* to learn and *what to build*, not a click-by-click walkthrough.
- Not a production system. SenseLedger is a learning lab. Testnet only, no real tokens, no real PII.
- Not exhaustive. Each topic is vast — the roadmaps are opinionated and pick the 20% that unlocks 80%.

## See also

- [brana-knowledge/dimensions/22-testing.md](~/enter_thebrana/brana-knowledge/dimensions/22-testing.md) — testing strategy that applies here too
- `/brana:research <topic>` — deeper dive on any sub-topic when you hit a wall
- `/brana:retrospective` — capture what worked and what didn't at each milestone
