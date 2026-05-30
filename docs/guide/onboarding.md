# Brana Onboarding — One-Command Install

## Prerequisites

- Rust (cargo) — for building the CLI
- Git, jq
- libssl-dev (Ubuntu: `sudo apt install libssl-dev`)

## Install

```bash
cd ~/enter_thebrana/thebrana

# 1. Build the CLI
OPENSSL_INCLUDE_DIR=/usr/include/openssl OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu \
  CARGO_PROFILE_RELEASE_LTO=off cargo build --release -p brana-cli \
  --manifest-path system/cli/rust/Cargo.toml
cp system/cli/rust/target/release/brana ~/.local/bin/brana

# 2. Deploy the identity layer + register the plugin
./bootstrap.sh

# 3. Verify installation
brana doctor
```

## What bootstrap.sh does

1. Deploys `~/.claude/CLAUDE.md` (mastermind identity)
2. Registers the brana plugin in `~/.claude/plugins/installed_plugins.json`
3. Snapshots `system/` to the plugin cache
4. Deploys scheduler scripts and git hooks
5. Configures ruflo MCP server in `settings.local.json`

Reports `N changes made` at the end — safe to re-run (idempotent).

## Verify health

```bash
brana doctor            # quick health check (binary, hooks, rules, deps)
brana doctor --validate # full structural check (runs validate.sh)
```

A fresh install expects 7/9+ checks passing. MCP servers and ruflo DB
start as warnings until ruflo is installed and a session has run.

## First session

```bash
claude                  # start Claude Code — brana plugin loads automatically
/brana:sitrep           # get oriented
/brana:backlog          # see what's next
```

## Day-to-day

```bash
./bootstrap.sh          # re-run after pulling — syncs plugin cache
brana doctor --validate # run before merging to main
```

See also: `docs/guide/ecosystem.md`, `docs/guide/day-to-day.md`
