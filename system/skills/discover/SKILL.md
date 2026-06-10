---
name: discover
description: "Runtime catalog — list all installed skills, agents, and active hooks. Use when you want to know what's available."
model: haiku
effort: low
keywords: [discover, skills, agents, hooks, catalog, list, available, inventory]
task_strategies: [investigation]
group: core
allowed-tools:
  - Bash
status: stable
growth_stage: evergreen
---
# Discover — Runtime Catalog

Show all installed brana components at runtime. Fast listing, no heavy I/O.

## Step 1 — Skills

Run:
```
brana skills list --json
```

Parse the JSON array. Each item has `name`, `group`, `description` fields.
Sort by `group` then `name`. Truncate description to 60 chars.

Render:
```
## Skills (N)
| Name | Group | Description |
|------|-------|-------------|
| ...  | ...   | ...         |
```

## Step 2 — Agents

Run:
```bash
grep -h "^name:\|^description:\|^model:" ${CLAUDE_PLUGIN_ROOT}/system/agents/*.md | paste - - -
```

Each triplet is one agent. Extract `name:`, `description:`, `model:` values (strip the key prefix).
Truncate description to 60 chars.

Render:
```
## Agents (N)
| Agent | Model | Description |
|-------|-------|-------------|
| ...   | ...   | ...         |
```

## Step 3 — Hooks

Run:
```bash
python3 - <<'EOF'
import json, sys
with open("${CLAUDE_PLUGIN_ROOT}/system/hooks/hooks.json") as f:
    d = json.load(f)
rows = []
for event, entries in d.get("hooks", {}).items():
    for entry in entries:
        matcher = entry.get("matcher", "*")
        for h in entry.get("hooks", []):
            script = h.get("args", ["", ""])[-1].replace("${CLAUDE_PLUGIN_ROOT}/", "")
            rows.append((event, script, matcher))
for r in sorted(rows):
    print("\t".join(r))
EOF
```

Render:
```
## Hooks (N)
| Event | Script | Matcher |
|-------|--------|---------|
| ...   | ...    | ...     |
```

## Output

Print all three sections in order: Skills → Agents → Hooks.
Include counts in each header (e.g. `## Skills (12)`).
Keep all descriptions truncated to 60 chars with `...` suffix if cut.
