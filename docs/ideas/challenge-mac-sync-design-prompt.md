# Prompt: deep challenge of the Mac / two-machine design (for a fresh session)

Written 2026-10-03 at the end of the macOS-portability session (t-3436). Paste the block below into a new Claude Code session started in `~/enter_thebrana/thebrana`. Home of record for the artifacts it names: ADR-095, the pack spec, epic t-3372.

```
You are a hostile but fair reviewer. Your job is to try to BREAK what was designed and built in the
macOS-portability session of 2026-10-02/03, then tell me what to keep, simplify or kill. Do NOT build
anything, do NOT edit any file in the repo, do NOT merge or push. Output findings only.

## Read first (in this order, before forming any opinion)
1. Memory: project_mac-company-managed-constraints (standing constraints for the Mac).
2. docs/architecture/decisions/ADR-095-two-machine-memory-sync.md  and
   docs/architecture/features/mac-knowledge-pack.md. They live on the UNMERGED branch
   macos-portability/docs/t-3436-adr-095-revision (worktree ../thebrana-t-3436). If thebrana-9a has
   already landed t-3435 on dev, the ADR may carry its "Amendment 2026-10-03" section too.
3. Backlog: brana backlog tree t-3372, and t-3403, t-3436, t-3405..t-3410, t-3416..t-3420, t-3437..t-3440.
4. The shipped code (already on main): system/hooks/lib/portable.sh (p_timeout and the fallback lock),
   system/scripts/run-test-suites.sh, tests/hooks/test-portable.sh, tests/scripts/test-run-test-suites.sh.
5. Facts about the situation (owner-stated, treat as true): the Mac used for client tabz is
   company-managed (enrolled in the employer's device management), at a regulated company. The owner does NOT want to
   alarm the employer, and the assistant will not design anything to evade employer visibility.
   The Linux laptop is the owner's personal machine, always on, currently swapping heavily.

## What to attack (be specific, cite file:line or task id for every finding)
A. Is the premise right at all?
   - Does the Mac need anything beyond the thebrana plugin and the tabz repo? Is the whole pack (builder,
     hold queue, signing, pull step; 14+ tasks) overbuilt? What is the SIMPLEST thing that meets the real
     need (including "nothing" and "a manually curated bundle")? Compare cost against value honestly.
   - Is 'one-way, never back' too strict (lost value) or is manual promotion unrealistic?
B. Security and compliance reasoning
   - Personal IP and other clients' data on an employer-owned device, and personal GitHub credentials
     on it: ownership, discoverability, IP-assignment and MDM-escrow angles the ADR may have missed.
   - Does a private repo + scoped token + signed pack actually satisfy a regulated environment, or
     is that framing wrong? What would the company's compliance contact object to first?
   - Scope tag + client deny-list scan + hold queue: how does a client leak through paraphrase, a
     description without a name, a doc quoting a schema? Will the owner rubber-stamp the hold queue
     (see memory pattern_enforcement-systems-overbuild-then-revert)? Fail-closed or fail-open in practice?
   - Signing: where does the allowed-signers file live, who provisions the verifier key to a company
     laptop, what happens on key compromise or rotation?
   - tabz data in personal stores (personal GitHub repo, iCloud, USB, the Linux disk): is the
     remediation plan sufficient and in the right order?
C. Evidence quality (verify, do not trust my numbers)
   - 'ruflo pattern namespace is auto-generated error-recurrence telemetry': this rests on a sample of
     tags and lengths, not a full audit. Re-run it properly on ~/.swarm/memory.db (all namespaces) and
     say whether cancelling t-3404 was justified.
   - The client-exposure counts (46/206 notes, 566/855 session entries, ...) came from regex deny lists
     with false positives (unlock, crea, somos, linkedin); recompute with a proper client list from
     tasks-portfolio.json.
   - 'ruflo MCP drops are memory pressure' is a hypothesis, not a finding. What else could it be?
D. Correctness of the shipped code (t-3390 and neighbours)
   - p_timeout now prefers its own perl-setsid group-kill watchdog even when timeout(1) exists.
     Attack: setsid side effects (controlling tty, Ctrl-C, job control), perl as a new dependency,
     pgid reuse, nested sessions escaping the group, 'type -t' + relative paths, bash 3.2 array
     slicing under set -u, exit-code differences from GNU timeout (124 vs 137, 'Killed' stderr),
     callers in sync-state.sh / pipeline-digest.sh / index-knowledge.sh / hooks that pass functions,
     aliases or $CF word-splits, behaviour under memory pressure, the peer's added 2s default grace.
   - The heartbeat ticker subshell and the mktemp flag file: orphans, races, cleanup on kill.
E. Process
   - Did we duplicate or contradict other sessions' work (t-3388..t-3395, t-3435)? Which of the new
     tasks should be cancelled, merged or re-ordered? Check the M+ discipline rule (ADR task, test
     task before impl, spec task, docs task).

## How to run it
- Use /brana:challenge --deep, or spawn 3 brana:challenger agents in ONE message with separate lenses
  (security/compliance, correctness of code, simplicity/YAGNI). Give each <=6 named files or the diff
  inline; challengers hit their turn limit often, so tell each to "deliver your verdict by turn 8".
  >=2 agents flagging the same concern = HIGH; one = OBSERVATION.
- Re-derive numbers from the live stores yourself (read-only). Mark anything you could not verify.
- A finding that REMOVES a safety or recovery mechanism before its replacement exists is
  non-overridable (ADR-094 decision 7).

## Output (text only, no edits)
1. Verdict per component: KEEP / SIMPLIFY / KILL / BLOCKED-ON-OWNER, with one line why:
   ADR-095 decisions 1-5, the pack (builder, hold queue, signing, Mac pull), the threat model rows
   T1-T7, p_timeout group kill, run-test-suites heartbeat, the cancelled t-3404.
2. Ranked findings: severity (HIGH / MED / LOW), evidence (file:line, command output, task id), the
   concrete failure scenario, and the smallest root-cause fix (no patches: say what class of problem
   it is and close the class).
3. What I got wrong or overstated in the earlier session, plainly.
4. The 3 decisions I (the owner) should make first, and what would change your mind on each.
5. Proposed task changes (cancel / merge / re-scope), listed but NOT applied.
Then stop and wait for me.
```
