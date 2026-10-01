#!/usr/bin/env bash
# Must-fire test for system/scripts/lint-portability.sh: every rule catches a
# seeded violation, the escape hatch and comment/test-dir exclusions hold.
# Run: bash tests/scripts/test-lint-portability.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LINT="$(cd "$SCRIPT_DIR/../.." && pwd)/system/scripts/lint-portability.sh"
PASS=0; FAIL=0
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . && mkdir -p system/hooks/lib tests s
run() { bash "$LINT" "$T" >/dev/null 2>&1; echo $?; }
put() { printf '%s\n' "$2" >"$1"; git add -A; }

echo "=== test-lint-portability.sh ==="
put s/clean.sh 'echo hi'; assert "clean tree passes" 0 "$(run)"
while IFS='|' read -r name code; do
    put s/bad.sh "$code"; assert "fires: $name" 1 "$(run)"
done <<'CASES'
flock|flock -n 9
date -d|x=$(date -d yesterday +%F)
date --date|x=$(date --date=yesterday +%F)
sha256sum|sha256sum f
md5sum|echo a | md5sum
stat -c|stat -c %Y f
sed -i|sed -i 's/a/b/' f
readlink -f|readlink -f x
grep -P|grep -oP 'a\Kb' f
grep -qP|grep -qP 'a' f
date -u -d|date -u -d '3 days ago' +%s
timeout|timeout 5 cmd
timeout -k|timeout -k 1 5 cmd
timeout var|timeout "$T" cmd
realpath|realpath -m x
find -printf|find . -type f -printf '%T@\n'
date -Iseconds|echo $(date -Iseconds)
date %N|date +%s%N
tac|tac file | head
head -n -1|head -n -1 f
sed BRE plus|sed 's/a\+/b/' f
sed BRE space|sed -n 's/x\s*//p' f
sed BRE alt|sed 's/a\|b/c/' f
grep BRE alt|grep -q 'a\|b' f
sed -E -i|sed -E -i 's/a/b/' f
sed -ri|sed -ri 's/a/b/' f
sed -n -i|sed -n -i 'p' f
sed --in-place|sed --in-place 's/a/b/' f
sed -i empty suffix (BSD form)|sed -i '' 's/a/b/' f
sha1sum|printf x | sha1sum
sha512sum|sha512sum f
touch -d|touch -d '35 days ago' f
touch --date|touch --date='1 day ago' f
getent|h=$(getent passwd 0)
nproc|n=$(nproc)
CASES
put s/bad.sh '# uses flock in a comment'; assert "full-line comment ignored" 0 "$(run)"
put s/bad.sh 'date -d x +%s || true  # portable-ok: guarded BSD fallback below'; assert "portable-ok escape hatch" 0 "$(run)"
rm s/bad.sh; printf '#!/usr/bin/env bash\nsed -i s/a/b/ f\n' >s/noext; git add -A; assert "fires: extensionless bash script" 1 "$(run)"
printf 'sed -i s/a/b/ f\n' >s/noext; git add -A; assert "extensionless non-shell file ignored" 0 "$(run)"
rm s/noext; put tests/t.sh 'flock -n 9'; assert "tests/ is scanned (t-3379)" 1 "$(run)"
rm tests/t.sh; mkdir -p system/hooks/tests tests/hooks tests/lib tests/scripts; put system/hooks/tests/t.sh 'timeout 5 cmd'; assert "*/tests/ is scanned" 1 "$(run)"
rm system/hooks/tests/t.sh; printf 'flock -n 9\n' >test-root.sh; git add -A; assert "root test*.sh is scanned" 1 "$(run)"; rm test-root.sh
for f in tests/lib/bsd-path.sh tests/hooks/test-portable.sh tests/scripts/test-lint-portability.sh; do
    printf 'flock -n 9\n' >"$f"; git add -A; assert "data file exempt by name: $f" 0 "$(run)"; rm "$f"
done
printf '# portable-ok-next: asserts flock is absent from the script under test\ngrep -q flock "$S"\n' >s/nx.sh; git add -A; assert "portable-ok-next covers the following line" 0 "$(run)"
printf '# portable-ok-next: reason\n\nflock -n 9\n' >s/nx.sh; git add -A; assert "portable-ok-next does not reach past a blank line" 1 "$(run)"
printf 'true\nflock -n 9\n' >s/nx.sh; git add -A; assert "no marker: still fires" 1 "$(run)"; rm s/nx.sh; git add -A
put system/hooks/lib/portable.sh 'flock -n 9'; assert "portable.sh itself excluded" 0 "$(run)"
put s/ok.sh 'source lib/portable.sh'$'\n''x=$(p_date_d 2024-01-02)'; assert "shim calls pass" 0 "$(run)"
put s/ok.sh 'echo "reflow lockfile stats"'; assert "no substring false positives" 0 "$(run)"
while IFS='|' read -r name code; do
    put s/ok.sh "source lib/portable.sh"$'\n'"$code"; assert "passes: $name" 0 "$(run)"
done <<'OKCASES'
p_timeout|p_timeout 5 cmd
sed -E ERE|sed -E 's/a+/b/' f
sed -nE ERE|sed -nE 's/(a|b)/c/p' f
sed -n -E ERE|sed -n -E 's/x+//p' f
grep -E alt|grep -qE 'a|b' f
grep -qiE alt|grep -qiE 'a|b' f
sed POSIX class|sed 's/[[:space:]]*$//' f
sed literal backslash-n|sed 's/a/b\nc/' f
timeout as a word in a string|echo "connect timeout exceeded"
sed -i.bak (portable suffix form)|sed -i.bak 's/a/b/' f
touch -t (portable)|touch -t 202401020304.05 f
p_sha1 shim|p_sha1 f
OKCASES


# Shim functions cannot be exec'd: env/nice/nohup/setsid/xargs/sudo/exec/command run an
# executable, so `env ... p_timeout ...` fails with 127 (t-3377: red-verification.sh took that
# for "test ran red" and wrongly registered green tests). Continuations must be joined.
while IFS='|' read -r name code; do
    printf 'source lib/portable.sh\n%b\n' "$code" >s/wrap.sh; git add -A; assert "fires: $name" 1 "$(run)"
done <<'WRAPCASES'
env before p_timeout|env -u GIT_DIR p_timeout 5 cmd
env then continuation|env -u A \\\n  -u B \\\n  p_timeout -k 2 60 node x
nohup p_timeout|nohup p_timeout 5 cmd &
xargs p_flock|echo x | xargs p_flock lock cmd
exec p_timeout|exec p_timeout 5 cmd
command p_timeout|command p_timeout 5 cmd
setsid p_timeout|setsid p_timeout 5 cmd
WRAPCASES
while IFS='|' read -r name code; do
    printf 'source lib/portable.sh\n%b\n' "$code" >s/wrap.sh; git add -A; assert "passes: $name" 0 "$(run)"
done <<'WRAPOK'
p_timeout then env|p_timeout 5 env -u A cmd
p_timeout then env continuation|p_timeout -k 2 60 \\\n  env -u A \\\n  node x
plain p_timeout|p_timeout 5 cmd
env without shim|env -u A cmd
env assignment then p_ in later command|env A=1 cmd; p_timeout 5 x
WRAPOK
rm -f s/wrap.sh; git add -A


# A file that calls a p_* shim must actually source portable.sh, or the call dies with
# "command not found" at runtime (hit twice in t-3374/t-3379: fixtures that COPY portable.sh
# but never source it). Mentions in comments do not count; neither does `cp .../portable.sh`.
printf 'x=$(p_date_d 2024-01-02)\n' >s/nosrc.sh; git add -A; assert "fires: shim used, portable.sh never sourced" 1 "$(run)"
printf 'cp lib/portable.sh /tmp/x\nx=$(p_md5 f)\n' >s/nosrc.sh; git add -A; assert "fires: portable.sh only copied, not sourced" 1 "$(run)"
printf 'source "$D/lib/portable.sh"\nx=$(p_md5 f)\n' >s/nosrc.sh; git add -A; assert "passes: sourced" 0 "$(run)"
printf '. "$D/lib/portable.sh"\nx=$(p_md5 f)\n' >s/nosrc.sh; git add -A; assert "passes: dot-sourced" 0 "$(run)"
printf '# uses p_date_d via the lib\necho hi\n' >s/nosrc.sh; git add -A; assert "passes: shim named only in a comment" 0 "$(run)"
printf 'x=$(p_md5 f)  # portable-ok: sourced by the parent script\n' >s/nosrc.sh; git add -A; assert "passes: portable-ok on the use" 0 "$(run)"
printf 'echo "p_timeout is documented"\n' >s/nosrc.sh; git add -A; assert "passes: prose in a string, no call shape" 0 "$(run)"
rm -f s/nosrc.sh; git add -A


# Shebang: `#!/bin/bash` (and /bin/sh) run the script under macOS's bash 3.2 when it is executed
# directly (statusline, MCP wrapper), bypassing bootstrap's PATH-bash >= 4 preflight. Use
# `#!/usr/bin/env bash`. No escape hatch: a trailing comment on a shebang is not portable.
for sb in '#!/bin/bash' '#!/bin/sh'; do
    printf '%s\necho hi\n' "$sb" >s/sb.sh; git add -A; assert "fires: shebang $sb" 1 "$(run)"
done
printf '#!/usr/bin/env bash\necho hi\n' >s/sb.sh; git add -A; assert "passes: #!/usr/bin/env bash" 0 "$(run)"
printf '#!/bin/bash\necho hi\n' >s/sb noext; mv "s/sb noext" s/sbnoext; git add -A; assert "fires: extensionless script with #!/bin/bash" 1 "$(run)"
rm -f s/sb.sh s/sbnoext; git add -A

echo; echo "Results: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
