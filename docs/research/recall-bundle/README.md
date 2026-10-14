# Recall bundle evaluation data (t-3515)

Frozen gold set and pre-registered gates for the recall bundle (ADR-099, epic t-3513).

| File | What it is |
|---|---|
| [gates-v1.md](gates-v1.md) | Pre-registered thresholds and the measured baseline |
| [gold-v1.jsonl](gold-v1.jsonl) | One line per task: query (subject + tags), set (`pointed` or `read`), gold note slugs |
| [labels-v1.tsv](labels-v1.tsv) | Every mined task→note pair with its label and the reason |
| [mine_pairs_v2.py](mine_pairs_v2.py) | Miner: finds memory-note slugs in completed tasks, per field, with a quoted window |
| [build_gold.py](build_gold.py) | Builds gold-v1.jsonl from the labels |
| [score_baseline.py](score_baseline.py) | Scores a `brana recall`-compatible command against the gold set |

## How the gold set was made (2026-10-14)

1. **Export:** `brana backlog query --status completed --output json` (1,969 completed tasks on 2026-10-14; the
   export itself is not committed).
2. **Mine:** `mine_pairs_v2.py` matched note slugs (≥ 18 characters, dated suffix and type prefix
   stripped) in each task's description, context and notes. Scope: the thebrana project memory and
   global `~/.claude/memory/`, top level only, so client notes and `archive*/` never enter (ADR-095,
   ADR-099 §2). Result: 144 hits, 130 task-note pairs, 104 tasks.
   - Fixed from v1 (`docs/ideas/ruvector-integration-options/scripts/mine_pairs.py`): per-field
     hits, quoted windows, scope restriction, note dates, and no dependency on a deleted job export.
3. **Label:** each pair was labelled from its quoted window by Claude:

   | Label | Meaning | Pairs |
   |---|---|---|
   | `pointed` | the ticket cited the note when written (description, or context written at or before start) | 49 |
   | `wrote` | the task created or updated the note | 45 |
   | `subject` | the note is what the task works on (memory tidy, leak fix, stale claim) | 14 |
   | `doc-collision` | the match was a docs/ file with the same slug | 14 |
   | `read` | the worker used the note during the work and the ticket had not pointed to it | 6 |
   | `unclear` | read and wrote cannot be told apart | 2 |

4. **Spot-check:** the owner reviewed a seeded random sample of 10 labels (seed 3515: pairs 5, 17,
   26, 27, 54, 80, 89, 104, 123, 126) one by one and agreed with all 10 (threshold: at most 2
   disagreements).

## Findings from building it

- **History cannot supply a "read" gold set.** Only 6 pairs show a note used during work that the
  ticket had not already named; most citations are pointers written into the ticket, or notes the
  task itself wrote.
- **v1's citation counts were inflated by two classes it could not see:** authorship (`wrote`, 45)
  and slug collisions with docs files (`doc-collision`, 14, mostly `brana-v2-compute-model` and
  `loop-native-redesign`).
- **Note dates are weak.** 85 of 144 hits had only a file modification time, which moves on every
  edit, so dates could not filter pairs. `pointed` needs no date: the ticket citing the note proves
  it existed.
- **The recall baseline is noisy and partly degraded** (see gates-v1.md): runs differ by about one
  task in 43, and in Claude Code sessions the vector leg is dropped at its deadline because ruflo is
  located by sourcing a shell script on every call.

## Reproducing

```bash
D=docs/research/recall-bundle
brana backlog query --status completed --output json > /tmp/completed.json
python3 -I $D/mine_pairs_v2.py /tmp/completed.json > /tmp/candidates.jsonl
python3 -I $D/build_gold.py $D/labels-v1.tsv /tmp/completed.json > /tmp/gold.jsonl   # equals gold-v1.jsonl
python3 -I $D/score_baseline.py $D/gold-v1.jsonl "$(command -v brana)" /tmp/per-task.jsonl
```

Labels are not reproducible by script; they are the frozen human-reviewed input.
