# Judge Sizing (shared)

Single authority for the ADR-082 sizing ladder (rungs 0–2): the deterministic
function mapping a build beat's machine-readable inputs to its judge/team shape,
plus the hard-signals table, critical-section path list, brief library, spawn
contracts, and escaped-defect log helpers.

**Decision:** [ADR-082](../../../docs/architecture/decisions/ADR-082-multi-agent-sizing-function.md)
(frozen — changing a rung or signal is an ADR amendment, then a one-line edit here).
**Spec:** [judge-escalation-valve.md](../../../docs/architecture/features/judge-escalation-valve.md).
**Wired by:** `challenger-gate.md` §Sizing valve (judge side), `build/phases/build-loop.md`
(in-loop critic), `build/phases/load.md` Step 0d (ac_state surface).

The ladder in one line: **rung 0** single challenger (floor, today's default) →
**rung 1** +sibling-path finder (effort ≥ M, or code touching a critical section) →
**rung 2** full funnel (any hard signal fired). Signals only raise, never lower;
no rung persists past the beat that armed it.

<!-- JUDGE-SIZING-BLOCK -->
```bash
# Exit contract — resolve_judge_rung:
#   prints exactly one of 0|1|2 at exit 0   (the armed rung)
#   exit 2  — the valve itself is broken (empty signals table, unknown signal
#             name). LOUD by design: a broken valve must never silently de-arm
#             to rung 0 (silent de-arming) nor default to rung 2 (cost explosion).
#             Precedent: exit-contract-lint.sh registry rule, NOT branch-prefix
#             (which degrades); only branch-prefix's test pattern is copied here.

# --- Hard signals (ADR-082 §3) — the arming vocabulary. Data, not code. ---
# Guard is the plain counter below, never ${#ARR[@]} under set -u
# (pattern_set-u-empty-assoc-array-fails-open).
JUDGE_SIGNALS="RECONSIDER_SEV4 PASS_WITH_GAPS CRITICAL_PATH SIBLING_VERDICT ESCAPED_DEFECT_AREA"
JUDGE_SIGNALS_COUNT=5

# --- Critical-section path prefixes (ADR-082 §1 seed list). One line per entry. ---
JUDGE_CRITICAL_PATHS="system/cli/rust/crates/brana-core/src
system/hooks
bootstrap.sh
system/skills/_shared/challenger-gate.md"

resolve_judge_rung() {
  local effort="${1:-}" nature="${2:-}" crit="${3:-0}" signals_csv="${4:-}"
  [ "$effort" = "null" ] && effort=""

  # Broken-valve guards first — LOUD, never a silent rung.
  if [ "${JUDGE_SIGNALS_COUNT:-0}" -le 0 ]; then
    echo "judge-sizing: signals table empty — valve broken" >&2
    return 2
  fi
  if [ -n "$signals_csv" ]; then
    local s
    for s in ${signals_csv//,/ }; do
      case " $JUDGE_SIGNALS " in
        *" $s "*) : ;;
        *) echo "judge-sizing: unknown signal '$s' — valve broken" >&2; return 2 ;;
      esac
    done
    # Any recognized hard signal → rung 2. Signals select the row, they don't stack.
    printf '2'; return 0
  fi

  # Rung 1: effort >= M, OR code nature with a critical-section hit.
  case "$effort" in M|L|XL) printf '1'; return 0 ;; esac
  if [ "$nature" = "code" ] && [ "$crit" = "1" ]; then
    printf '1'; return 0
  fi

  # Rung 0: the residual floor — every remaining input lands here.
  printf '0'; return 0
}

# nature_class(kind, "file1 file2 ...") → code|procedure|docs — riskiest wins
# (code > procedure > docs). kind sets a floor class; each diff file maps to a
# class; the max governs (ADR-082 spec assumption, challenge-confirmed).
nature_class() {
  local kind="${1:-}" files="${2:-}" best=0 c f
  case "$kind" in
    feature|fix|refactor|test) best=2 ;;
    ops)                       best=1 ;;
    *)                         best=0 ;;   # docs/design/research/null → docs floor
  esac
  for f in $files; do
    case "$f" in
      *.rs|*.sh|*.py|*.ts|system/hooks/*|system/scripts/*) c=2 ;;
      system/skills/*|system/rules/*|system/agents/*)      c=1 ;;
      *)                                                   c=0 ;;
    esac
    [ "$c" -gt "$best" ] && best=$c
  done
  case "$best" in 2) printf 'code' ;; 1) printf 'procedure' ;; *) printf 'docs' ;; esac
}

# criticality_hit("file1 file2 ...") → 1 if any file matches a critical prefix, else 0
criticality_hit() {
  local files="${1:-}" f p
  for f in $files; do
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$f" in "$p"|"$p"/*) printf '1'; return 0 ;; esac
    done <<< "$JUDGE_CRITICAL_PATHS"
  done
  printf '0'
}

# blind_author_arms(rung, ac_state, nature) → yes|no  (ADR-082 §5 precondition:
# rung >= 1 AND approved AC AND testable code nature). Opt-in mechanism — the
# pilot gates default-on promotion only, never this arming rule.
blind_author_arms() {
  local rung="${1:-0}" ac_state="${2:-none}" nature="${3:-docs}"
  if [ "$rung" -ge 1 ] 2>/dev/null && [ "$ac_state" = "approved" ] && [ "$nature" = "code" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

# parse_sibling_verdict(verdict_text) → yes|no|missing — signal 4's recorded
# verdict field. "missing" = prompt drift: treat as NOT fired, log the omission
# (the caller records it in the beat report).
parse_sibling_verdict() {
  local text="${1:-}" line
  line=$(printf '%s' "$text" | grep -io 'siblings:[[:space:]]*\(yes\|no\)' | head -1)
  case "$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')" in
    *yes) printf 'yes' ;;
    *no)  printf 'no' ;;
    *)    printf 'missing' ;;
  esac
}

# append_escaped_defect(log_path, area, signal, rung, verified_findings, cost_tokens [, control_arm_json])
# Appends one JSONL record (ADR-082 §7 minimum shape). Creates the file on first firing.
append_escaped_defect() {
  local log="${1:?}" area="${2:?}" signal="${3:?}" rung="${4:?}" findings="${5:-0}" cost="${6:-0}" control="${7:-}"
  local extra=""
  [ -n "$control" ] && extra=",\"control_arm\":$control"
  printf '{"date":"%s","area":"%s","signal":"%s","rung_armed":%s,"verified_findings":%s,"cost_tokens":%s%s}\n' \
    "$(date +%Y-%m-%d)" "$area" "$signal" "$rung" "$findings" "$cost" "$extra" >> "$log"
}

# judge_area_weight(area_prefix [, log_path]) → count of records in the 30-day
# window whose area prefix-matches. Signal 5 (ESCAPED_DEFECT_AREA) fires on
# count >= 1. Absent/empty log → 0 (a real negative, never an error): the
# stigmergy trail — deposits arm, the window evaporates (ADR-082 §3/§7).
judge_area_weight() {
  local area="${1:?}" log="${2:-docs/ops/escaped-defects.jsonl}"
  [ -f "$log" ] || { printf '0'; return 0; }
  local cutoff count
  cutoff=$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)
  count=$(jq -r --arg a "$area" --arg c "$cutoff" \
    'select(.date >= $c) | select(.area | startswith($a)) | .date' "$log" 2>/dev/null | wc -l)
  printf '%s' "${count:-0}"
}

# --- Brief library (ADR-082 §4a) + subset-only allowlists (§4e). Data. ---
# Format: name|nature-router-key|tool allowlist (space-separated)
JUDGE_BRIEFS="second-variant|code|Read Grep Glob
concurrency-lock|code|Read Grep Glob
read-only-claims|procedure|Read Grep Glob
denied-verb-completeness|procedure|Read Grep Glob
contract-ac-fidelity|docs|Read Grep Glob"
JUDGE_BRIEF_COUNT=5

# Verbs no panel role may ever hold (runner manifest, ADR-079/080). A brief
# allowlist may only NARROW the base tool set — never contain these.
JUDGE_DENIED_VERBS="ac-approve wave-set-status batch-approve merge git-push backlog-write"
JUDGE_DENIED_COUNT=6

# judge_allowlist_violations() → prints "brief:verb" per violation; empty = §4e AC holds
judge_allowlist_violations() {
  local line name tools v
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%%|*}"
    tools="${line##*|}"
    for v in $JUDGE_DENIED_VERBS; do
      case " $tools " in *" $v "*) printf '%s:%s\n' "$name" "$v" ;; esac
    done
  done <<< "$JUDGE_BRIEFS"
}
```
<!-- /JUDGE-SIZING-BLOCK -->

> The `JUDGE-SIZING-BLOCK` markers are load-bearing:
> `tests/procedures/test-judge-sizing.sh` extracts exactly that span and sources it,
> so the test always exercises the shipped source. Do not remove or rename them,
> and keep the fences inside the markers.

## Brief router

Two finder briefs per rung-2 firing, selected by the beat's `nature_class`:

| Nature | Finder briefs |
|---|---|
| code | second-variant + concurrency-lock |
| procedure | read-only-claims + denied-verb-completeness |
| docs | read-only-claims + contract-ac-fidelity |

Rung 1 always uses **second-variant** alone (the probe's dominant miss class —
3 of 4 verified misses were sibling-path blindness).

## Spawn contracts

Contract-level prompt requirements for every panel role (ADR-082 §4, all
probe-validated): **blinding** (finders read the diff only — no task notes, no
backlog, no git history), **"empty findings are a respectable answer"** stated
verbatim, parallel spawns never cascading, and subset-only tool allowlists
(the `JUDGE_BRIEFS` data above — `judge_allowlist_violations()` must print
nothing).

### Finders (rung 1–2)

Mid-tier model (sonnet). Adversarial-hunt stance. Context: diff only. Prompt
skeleton: brief text + "Empty findings are a respectable answer" + the diff.
Output: numbered findings with file:line, severity 1–5, plus the recorded
verdict field `SIBLINGS: yes|no — paths` (signal 4's source; `missing` = treat
as not-fired, log the omission).

### Filter (rung 2)

Haiku. Dedup findings against each other and against the beat's recorded
challenger findings; drop intermediate-state noise. Never invents; only merges
and drops.

### Verify (rung 2)

Strongest available tier (opus/fable). Default-refute stance ("assume the
finding is wrong; confirm only with file:line evidence"). Context: full repo
access. Split verdicts (verifiers disagree) surface as verdict class `SPLIT`
to the human valve — never suppressed to FALSE_POSITIVE.

### In-loop critic (rung 2, build-team side)

Fresh-context sonnet spawned at each beat boundary during BUILD (see
`build/phases/build-loop.md` §In-loop critic). Explicitly spawned, never inline
self-review (Actor≠Evaluator, ADR-080 §3). Rungs 0–1 keep critique at CLOSE.

### Blind test-author (rung ≥ 1, opt-in)

Arms only when `blind_author_arms(rung, ac_state, nature)` prints `yes` —
rung ≥ 1 AND `ac_state: approved` AND code nature. When it does not arm, the
beat report states why (e.g. `did not arm: AC unapproved`) — an unarmed
mechanism must be observable, never silent (ADR-082 §2 Timing).

Contract: the test-author receives ONLY the task's approved `acceptance_criteria`
and the repo's test conventions — never the implementation plan, never the diff.
It writes failing tests; the red-verification hook registers them with a content
hash (`tests_hashes`), and the builder implements until green. Default-on
promotion is pilot-gated (ADR-082 §6); until then the mechanism is opt-in per
beat.

## Field notes

(none yet — first firing seeds this section)
