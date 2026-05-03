# Data Engineering — SenseLedger Hands-On

Scaffold for the data-engineering roadmap. Everything here runs locally via
`docker compose` until scenario 8, where you port to a managed cluster.

## What's here

```
data-engineering/
├── README.md                  ← you are here
├── docker-compose.yml         ← Redpanda + schema-registry + MinIO + Postgres + Timescale + Jaeger
├── .env.example               ← non-secret defaults (copy to .env)
├── scenarios/
│   ├── 01-batch-etl/          ← JSONL → Parquet → DuckDB + dbt
│   ├── 02-orchestration/      ← Dagster/Prefect DAG with backfill
│   ├── 03-streaming/          ← Redpanda producer + Flink/Spark consumer
│   ├── 04-cdc/                ← Debezium → Redpanda
│   ├── 05-lakehouse/          ← Iceberg/Delta on MinIO
│   ├── 06-data-quality/       ← Great Expectations / Soda + OpenLineage
│   └── 07-observability/      ← SLOs + dashboards
├── contracts/                 ← data contracts (schema, SLA, owner, consumers)
│   └── senseledger.readings.v1.yaml
├── generators/                ← synthetic data generators (fake readings)
│   └── README.md
└── cost-model.md              ← filled in at scenario 8
```

## Prerequisites

- Docker + Compose v2
- Python 3.11+ and `uv` (or `pip`/`poetry`) for local scripts
- One stream processor of your choice: Flink (`flink-kubernetes-operator` if in k8s, or Docker for local) or Spark
- dbt-core + dbt-duckdb (or dbt-postgres if you prefer)
- Dagster or Prefect — pick one. The rest of the docs assume **Dagster**.

## Quickstart

```bash
# 1. Copy env, edit if needed
cp .env.example .env

# 2. Bring up the stack
docker compose up -d

# 3. Verify
docker compose ps
docker compose logs -f redpanda
```

Stack endpoints (defaults):

| Service | URL | Notes |
|---|---|---|
| Redpanda admin | http://localhost:9644 | `rpk` CLI works against this |
| Redpanda broker | localhost:19092 | for producers/consumers |
| Schema Registry | http://localhost:18081 | JSON Schema / Avro |
| MinIO console | http://localhost:9001 | user: `minioadmin` / pass: `minioadmin` |
| Postgres (operational) | localhost:5432 | `senseledger` / `senseledger` |
| TimescaleDB (analytical) | localhost:5433 | `senseledger` / `senseledger` |
| Jaeger UI | http://localhost:16686 | for OTel traces |

## Scenario layout

Each scenario folder contains its own `README.md` with:

1. **Goal** — one sentence.
2. **What's new** — which services get added, which code lives where.
3. **Run** — the commands, in order.
4. **Exit criteria** — how you know it's done.
5. **Journal** — free-form notes you fill in as you go.

Scenarios build on each other. Don't jump ahead without finishing the previous
scenario's exit criteria.

## Conventions

- **Schemas are versioned.** `senseledger.readings.v1` is the first; breaking
  changes mean a new `v2`, not a silent change.
- **Contracts live in `contracts/`.** Every topic or table that crosses a
  boundary has a contract file.
- **No production secrets.** Everything is local, throwaway, MinIO-style.
  Even when you port to the cloud (scenario 8), use cheap buckets, not prod data.
- **Idempotency is the test.** Any scenario that can't be re-run safely isn't done.

## Where this feeds the fusion project

- `contracts/` goes straight into `projects/fusion/contracts/` when you wire
  the pipeline to the real mobile-app ingestion.
- The stream processor from scenario 3 is the same binary that runs as a
  `Deployment` on k8s (scenario 5 of the k8s roadmap needs it for KEDA autoscaling).
- The reward-computation job (hourly merkle root) from the blockchain roadmap
  is a CronJob that reads from the marts built in scenarios 2 and 5.
