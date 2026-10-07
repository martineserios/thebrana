#!/usr/bin/env bash
# t-3488 — full-power ruflo trial: isolated, idempotent setup.
# Never touches the live install: no -g, no npx, HOME/CLAUDE_CONFIG_DIR/CLAUDE_FLOW_MEMORY_PATH all point into $T.
set -euo pipefail

T="${RUFLO_TRIAL_DIR:-$HOME/enter_thebrana/ruflo-trial}"
B="${BRANA_REPO:-$HOME/enter_thebrana/thebrana}"
RUFLO_VER=3.55.0
GUIDANCE_VER=3.0.0
# Core @claude-flow packages the CLI imports but ruflo@3.55.0 does not ship. @claude-flow/core is imported
# too but is NOT published on npm (2026-10-07). Domain plugins (healthcare, legal, financial, …) deliberately omitted.
CORE_PKGS=(
  @claude-flow/mcp@3.1.0 @claude-flow/swarm@3.0.1 @claude-flow/claims@3.0.0
  @claude-flow/embeddings@3.0.0-alpha.45 @claude-flow/performance@3.0.0 @claude-flow/testing@3.0.0
  @claude-flow/plugins@3.0.1 @claude-flow/aidefence@3.0.3 @claude-flow/integration@3.0.0
  @claude-flow/teammate-plugin@1.0.0-alpha.1 @claude-flow/browser@3.0.0 @claude-flow/codex@3.0.3
)

mkdir -p "$T/proj" "$T/home/.claude" "$T/memory"
cd "$T"
[ -f package.json ] || npm init -y >/dev/null
npm install --save-exact --no-audit --no-fund "ruflo@$RUFLO_VER" "@claude-flow/guidance@$GUIDANCE_VER" "${CORE_PKGS[@]}" >> "$T/npm-install.log" 2>&1
R="$T/node_modules/.bin/ruflo"
run() { HOME="$T/home" CLAUDE_FLOW_MEMORY_PATH="$T/memory" "$R" "$@"; }

cd "$T/proj"
git rev-parse --git-dir >/dev/null 2>&1 || git init -q -b dev
git config user.email trial@local; git config user.name trial

# init — every flag that would touch the real ~/.claude is OFF:
#   --no-global (no ~/.claude/CLAUDE.md pointer block)  --no-plugin-install (no `claude plugin install` into the real config)
#   --no-signup --no-skills-sh --no-codex-detect        (no enrollment / registration / Codex detection)
if [ ! -f .claude/settings.json ]; then
  run init --full --with-embeddings --all-agents --no-global --no-signup --no-skills-sh --no-codex-detect --no-plugin-install
fi

# .mcp.json: init writes `npx -y ruflo@latest` — rewrite to the local pinned binary (ADR-033).
python3 - "$T" <<'PY'
import json, sys
T = sys.argv[1]; p = '.mcp.json'
d = json.load(open(p)) if __import__('os').path.exists(p) else {'mcpServers': {}}
d.setdefault('mcpServers', {})['claude-flow'] = {
    'command': f'{T}/node_modules/.bin/ruflo', 'args': ['mcp', 'start'],
    'env': {'HOME': f'{T}/home', 'CLAUDE_FLOW_MEMORY_PATH': f'{T}/memory'}}
json.dump(d, open(p, 'w'), indent=2)
PY

# Constitution: brana's rules appended once to the project CLAUDE.md (what `guidance compile` reads).
MARK='<!-- brana-rules-constitution -->'
if ! grep -q "$MARK" CLAUDE.md 2>/dev/null; then
  { echo; echo "$MARK"; echo "# Trial constitution — brana rules for guidance compile"
    for f in "$B"/system/rules/*.md; do [ "$(basename "$f")" = README.md ] && continue
      echo; echo "<!-- $(basename "$f") -->"; cat "$f"; done; } >> CLAUDE.md
fi

run embeddings init --force >/dev/null
run guidance compile | grep -E 'Total rules|failed' || true
run autopilot config --max-iterations 20 --timeout 60 >/dev/null 2>&1 || true

# Mods: not in the npm package — only via a GitHub marketplace clone. Keep it in the SCRATCH config dir and pin by SHA.
export CLAUDE_CONFIG_DIR="$T/home/.claude"
MP="$T/home/.claude/plugins/marketplaces/ruflo"
[ -d "$MP" ] || claude plugin marketplace add ruvnet/ruflo
{ echo "ruflo npm: $RUFLO_VER"; echo "@claude-flow/guidance: $GUIDANCE_VER"
  echo "marketplace: git@github.com:ruvnet/ruflo.git @ $(git -C "$MP" rev-parse HEAD) ($(git -C "$MP" log -1 --format=%cI))"
  echo "claude: $(claude --version 2>/dev/null | head -1)"; echo "node: $(node --version)"; } > "$T/PIN.txt"

echo "== verify =="
run guidance status | grep -E 'Total rules|Shard' || true
run mods doctor || true
run hooks list | tail -1 || true
cat "$T/PIN.txt"
cat <<EOF

MANUAL (interactive terminal, run session):
  cd $T/proj && HOME=$T/home $R policy init --mode enforce      # refuses non-interactive terminals by design
  cp ~/.claude/.credentials.json $T/home/.claude/ && chmod 600 $T/home/.claude/.credentials.json   # parity/mods arm; DELETE after the run
  CLAUDE_CONFIG_DIR=$T/home/.claude claude plugin install ruflo-mods@ruflo --scope project
  HOME=$T/home $R daemon start && HOME=$T/home $R autopilot enable
Never pass --claude without --no-auto-permissions. Never run anything against the thebrana checkout.
EOF
