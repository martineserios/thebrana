
# Align — Active Project Alignment

DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT.

Creates files, configures structure, and implements practices. Unlike `/brana:onboard` (diagnostic, read-only), this skill actively builds. Replaces `/project-align` and `/venture-align`.

## When to use

Initial setup of a new project, or when an existing project needs structural alignment. Run `/brana:onboard` first for the diagnostic — `/brana:align` implements what `/brana:onboard` finds.

---

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: DISCOVER, ASSESS, PLAN, IMPLEMENT, VERIFY, DOCUMENT.

**Plan mode:** Enter plan mode for DISCOVER and ASSESS (read-only diagnostic phases). Exit plan mode before IMPLEMENT.

---

## Phase 0: DISCOVER

Before assessment, gather context. This shapes tier, CLAUDE.md content, and implementation depth.

**Ask what can't be inferred. Skip what's obvious from the codebase.**

### Auto-detect project type

Same detection as `/brana:onboard`: check for manifests (code) and venture dirs/keywords (venture). Classify as code, venture, or hybrid.

### Brainstorm / research repo detection (errata #154)

Before applying the venture or code checklist, check for content-only repos:

```bash
total=$(find . -not -path '*/.*' -type f | wc -l)
md=$(find . -not -path '*/.*' -name '*.md' -type f | wc -l)
has_src=$([ -d src ] && echo 1 || echo 0)
has_manifest=$(ls package.json Cargo.toml pyproject.toml setup.py go.mod 2>/dev/null | wc -l)
```

**Classify as `brainstorm`** if:
- No `src/` directory AND no manifest files AND >80% of files are `.md`
- OR `type: brainstorm` declared in `.claude/CLAUDE.md`

**On brainstorm detection:** Auto-select Foundation-only scope: F1, F5, F6, .gitignore. Skip venture/code checklists entirely. Log to user:
> "Brainstorm/research repo detected (no src/, no manifests, >80% markdown). Applying Foundation-only scope (F1, F5, F6, .gitignore). Override with 'full venture' or 'full code' to run the complete checklist."

Offer override before proceeding.

### Greenfield questions
1. What is this project? One-sentence description.
2. Tech stack? (code) / Business model? (venture)
3. Scale and lifecycle? Experiment / production / long-lived?
4. Domain? The business problem, not the tech.
5. What are you building first?

### Brownfield questions
1. Existing conventions to keep?
2. Domain? (if not obvious)
3. Building next?

---

## Phase 1: ASSESS

Spawn the `client-scanner` (code) or `venture-scanner` (venture) agent. If unavailable, run manually.

### Code checklist (28 items)

| Group | Items |
|-------|-------|
| Foundation (F1-F5) | Git, CLAUDE.md, rules, conventional commits, inbox |
| SDD (S1-S5) | docs/decisions/, ADR, PreToolUse hook, /decide, spec-first |
| DDD (D1-D4) | Glossary, bounded contexts, ubiquitous language, model |
| TDD (T1-T4) | Test framework, runner, tdd-guard, coverage |
| Quality (Q1-Q4) | Linter, CI, security, code review |
| PM & Memory (P1-P5) | Issues, patterns, portfolio, recall, memory hygiene |
| Verification (V1-V3) | Hook fires, tests pass, alignment report |

### Venture checklist (stage-cumulative)

| Group | Items |
|-------|-------|
| Foundation (F1-F5) | Description, decision log, metrics, cadence, inbox |
| Validation (V1-V5) | Hypothesis, MVP, experiments, burn rate, referrers |
| Growth (G1-G5) | OKRs, SOPs, meetings, hiring, decision framework |
| Scale (S1-S5) | Org chart, dept OKRs, automation, dashboard, onboarding |

Each item: **present**, **partial**, **missing**. Output gap report with visual progress bars.

---

## Phase 2: PLAN

### Tier selection (code projects)
- **Minimal** — 4 items, quick, good for experiments
- **Standard** — 13 items, recommended for shipping projects
- **Full** — 28 items, for long-lived/complex projects

### Stage selection (venture clients)
Items are stage-cumulative. Only implement up to the current stage.

Present the plan and **wait for user approval**.

---

## Phase 3: IMPLEMENT

Execute item by item. Ask for confirmation before each major step.

### Code foundation items

**F1 — Git:** Skip if `.git/` exists.
**F2 — CLAUDE.md:** Create/merge `.claude/CLAUDE.md` with project description, stack, conventions, domain.

**Merge-safety (errata #140):** Before appending any `## Section`, grep the existing file for that heading. If it already exists, merge content under it — do not create a duplicate heading. Flag conflicts to the user.
```bash
grep -q "^## Docs" .claude/CLAUDE.md 2>/dev/null && echo "heading exists — merge" || echo "heading missing — append"
```

**Content constraints (errata #141):** Apply `claudemd.md` Step 2 include/exclude rules when writing CLAUDE.md content. Specifically omit:
- Frequently-changing fields (Status, Key Contacts with "TBD" values)
- Conventions CC already knows (conventional commit type lists — just give the format + example)
- Verbose tables when a compact inline list suffices (compress stack to one line unless >10 components)
- File-by-file descriptions or long explanations

Goal: CLAUDE.md should be <60 lines after F2. If it exceeds 80 lines, run `/brana:claudemd` audit before proceeding to VERIFY.
**F3 — Rules:** Copy relevant rules from `~/.claude/rules/`. Stack-specific rules get path scoping.
**F4 — Commits:** Document conventional commits in CLAUDE.md.
**F5 — Inbox:** Ensure `inbox/` exists and is gitignored. Create if missing:
```bash
mkdir -p inbox
# Add to .gitignore if not already present
grep -q '^inbox/' .gitignore 2>/dev/null || echo 'inbox/' >> .gitignore
```
**F6 — Attribution:** Ensure `.claude/settings.local.json` suppresses CC attribution lines (undercover mode). Merge if file exists; create if not:
```bash
mkdir -p .claude
SETTINGS=".claude/settings.local.json"
if [ -f "$SETTINGS" ]; then
  # Merge attribution block into existing file (python3 safe JSON merge)
  uv run python3 -c "
import json, sys
with open('$SETTINGS') as f:
    s = json.load(f)
s.setdefault('attribution', {})
s['attribution']['commit'] = ''
s['attribution']['pr'] = ''
with open('$SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
print('merged')
"
else
  echo '{"attribution":{"commit":"","pr":""}}' | uv run python3 -c "
import json,sys; print(json.dumps(json.load(sys.stdin), indent=2))
" > "$SETTINGS"
  echo 'created'
fi
```
Skip if `.claude/settings.local.json` already has both `attribution.commit` and `attribution.pr` set to `""`.

### Code SDD items

**S1:** `mkdir -p docs/decisions`
**S2:** Create first ADR pre-populated from DISCOVER answers.
**S3:** Verify PreToolUse hook is installed (run `deploy.sh` if needed).
**S4-S5:** Verify skill availability, document convention.

### Code TDD items

**T1:** Detect/initialize test framework from stack.
**T2:** Run tests, verify exit 0.
**T3:** Check tdd-guard availability.
**T4:** Configure coverage baseline.

### Venture foundation items

**F1 — Description:** Create/merge CLAUDE.md with business context (stage, domain, team, framework).
**F2 — Decision log:** `mkdir -p docs/decisions`. Create ADR-001 for framework selection.
**F3 — Metrics:** `mkdir -p docs/metrics`. Create README with stage-appropriate metric tables.
**F4 — Cadence:** `mkdir -p docs/meetings`. Create cadence.md with stage-appropriate meeting schedule.
**F5 — Inbox:** Ensure `inbox/` exists and is gitignored (same as code F5).

### Venture stage items

Create stage-appropriate templates: hypothesis docs, experiment tracking, OKR templates, SOP directory, hiring plan, referrer tracking — based on the assessed stage.

### Important rules
- **Never overwrite existing files** — read first, merge, ask on conflict
- **Brownfield: respect existing conventions**
- **Venture: don't systematize too early** — wait for 3+ repeats before SOP

---

## Phase 4: VERIFY

Re-run the checklist. Compare before/after:

```
ALIGNMENT REPORT
================
Type: {Code | Venture | Hybrid}
Tier/Stage: {Standard | Growth | ...}

                Before    After
Foundation:     ■■□□      ■■■■    2/4 → 4/4
SDD:            □□□□□     ■■■■□   0/5 → 4/5
                ──────    ──────
Total:          2/9       8/9

Remaining gaps:
  S5 — Spec-first convention (builds over time)
```

---

## Phase 5: DOCUMENT

1. **Store in ruflo:**
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   [ -n "$CF" ] && cd "$HOME" && $CF memory store \
     -k "alignment:{PROJECT}:{date}" \
     -v '{"type": "{code|venture}-alignment", "score_before": N, "score_after": N}' \
     --namespace alignment \
     --tags "client:{PROJECT},type:alignment" \
     --upsert
   ```
2. **Update portfolio.md** with project entry
3. **Save `.claude/alignment-report.md`** in the project

---

## Rules

- **Ask for clarification when needed.** Unusual structure, unclear domain, ambiguous stage — ask.
- **Never overwrite existing files.** Read first, merge, ask on conflict.
- **Respect the user's tier/stage choice.** Recommend, don't override.
- **Stage drives venture structure.** Don't implement Growth items for Discovery businesses.
- **Graceful degradation.** Claude-flow unavailable → auto memory fallback.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:align — {STEP}`
2. The `in_progress` task is your current phase — resume from there
3. Check `.claude/alignment-report.md` if VERIFY was already reached
