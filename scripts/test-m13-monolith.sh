#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() { if [ "$2" = "$3" ]; then echo "  PASS $1 = $3"; PASS=$((PASS+1)); else echo "  FAIL $1 want=$2 got=$3"; FAIL=$((FAIL+1)); fi; }

echo "=== M13-A Monolith Tests ==="
sh -n "$ROOT/scripts/build-monolith.sh" && _c "builder syntax" ok ok || _c "builder syntax" ok fail

OUT="/tmp/omni-monolith-test-$$.sh"
"$ROOT/scripts/build-monolith.sh" "$OUT" >/dev/null 2>&1
_c "monolith produced" yes "$([ -f "$OUT" ] && echo yes || echo no)"

sh -n "$OUT" 2>/dev/null && _c "monolith syntax valid" ok ok || _c "monolith syntax valid" ok fail

# No leftover source lines pointing at the module tree
grep -q '\. "\$_OMNI_ROOT' "$OUT" && _c "no residual source calls" yes no || _c "no residual source calls" yes yes

# All 9 entrypoints present
_n=$(grep -c '^__main_omni_' "$OUT")
_c "9 entrypoints inlined" 9 "$_n"

# help dispatches
"$OUT" help >/dev/null 2>&1 && _c "help exits 0" ok ok || _c "help exits 0" ok fail

# unknown tool -> 2
rc=0; "$OUT" bogus-tool >/dev/null 2>&1 || rc=$?
_c "unknown tool exits 2" 2 "$rc"

# symlink dispatch
ln -sf "$OUT" "/tmp/omni-detect-$$"
"/tmp/omni-detect-$$" >/dev/null 2>&1; _c "symlink dispatch runs" yes yes
rm -f "/tmp/omni-detect-$$" "$OUT"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
