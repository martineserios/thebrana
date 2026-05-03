# Scenario 1 — Batch ETL, Parquet, DuckDB

> The hello-world of this roadmap. Get the end-to-end shape right before touching anything distributed.

## Goal

Generate 1M fake SenseLedger readings, write them as partitioned Parquet, load them in DuckDB, build a small dbt project on top, and answer a real question with SQL.

## What you'll add

- `generators/batch-jsonl/` — a deterministic JSONL generator (seed-based).
- `pipelines/batch_etl/` — a single Python script that validates → cleans → writes Parquet partitioned by `date=/sensor_type=`.
- `dbt/senseledger/` — a dbt-duckdb project with `staging`, `intermediate`, and `marts` layers.

## Run

```bash
# 1. Generate data (writes to ./data/raw/*.jsonl)
python generators/batch-jsonl/generate.py --days 1 --devices 500 --seed 42

# 2. Run the pipeline (JSONL → Parquet)
python pipelines/batch_etl/main.py --input ./data/raw --output ./data/curated

# 3. dbt
cd dbt/senseledger
dbt build                   # runs models + tests

# 4. Query in DuckDB
duckdb ./data/warehouse.duckdb
> SELECT hour, percentile_cont(0.95) WITHIN GROUP (ORDER BY value) AS p95
  FROM marts.hourly_sound_dev_a
  WHERE hour >= now() - INTERVAL 1 DAY
  GROUP BY hour ORDER BY hour;
```

## Exit criteria

- [ ] `dbt build` runs green — models + tests.
- [ ] The query above returns in < 1s on a laptop.
- [ ] `pipelines/batch_etl/main.py` is idempotent: running it twice with the same input produces the same output.
- [ ] Parquet files are partitioned on disk as `date=YYYY-MM-DD/sensor_type=X/*.parquet`.
- [ ] You can explain why Parquet is smaller and faster than the JSONL input.

## Journal

_fill in as you go_
