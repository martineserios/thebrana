# Go for Harness & Loop Engineering — Evaluation

> Research spike · t-2171 · 2026-06-20 · epic: harness-engineering
> Question: Should thebrana adopt Go — leveraging its concurrency features — for harness
> and loop engineering? Audit backlog / brana-cli integration surface and new-feature
> possibilities.

## TL;DR

**No** for every component that exists today. Go solves problems thebrana does not
have, and adopting it would re-introduce the exact cross-language split that
[ADR-026](../architecture/decisions/ADR-026-full-rust-mcp-architecture.md) deliberately
eliminated 2.5 months ago.

**One genuine "maybe"**: if loop orchestration is ever extracted *out of* Claude Code's
native `/loop` + `Workflow` into a standalone autonomous **orchestration daemon**, that —
and only that — is a profile where Go's goroutine/worker-pool model is a real contender.
Even then it competes head-to-head with Rust + tokio, which the team already runs.

Recommendation: **do not adopt Go now.** Park it as a candidate language for a *future
standalone factory daemon* only, gated on that daemon actually being specced. Fix the one
real concurrency gap (tasks.json locking, t-2166) in Rust — it is language-agnostic and
Go would not help.

---

## 1. The question is built on a category error

The prompt assumes "the harness" and "the loop" are programs that could be written in Go.
They are not. Grounding from the codebase (two exploration passes, 2026-06-20):

| Layer | What it actually is | Could Go touch it? |
|-------|--------------------|--------------------|
| **Harness** | Claude Code's native instruction loading + 5 shell hooks (`~/.claude/hooks/*.sh`) + ruflo MCP + the `brana` CLI | Only the CLI is compiled. Hooks are shell; loading is Claude-internal. |
| **Loop engineering** | Claude Code's native `/loop` recipe + `Workflow` JS scripts dispatching worktree-isolated agents (foreman → task-crew) | **No compiled language at all.** Orchestration lives in Claude + JS. |
| **brana CLI** | Rust — 3-crate Cargo workspace (`brana-core` / `brana-cli` / `brana-mcp`), ~108K LOC, 12 ms startup | This is the only real "could we use Go" surface. |

So "Go for the harness/loop" collapses to one concrete question: **should the brana CLI
(or a future orchestration daemon) be Go instead of Rust?** Everything else in the prompt
is shell or Claude-native and out of scope for any compiled language.

---

## 2. The current Rust footprint (what Go would replace)

From source audit of `system/cli/rust/`:

- **`brana-cli`** — sync by design. Zero async. ~20 subcommands across 14 modules
  (backlog, ops, feed, inbox, knowledge, skills, memory, session…). Parallelism where it
  exists is `std::thread::scope` + `Mutex<Value>` (e.g. `sync.rs`, `sync_linear.rs`).
- **`brana-core`** — shared sync library. `serde_json`, `rusqlite` (bundled FTS5), `clap`,
  `ureq` (sync HTTP). No async.
- **`brana-mcp`** — thin MCP adapter, `#[tokio::main]`, but tokio is used **only** for
  stdio multiplexing. All business logic is inherited sync from `brana-core`.
- **tasks.json write path** — `load_raw()` → mutate in-memory → `write_atomic()`
  (temp + POSIX atomic rename), with PID-scoped temp names
  (`tasks.json.{PID}.tmp`). **No file lock, no reader-writer sync, last-write-wins.**
  This is the gap [t-2166](#) tracks.

Key reading:
- `crates/brana-core/src/tasks.rs` — write_atomic / load_raw / save_tasks
- `crates/brana-mcp/src/tools/backlog_batch.rs` — batch mutation
- `crates/brana-cli/src/sync.rs` — thread::scope + Mutex parallelism
- `crates/brana-mcp/src/main.rs` — tokio for I/O only

---

## 3. Go vs. Rust for *this* workload

External validation (web, 2026-06; sources below) lines up with the well-known split:

| Dimension | Go | Rust / tokio | Relevant to thebrana? |
|-----------|----|--------------|-----------------------|
| Concurrency ergonomics | goroutines + channels — simplest mental model | async/await + lifetimes/pinning + "colored functions" — harder | thebrana's CLI is **sync**; ergonomics of async barely matter |
| I/O-bound fan-out | excellent (runtime multiplexes onto OS threads) | excellent, lower overhead | CLI does **local file I/O**, not network fan-out — Go's edge doesn't apply |
| CPU-bound | good (GC pauses possible) | best (no runtime overhead) | knowledge/FTS work is CPU-bound — Rust favoured |
| Memory at scale | ~3× overhead at 100K concurrent tasks (goroutine stacks) | lean (task ≈ struct) | thebrana never has 100K tasks; irrelevant |
| Startup / single binary | fast, single binary | fast (12 ms measured), single static binary | parity — no win for Go |
| Fast-CLI precedent | DevOps tooling (kubectl, gh) | ripgrep / fd / delta / bottom — define the category | Rust owns the "fast local CLI" niche |
| Already in the stack | no | **yes** | adopting Go = +1 toolchain, +1 language |

**Verdict for the CLI:** Go offers *nothing* the workload needs. Its standout advantage —
cheap massive I/O-bound concurrency — is for network servers with thousands of live
connections. thebrana's CLI is a single-user, short-lived, local-file process where
Rust already delivers 12 ms startup, a single static binary, no GC, and compiler-enforced
schema consistency. Switching would trade those away for simpler async that the sync CLI
doesn't use.

**The ADR-026 wall:** [ADR-026](../architecture/decisions/ADR-026-full-rust-mcp-architecture.md)
(accepted 2026-04-05) absorbed 2,950 lines of Python into Rust specifically to get *one*
type system, compiler-enforced schemas, zero runtime deps, and **"no cross-language
bridges."** Introducing Go re-opens exactly that wound — two schema definitions, two build
toolchains, an FFI or serialization seam between them. This is a settled architectural
decision; Go would re-litigate it with no compensating benefit.

---

## 4. Where Go's concurrency *would* genuinely shine

To be fair to the premise — Go's worker-pool / fan-out-fan-in / supervisor model
(`gammazero/workerpool`, channel-based job queues, `context` cancellation) is a category
leader for **one shape of program**: a long-running concurrent service that supervises
many independent jobs. Classic uses: job queues, build farms, CI runners, agent
supervisors.

thebrana does not run such a service **today** — the loop/foreman lives inside Claude
Code's `/loop` + `Workflow`, which already provide fan-out, worktree isolation, and
journal-resume (see `docs/research/2026-06-11-loop-native-redesign.md`). The concurrency
is orchestrated by Claude + JS, not by a compiled supervisor.

**The one real new-feature possibility:** if the loop-native roadmap ever graduates from
"foreman as a per-session `/loop` recipe" to a **standalone autonomous orchestration
daemon** — a process that runs outside any Claude session, polls the backlog, maintains a
worker pool of dispatched task-crews, supervises stalls, and merges results — *that* is a
textbook Go program:

- goroutine-per-task-crew with a bounded worker pool (back-pressure on concurrent builds)
- channels for the job queue + results collector
- `context.Context` for stall-watchdog cancellation (the rehearsal's 18-min hang, t-1991)
- trivial `net/http` control surface / status endpoint
- single static binary, easy to run as a systemd service alongside `brana-scheduler`

But note: this competes directly with **Rust + tokio**, which `brana-mcp` already proves
the team can ship. The honest comparison there is "Go's simpler supervisor ergonomics" vs.
"one fewer language + reuse brana-core's task types directly." For a daemon that must
read/write tasks.json and call brana logic, *reusing brana-core in a Rust+tokio daemon
beats a Go rewrite of that logic.* Go only pulls ahead if the daemon is mostly
orchestration glue with little brana-core logic — which is unlikely, since dispatch
decisions need backlog reads, lint, and AC parsing that already live in brana-core.

---

## 5. The tasks.json concurrency gap (t-2166) — language-agnostic

The prompt's "leverage concurrency features" instinct points at a real bug: multiple live
sessions clobber tasks.json (observed 2026-06-20, 6 sessions, lost writes). **Go does not
fix this and is not needed to.** The fix is `flock(2)` (or a `.lock` sibling) around the
read-modify-write, with next-id recomputed under the lock — identical design in either
language:

- Rust: `fs2`/`fs4` file locks, or advisory `flock` via `nix`, wrapping the existing
  `write_atomic()`. Reuses all current code.
- Go: `syscall.Flock` + the same temp-rename.

Since the write path is already Rust and already does atomic rename, the locking fix is a
~30-line change in `brana-core/src/tasks.rs`, not a language decision. **t-2166 should be
done in Rust regardless of this evaluation.**

---

## 6. Integration surface, if Go were ever adopted (for completeness)

If a future Go daemon happens, the integration contract with the existing Rust stack:

- **Don't reimplement backlog logic in Go.** Shell out to `brana backlog … --json` (the
  CLI already emits JSON on stdout) or call the MCP server. Keeps one source of truth for
  schema/validation, sidesteps the ADR-026 "two schemas" trap.
- **tasks.json**: never have the Go daemon write it directly while the Rust CLI/MCP also
  write — that multiplies the t-2166 race across languages. The daemon dispatches; brana
  owns the file.
- **Worktrees / git**: same discipline as the JS workflow today (compose, isolate, merge).

This is a thin-client pattern: Go (if ever) orchestrates; Rust owns data + logic.

---

## 7. Recommendation & follow-ups

1. **Do not adopt Go for the CLI, MCP, hooks, or any current component.** ADR-026 stands;
   no concurrency or performance case exists for the actual workload.
2. **Fix tasks.json locking (t-2166) in Rust** — `flock` + atomic rename. Unblocks the
   real concurrency pain. This research *feeds* t-2166; the fix is language-agnostic.
3. **Loop orchestration stays Claude-native** (`/loop` + `Workflow`) per the loop-native
   roadmap — feeds t-1994. No compiled language belongs there yet.
4. **Park Go as a tagged candidate for one specific future**: a standalone autonomous
   orchestration daemon, *if and when* it is specced. At that point run a real Go-vs-(Rust
   + tokio) decision, weighing "simpler supervisor" against "one language + reuse
   brana-core." Default expectation: Rust + tokio wins because the daemon needs brana-core
   logic.

**Net:** Go is a good language whose strengths (cheap network-scale I/O concurrency,
simple supervisors) don't intersect thebrana's current shape. Keep it on the shelf for a
hypothetical orchestration service; build nothing in it today.

---

## Sources

External (validation pass, 2026-06):
- [Rust vs Go: Which One to Choose in 2025 — JetBrains](https://blog.jetbrains.com/rust/2025/06/12/rust-vs-go/)
- [Tokio Versus Goroutines: Latency Under Adversarial Load — dev.to](https://dev.to/speed_engineer/tokio-versus-goroutines-latency-under-adversarial-load-5ll)
- [Go vs. Rust: Battling it Out Over Concurrency — dev.to](https://dev.to/shrsv/go-vs-rust-battling-it-out-over-concurrency-5c9)
- [Go Concurrency Patterns: Worker Pool, Fan-In/Fan-Out & Pipeline — dev.to](https://dev.to/serifcolakel/go-concurrency-patterns-worker-pool-fan-in-fan-out-pipeline-49pd)
- [workerpool package — gammazero/workerpool](https://pkg.go.dev/github.com/gammazero/workerpool)

Internal grounding:
- `docs/architecture/decisions/ADR-026-full-rust-mcp-architecture.md` — Rust decision, "no cross-language bridges"
- `docs/research/2026-06-11-loop-native-redesign.md` — foreman/task-crew, rehearsal findings
- `docs/architecture/decisions/ADR-052-close-queue-architecture.md` — Rust-owned atomic writes
- `system/cli/rust/crates/brana-core/src/tasks.rs` — tasks.json write path (t-2166 surface)
