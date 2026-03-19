# ADR-024: Content Polling Architecture & Keyring Credentials

**Date:** 2026-03-19
**Status:** accepted
**Task:** t-585

## Context

Brana needs to monitor external content sources (RSS feeds, email newsletters) and act on new content. The scheduler already runs cron-like jobs via systemd timers, but had no general-purpose content polling.

For email (Gmail IMAP), credentials must be stored securely. Env vars in shell profiles are visible via `env` and `/proc/*/environ`.

## Decision

### Content Polling

Add two CLI subcommand groups to the Rust brana binary:

1. **`brana feed`** — RSS/Atom polling via `feed-rs` + `ureq` (blocking HTTP). HTTP conditional requests (ETag/If-Modified-Since) for efficient polling.
2. **`brana inbox`** — Gmail IMAP newsletter management via `imap` crate. Multi-account support. Subscription registry with sender matching.

Each feed/account is a scheduler job. No separate orchestration layer — the existing systemd timer infrastructure handles scheduling.

### Credential Storage

Use the `keyring` crate (v3) for OS-native secret storage:

| OS | Backend |
|----|---------|
| Linux | Secret Service (GNOME Keyring / KWallet) |
| macOS | Keychain |
| Windows | Credential Manager |

Credentials stored via `brana inbox set-password` (interactive, no echo). Env var fallback preserved for headless/CI environments.

## Consequences

- **Binary size:** 1.4MB → 4.8MB (+3.4MB from TLS + HTTP + IMAP + keyring). Future network features are amortized.
- **No Python/bash dependency** for polling — pure Rust.
- **Cross-platform credentials** — same code on Linux/macOS/Windows.
- **Env var fallback** ensures scheduler jobs work in headless contexts where keyring may be unavailable (e.g., systemd user services without a desktop session).
- **imap crate v2** — v3 is alpha-only. Future compat warning exists on imap-proto.

## Alternatives Considered

1. **Python feedparser + bash scripts** — rejected for polyglot complexity, per challenger review.
2. **Separate sources.json registry** — rejected as unnecessary config duplication (feeds.json IS the registry).
3. **Action dispatcher framework** — rejected as over-engineering (poll scripts call `brana backlog add` directly).
4. **OAuth2 for Gmail** — rejected for complexity (token refresh, redirect flow). App Password + keyring is simpler.
5. **Encrypted config field** — rejected for non-standard approach. OS keyrings are battle-tested.
