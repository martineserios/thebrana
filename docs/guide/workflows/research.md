# Research

The `/brana:research` command is the atomic research primitive — takes a topic, follows references, produces structured findings.

## Quick start

```
/brana:research context engineering       — research a topic
/brana:research 14                        — research updates for a specific dimension doc
/brana:research creator:simon-willison    — check a creator's recent output
/brana:research leads                     — process queued research leads
/brana:research registry                  — check source registry health
/brana:research --refresh                 — batch refresh all dimension docs
/brana:research --refresh high            — refresh high-priority docs only
```

## How it works

1. **Source registry** — `research-sources.yaml` tracks trusted sources, creators, and check cadences
2. **Phase 1 (wide scan)** — parallel scouts search the web for updates (metadata only)
3. **Phase 2 (triage)** — findings ranked by severity and relevance
4. **Phase 3 (deep dive)** — targeted deep reads on high-priority findings
5. **Output** — structured report with tagged findings: `[NEW]`, `[UPDATE]`, `[VERSION]`, `[STALE]`

## With NotebookLM

```
/brana:research context engineering --nlm
```

Queries NotebookLM notebooks for prior knowledge before web research. Uses specific technical nouns as query anchors to avoid generic responses.

## Batch refresh (`--refresh`)

Refreshes dimension docs in `brana-knowledge/dimensions/` by launching parallel scout agents grouped by topic. Scopes: `all`, `high`, `medium`, `low`, `venture`, or a specific doc number.

## Tips

- Always read project docs first — web research builds on what docs decided
- Research findings are auto-stored with low confidence (0.3) and 30-day TTL
- Findings that survive into a spec get promoted to 0.6 confidence
- The registry tracks what was checked and when — prevents redundant research
