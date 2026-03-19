# brana feed + brana inbox

Monitor RSS/Atom feeds and manage Gmail newsletter subscriptions from the CLI. Feeds are polled with HTTP conditional requests (no wasted bandwidth). Newsletters are tracked via IMAP.

## Quick Start

```bash
# Add and poll an RSS feed
brana feed add https://simonwillison.net/atom/everything/ --name simon-willison
brana feed poll simon-willison

# Add a Gmail account (prompts for App Password, stores in OS keyring)
brana inbox add-account personal --user you@gmail.com

# Register a newsletter subscription and poll
brana inbox add stratechery --from "ben@stratechery.com" --frequency weekly
brana inbox poll
```

## How It Works

### brana feed

1. Register a feed URL with `brana feed add`
2. Poll with `brana feed poll` — sends HTTP GET with ETag/If-Modified-Since headers
3. If new entries exist, executes the configured action (log to JSONL or create a backlog task)
4. State is cached per feed — subsequent polls only fetch if content changed (304 response = skip)

### brana inbox

1. Register newsletter subscriptions with `brana inbox add` (name + sender email)
2. Poll with `brana inbox poll` — connects to Gmail via IMAP TLS, searches for UNSEEN emails
3. Matches emails against registered subscriptions by sender address
4. Logs results to JSONL (matched + unmatched)

## Options

### brana feed

| Command | Options | Description |
|---------|---------|-------------|
| `feed add <url>` | `--name NAME`, `--action log\|task` | Register a feed. Name derived from URL if omitted. Action: `log` (default) or `task` |
| `feed list` | — | Show all registered feeds |
| `feed poll [NAME]` | `--all` | Poll one feed by name, or all with `--all` |
| `feed remove <name>` | — | Remove a feed and its state |
| `feed status` | — | Show last poll results per feed |

### brana inbox

| Command | Options | Description |
|---------|---------|-------------|
| `inbox add-account <name>` | `--user-env VAR`, `--pass-env VAR`, `--label LABEL` | Add a Gmail account |
| `inbox add <name>` | `--from EMAIL`, `--frequency daily\|weekly\|monthly`, `--account NAME` | Register a subscription (on first account if `--account` omitted) |
| `inbox list` | — | Show all accounts and subscriptions |
| `inbox poll` | `--label LABEL`, `--account NAME` | Poll all enabled accounts (or one with `--account`) |
| `inbox remove <name>` | — | Remove a subscription from any account |
| `inbox status` | — | Show per-account arrival stats |

## Examples

### Monitor a Substack

```bash
brana feed add https://newsletter.substack.com/feed --name my-newsletter
brana feed poll my-newsletter
```

New entries are appended to `~/.claude/scheduler/feed-log.jsonl`.

### Auto-create tasks from feed entries

```bash
brana feed add https://github.com/anthropics/claude-code/releases.atom --name cc-releases --action task
brana feed poll cc-releases
```

Each new release creates a task in the backlog: `[cc-releases] Release v2.2.0`.

### Schedule automatic polling

Enable the pre-configured scheduler jobs:

```bash
brana ops enable feed-poll    # 3x daily: 08:00, 12:00, 18:00
brana ops enable inbox-poll   # daily at 09:00
```

### Common feed URLs

| Source | URL pattern |
|--------|------------|
| Substack | `https://{pub}.substack.com/feed` |
| Medium | `https://medium.com/feed/@{user}` |
| YouTube | `https://youtube.com/feeds/videos.xml?channel_id={ID}` |
| GitHub releases | `https://github.com/{owner}/{repo}/releases.atom` |
| Reddit | `https://reddit.com/r/{sub}/.rss` |

## Setup: Gmail Accounts

`brana inbox` supports multiple Gmail accounts. Each needs an App Password.

### Step 1: Create App Passwords

For each Gmail account (personal, workspace, etc.):

1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2. Select "Mail" and your device
3. Copy the 16-character password

### Step 2: Register accounts (passwords stored in OS keyring)

```bash
# Prompts for App Password securely (no echo, stored in system keyring)
brana inbox add-account personal --user you@gmail.com
brana inbox add-account work --user you@company.com --label "Work Newsletters"
```

Passwords are stored in your OS keyring (GNOME Keyring, macOS Keychain, or Windows Credential Manager). Never in plaintext files or env vars.

To update a password later:
```bash
brana inbox set-password personal
```

### Step 3: Add subscriptions per account

```bash
brana inbox add stratechery --from "ben@stratechery.com" --account personal
brana inbox add company-digest --from "digest@company.com" --account work
```

### Step 4: Poll all accounts

```bash
brana inbox poll              # polls all enabled accounts
brana inbox poll --account work   # poll only work
```

Works with individual Gmail and Google Workspace accounts, on Linux, macOS, and Windows.

## Files

| Path | Purpose |
|------|---------|
| `~/.claude/scheduler/feeds.json` | Feed registry |
| `~/.claude/scheduler/inbox.json` | Inbox config (accounts + subscriptions) |
| `~/.claude/scheduler/state/{name}.json` | Per-feed poll state (ETag, last entries) |
| `~/.claude/scheduler/state/inbox-{account}.json` | Per-account inbox poll state (last UID) |
| `~/.claude/scheduler/feed-log.jsonl` | Feed entry log |
| `~/.claude/scheduler/inbox-log.jsonl` | Email log |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `no password for 'personal'` | Run `brana inbox set-password personal` to store in keyring |
| `IMAP login failed` | Verify App Password is correct. Regular passwords don't work. Run `brana inbox set-password <account>` to re-enter. |
| `selecting mailbox 'Newsletters'` | Create the label in Gmail first, or use `--label "Other Label"` |
| Feed poll returns 0 but entries exist | First poll caches all entries. Second poll detects new ones. |
| Build fails: `pkg-config could not be found` | Set `OPENSSL_DIR=/usr OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu OPENSSL_INCLUDE_DIR=/usr/include/openssl` |
