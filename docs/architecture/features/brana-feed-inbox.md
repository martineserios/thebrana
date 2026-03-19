# Feature: brana feed + brana inbox CLI subcommands

**Date:** 2026-03-19
**Status:** shipped
**Task:** t-585

## Problem

No unified way to monitor external content sources (RSS, Substack, Medium, blogs, newsletters) or manage email newsletter subscriptions from the brana CLI. Content monitoring is manual — the user checks sources ad-hoc. The scheduler has content-fetching scripts (cc-changelog-check.sh, check-agentdb-integration.sh) but no general-purpose polling framework.

## Decision Record (frozen 2026-03-19)

> Do not modify after acceptance.

**Context:** Spike t-472 evaluated content polling patterns. Challenger review simplified the architecture: no separate sources.json registry, no action dispatcher framework. Each feed is a scheduler job. Existing poll scripts (cc-changelog-check.sh, check-agentdb-integration.sh) prove the pattern works at ~50 LOC each.

**Decision:** Add two subcommand groups to the brana Rust CLI:
1. `brana feed` — RSS/Atom polling (covers Substack, Medium, blogs, YouTube, GitHub releases, Reddit, podcasts, Twitter/Telegram via RSS bridges)
2. `brana inbox` — Gmail newsletter management via IMAP (individual + Workspace accounts)

Pure Rust implementation. No Python, no async runtime. New deps: `feed-rs` (RSS parser), `ureq` (blocking HTTP), `imap` + `mailparse` (IMAP).

**Consequences:**
- Binary size increases ~400-500KB (feed-rs + ureq + imap + mailparse + native-tls)
- Gmail requires App Password (one-time setup, stored as env var)
- Scheduler integration: one `brana feed poll --all` job + one `brana inbox poll` job

## Constraints

- Pure Rust — no Python, no async (tokio), keep binary lean
- Gmail only for email (user's accounts are all Google individual or Workspace)
- IMAP + App Password — no OAuth flow, no token refresh complexity
- Credentials via env vars only (`BRANA_GMAIL_USER`, `BRANA_GMAIL_APP_PASSWORD`)
- Follow existing CLI patterns: clap derive, anyhow errors, themed output
- Each feed = a scheduler job entry (no separate registry abstraction)

## Scope (v1)

### brana feed

| Subcommand | Purpose |
|------------|---------|
| `brana feed add <url> [--name NAME] [--action log\|task]` | Register a feed |
| `brana feed list` | Show all registered feeds with last poll status |
| `brana feed poll [NAME \| --all]` | Poll one or all feeds, detect + act on new entries |
| `brana feed remove <name>` | Remove a feed |
| `brana feed status` | Show last poll results per feed |

**Config:** `~/.claude/scheduler/feeds.json`
```json
[
  {
    "name": "simon-willison",
    "url": "https://simonwillison.net/atom/everything/",
    "action": "log",
    "enabled": true
  }
]
```

**State (per-feed):** `~/.claude/scheduler/state/{name}.json`
```json
{
  "etag": "\"abc123\"",
  "last_modified": "Wed, 19 Mar 2026 10:00:00 GMT",
  "last_entry_ids": ["entry-1", "entry-2", "entry-3"],
  "last_poll": "2026-03-19T16:00:00Z",
  "new_count": 2
}
```

**Actions on new entries:**
- `log` (default) — append to `~/.claude/scheduler/feed-log.jsonl`
- `task` — call `brana backlog add --json '{"subject":"[feed] title","stream":"research","tags":["feed","source-name"]}'`

**Polling logic:**
1. HTTP GET with `If-None-Match: {etag}` + `If-Modified-Since: {last_modified}`
2. 304 → no changes, update last_poll timestamp
3. 200 → parse with feed-rs, compare entry IDs against last_entry_ids
4. New entries → execute action, update state

### brana inbox

| Subcommand | Purpose |
|------------|---------|
| `brana inbox poll [--label LABEL]` | Check Gmail for new newsletter emails (default label: `Newsletters`) |
| `brana inbox list` | Show registered newsletter subscriptions |
| `brana inbox add "Name" --from "sender@example.com"` | Register a subscription |
| `brana inbox remove <name>` | Remove a subscription |
| `brana inbox status` | Show arrival stats (expected vs actual per subscription) |

**Config:** `~/.claude/scheduler/inbox.json`
```json
{
  "imap_host": "imap.gmail.com",
  "imap_port": 993,
  "user_env": "BRANA_GMAIL_USER",
  "password_env": "BRANA_GMAIL_APP_PASSWORD",
  "label": "Newsletters",
  "subscriptions": [
    {
      "name": "stratechery",
      "from": "ben@stratechery.com",
      "frequency": "weekly",
      "enabled": true
    }
  ]
}
```

**Polling logic:**
1. Connect IMAP TLS to imap.gmail.com:993
2. SELECT the configured label/folder
3. SEARCH UNSEEN — get UIDs of unread messages
4. FETCH headers (From, Subject, Date) for each
5. Match against registered subscriptions by `from` field
6. Log to `~/.claude/scheduler/inbox-log.jsonl`
7. Mark as SEEN (don't delete)

**State:** `~/.claude/scheduler/state/inbox.json`
```json
{
  "last_poll": "2026-03-19T16:00:00Z",
  "last_uid": 4523,
  "unmatched_count": 2
}
```

### Scheduler integration

Two new jobs in scheduler.json template:
```json
{
  "name": "feed-poll",
  "type": "command",
  "command": "brana feed poll --all",
  "schedule": "*-*-* 08:00,12:00,18:00:00",
  "enabled": false,
  "timeoutSeconds": 120
},
{
  "name": "inbox-poll",
  "type": "command",
  "command": "brana inbox poll",
  "schedule": "*-*-* 09:00:00",
  "enabled": false,
  "timeoutSeconds": 60
}
```

## Design

### File layout (in worktree)

```
system/cli/rust/
├── Cargo.toml                    ← +feed-rs, +ureq, +imap, +mailparse, +native-tls
├── src/
│   ├── cli.rs                    ← +FeedCmd, +InboxCmd enums
│   ├── main.rs                   ← +Commands::Feed, +Commands::Inbox match arms
│   ├── commands/
│   │   ├── mod.rs                ← +pub mod feed; +pub mod inbox;
│   │   ├── feed.rs               ← ~120 LOC: add/list/poll/remove/status
│   │   └── inbox.rs              ← ~120 LOC: poll/list/add/remove/status
│   └── ...
```

### Dependencies

| Crate | Purpose | Size impact |
|-------|---------|-------------|
| `feed-rs` | RSS/Atom/JSON Feed parsing | ~200KB |
| `ureq` | Blocking HTTP client (no tokio) | ~150KB |
| `imap` | IMAP client | ~50KB |
| `mailparse` | MIME email parsing | ~30KB |
| `native-tls` | TLS for IMAP (ureq uses rustls) | shared with system |

### Key patterns

- **Config files** read/written with serde_json (same as tasks.json pattern)
- **State files** are atomic: write to `.tmp`, rename
- **Themed output** via existing `themes::Theme` (reuse task-line icons for status)
- **Error handling** via anyhow (consistent with rest of CLI)
- **No daemon** — poll is a one-shot command, scheduler fires it

## Code Flow

### brana feed poll

1. **Entry:** `main.rs` → `Commands::Feed` → `commands::feed::cmd_feed(FeedCmd::Poll)`
2. **Core:** `cmd_poll()` iterates enabled feeds → `poll_one()` per feed:
   - HTTP GET via `ureq` with conditional headers (`If-None-Match`, `If-Modified-Since`)
   - Parse response with `feed_rs::parser::parse()`
   - Diff entry IDs against `last_entry_ids` in state
3. **Output:** New entries → action handler (`log` appends to JSONL, `task` shells out to `brana backlog add`). State updated atomically.

### brana inbox poll

1. **Entry:** `main.rs` → `Commands::Inbox` → `commands::inbox::cmd_inbox(InboxCmd::Poll)`
2. **Core:** `cmd_poll()`:
   - Read creds from env vars → `imap::connect()` TLS → `login()` → `select()` label
   - `uid_search("UNSEEN")` → `uid_fetch()` headers → match `From` against subscriptions
3. **Output:** Matched/unmatched logged to JSONL. State updated with last UID.

## Testing

```bash
cd system/cli/rust
OPENSSL_DIR=/usr OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu \
  OPENSSL_INCLUDE_DIR=/usr/include/openssl \
  cargo test -- --test-threads=1
```

20 tests across feed + inbox: config CRUD, state roundtrip, derive_name, header extraction, subscription matching, log serialization, atomic writes.

## Known Limitations

- **Binary size +3.4MB** (1.4→4.8MB) — mostly TLS. Acceptable but notable.
- **imap crate v2** — v3 is alpha-only. Has future-incompat warning on imap-proto.
- **No OAuth** — Gmail App Password only. Works for individual + Workspace but requires manual setup.
- **No full-text content extraction** — inbox poll reads headers only, not email body.
- **No themed output** — feed/inbox commands output raw JSON. Themed rendering deferred.
- **OPENSSL env vars needed** for builds without pkg-config.

## Documentation Plan

- [x] **User guide** — `docs/guide/features/brana-feed-inbox.md`
- [x] **Tech doc** — `docs/architecture/features/brana-feed-inbox.md` (this file)
- [ ] **Existing docs to update** — `docs/guide/scheduler.md` (new jobs), brana CLI reference in CLAUDE.md

## Challenger findings

(from t-472 spike challenger review)
- sources.json is unnecessary — feed config lives in feeds.json, not a separate registry
- Action dispatcher is over-engineering — poll scripts call brana backlog add directly
- IMAP poller should be v1 (user confirmed), not deferred
- ~400 LOC total is right-sized after simplification
- Bash+Python hybrid avoided by going pure Rust
