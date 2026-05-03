# Data Engineering Roadmap

> Intermediate, scenario-driven. Assumes SQL, basic Python, comfort with Docker. Goal: ship a production-shaped pipeline for SenseLedger covering batch ETL, streaming, and a small lakehouse — with tests, SLAs, and observability.

## Mental model first

Data engineering is not "writing ETL scripts." It's running a reliable system that turns raw events into trusted, queryable state. Keep these framings front and center:

1. **Pipelines are services.** Treat them like services — SLOs, runbooks, on-call, version control, CI.
2. **Idempotency or bust.** Any pipeline step that can't be re-run safely is a future 3am incident.
3. **Batch and streaming are the same thing at different windows.** The patterns (watermarks, late arrivals, deduplication, backfill) are shared. Learn one deeply, the other is ~70% free.
4. **The hardest part is contracts.** Schemas, semantics, ownership, backfills, breaking changes. Tools are easy. Contracts are political.
5. **Observe the data, not just the jobs.** Green job + wrong data = silent failure. Data quality is a first-class metric.

## Core surface area

You should be fluent with:

| Area | What to know |
|------|--------------|
| Storage formats | Parquet (why columnar, what stats it stores), Avro/JSON for streams, partitioning strategies |
| Table formats | Iceberg vs Delta vs Hudi — ACID on object storage, schema evolution, time travel |
| Query engines | DuckDB (local/embedded), Trino/Starburst (federation), ClickHouse (OLAP), BigQuery/Snowflake (warehouse) |
| Stream processing | Kafka / Redpanda, consumer groups, exactly-once, schema registry, compaction, tiered storage |
| Stream frameworks | Flink or Spark Structured Streaming (choose one), ksqlDB or Materialize for SQL-on-streams |
| Orchestration | Airflow (old guard), Dagster or Prefect (modern). Understand DAGs, sensors, backfills, retries. |
| Transform | dbt — models, tests, exposures, sources, freshness. You will write a lot of these. |
| CDC | Debezium or native engines (Postgres logical replication, MySQL binlog) |
| Data quality | Great Expectations, Soda, dbt tests, Elementary |
| Lineage / catalog | OpenLineage, Marquez, Datahub, Unity Catalog (if on Databricks) |

## Scenarios

### Scenario 1 — Batch ETL, Parquet, DuckDB (the "hello world")

Get the end-to-end shape right before touching anything distributed.

- Generate fake SenseLedger readings (1M rows, 24 hours, 500 devices) in JSON Lines.
- Build a small Python pipeline: read JSONL → validate schema → clean/normalize → write Parquet partitioned by `date=/device_type=`.
- Load the Parquet set into DuckDB. Write SQL answering: "What's the hourly p95 sound level for device type A over the last 24h?"
- Wrap it in dbt: one staging model, one intermediate, one mart. Add tests (`not_null`, `unique`, `accepted_values`).
- **Exit criteria**: `dbt build` runs green; DuckDB query answers the question in < 1s.

### Scenario 2 — Orchestration and backfills

- Move the Scenario 1 pipeline behind an orchestrator (Dagster or Prefect — pick one and stick with it for the whole roadmap).
- Make it scheduled hourly.
- Introduce a late-arrival: some device sends yesterday's data today. Handle it with a partitioned asset that's idempotent on re-run.
- Simulate a 7-day outage and backfill. Watch how your orchestrator handles it.
- **Exit criteria**: You can backfill any 24h window independently and get deterministic output; late events end up in the right partition.

### Scenario 3 — Streaming ingestion with Redpanda

- Replace the JSONL generator with a producer that writes to a Redpanda topic (`senseledger.readings.v1`).
- Register the schema in the schema registry (Avro or JSON Schema).
- Write a stream processor (Flink or Spark Structured Streaming) that:
  - Parses + validates the event,
  - Drops duplicates on `(device_id, sensor_id, event_time)` within a 2-hour window,
  - Aggregates into 1-minute tumbling windows per device.
- Sink aggregates into TimescaleDB (hypertable on `minute`).
- **Exit criteria**: Producer at 5k events/sec, no duplicates in the sink, watermark lag visible in a dashboard.

### Scenario 4 — CDC from an operational database

- Imagine SenseLedger has a "station registry" in Postgres (stations table with metadata).
- Set up Debezium → Redpanda to stream all changes out of Postgres as CDC events.
- Join the CDC stream against the readings stream so every reading is enriched with current station metadata (stream-to-stream lookup, or broadcast the dimension).
- **Exit criteria**: Update a station row in Postgres; within seconds, new readings in the pipeline reflect the updated metadata.

### Scenario 5 — The lakehouse slice

- Add an object store (MinIO locally, S3/GCS in cloud).
- Write the aggregated stream output to an Iceberg table (or Delta, your choice — commit to one).
- Query the Iceberg table from DuckDB *and* from Trino. Same data, two engines.
- Exercise schema evolution: add a new column `noise_source`, backfill it for recent data, make sure readers still work.
- Exercise time travel: "what did this table look like 1 hour ago?"
- **Exit criteria**: ACID table on object storage, queryable from two engines, schema evolved without breaking consumers.

### Scenario 6 — Data quality and contracts

- Add Great Expectations (or Soda) suites to every boundary: landing, cleaned, aggregated, marts.
- Enforce: value ranges, null rates, row count deltas, schema drift.
- Publish an OpenLineage event stream from the orchestrator; view it in Marquez.
- Define an explicit contract for the `senseledger.readings.v1` topic: schema, SLAs (freshness, completeness), owner, consumers. Put it in `learning/projects/data-engineering/contracts/`.
- **Exit criteria**: A failing data-quality check halts the downstream pipeline and notifies you. A schema change without a contract bump is blocked in CI.

### Scenario 7 — Observability and SLOs

- Define SLOs for the pipeline:
  - Freshness: "aggregates are at most 2 minutes behind real-time, 99% of the time"
  - Completeness: "≥ 99.5% of expected devices reporting per 5-min window"
  - Correctness: "zero duplicate (device, sensor, event_time) rows in the mart"
- Wire Prometheus metrics out of the orchestrator and stream processor.
- Build a Grafana dashboard that shows error budget burn for each SLO.
- **Exit criteria**: You can answer "are we meeting our SLOs this week?" in one glance.

### Scenario 8 — Cost and scale

- Benchmark: how many events/sec can a single consumer handle? Where's the bottleneck (network, serde, sink)?
- Scale horizontally: partition the topic, scale the consumer group, verify ordering assumptions still hold.
- Measure: storage cost per million events (raw JSONL vs Parquet vs Iceberg), query cost per query.
- Write a one-page "cost model" doc for SenseLedger in `projects/data-engineering/cost-model.md`.
- **Exit criteria**: You can predict the monthly bill for 10x, 100x growth within ~30% accuracy.

## Where this feeds SenseLedger

| Data eng deliverable | SenseLedger piece |
|----------------------|-------------------|
| Scenario 1 | Offline analysis of historical readings |
| Scenario 3 | Real-time ingestion path behind the ingest API |
| Scenario 4 | Station metadata always fresh in the pipeline |
| Scenario 5 | Canonical, versioned history of all readings (audit + replays) |
| Scenario 6 | Data contracts that the wallet bridge trusts when attesting on-chain |
| Scenario 7 | SLO dashboards alongside k8s dashboards |

## Resources

- *Designing Data-Intensive Applications* (Kleppmann) — the canonical text. If you haven't read it, read it.
- `duckdb.org/docs`
- `iceberg.apache.org` (or `delta.io`)
- `debezium.io/documentation`
- `docs.getdbt.com`
- `dagster.io/docs` or `docs.prefect.io`
- `flink.apache.org/docs` or `spark.apache.org/docs/latest/structured-streaming-programming-guide.html`
- `openlineage.io`

## Anti-patterns to avoid

- Orchestrators doing transforms. Airflow/Dagster should orchestrate — the compute lives in dbt/Spark/SQL.
- Mixing operational and analytical state in the same Postgres. OLTP and OLAP have different futures.
- "We'll add tests later." You won't. Write tests with the first model.
- Home-rolled dedup by reading the whole table back. Use watermarks + state stores, or use Iceberg `MERGE`.
- CSV as an interchange format. Parquet, Avro, or JSON Lines — never CSV past ingestion.
- Assuming event time == processing time. It never does.

## Done when

- SenseLedger has a pipeline from device → ingest → stream → aggregate → lakehouse → mart, with SLOs, data quality gates, and lineage.
- You can answer: "how do I backfill 3 days?", "how do I add a new metric?", "how do I evolve the schema without breaking downstream?" — without thinking hard.
- You have a cost model you trust.
