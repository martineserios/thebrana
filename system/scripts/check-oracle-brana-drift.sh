#!/usr/bin/env bash
# check-oracle-brana-drift.sh — is oracle-hub's brana binary current? (t-2501)
#
# oracle-hub runs a hand-shipped static musl brana with no local build
# capability. Twice (2026-07-27, 2026-08-01) a stale binary silently ran
# days behind main, producing malformed tasks / failed drains with zero
# signal. This check makes drift visible without anyone going looking:
# run it from a scheduler job — a non-zero exit surfaces as a FAILED job.
#
# Verdicts:
#   OK        exit 0 — manifest sha matches binary, no cli commits since build
#   SKIP      exit 0 — hub unreachable (laptop offline / hub down: not an alarm)
#   UNMANAGED exit 1 — no manifest next to the binary (shipped outside ship script)
#   SWAPPED   exit 1 — binary sha256 differs from manifest (replaced out-of-band)
#   DRIFT     exit 1 — origin/main has commits under system/cli/rust newer than
#                      the manifest's built-from commit
#
# The manifest is written by system/scripts/ship-brana-oracle.sh.
# Env overrides (tests): SSH_BIN, REPO, OH_TARGET, REMOTE_BIN.

set -uo pipefail

SSH_BIN="${SSH_BIN:-ssh}"
OH_TARGET="${OH_TARGET:-oracle-hub}"
REMOTE_BIN="${REMOTE_BIN:-/home/ubuntu/.local/bin/brana}"
REMOTE_MANIFEST="$REMOTE_BIN.manifest.json"
REPO="${REPO:-$HOME/enter_thebrana/thebrana}"
# Pathspec = the shipped binary's dependency closure ONLY (brana-cli ->
# brana-core, plus workspace manifests). Counting the whole workspace dir
# false-alarms on brana-mcp-only commits — a crate the shipped binary does
# not contain (challenger iteration 1, 2026-08-02).
CLI_PATHS=(
  "system/cli/rust/crates/brana-cli"
  "system/cli/rust/crates/brana-core"
  "system/cli/rust/Cargo.toml"
  "system/cli/rust/Cargo.lock"
)

log() { echo "[oracle-brana-drift] $*"; }

remote() { "$SSH_BIN" -o ConnectTimeout=10 -o BatchMode=yes "$OH_TARGET" "$1"; }

# 1. Reachability — an offline hub (or laptop) is a skip, never an alarm.
if ! remote "true" >/dev/null 2>&1; then
  log "SKIP: $OH_TARGET unreachable — check not performed"
  exit 0
fi

# 2. Manifest present?
manifest="$(remote "cat $REMOTE_MANIFEST 2>/dev/null")" || manifest=""
if [[ -z "$manifest" ]]; then
  log "UNMANAGED: no manifest at $REMOTE_MANIFEST — binary was shipped outside ship-brana-oracle.sh; provenance unknown. Re-ship: system/scripts/ship-brana-oracle.sh"
  exit 1
fi

m_commit="$(echo "$manifest" | jq -r '.commit // empty' 2>/dev/null)"
m_sha="$(echo "$manifest" | jq -r '.sha256 // empty' 2>/dev/null)"
if [[ -z "$m_commit" || -z "$m_sha" ]]; then
  log "UNMANAGED: manifest at $REMOTE_MANIFEST is malformed (missing commit/sha256). Re-ship: system/scripts/ship-brana-oracle.sh"
  exit 1
fi
# Remote-sourced values never reach git argv unvalidated (defense-in-depth —
# a compromised hub must not get to pick our git arguments).
if ! [[ "$m_commit" =~ ^[0-9a-fA-F]{7,40}$ ]] || ! [[ "$m_sha" =~ ^[0-9a-fA-F]{64}$ ]]; then
  log "UNMANAGED: manifest at $REMOTE_MANIFEST is malformed (commit/sha256 not valid hex). Re-ship: system/scripts/ship-brana-oracle.sh"
  exit 1
fi

# 3. Does the deployed binary match what the manifest says was shipped?
actual_sha="$(remote "sha256sum $REMOTE_BIN 2>/dev/null" | awk '{print $1}')"
if [[ "$actual_sha" != "$m_sha" ]]; then
  log "SWAPPED: binary sha256 does not match manifest (binary ${actual_sha:0:12}… vs manifest ${m_sha:0:12}…) — replaced out-of-band. Re-ship to restore provenance."
  exit 1
fi

# 4. Has main moved under the shipped binary's paths since the build?
# A fetch failure must be LOUD: silently comparing against a stale cached
# origin/main reproduces the exact silent-staleness failure this check
# exists to eliminate (challenger iteration 1, 2026-08-02).
if git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
  if ! git -C "$REPO" fetch -q origin main 2>/dev/null; then
    log "FETCH-FAILED: could not refresh origin/main — a comparison now would run against a stale cached ref, which is exactly the silent staleness this check exists to catch. Verdict unreliable; investigate network/auth and re-run."
    exit 1
  fi
fi
if ! git -C "$REPO" cat-file -e "$m_commit" 2>/dev/null; then
  log "DRIFT: manifest commit $m_commit not found in local repo — cannot measure distance (shallow clone or foreign commit). Treating as drifted; re-ship from current main."
  exit 1
fi
upstream="origin/main"
git -C "$REPO" rev-parse -q --verify "$upstream" >/dev/null 2>&1 || upstream="main"
count="$(git -C "$REPO" rev-list --count "$m_commit..$upstream" -- "${CLI_PATHS[@]}" 2>/dev/null || echo 0)"
if [[ "$count" -gt 0 ]]; then
  log "DRIFT: $count commit(s) to the shipped binary's paths (${CLI_PATHS[*]}) on $upstream since shipped commit ${m_commit:0:12} — hub binary is behind. Re-ship: system/scripts/ship-brana-oracle.sh"
  exit 1
fi

log "OK: oracle-hub brana current (commit ${m_commit:0:12}, sha verified, 0 cli commits since build)"
exit 0
