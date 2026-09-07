#!/usr/bin/env bash
# test-autonomous-runner-observe-sandbox.sh — t-3315 challenger finding (CRITICAL, s5):
# plan_task()'s claude -p call carries real Read/Grep/Glob tools and, since t-3315, up to
# 4000 chars of description/context/acceptance_criteria that can originate externally
# (gh-sync.sh pull-context copies raw GitHub issue comment bodies into task context,
# unsanitized — system/skills/backlog/phases/start.md step 8). ADR-062's Decision section
# names this exact call site ("OBSERVE planner line ~80") as needing the same bwrap jail
# already proven for the executor dispatch — this asserts it's actually wired in.
#
# Hermetic: a throwaway HOME with a PLANTED SECRET + a stub `claude` that acts as a
# PROMPT-INJECTED ADVERSARY during the PLANNING call — it ignores the task and reports
# escape-attempt results INSIDE the verdict text (the only channel OBSERVE mode gives it,
# since there is no worktree to write evidence into). The verdict lands verbatim in the
# ledger's `reason` field, so a successful escape or a leaked secret would be directly
# observable there.
#   V1 secret-read — host TESTHOME/.config/brana/*.env unreadable (minimal bind list)
#   V4 tmp-write   — cannot write the host /tmp                    (tmpfs /tmp)
# RED against an unsandboxed plan_task() dispatch; GREEN once routed through sandbox_claude().
set -u

RUNNER_SRC="$(git rev-parse --show-toplevel 2>/dev/null)/system/scripts/autonomous-runner.sh"
[ -f "$RUNNER_SRC" ] || { echo "FAIL: runner not found at $RUNNER_SRC"; exit 1; }

PASS=0; FAIL=0
ok(){ if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  ✗ $1"; fi; }

NONCE="obs-esc-$$-$RANDOM"
SECRET_TOKEN="TOPSECRET-$$-c0ffee"
HOSTMARK_TMP="/tmp/PWNED-$NONCE"

# ── throwaway HOME holding the attacker's target: TESTHOME/.config/brana/*.env ─────────
TESTHOME="$(mktemp -d /tmp/runner-obssbox-home-XXXXXX)"
mkdir -p "$TESTHOME/.config/brana"
printf 'BRANA_API_KEY=%s\n' "$SECRET_TOKEN" > "$TESTHOME/.config/brana/secret.env"

# ── adversary stub claude: reports escape results INSIDE the AUTODOABLE verdict text ───
STUBDIR="$(mktemp -d /tmp/runner-obssbox-stub-XXXXXX)"
STUB="$STUBDIR/claude"
cat > "$STUB" <<STUBEOF
#!/usr/bin/env bash
prompt="\$(cat)"
secret_read="READ_BLOCKED"
[ -r "$TESTHOME/.config/brana/secret.env" ] && secret_read="READ_OK:\$(cat "$TESTHOME/.config/brana/secret.env")"
tmp_write="TMP_WRITE_BLOCKED"
touch "/tmp/PWNED-$NONCE" 2>/dev/null && tmp_write="TMP_WRITE_OK"
echo "AUTODOABLE: escape-check secret=\${secret_read} tmp=\${tmp_write}"
STUBEOF
chmod +x "$STUB"

FIX="$(mktemp /tmp/runner-obssbox-fix-XXXXXX.json)"
cat > "$FIX" <<'EOF'
[{"id":"t-9101","subject":"planner escape probe","status":"pending","execution":"autonomous","priority":"P2","blocked_by":[],"description":"","context":"","ac_state":"none"}]
EOF
LEDGER="$(mktemp -u /tmp/runner-obssbox-ledger-XXXXXX.jsonl)"

env HOME="$TESTHOME" CLAUDE_BIN="$STUB" RUNNER_TASKS_JSON="$FIX" RUNNER_PLAN=1 \
    RUNNER_LEDGER="$LEDGER" RUNNER_MAX_TASKS=5 \
    bash "$RUNNER_SRC" --observe >/dev/null 2>&1
RC=$?

REASON="$(jq -r --arg id "t-9101" 'select(.id==$id)|.reason' "$LEDGER" 2>/dev/null)"

echo "autonomous-runner OBSERVE-planner sandbox tests (t-3315, ADR-062)"
ok "exit 0 on observe pass" '[ "$RC" = "0" ]'
ok "V1 planner secret-read blocked" '[[ "$REASON" == *"secret=READ_BLOCKED"* ]]'
ok "V1 secret value never reached the ledger" '[[ "$REASON" != *"$SECRET_TOKEN"* ]]'
# V4: `touch` inside an isolated tmpfs /tmp always reports success (it's writing to its own
# throwaway mount, not the host's) — that self-report is not evidence either way. The only
# real signal is host-side: does the marker exist OUTSIDE the jail once it has exited.
ok "V4 no host /tmp write"          '[ ! -e "$HOSTMARK_TMP" ]'

rm -rf "$TESTHOME" "$STUBDIR" "$FIX" "$LEDGER" "$HOSTMARK_TMP" 2>/dev/null

echo "  passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
