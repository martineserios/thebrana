#!/usr/bin/env python3
# runner-egress-proxy.py — host-side HTTP CONNECT allowlist proxy for the autonomous
# runner's sandboxed executor (ADR-062 egress addendum, t-2173).
#
# Listens on a UNIX socket (bind-mounted into the bwrap --unshare-net jail, which has no
# other route out). The jailed `claude -p` reaches it via in-jail socat + HTTPS_PROXY.
# Only CONNECT to an allowlisted host:443 is tunneled; everything else gets 403. The proxy
# resolves the target host-side, so the jail needs no DNS.
#
# Usage: runner-egress-proxy.py <unix-socket-path> <comma-separated-allowed-hosts>
#   e.g. runner-egress-proxy.py /tmp/egress.sock api.anthropic.com
# Stderr logs one ALLOW/DENY line per CONNECT (the audit trail). No third-party deps.
#
# There is intentionally NO allow-all / wildcard mode: the allowlist is exact-host only,
# so the boundary cannot be silently widened by a stray argument.
import os
import sys
import socket
import select
import threading
import ctypes
import signal

ALLOW_PORTS = {443}


def _die_with_parent():
    # PR_SET_PDEATHSIG=SIGTERM (prctl 1): if the spawning shell goes away, the kernel
    # signals this daemon — a hard backstop so a leaked proxy can never hold a pipe open.
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def pump(a, b):
    try:
        while True:
            r, _, _ = select.select([a, b], [], [], 120)
            if not r:
                break
            for s in r:
                data = s.recv(65536)
                if not data:
                    return
                (b if s is a else a).sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.close()
            except OSError:
                pass


def handle(client, allow):
    try:
        client.settimeout(15)
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(4096)
            if not chunk:
                client.close()
                return
            buf += chunk
            if len(buf) > 8192:
                break
        line = buf.split(b"\r\n", 1)[0].decode("latin1")
        parts = line.split()
        if len(parts) < 2 or parts[0].upper() != "CONNECT":
            client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            client.close()
            return
        host, _, port = parts[1].partition(":")
        host = host.lower()
        port = int(port or "443")
        if host not in allow or port not in ALLOW_PORTS:
            sys.stderr.write(f"[egress-proxy] DENY {host}:{port}\n")
            sys.stderr.flush()
            client.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
            client.close()
            return
        sys.stderr.write(f"[egress-proxy] ALLOW {host}:{port}\n")
        sys.stderr.flush()
        upstream = socket.create_connection((host, port), timeout=15)
        client.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
        client.settimeout(None)
        pump(client, upstream)
    except Exception as exc:  # noqa: BLE001 — a bad request must not kill the proxy
        sys.stderr.write(f"[egress-proxy] ERR {exc}\n")
        sys.stderr.flush()
        try:
            client.close()
        except OSError:
            pass


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: runner-egress-proxy.py <unix-socket> <allowed-hosts-csv>\n")
        sys.exit(2)
    # Drop every inherited fd >=3. This daemon is spawned from inside a command
    # substitution (DOUT="$(… | sandbox_claude …)"); if it kept the inherited pipe fd open
    # it would hang the substitution (and the calling harness) until killed. We need none of
    # them — only the listen socket created below.
    try:
        os.closerange(3, 4096)
    except OSError:
        pass
    _die_with_parent()
    sock_path = sys.argv[1]
    allow = {h.strip().lower() for h in sys.argv[2].split(",") if h.strip()}
    if not allow:
        sys.stderr.write("[egress-proxy] refusing to start with an empty allowlist\n")
        sys.exit(2)
    if os.path.exists(sock_path):
        os.unlink(sock_path)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    os.chmod(sock_path, 0o600)
    srv.listen(64)
    sys.stderr.write(f"[egress-proxy] listening unix:{sock_path} allow={sorted(allow)}\n")
    sys.stderr.flush()
    try:
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=handle, args=(conn, allow), daemon=True).start()
    finally:
        try:
            os.unlink(sock_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
