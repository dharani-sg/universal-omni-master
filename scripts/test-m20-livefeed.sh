#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== M20 Live Telemetry Feed Tests ==="

sh -n "$ROOT/src/deploy/livefeed.sh" && _c "syntax: livefeed.sh" ok ok || _c "syntax: livefeed.sh" ok fail

WORK="${TMPDIR:-/tmp}/omni-m20-$$"
mkdir -p "$WORK"
export OMNI_LIVEFEED_LOG="$WORK/livefeed.log"

. "$ROOT/src/deploy/livefeed.sh"

# Test 1: basic execution preserves exit code
rc=0; livefeed_exec "test-phase" true >/dev/null 2>&1 || rc=$?
_c "livefeed_exec success rc=0" 0 "$rc"

rc=0; livefeed_exec "test-fail" false >/dev/null 2>&1 || rc=$?
_c "livefeed_exec failure rc=1" 1 "$rc"

# Test 2: output is logged to file
: > "$OMNI_LIVEFEED_LOG"
livefeed_exec "echo-test" sh -c 'echo hello; echo world' >/dev/null 2>&1
_logged=$(wc -l < "$OMNI_LIVEFEED_LOG" | tr -d ' ')
_c "livefeed logs output lines" yes "$([ "$_logged" -ge 2 ] && echo yes || echo no)"

grep -q 'hello' "$OMNI_LIVEFEED_LOG"
_c "livefeed log contains command output" 0 "$?"

grep -q 'echo-test' "$OMNI_LIVEFEED_LOG"
_c "livefeed log contains phase label" 0 "$?"

# Test 3: portrait mode filters output
: > "$OMNI_LIVEFEED_LOG"
TUI_LAYOUT=portrait livefeed_exec "portrait-test" \
    sh -c 'i=1; while [ $i -le 25 ]; do echo "line $i"; i=$((i+1)); done; echo "Installing pkg"' \
    >/dev/null 2>"$WORK/portrait.stderr"

# Portrait should show the "Installing" marker line but not every single line
grep -q 'Installing' "$WORK/portrait.stderr"
_c "portrait shows marker lines" 0 "$?"

# Test 4: landscape mode shows all lines
: > "$OMNI_LIVEFEED_LOG"
TUI_LAYOUT=landscape livefeed_exec "landscape-test" \
    sh -c 'echo "line1"; echo "line2"; echo "line3"' \
    >/dev/null 2>"$WORK/landscape.stderr"

_stderr_lines=$(wc -l < "$WORK/landscape.stderr" | tr -d ' ')
# Expect at least 3 content lines + 2 header/footer = 5
_c "landscape shows all lines" yes "$([ "$_stderr_lines" -ge 5 ] && echo yes || echo no)"

# Test 5: summary reports correctly
livefeed_summary > "$WORK/summary.out" 2>&1
grep -q 'lines logged' "$WORK/summary.out"
_c "summary reports line count" 0 "$?"

# Test 6: clear guard under OMNI_SYSROOT
rc=0; OMNI_SYSROOT=/tmp/fx livefeed_clear >/dev/null 2>&1 || rc=$?
_c "livefeed_clear OMNI_SYSROOT guard 126" 126 "$rc"

# Test 7: clear works without guard
unset OMNI_SYSROOT
livefeed_clear
_c "livefeed_clear empties log" 0 "$(wc -c < "$OMNI_LIVEFEED_LOG" | tr -d ' ')"

rm -rf "$WORK"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
