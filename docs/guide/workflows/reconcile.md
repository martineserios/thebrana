# Reconciling Drift

`/brana:reconcile` is the unified maintenance command for the brana system. It detects and fixes drift between specs and implementation, catches security issues, cascades spec changes, and cleans up the knowledge system.

## Quick start

```
/brana:reconcile                          -- consistency check (default)
/brana:reconcile --scope security         -- secrets, permissions, MCP count
/brana:reconcile --scope propagation      -- cascade pending errata through doc layers
/brana:reconcile --scope knowledge        -- stale dimensions, event log bloat, ruflo noise
/brana:reconcile --scope all              -- full system health check
```

## The 4 scopes

### consistency (default)

Detects documentation drift: hardcoded counts in ADRs and living docs that no longer match the actual implementation. Low-severity, informational.

**Run when:** specs were manually edited, after `/brana:maintain-specs` cascades, or before starting a new build phase.

**Typical findings:** "ADR-012 says '27 skills' but actual count is 32", "ADR missing status frontmatter".

**Cadence:** Before each build phase, or monthly.

---

### security

6 checks for credential leaks, dangerous settings, and MCP token tax.

**Checks:**
1. Secrets in config files, CLAUDE.md, rules, skills, hooks (14 regex patterns)
2. Hook permission escalation (`chmod 777`, `chown` to root)
3. MCP server count (>5 active servers = flag — each adds 4–17K tokens/session)
4. Dangerous settings (`bypassPermissions: true`, `allowedTools: ["*"]`)
5. Unencrypted credential files (`.env`, `*.pem`, `*.key` outside `.gitignore`)
6. Acquired skill safety (dangerous allowed-tools, external URLs, hook registration)

**Run when:** before sharing config, after adding MCP servers, after installing acquired skills, or monthly.

**Cadence:** Monthly, or immediately after any config change.

---

### propagation

Cascades pending errata through the spec layer hierarchy: dimension → reflection → roadmap. Also re-evaluates reflections against dimension docs and checks the spec graph for consistency.

**Run when:** after editing dimension docs, when errata accumulate in doc 24, or as part of a full maintenance cycle.

**Cadence:** After any spec doc edits, or monthly.

---

### knowledge

DECAY hygiene for the knowledge system: stale dimension docs, event log bloat, and low-value ruflo pattern entries.

**Checks:**
1. Dimension docs >90 days old with no recent ruflo search hits → mark stale
2. Event log entries >90 days old (>20 entries → offer to archive with digest)
3. Ruflo pattern entries >180 days old with confidence <0.3 → offer to delete

**Run when:** after bulk indexing, when ruflo memory seems stale, weekly as routine hygiene.

**Cadence:** Weekly.

---

## What to expect

Reconcile always:
1. **Creates a worktree branch** (`chore/reconcile-YYYYMMDD`) — never modifies main directly
2. **Presents a drift report** and waits for your approval before making any changes
3. **Applies only auto-fixable changes** (text updates, config corrections, metadata) — never creates new skills or makes architectural changes
4. **Commits each logical group separately** with `chore(reconcile):` messages
5. **Logs findings to doc 24** (`docs/24-roadmap-corrections.md`)

For security scope: no auto-fix — security issues always require human judgment.

## After reconcile

Reconcile gives you a branch to merge, not a deployed change:

```bash
# Merge when ready
cd ~/enter_thebrana/thebrana
git merge --no-ff chore/reconcile-YYYYMMDD
git worktree remove ../thebrana-chore/reconcile-YYYYMMDD
git branch -d chore/reconcile-YYYYMMDD
```

Items that require building something new (a missing skill, a new hook) are deferred and logged as backlog tasks. Reconcile fixes drift in existing files — it doesn't build new capabilities.

## Consistency vs reconcile vs memory audit

| Tool | Checks | When |
|------|--------|------|
| `/brana:reconcile --scope consistency` | Spec docs vs implementation | Monthly, pre-build-phase |
| `/brana:reconcile --scope security` | Credentials, permissions, MCP tax | Monthly, post-config-change |
| `/brana:reconcile --scope propagation` | Errata cascade, reflection gaps | After spec edits |
| `/brana:reconcile --scope knowledge` | Stale knowledge, log bloat | Weekly |
| `/brana:memory review --audit` | Doc-to-doc contradictions | Monthly |

## Key rules

- **Plan then apply.** You always see the full drift report and approve before any changes happen. Reconcile never acts silently.
- **Materiality filter is strict.** Only drift that would cause wrong behavior or wrong implementation decisions is surfaced. Cosmetic differences are discarded.
- **Never auto-delete.** "Extra" items that specs don't mention get flagged for review — the user decides whether to remove them.
- **One branch, atomic commits.** All reconcile work happens on a single worktree branch.
