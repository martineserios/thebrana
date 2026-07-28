# `brana knowledge process-url` — turn a captured link into knowledge

Captured links pile up faster than they get read. This command takes a URL,
fetches it, extracts a short insight, and stores it in the ruflo `knowledge`
namespace — where `brana recall` can find it.

It runs unattended, which is the point: the intended use is a nightly cron
draining a backlog of link stubs, not one-off manual runs.

## Usage

```bash
brana knowledge process-url https://example.com/some-post
```

Output on success:

```
Stored: knowledge:url:example-com-some-post
<the extracted insight summary>
```

Run it again on the same URL and it costs nothing:

```
already stored: knowledge:url:example-com-some-post
```

The key is derived purely from the URL, so re-running a batch never re-fetches
or re-pays for work already done.

## The two fetch paths

Routing is automatic, by URL:

| URL | Path | Needs |
|---|---|---|
| Anything non-LinkedIn | Plain HTTP GET + HTML-to-text | Nothing |
| `linkedin.com/...` | Headless `claude -p` → `linkedin-scraper-mcp` | One-time login (below) |

LinkedIn is auth-gated and JS-heavy, so a plain GET cannot read it.

## One-time LinkedIn setup

Install the scraper and log in **once**, interactively:

```bash
uv tool install linkedin-scraper-mcp
linkedin-scraper-mcp --login
```

That establishes a browser profile with stored cookies. Everything afterwards
runs fully headless against that profile.

Check it whenever you want:

```bash
linkedin-scraper-mcp --status
# ✅ Session is valid (profile: ~/.linkedin-mcp/profile)
```

**When the session expires**, `process-url` fails immediately and loudly rather
than quietly returning nothing:

```
LinkedIn session is not usable — run `linkedin-scraper-mcp --login` to refresh it.
```

That is deliberate. A silent skip would look identical to "this author has no
recent posts", and a nightly job would report success while storing nothing for
weeks.

### A real limitation, worth knowing up front

`linkedin-scraper-mcp` has **no fetch-this-exact-post tool**. Every tool takes a
structured identifier and builds its own URL. The closest primitive returns an
author's *recent posts feed*, so this command parses the author and title out of
the URL, fetches that feed, and text-matches to find the post.

Consequently: **older posts often won't be found.** That is reported as a miss,
not a failure —

```
post not found in the author's recent feed: https://linkedin.com/posts/...
```

— nothing is stored, and the link's tracking task is *not* offered for
cancellation. Full rationale in
[ADR-070](../../architecture/decisions/ADR-070-knowledge-process-url-headless-fetch.md).

## Batch mode

Drain many links at once from a JSONL file — one `{"id","url"}` record per line:

```jsonl
{"id":"t-1201","url":"https://example.com/a"}
{"id":"t-1202","url":"https://www.linkedin.com/posts/someone_a-post-abc123"}
```

```bash
brana knowledge process-url --file links.jsonl
```

Each URL is processed in sequence and reported individually. One dead link does
not strand the rest of the run. At the end:

```
Processed 2 URL(s), 0 failed.
Task IDs safe to cancel (advisory — not applied):
  t-1201
```

Two things to note about that list:

- **It is advisory.** The command never calls `brana backlog set`. You decide.
- **Only URLs whose content actually landed in the knowledge base appear.** A
  post that wasn't found, or a page that fetched empty, is left off — its stub
  still has real work behind it.

Blank lines are ignored. A malformed record names its line number.

**Exit code:** non-zero only when a URL genuinely failed to fetch or store.
"Not found" and "empty content" are expected outcomes and do not trip it — a
batch containing one old LinkedIn post should not page you.

## Nightly cron

```bash
#!/usr/bin/env bash
# Drain captured links into the knowledge base.
set -uo pipefail

LINKS=~/.claude/link-queue.jsonl
[ -s "$LINKS" ] || exit 0

if ! linkedin-scraper-mcp --status >/dev/null 2>&1; then
  echo "LinkedIn session dead — run: linkedin-scraper-mcp --login" >&2
  exit 1
fi

brana knowledge process-url --file "$LINKS"
```

Retry and backoff belong in this wrapper, not in the command — `process-url` is
single-shot per invocation by design.

## Where it stores, and where it doesn't

Storage is the ruflo `knowledge` namespace, keyed `knowledge:url:{slug}`, tagged
with the platform and the extracted topic. Search it with `brana recall`.

This is **independent of the inbox→dimensions pipeline**. It does not read or
write `~/.swarm/knowledge-pipeline-state.json`, does not take the pipeline lock,
and does not write dimension docs. Feeding fetched content into that pipeline is
a separate, still-open decision (t-1144).

## When nothing gets stored

| You see | Meaning |
|---|---|
| `already stored: …` | Same URL processed before. Working as intended. |
| `post not found in the author's recent feed` | LinkedIn post older than the returned feed. Expected. |
| `warning: content … is empty or too short` | Fetched an auth wall or a JS-only shell. Nothing worth keeping. |
| `LinkedIn session is not usable` | Re-run `linkedin-scraper-mcp --login`. |

## See also

- [ADR-070](../../architecture/decisions/ADR-070-knowledge-process-url-headless-fetch.md) — why headless-first, and the Tier-2 correction
- [Feature spec](../../architecture/features/knowledge-process-url.md) — scope, edge cases, assumptions
