# Synthetic data generators

Placeholder for the synthetic reading generators used across scenarios.

Put each generator in its own subfolder with a `pyproject.toml` (or plain
`requirements.txt`) and a `README.md` describing:

- What it produces
- How much (rows / events / second)
- Parameters (device count, distribution, anomaly injection)
- Where it writes to (JSONL file, Redpanda topic, Postgres table, etc.)

Suggested first generator: `batch-jsonl/` — writes N days of synthetic
readings for M devices into a JSONL file. Used by scenarios 1 and 2.

Second generator: `stream-redpanda/` — a live producer that writes at a
configurable rate to the `senseledger.readings.v1` topic. Used by scenario 3+.

Keep generators deterministic via seeds — you want reproducible runs.
