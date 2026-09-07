#!/usr/bin/env bash
# sandbox-claude.sh — shared bwrap capability jail for dispatching `claude -p` (ADR-062).
#
# Extracted from autonomous-runner.sh (t-3317) so every claude -p call site that feeds
# externally-sourced content into the model — the runner's OBSERVE planner AND
# feed-summarize.sh's article summarizer — shares one sandboxing implementation instead
# of two copies that can silently drift apart (the exact gap t-3317 closed: a second
# call site existed with no sandboxing at all). Source this file, then call
# sandbox_claude(). Requires CLAUDE_BIN to be set by the caller before sourcing (both
# callers already default it: `CLAUDE_BIN="${CLAUDE_BIN:-...}"`).
#
# SANDBOX-CLAUDE-BLOCK — t-3257/t-3317: test-autonomous-runner-real-claude-compat.sh
# extracts exactly this span and sources it, so the opt-in real-claude compat check
# always exercises the shipped sandbox_claude() rather than a reimplementation (same
# convention as EPIC-WALK-BLOCK / BRANCH-PREFIX-BLOCK). Do not remove or rename these
# markers; keep the fences inside them. The extracting test re-sets RUNNER_SCRIPT_DIR
# after sourcing (it would otherwise resolve to the temp extraction file's directory,
# not this file's real location).
resolve_claude() { local cb="${CLAUDE_BIN:-}"; [ -x "$cb" ] || cb="$(command -v claude 2>/dev/null || true)"; echo "$cb"; }

# RUNNER_SCRIPT_DIR anchors the egress proxy lookup below (runner-egress-proxy.py lives
# in system/scripts/, this file lives in system/scripts/lib/). Only set it from our own
# location if the caller hasn't already pinned one.
RUNNER_SCRIPT_DIR="${RUNNER_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# stage_runner_home <dst> : build a writable per-run HOME holding ONLY the claude
# subscription auth state, with third-party MCP tokens + history + project data stripped.
# WHY writable (not an --ro-bind of the cred file): `claude` rewrites ~/.claude.json on
# startup, so a read-only bind makes it bail "Not logged in · Please run /login" (ADR-062
# addendum, spike-validated 2026-06-21). Exposing a writable copy of the live OAuth token to
# the executor is safe ONLY because egress is allowlisted (token unexfiltratable) — never
# stage real creds without the egress proxy active.
stage_runner_home() {
  local dst="$1"
  mkdir -p "$dst/.claude"; chmod 700 "$dst" "$dst/.claude"
  if [ -f "$HOME/.claude/.credentials.json" ]; then
    # keep ONLY the claude subscription oauth; drop mcpOAuth.* (linear/supabase/… tokens)
    jq '{claudeAiOauth}' "$HOME/.claude/.credentials.json" 2>/dev/null > "$dst/.claude/.credentials.json" \
      || cp "$HOME/.claude/.credentials.json" "$dst/.claude/.credentials.json"
    chmod 600 "$dst/.claude/.credentials.json"
  fi
  if [ -f "$HOME/.claude.json" ]; then
    # keep account identity; strip MCP servers (so none load → egress stays to the API host)
    # + mcpOAuth tokens + history/projects bulk.
    jq 'del(.mcpServers, .mcpOAuth, .history, .projects, .tipsHistory, .cachedChangelog)' \
      "$HOME/.claude.json" 2>/dev/null > "$dst/.claude.json" \
      || cp "$HOME/.claude.json" "$dst/.claude.json"
    chmod 600 "$dst/.claude.json"
  fi
}

# sandbox_claude <workdir> <claude args...> : run `claude -p` inside a bubblewrap
# capability jail (ADR-062 + egress addendum). The prompt is read from STDIN and forwarded
# into the jail. Containment (spike-validated, single-level userns — works under Ubuntu
# 24.04+ apparmor_restrict_unprivileged_userns):
#   - minimal --ro-bind list (NOT /) → ~/.config/brana/*.env, ~/.ssh, ~/.aws are ABSENT
#   - env -i → inherited env secrets (LINEAR_API_KEY, …) cleared
#   - writable per-run HOME copy (claude state only, MCP/secrets stripped), rm -rf'd after
#   - <workdir> bound to /workspace = the ONLY host-backed writable path
#   - rlimits via inner ulimit (bwrap 0.11.1 has no --rlimit-* flags)
#   - EGRESS: --unshare-net (jail = loopback only) + a bind-mounted unix socket to a host
#     CONNECT allowlist proxy (api.anthropic.com only); in-jail socat + HTTPS_PROXY route
#     traffic through it. nft/slirp + srt are infeasible unprivileged on this host, so this
#     unix-socket bridge is the boundary. The proxy resolves host-side → jail needs no DNS.
# Graceful fallback to UNSANDBOXED (loud warning) when bwrap is missing or RUNNER_SANDBOX=0
# (e.g. CI without user namespaces, or orchestration tests that stub `claude`).
SANDBOX="${RUNNER_SANDBOX:-1}"
EGRESS="${RUNNER_EGRESS:-1}"
EGRESS_ALLOW="${RUNNER_EGRESS_ALLOW:-api.anthropic.com}"
EGRESS_PORT="${RUNNER_EGRESS_PORT:-18080}"

sandbox_claude() {
  local wd="$1"; shift
  local cb; cb="$(resolve_claude)"
  if [ "$SANDBOX" = "0" ] || ! command -v bwrap >/dev/null 2>&1; then
    [ "$SANDBOX" != "0" ] && echo "[sandbox-claude] WARN: bwrap unavailable — dispatch running UNSANDBOXED (ADR-062)" >&2
    ( cd "$wd" && timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" "$cb" "$@" )
    return $?
  fi
  local cbr; cbr="$(readlink -f "$cb")"
  local rhome rsock="" proxy_pid=""
  rhome="$(mktemp -d "${TMPDIR:-/tmp}/runner-home-XXXXXX")"
  stage_runner_home "$rhome"
  local -a B=(--unshare-ipc --unshare-pid
    --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib)
  [ -e /lib64 ] && B+=(--ro-bind /lib64 /lib64)
  B+=(--ro-bind /etc /etc --ro-bind "$cbr" /opt/claude --bind "$rhome" /home/sb)
  [ -e "$HOME/.cargo" ]    && B+=(--ro-bind "$HOME/.cargo" /home/sb/.cargo)
  [ -e "$HOME/.gitconfig" ] && B+=(--ro-bind "$HOME/.gitconfig" /home/sb/.gitconfig)
  B+=(--bind "$wd" /workspace --tmpfs /tmp --proc /proc --dev /dev --chdir /workspace)

  local egress_proxy="$RUNNER_SCRIPT_DIR/runner-egress-proxy.py"
  local inner='ulimit -u 200 2>/dev/null; ulimit -f 1024000 2>/dev/null; exec /opt/claude "$@"'
  if [ "$EGRESS" = "1" ] && command -v python3 >/dev/null 2>&1 \
       && command -v socat >/dev/null 2>&1 && [ -f "$egress_proxy" ]; then
    rsock="$(mktemp -u "${TMPDIR:-/tmp}/runner-egress-XXXXXX.sock")"
    # Redirect BOTH stdout and stderr away from the caller's fds: this proxy is a background
    # daemon, and if it inherited stdout it would hold a command-substitution pipe open
    # (DOUT="$(… | sandbox_claude …)") and hang the dispatch until killed.
    python3 "$egress_proxy" "$rsock" "$EGRESS_ALLOW" >/dev/null 2>>"${RUNNER_EGRESS_LOG:-/dev/null}" </dev/null &
    proxy_pid=$!
    local i=0; while [ ! -S "$rsock" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    B+=(--unshare-net --bind "$rsock" /egress.sock)
    # In-jail bridge: a localhost proxy endpoint → the bind-mounted unix socket. We must NOT
    # `exec` claude here: under --unshare-pid bwrap is the ns init and waits on ALL children,
    # so the backgrounded socat (a daemon) would keep it alive and hang the dispatch's command
    # substitution. Run claude, then reap socat (pkill children + kill listener + wait) so the
    # ns empties and bwrap exits. Written to a bound FILE (not `bash -c`) — the inline-string
    # form proved fragile under the runner's command-substitution; the file form is robust.
    cat > "$rhome/.sbx-inner.sh" <<EOF
socat -T 3 TCP4-LISTEN:$EGRESS_PORT,bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:/egress.sock </dev/null >/dev/null 2>&1 &
__sp=\$!
sleep 0.4
export HTTPS_PROXY=http://127.0.0.1:$EGRESS_PORT HTTP_PROXY=http://127.0.0.1:$EGRESS_PORT NO_PROXY=
ulimit -u 200 2>/dev/null; ulimit -f 1024000 2>/dev/null
/opt/claude "\$@"; __rc=\$?
pkill -P "\$__sp" 2>/dev/null; kill "\$__sp" 2>/dev/null; wait 2>/dev/null
exit "\$__rc"
EOF
    inner=""   # empty → dispatch via the bound /home/sb/.sbx-inner.sh file
  elif [ "$EGRESS" = "1" ]; then
    echo "[sandbox-claude] WARN: egress deps missing (python3/socat/proxy) — dispatch network UNRESTRICTED (ADR-062)" >&2
  fi

  if [ -n "$inner" ]; then
    timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" bwrap "${B[@]}" \
      env -i HOME=/home/sb PATH=/usr/sbin:/usr/bin:/bin TERM="${TERM:-dumb}" \
      bash -c "$inner" _ "$@"
  else
    timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" bwrap "${B[@]}" \
      env -i HOME=/home/sb PATH=/usr/sbin:/usr/bin:/bin TERM="${TERM:-dumb}" \
      bash /home/sb/.sbx-inner.sh "$@"
  fi
  local rc=$?
  [ -n "$proxy_pid" ] && kill "$proxy_pid" 2>/dev/null
  [ -n "$rsock" ] && rm -f "$rsock" 2>/dev/null
  rm -rf "$rhome" 2>/dev/null
  return $rc
}
# /SANDBOX-CLAUDE-BLOCK
