# Spike: Install Friction Evaluation — bootstrap vs one-liner vs pipx vs cargo

> t-661 | harness-core epic | 2026-06-08

## What Brana Actually Needs to Install

Brana has two distinct components that must arrive together:

| Component | What it is | How it lives |
|-----------|-----------|-------------|
| **Rust binary** (`brana`) | CLI — backlog, transcribe, files, feed, mcp | `cargo install` target |
| **CC plugin** (system/) | Skills, hooks, agents, rules, CLAUDE.md | `~/.claude/` via bootstrap.sh or `claude plugin install` |

No install approach that covers only one of these two is complete. The key question is which approach delivers both with the least friction.

---

## Approach Comparison

### 1. Current: curl-pipe → clone → bootstrap.sh

```bash
curl -fsSL https://raw.githubusercontent.com/martineserios/thebrana/main/install.sh | bash
```

**Steps:** curl → clone (~200MB repo) → bootstrap.sh (733 lines: CLAUDE.md, scripts, scheduler, plugin cache sync)

| Dimension | Assessment |
|-----------|-----------|
| Prerequisites | git, jq (soft), Node.js (soft for ruflo) |
| Steps to working | 1 command — then restart CC |
| Update path | Re-run `./install.sh` or `git pull && ./bootstrap.sh` |
| Portability | Linux + macOS; Windows via WSL only |
| Context cost at install | Clones full 200MB repo to user's home. Heavy disk footprint. |
| Portability of config | Config lives in `~/.claude/` — survives re-installs |
| Plugin model | `bootstrap.sh --sync-plugin` copies system/ into CC plugin cache |

**Friction points:**
- Clones full repo including git history (not just the runtime files)
- `jq` and `Node.js` prereq warnings confuse new users
- `bootstrap.sh` at 733 lines is hard to audit
- No version pinning — always installs HEAD

**Verdict:** Works. Friction is real but manageable for solo operators. Not distribution-ready.

---

### 2. pipx-style (Python installer)

Pattern: `pipx install brana` → `brana install` bootstraps the rest.

Used by: SuperClaude (`pipx install superclaude && superclaude install`)

| Dimension | Assessment |
|-----------|-----------|
| Prerequisites | Python 3.10+, pipx |
| Steps to working | `pipx install brana` → `brana install` → restart CC |
| Update path | `pipx upgrade brana && brana install --update` |
| Portability | Linux + macOS + Windows (Python is cross-platform) |
| Context cost | Small Python package (~50KB) + bootstrapped plugin files |
| Plugin model | Python `brana install` command copies plugin files to `~/.claude/` |

**Friction points:**
- Python adds a dependency that brana doesn't otherwise use (Rust binary is the CLI)
- pipx isolates the venv but Python startup overhead is real (~100ms)
- SuperClaude's model shows the pattern works but their install doesn't include a native binary
- **Core mismatch:** the `brana` CLI is Rust, not Python. Wrapping it in pipx means shipping the binary inside a Python package, which is non-standard and fragile on arm64/x86_64 differences

**Verdict:** Wrong abstraction for brana. SuperClaude works with pipx because their "installer" is pure Python. Brana's CLI is a compiled binary — pipx adds overhead without benefit.

---

### 3. brew tap (macOS/Linux)

Pattern: `brew tap martineserios/brana && brew install brana`

| Dimension | Assessment |
|-----------|-----------|
| Prerequisites | Homebrew (standard on macOS; installable on Linux) |
| Steps to working | `brew install brana` → `brana bootstrap` → restart CC |
| Update path | `brew upgrade brana` |
| Portability | macOS (native), Linux (linuxbrew or self-managed), no Windows |
| Context cost | Compiled binary + plugin files via formula `source` stanza |
| Plugin model | `brana bootstrap` post-install hook deploys `~/.claude/` files from embedded resources |

**Friction points:**
- Formula maintenance: every release requires formula update (bottle build, SHA update)
- `brew` not available on all Linux systems (CI, servers, Docker)
- Plugin files must be embedded in the binary or bundled with the formula — complicates the `system/` update cycle
- Two-step still required: `brew install brana` + `brana bootstrap`

**Verdict:** Best UX on macOS for developer-facing tools. Significant maintenance overhead. Viable as a distribution target after 1.0, not before.

---

### 4. cargo install (one-liner)

Pattern: `cargo install brana-cli && brana bootstrap`

| Dimension | Assessment |
|-----------|-----------|
| Prerequisites | Rust toolchain (rustup) |
| Steps to working | `cargo install brana-cli` → `brana bootstrap` → restart CC |
| Update path | `cargo install brana-cli --force` |
| Portability | Linux + macOS + Windows (Rust is cross-platform) |
| Context cost | Builds from source (~2–5 min first install, ~30s if cached) |
| Plugin model | `brana bootstrap` deploys plugin files from embedded resources or remote fetch |

**Friction points:**
- Rust toolchain is a 1GB+ install for users who don't already have it
- Build time is a real barrier for first-time installers
- Plugin files (system/) cannot live in the binary without significant refactor (embed! macro or remote fetch)
- `cargo install --force` for updates is clunky UX

**Verdict:** Right model for developers already in Rust. Wrong model for general distribution. `brana bootstrap` post-install is already how the Rust CLI works — the question is how to deliver the binary without requiring a local build.

---

### 5. Hybrid: prebuilt binary + curl-pipe

Pattern:
```bash
curl -fsSL https://brana.sh/install | bash
# Downloads: brana binary (platform-specific), then runs: brana bootstrap
```

| Dimension | Assessment |
|-----------|-----------|
| Prerequisites | curl, bash |
| Steps to working | 1 command → restart CC |
| Update path | Re-run install script |
| Portability | Linux + macOS; Windows via WSL |
| Context cost | Binary-only download (<10MB) + plugin files via `brana bootstrap` |
| Plugin model | `brana bootstrap` is the install verb — same flow as today |

This is the approach used by most modern CLI tools: `gh`, `volta`, `mise`. The installer script detects the platform, downloads the right binary, puts it in `$PATH`, and runs the one-time setup command.

**What changes:** The current `install.sh` clones the full repo. A binary-based install would:
1. Download the platform-specific `brana` binary from GitHub releases
2. Run `brana bootstrap` which reads plugin files from an embedded `system.tar.gz` (or fetches them from a GitHub release asset)

This requires embedding the plugin files into the binary at release time (or fetching them separately), which is new work — but it's architecturally cleaner.

---

## Recommendation

**Short term (current):** Keep `install.sh` → clone → `bootstrap.sh`. It works for a solo operator. The friction is acceptable.

**Medium term target (1.0 distribution):** Prebuilt binary + curl-pipe installer.

Rationale:
- Eliminates the 200MB repo clone (replaced by <10MB binary)
- Eliminates Rust toolchain requirement for end users
- Keeps `brana bootstrap` as the single install verb (already the right abstraction)
- Works on Linux + macOS without additional toolchain requirements
- Enables GitHub Releases as the delivery channel (versioned, auditable)

**Deferred (post-1.0):** Add brew tap for macOS users who prefer managed installs.

**Skip permanently:** pipx (wrong abstraction for a Rust binary).

---

## Prerequisite for Binary Distribution

The `system/` plugin files must be either:
1. **Embedded in the binary** at release time via `include_bytes!` / archive embed
2. **Fetched from GitHub releases** by `brana bootstrap` on first run

Option 2 is lower effort: `brana bootstrap` already knows how to deploy to `~/.claude/`. Extend it to accept a `--release-url` flag that downloads a `system.tar.gz` release asset instead of reading from a local path.

This is a separate implementation task — this spike does not implement it.

## Related

- [docs/architecture/bootstrap.md](../architecture/bootstrap.md) — current bootstrap.sh internals
- [docs/guide/getting-started.md](../guide/getting-started.md) — user-facing install docs
- [ADR-022](../architecture/decisions/ADR-022-brana-cli.md) — Brana CLI (Rust)
