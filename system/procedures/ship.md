
# Ship

Push a build out the door. Six steps: pre-flight, deploy, document, verify, monitor, rollback. Each step adapts to the project — detects test frameworks, deploy methods, and registries automatically. Manual override is always available.

## Invocation

```
/brana:ship                        — detect target from context
/brana:ship bootstrap              — deploy the brana identity layer
/brana:ship t-123                  — ship the work from a specific task
/brana:ship npm                    — publish an npm package
```

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: PRE-FLIGHT, DEPLOY, DOCUMENT, VERIFY, MONITOR, ROLLBACK.

ROLLBACK is conditional — only executed if VERIFY or MONITOR fails.

## Rules

- **Never auto-deploy without user confirmation.** Pre-flight ends with an explicit gate.
- **Pre-flight failure blocks deploy.** Hard gate — no override.
- **Rollback is always optional and prompted.** Never auto-rollback.
- **Project detection is best-effort.** Always offer manual override via AskUserQuestion when detection is ambiguous.

---

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__hive-mind_init,mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")

## Steps

### Step 0: Goal injection

Set session orientation before any checks run:
- **If task_id known:** extract `AC:` lines from task context (same pattern as `build.md` Step 0 sub-step 0). If found, call `/goal {criteria}`.
- **If no task_id or no `AC:` lines:** call `/goal "ship {target}: all checks pass, deployed, verified"` where `{target}` is the npm package name, task subject, or branch name.
- Skip for `bootstrap` invocation — the goal is implicit.

### Step 1: Pre-flight — Is this safe to deploy?

Run all safety checks before touching anything external.

1. **Uncommitted changes** — `git status --porcelain`. If dirty, warn and ask whether to proceed.

2. **Tests** — detect and run the project's test suite:

   | Indicator | Command |
   |-----------|---------|
   | `Cargo.toml` | `cargo test` |
   | `pytest.ini` / `pyproject.toml` [tool.pytest] / `tests/` | `uv run pytest` |
   | `package.json` with `test` script | `npm test` |
   | `Makefile` with `test` target | `make test` |
   | None detected | Skip with warning |

3. **Build** — does it compile/bundle?

   | Indicator | Command |
   |-----------|---------|
   | `Cargo.toml` | `cargo build --release` |
   | `package.json` with `build` script | `npm run build` |
   | `Makefile` with `build` target | `make build` |
   | None detected | Skip |

4. **Environment config** — check for required env vars. Look for `.env.example`, `docker-compose.yml` env sections, or deployment config files. Flag any that are unset.

5. **Task status** — if a task ID was provided (`$ARGUMENTS` matches `t-\d+`):
   ```bash
   brana backlog show <id>
   ```
   Verify status is `in-progress` or `done`. If `blocked` or `pending`, warn.

6. **Gate** — summarize pre-flight results and ask:

   ```
   AskUserQuestion: "Pre-flight passed. Deploy?"
   Options: ["Deploy now", "Abort"]
   ```

   If any check failed, change the prompt to include the failure summary and add a "Deploy anyway (force)" option.

   **If user selects Abort → stop. Do not proceed to Step 2.**

### Step 2: Deploy — Push it out

Detect the deploy method from project files, then execute.

**Detection order** (first match wins):

| Indicator | Method | Command |
|-----------|--------|---------|
| `bootstrap.sh` in repo root | Bootstrap | `./bootstrap.sh` |
| `railway.json` or `railway.toml` | Railway | `railway up` |
| `Dockerfile` | Docker | `docker build -t <name> . && docker push <name>` |
| `package.json` with `publish` script | npm publish | `npm publish` |
| `Cargo.toml` with `publish = true` (or no `publish = false`) | Cargo publish | `cargo publish` |
| `deploy.sh` in repo root | Custom script | `./deploy.sh` |
| None detected | Manual | AskUserQuestion for deploy command |

**Run the detected command.** Capture stdout and stderr — they feed into the verify step.

If the deploy command exits non-zero, report the error and skip to Step 6 (Rollback).

### Step 3: Document — Record what shipped

1. **Task update** — if a task ID was provided:
   ```bash
   brana backlog set <id> status completed
   ```

2. **Changelog** — if `CHANGELOG.md` exists, append an entry:
   ```markdown
   ## [version] — YYYY-MM-DD
   - <summary of what shipped, derived from git log or task description>
   ```

3. **Version bump** — if applicable:

   | File | Action |
   |------|--------|
   | `Cargo.toml` | Bump `version` field (patch unless user specifies) |
   | `package.json` | Bump `version` field (patch unless user specifies) |

   Ask user before bumping: `AskUserQuestion: "Bump version? Currently X.Y.Z" Options: ["Patch → X.Y.Z+1", "Minor → X.Y+1.0", "Major → X+1.0.0", "Skip"]`

4. **Commit** doc changes (changelog, version bump) if any were made.

### Step 4: Verify — Did it work?

Run post-deploy checks to confirm the deploy succeeded.

| Deploy type | Verification |
|-------------|-------------|
| CLI / binary | Run `<binary> --version` or `<binary> --help` |
| Web service | `curl -sf <health-endpoint>` if URL is known |
| npm package | `npm view <package>@latest version` |
| Cargo crate | `cargo search <crate> --limit 1` |
| Bootstrap | `./bootstrap.sh --check` if supported |
| Docker | `docker run <image> --version` or health check |
| Custom | Ask user for verification command |

Report result:
- **Success**: "Deploy verified — [details]"
- **Failure**: "Verification failed: [reason]" → proceed to Step 6

### Step 5: Monitor — Is it stable?

This step is **advisory** — print guidance, don't block.

| Deploy type | Guidance |
|-------------|----------|
| Web service | "Watch logs for 15 min: `railway logs` / `docker logs -f <container>`" |
| CLI / binary | Run a representative command to exercise the new version |
| npm package | "Check https://www.npmjs.com/package/<name> for published version" |
| Cargo crate | "Check https://crates.io/crates/<name> for published version" |

If the representative command fails or output looks wrong, flag it and suggest proceeding to Step 6.

### Step 6: Rollback (conditional) — Undo if needed

Only execute if Step 4 or Step 5 detected a problem.

```
AskUserQuestion: "Verification/monitoring detected issues. Rollback?"
Options: ["Rollback to previous version", "Keep current deploy", "Investigate first"]
```

**If user selects Rollback:**

| Deploy type | Rollback method |
|-------------|----------------|
| Git-based (bootstrap, scripts) | `git revert HEAD` |
| Railway | `railway rollback` |
| Docker | Re-tag previous image, push |
| npm | `npm unpublish <pkg>@<version>` (if within 72h) |
| Cargo | Cargo doesn't support unpublish — `cargo yank` instead |
| Custom | Ask user for rollback command |

**If user selects "Investigate first"** — stop and hand control back to the user.

---

## Project Detection Summary

The skill builds a deploy profile on entry by scanning the project root:

```
Scan: Cargo.toml, package.json, Dockerfile, railway.json, railway.toml,
      bootstrap.sh, deploy.sh, Makefile, .env.example, docker-compose.yml
```

This profile drives all 6 steps. When detection is ambiguous (e.g., both `Dockerfile` and `railway.json` exist), ask the user which method to use.
