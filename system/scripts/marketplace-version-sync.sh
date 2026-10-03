#!/usr/bin/env bash
# marketplace-version-sync.sh — every plugin listed in .claude-plugin/marketplace.json must carry
# the version its source directory's plugin.json declares (ci.yml "Check version sync", t-3448).
#
# WHY by name. The old inline step read plugins[0] for brana; the first mods entry (ADR-096,
# bootstrap 7g installs them from this marketplace) would have silently become "brana" there.
# Entries are matched by name; the brana entry's source is ./system, each mod's is ./mods/<name>.
# Usage: marketplace-version-sync.sh [ROOT]      Exit 1 on any mismatch or missing manifest.
set -u
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 2
MP=.claude-plugin/marketplace.json
[ -f "$MP" ] || { echo "marketplace-version-sync: $MP not found under $ROOT" >&2; exit 2; }
python3 - "$MP" <<'PY'
import json, os, sys
mp = json.load(open(sys.argv[1]))
bad = 0
seen_brana = False
for p in mp.get("plugins", []):
    name, ver, src = p.get("name"), p.get("version"), p.get("source", "")
    if name == "brana":
        seen_brana = True
    if not (name == "brana" or src.startswith("./mods/")):
        continue
    manifest = os.path.join(src, ".claude-plugin", "plugin.json")
    if not os.path.isfile(manifest):
        print(f"  FAIL: {name}: {manifest} missing (marketplace entry points at a directory with no plugin manifest)"); bad += 1; continue
    have = json.load(open(manifest)).get("version")
    if have != ver:
        print(f"  FAIL: {name}: marketplace.json says {ver}, {manifest} says {have}"); bad += 1
    else:
        print(f"  ok: {name} {ver} ({src})")
if not seen_brana:
    print("  FAIL: no 'brana' entry in marketplace.json"); bad += 1
print(f"marketplace-version-sync: {'in sync' if bad == 0 else str(bad) + ' mismatch(es)'}")
sys.exit(1 if bad else 0)
PY
