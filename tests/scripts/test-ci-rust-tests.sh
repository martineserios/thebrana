#!/usr/bin/env bash
# CI runs the Rust test suites (t-3472). Before it, no job ran them: the rust job only built
# brana-mcp, and validate.sh Check 46 compiles tests with --no-run. This pins, in ci.yml's
# required `rust` job:
#   - a step running `cargo test --workspace` (brana-cli, brana-core, brana-mcp);
#   - BRANA_REQUIRE_FFMPEG=1 on it, so the real-ffmpeg transcribe frame tests fail instead of
#     skipping when ffmpeg is missing (the guard's must-fire was verified by hand, t-3472);
#   - ffmpeg installed BEFORE that step, with the >= 5.1 floor asserted (-fps_mode);
#   - a job timeout-minutes, so a hung test can't hold a required check pending for hours.
# Run: bash tests/scripts/test-ci-rust-tests.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
# Same PyYAML rule as test-ci-mods-harness.sh: required on the ubuntu tests job, named SKIP on macOS.
if ! python3 -c 'import yaml' 2>/dev/null; then
    if [ "$(uname -s)" = Darwin ]; then echo "=== test-ci-rust-tests.sh ==="; echo "  SKIP: PyYAML absent on this macOS runner — the ubuntu tests job checks the workflow files"; exit 0; fi
    echo "  FAIL: PyYAML (python3 -c 'import yaml') is required to parse the workflow files"; exit 1
fi
assert() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  PASS: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')"; fi; }
cd "$ROOT" || exit 2
echo "=== test-ci-rust-tests.sh ==="

# One line per fact about the rust job, computed from the parsed workflow.
facts=$(python3 - <<'PY'
import yaml
job = yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]["rust"]
steps = job.get("steps", [])
runs = [(s.get("run") or "") for s in steps]
test_i = next((i for i, r in enumerate(runs) if "cargo test --workspace" in r), -1)
ff_i = next((i for i, r in enumerate(runs) if "apt-get install" in r and "ffmpeg" in r), -1)
print("test_step", "yes" if test_i >= 0 else "no")
env = (steps[test_i].get("env") or {}) if test_i >= 0 else {}
print("require_ffmpeg", str(env.get("BRANA_REQUIRE_FFMPEG", "")))
print("ffmpeg_before_test", "yes" if 0 <= ff_i < test_i else "no")
print("ffmpeg_floor", "yes" if ff_i >= 0 and "5.1" in runs[ff_i] and "exit 1" in runs[ff_i] else "no")
print("timeout", "yes" if isinstance(job.get("timeout-minutes"), int) else "no")
PY
)
fact() { printf '%s\n' "$facts" | awk -v k="$1" '$1 == k { print $2 }'; }

assert "rust job runs cargo test --workspace" "yes" "$(fact test_step)"
assert "BRANA_REQUIRE_FFMPEG=1 on the test step" "1" "$(fact require_ffmpeg)"
assert "ffmpeg installed before the test step" "yes" "$(fact ffmpeg_before_test)"
assert "install step asserts the ffmpeg >= 5.1 floor" "yes" "$(fact ffmpeg_floor)"
assert "rust job has timeout-minutes" "yes" "$(fact timeout)"

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
