# Try the New Features — ADR-059 / ADR-060

Copy-paste prompts to exercise what shipped in the substrate + branch-strategy build.
**Each is self-contained — run one per fresh session.** Tracked by t-2167.

> **First, restart Claude Code once** so the new secret-scan PreToolUse hook is active (it's
> deployed but hooks load at session start).

---

## 1 · Autonomous runner — observe mode (safe, read-only)

```
Run the autonomous runner in observe mode over my backlog:
RUNNER_PLAN=1 bash system/scripts/autonomous-runner.sh --observe
Then show me the ledger and explain its would-run / would-park / excluded calls. Don't change anything.
```
**Expect:** scans all tasks, finds 0 eligible (nothing opted in), shows the default-deny gate working.

---

## 2 · Autonomous runner — one real task, end-to-end (worktree isolation + PR)

```
Pick one safe, small pending task (docs or lint kind), mark it execution:autonomous, then run the
autonomous runner on just that task: bash system/scripts/autonomous-runner.sh --run-one
Show me the ephemeral worktree it used, the runner/auto branch + commit it produced, and confirm
my live working tree and main were never touched. Do NOT merge — leave it for my review.
```
**Expect:** work in `/tmp/brana-runner/<id>`, a `runner/auto/<id>` branch with one commit, base pristine, worktree cleaned up.

---

## 3 · Secret-scan gate (t-2138)

```
Verify the secret-scan gate works: create a file containing a fake Slack bot token in the
standard format (the literal prefix x-o-x-b joined, then a dash, ten digits, a dash, ten more
digits, a dash, and 24 alphanumeric chars — generate the value yourself). Stage it, try to commit,
confirm the hook blocks it. Then change the token to "xoxb-REDACTED" and confirm that passes. Clean up after.
```
(The literal token isn't written here on purpose — a doc about secret-scanning must not carry a scannable token; GitHub push protection would flag this very file. Claude generates the test value at runtime.)
**Expect:** commit blocked with a secret-scan error; redacted version allowed.

---

## 4 · The new dev → main branch flow (ADR-060)

```
Make a small doc improvement following the new ADR-060 branch strategy: branch off dev (not main),
commit, and open a PR targeting dev. Explain how this would later promote dev → main = ship.
Don't merge.
```
**Expect:** a feature branch off `dev`, PR into `dev`; `main` stays the protected production line.

---

## 5 · Session unit-key routing (close-from-main guard, t-2152/t-2154)

```
Show me how session handoff routing now works: I'm on main. Run a minimal session write
(brana session write --minimal) and tell me where it routed and whether it warned about orphaning.
Then explain how the epic marker / focus would route it to its unit bucket instead.
```
**Expect:** a loud warning about closing from `main` with no epic, instead of silently orphaning.

---

## 6 · Native workflows — the substrate (ADR-059)

```
Use a hive-mind workflow to answer: "What's the riskiest assumption in brana's autonomous runner design?"
3 workers, haiku.
```
```
Run a sweep over system/scripts/autonomous-runner.sh looking for bugs and shell-robustness issues.
```
**Expect:** multi-agent fan-out → verify → synthesize, on your subscription. **Heaviest — real tokens.**

---

## 7 · bootstrap guard (quick, t-2151)

```
Confirm the bootstrap production guard: from a non-main branch, run ./bootstrap.sh and show it aborts;
then show that ./bootstrap.sh --check is still allowed.
```
**Expect:** abort off-main with guidance; `--check` works read-only.
