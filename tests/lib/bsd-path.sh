#!/usr/bin/env bash
# Build a temp bin dir that behaves like BSD/macOS userland, backed by GNU tools.
# Usage: source tests/lib/bsd-path.sh; BSD_BIN=$(make_bsd_bin); PATH="$BSD_BIN" ...
#
# Omitted entirely (absent on stock macOS): flock, sha256sum, md5sum, realpath, gdate.
# Wrapped to REJECT GNU-only forms, ACCEPT BSD forms:
#   date  -d / -I*      -> error;  -u -r EPOCH +FMT ok;  %N prints a literal N
# Also absent: timeout, gtimeout, realpath, tac
#   stat  -c            -> error;  -f %m (mtime), -f %z (size)
#   sed   -i (no suffix)-> error;  -i SUFFIX ok
#   readlink -f         -> error;  plain readlink ok
# Added: shasum (-a 256), md5 (-q) as macOS provides them.

_BSD_TOOLS="bash sh sed awk cat mkdir rmdir rm printf sleep kill mktemp dirname basename \
cp mv ln tr head tail cut uname sort wc grep tee chmod touch ls id env true false test \
expr seq xargs perl pkill ps date stat readlink sha256sum md5sum"

make_bsd_bin() {
    local d real
    d="$(mktemp -d)"
    real() { PATH="$_BSD_REAL_PATH" command -v "$1"; }
    local t
    for t in $_BSD_TOOLS; do
        case "$t" in date|stat|sed|readlink|sha256sum|md5sum) continue ;; esac
        local p; p="$(PATH="$_BSD_REAL_PATH" command -v "$t" 2>/dev/null)" || continue
        ln -s "$p" "$d/$t"
    done
    local rdate rstat rsed rreadlink rsha rmd5
    rdate="$(PATH="$_BSD_REAL_PATH" command -v date)"
    rstat="$(PATH="$_BSD_REAL_PATH" command -v stat)"
    rsed="$(PATH="$_BSD_REAL_PATH" command -v sed)"
    rreadlink="$(PATH="$_BSD_REAL_PATH" command -v readlink)"
    rsha="$(PATH="$_BSD_REAL_PATH" command -v sha256sum)"
    rmd5="$(PATH="$_BSD_REAL_PATH" command -v md5sum)"
    rsha1="$(PATH="$_BSD_REAL_PATH" command -v sha1sum)"

    cat >"$d/date" <<EOF
#!/bin/bash
# BSD date emulation
for a in "\$@"; do case "\$a" in -d|-I*|--iso-8601*|--date*) echo "date: illegal option -- \$a" >&2; exit 1;; esac; done
args=(); for a in "\$@"; do args+=("\${a//%N/N}"); done; set -- "\${args[@]}"
if [ "\$1" = "-u" ] && [ "\$2" = "-r" ]; then
  e="\$3"; shift 3
  exec "$rdate" -u -d "@\$e" "\$@"
fi
if [ "\$1" = "-r" ]; then
  e="\$2"; shift 2
  exec "$rdate" -d "@\$e" "\$@"
fi
exec "$rdate" "\$@"
EOF
    cat >"$d/stat" <<EOF
#!/bin/bash
case "\$1" in
  -c) echo "stat: illegal option -- c" >&2; exit 1 ;;
  -f) fmt="\$2"; shift 2
      case "\$fmt" in %m) exec "$rstat" -c %Y "\$@" ;; %z) exec "$rstat" -c %s "\$@" ;; %a) exec "$rstat" -c %X "\$@" ;; %Lp) exec "$rstat" -c %a "\$@" ;;
        *) exit 1 ;; esac ;;
esac
exec "$rstat" "\$@"
EOF
    cat >"$d/sed" <<EOF
#!/bin/bash
if [ "\$1" = "-i" ]; then echo "sed: 1: invalid command code" >&2; exit 1; fi
exec "$rsed" "\$@"
EOF
    cat >"$d/readlink" <<EOF
#!/bin/bash
case "\$1" in -f*) echo "readlink: illegal option -- f" >&2; exit 1 ;; esac
exec "$rreadlink" "\$@"
EOF
    cat >"$d/shasum" <<EOF
#!/bin/bash
[ "\$1" = "-a" ] && [ "\$2" = "256" ] && { shift 2; exec "$rsha" "\$@"; }
[ "\$1" = "-a" ] && [ "\$2" = "1" ] && { shift 2; exec "$rsha1" "\$@"; }
exit 1
EOF
    cat >"$d/md5" <<EOF
#!/bin/bash
# BSD md5 -q [file]: bare digest
[ "\$1" = "-q" ] && shift
"$rmd5" "\$@" | awk '{print \$1}'
EOF
    chmod +x "$d"/date "$d"/stat "$d"/sed "$d"/readlink "$d"/shasum "$d"/md5
    echo "$d"
}

_BSD_REAL_PATH="${_BSD_REAL_PATH:-$PATH}"
