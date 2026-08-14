#!/usr/bin/env python3
"""t-2591 Phase 0: classify build-session tokens as understanding / churn / orchestration.

Implements docs/ideas/phase0-preregistration.md exactly. Do not change the classification
rules here without noting the deviation — the pre-registration is the contract.
"""
import json, sys, os, glob

UNDERSTANDING = {"Read", "Grep", "Glob", "Explore", "Agent", "WebFetch", "WebSearch", "Skill"}
CHURN = {"Bash", "Edit", "Write", "NotebookEdit"}
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}

PROJ = os.path.expanduser("~/.claude/projects/-home-martineserios-enter-thebrana-thebrana")


def turn_tokens(msg):
    u = (msg or {}).get("usage") or {}
    return (u.get("input_tokens", 0) or 0) + (u.get("cache_creation_input_tokens", 0) or 0) \
        + (u.get("cache_read_input_tokens", 0) or 0) + (u.get("output_tokens", 0) or 0)


def tools_in(msg):
    out = []
    for blk in (msg or {}).get("content") or []:
        if isinstance(blk, dict) and blk.get("type") == "tool_use":
            name = blk.get("name", "")
            # subagent_type refines Agent/Task calls; treat all Agent spawns as understanding
            out.append(name)
    return out


def classify(tools):
    """Mixed turns -> highest-cost-to-export class present. Biased AGAINST delegation."""
    if any(t in UNDERSTANDING for t in tools):
        return "understanding"
    if any(t in CHURN for t in tools):
        return "churn"
    return "orchestration"


def analyze(path):
    totals = {"understanding": 0, "churn": 0, "orchestration": 0}
    is_build = False
    cold = 0
    seen_write = False
    turns = 0
    branches = set()
    for line in open(path, errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        gb = d.get("gitBranch") or ""
        if gb:
            branches.add(gb)
            if "/t-" in gb:
                is_build = True
        if d.get("type") != "assistant":
            continue
        msg = d.get("message") or {}
        tk = turn_tokens(msg)
        if tk == 0:
            continue
        turns += 1
        tools = tools_in(msg)
        totals[classify(tools)] += tk
        if not seen_write:
            cold += tk
            if any(t in WRITE_TOOLS for t in tools):
                seen_write = True
    total = sum(totals.values())
    return {
        "path": os.path.basename(path), "is_build": is_build, "turns": turns,
        "totals": totals, "total": total,
        "cold": cold, "cold_share": (cold / total) if total else 0.0,
        "reached_write": seen_write,
        "branches": sorted(b for b in branches if "/t-" in b)[:2],
        "mtime": os.path.getmtime(path),
    }


def main():
    files = glob.glob(os.path.join(PROJ, "*.jsonl"))
    results = [analyze(f) for f in files]
    builds = [r for r in results if r["is_build"] and r["total"] > 0 and r["reached_write"]]
    builds.sort(key=lambda r: r["mtime"], reverse=True)
    N = 12
    sel = builds[:N]
    print(f"available build sessions (reached a write): {len(builds)}")
    print(f"N used: {len(sel)} (pre-registered N={N})\n")

    pooled = {"understanding": 0, "churn": 0, "orchestration": 0}
    for r in sel:
        for k in pooled:
            pooled[k] += r["totals"][k]
    tot = sum(pooled.values())

    print(f"{'session':<20}{'total':>12}{'under%':>9}{'churn%':>9}{'orch%':>8}{'cold%':>8}  branch")
    for r in sel:
        t = r["total"]
        print(f"{r['path'][:18]:<20}{t:>12,}"
              f"{100*r['totals']['understanding']/t:>8.1f}%"
              f"{100*r['totals']['churn']/t:>8.1f}%"
              f"{100*r['totals']['orchestration']/t:>7.1f}%"
              f"{100*r['cold_share']:>7.1f}%  {(r['branches'] or [''])[0][:34]}")

    churn_share = pooled["churn"] / tot if tot else 0
    colds = sorted(r["cold_share"] for r in sel)
    median_cold = colds[len(colds)//2] if colds else 0

    print(f"\n--- POOLED (N={len(sel)}) ---")
    for k, v in pooled.items():
        print(f"  {k:<15}{v:>14,}  {100*v/tot:>5.1f}%")
    print(f"  {'TOTAL':<15}{tot:>14,}")
    print(f"\nchurn_share      = {churn_share:.3f}")
    print(f"median cold_load = {median_cold:.3f}")

    if churn_share >= 0.50:
        verdict = "PROCEED"
    elif churn_share >= 0.35:
        verdict = "INCONCLUSIVE"
    else:
        verdict = "KILL"
    veto = median_cold > 0.40
    print(f"\nchurn verdict    = {verdict}")
    print(f"quota veto       = {'YES (median cold-load > 0.40)' if veto else 'no'}")
    print(f"FINAL            = {'KILL (quota veto overrides)' if veto and verdict == 'PROCEED' else verdict}")


if __name__ == "__main__":
    main()
