# Fusion Project — SenseLedger

> The integrating project. Every track's learning delivers a piece of this. This doc is the architectural spec you'll come back to whenever you're not sure where a thing should live.

## Vision

A decentralized community environmental-sensor network, run by the people who contribute data. Participants install a mobile app, passively contribute sensor readings (sound, motion, approximate location, and optionally air quality from paired BLE sensors), and get rewarded with the SENSE token for verified contributions. A DAO of SENSE holders governs the validation rules, reward rates, and treasury.

**Non-goals**: this is a learning lab. It's testnet only. No real PII is collected. No production SLAs. No real money.

## Why this is a good learning fusion

Each of the four tracks has a load-bearing job. None of them are decoration.

- **Mobile** is where the data comes from. Without it, there's nothing to learn.
- **Data engineering** is how raw readings become trustworthy state. Without it, the chain has nothing to reward.
- **Kubernetes** is how the backend actually runs, observably, safely, and reproducibly.
- **Blockchain** is what makes the economic loop credible — reward distribution and governance can't be a centralized database without undermining the whole premise.

Remove any one and the project collapses. That's the test of a good fusion project.

## System architecture

```
┌─────────────────────┐                                  ┌──────────────────────┐
│                     │                                  │                      │
│   Mobile app        │                                  │     Ethereum         │
│   (Flutter / RN)    │                                  │     (Sepolia)        │
│                     │                                  │                      │
│ - onboarding        │         HTTPS / gRPC             │  SenseToken (ERC20)  │
│ - sensor sampling   │ ──────────────────────────────▶  │  StationNFT (ERC721) │
│ - offline queue     │                                  │  RewardDistributor   │
│ - wallet / DAO UI   │ ◀──── WalletConnect / RPC ─────▶ │  SenseDAO + Timelock │
│                     │                                  │                      │
└────────┬────────────┘                                  └──────────┬───────────┘
         │                                                          ▲
         │                                                          │
         │ POST /ingest                                              │ merkle roots,
         │                                                          │ station mints,
         ▼                                                          │ DAO events
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Kubernetes cluster                                │
│                                                                                │
│  ┌────────────┐   ┌──────────────┐   ┌────────────┐   ┌─────────────────┐    │
│  │ ingest API │──▶│  Redpanda /  │──▶│  stream    │──▶│ TimescaleDB     │    │
│  │ (FastAPI)  │   │  Kafka       │   │  worker    │   │ (aggregates)    │    │
│  │            │   │              │   │ (Flink/    │   │                 │    │
│  └────────────┘   └──────────────┘   │  Spark)    │   └─────────────────┘    │
│                                       │            │            │             │
│                                       │            │            ▼             │
│                                       │            │   ┌─────────────────┐    │
│                                       │            │   │ Iceberg lake    │    │
│                                       │            │   │ (MinIO / S3)    │    │
│                                       │            │   └─────────────────┘    │
│                                       │            │            │             │
│                                       │            │            ▼             │
│                                       │            │   ┌─────────────────┐    │
│                                       │            └──▶│  wallet-bridge  │◀───┼── K8s secrets
│                                       │                │  (posts roots,  │    │
│                                       │                │   mints NFTs,   │    │
│                                       │                │   listens to    │    │
│                                       │                │   DAO events)   │    │
│                                       │                └─────────────────┘    │
│                                       │                                        │
│  ┌────────────┐   ┌──────────────┐   ┌────────────┐   ┌─────────────────┐    │
│  │ query API  │◀──┤  dbt marts   │◀──┤   DAG      │   │  Prom + Loki    │    │
│  │ (GraphQL / │   │  (DuckDB/    │   │ (Dagster   │   │  + Grafana      │    │
│  │  REST)     │   │   Trino)     │   │  /Prefect) │   │  + OTel         │    │
│  └────────────┘   └──────────────┘   └────────────┘   └─────────────────┘    │
│                                                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Bounded contexts

Treat each of these as an owned subsystem. Each has its own data model, its own deploy cadence, and its own failure domain.

### 1. Reading capture (mobile)
- Owns: sensor access, sampling sessions, local SQLite, offline queue, upload.
- Contracts: `POST /ingest/v1/readings` with schema-versioned payload.
- Failures: permissions denied, battery low, offline — all handled gracefully.

### 2. Ingestion (k8s, backend)
- Owns: validation, authentication (device tokens), rate limiting, write to Redpanda topic.
- Contracts: accepts the mobile schema; writes to `senseledger.readings.v1` topic.
- SLO: 99.9% availability, p95 latency < 250ms, zero data loss on ack.

### 3. Stream processing (k8s, backend)
- Owns: parse, dedup, aggregate (1-min windows), enrich with station metadata, write to TimescaleDB and Iceberg.
- Contracts: reads `senseledger.readings.v1`, writes `senseledger.readings_1min.v1` and Iceberg tables.
- SLO: watermark lag < 2 minutes 99% of the time.

### 4. Query / analytics (k8s, backend)
- Owns: dbt marts, query API, rate limiting, caching.
- Contracts: versioned REST/GraphQL endpoints consumed by mobile app and dashboards.
- SLO: p95 query latency < 1s, freshness < 5 minutes.

### 5. Reward computation (k8s, backend)
- Owns: the epoch-based reward math — "given verified readings in the last hour, how many SENSE does each contributor get?"
- Contracts: produces a signed merkle root + the full recipient list per epoch.
- Runs as a `CronJob` every hour. Idempotent on re-run.

### 6. Wallet bridge (k8s, backend)
- Owns: hot wallet, nonce management, submitting txs, listening to chain events.
- Contracts: consumes the reward computation output; posts roots on-chain; mints Station NFTs.
- **Single most security-sensitive service.** Dedicated namespace, hardened, minimal egress.

### 7. On-chain (Ethereum)
- Owns: tokens, rewards, governance, station NFTs.
- Contracts: the ERC interfaces + DAO Governor interface.

### 8. Governance / DAO UI (mobile + on-chain)
- Owns: proposal creation, voting UI, results display.
- Contracts: reads from the SenseDAO Governor and the indexer; writes signed votes.

## Data contracts (the things that will break you if you wing them)

### `senseledger.readings.v1` (Avro / JSON Schema)

```yaml
name: senseledger.readings.v1
fields:
  - event_id:       string (uuid v7)
  - device_id:      string        # hash of device fingerprint
  - station_id:     string?       # optional, if the device is registered
  - sensor_type:    enum [sound, accel, gyro, gps, air_quality]
  - event_time:     long          # epoch ms, from the device's clock
  - ingest_time:    long          # epoch ms, set by the ingest API
  - value:          double | record
  - unit:           string
  - app_version:    string
  - schema_version: int = 1
owner: reading-capture
consumers: [ingestion, stream-processing, wallet-bridge]
sla:
  freshness: 2m
  completeness: 99%
```

### Reward epoch output

```yaml
name: senseledger.reward_epoch.v1
fields:
  - epoch_id:       long
  - window_start:   long
  - window_end:     long
  - recipients:     array[{ address: string, amount: uint256 }]
  - merkle_root:    bytes32
  - signer:         address       # signed by the reward-computation service
  - signature:      bytes
owner: reward-computation
consumers: [wallet-bridge, indexer]
```

## Source of truth rules

1. **Reading data**: TimescaleDB is the operational truth; the Iceberg lake is the historical/analytical truth; the chain has no idea about individual readings.
2. **Rewards**: The chain is the truth. Backend-computed rewards are "proposed"; only when the tx is confirmed and the merkle root is posted do they become official.
3. **Governance**: The chain is the truth, always. The DAO owns the config values that the backend respects. Backend config must reflect chain state, never the other way around.
4. **Station identity**: The chain is the truth. StationNFT ownership is canonical. The backend caches it.

## Security stance (the short version)

- **Mobile**: Keystore/Keychain for secrets. No custom crypto. SSL pinning. No PII beyond device fingerprint (hashed).
- **Backend**: Zero trust — every service auths to every other service with short-lived tokens. Secrets from a proper manager, never in YAML.
- **Wallet bridge**: Hot wallet with MINTER_ROLE only. MINTER_ROLE can be revoked by the DAO. Gas cap. Circuit breaker. Dedicated namespace, hardened PSA, NetworkPolicy egress-only to RPC + K8s API.
- **Contracts**: OZ primitives, no reinvention. Slither clean. Fuzz clean. Timelock on governance. No upgradeability unless explicitly justified per contract.

## Integration checkpoints

These are the moments when progress on one track becomes progress on the fusion project:

| Checkpoint | Requires | Unlocks |
|------------|----------|---------|
| **C1**: Ingest stub running on `kind` | k8s scenario 1 | Mobile can target a real endpoint |
| **C2**: Mobile posts readings successfully | mobile scenario 4, C1 | Stream processor has real data |
| **C3**: Aggregates landing in Timescale | data-eng scenario 3, C2 | Query API can serve real dashboards |
| **C4**: SenseToken on Sepolia | blockchain scenario 1 | Mobile can show a real balance |
| **C5**: Merkle-root claims working end-to-end | blockchain scenario 3, C2–C3 | Real reward loop lives |
| **C6**: DAO proposal executed | blockchain scenario 4, mobile scenario 6 | Governance actually changes backend behavior |
| **C7**: Hardened, GitOps'd, observed | k8s scenarios 6–8 | Project is "done" for learning purposes |

## Deploy topology

- **Repo**: this repo — `learning/projects/fusion/` holds the integration manifests, the Helm/Kustomize overlays, and the wiring docs. Actual service code lives in sibling project folders and is referenced by image.
- **Environments**: `dev` (kind, local only), `staging` (managed k8s + Sepolia), no prod.
- **GitOps**: ArgoCD (or Flux) points at `learning/projects/fusion/overlays/staging/`.
- **Secrets**: External Secrets Operator → your chosen secret manager.

## Open questions (intentional)

These are questions you should answer *during* the project, not before. Writing them down now makes the "ah, that's why" moment more likely.

1. How do you stop a Sybil attack — one user running 50 fake devices?
2. How do you bootstrap DAO voting power without making the initial distribution feel like a rug?
3. How do you handle device clock skew when `event_time` controls reward windows?
4. What's the minimum-viable data quality score for a reading to count for rewards?
5. What happens if the backend goes down for 3 days — can the pipeline catch up without double-paying?
6. How do you detect and punish colluding validators if quality is community-verified?
7. Who pays the gas for mobile users claiming rewards? (Hint: look at meta-transactions / ERC-4337 paymasters.)

## Done when

- An end-to-end demo runs: install the app → register → passively contribute for an hour → see rewards claimable → claim them → vote on a DAO proposal → see the proposal execute → see the backend change its behavior based on the new config.
- Every subsystem has an owner doc, a runbook, and a dashboard.
- You can give a 20-minute walkthrough of the system to a non-expert without hand-waving.

## Where to start

Start at C1 — getting a trivial ingest API running on `kind`. Everything else hangs off that.
