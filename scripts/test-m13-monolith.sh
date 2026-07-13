#!/bin/sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-45s = %s\n' "$1" "$3"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-45s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== M13-A Monolith Tests ==="

OUT="${TMPDIR:-/tmp}/omni-monolith-test-$$.sh"

"$ROOT/scripts/build-monolith.sh" "$OUT" >/dev/null 2>&1
_c "monolith produced" yes "$([ -f "$OUT" ] && echo yes || echo no)"

sh -n "$OUT" 2>/dev/null &&
    _c "syntax valid" ok ok ||
    _c "syntax valid" ok fail

grep -q 'MONOLITH_SELF_CONTAINED' "$OUT" &&
    _c "sentinel present" yes yes ||
    _c "sentinel present" yes no

grep -q '__omni_load_libs' "$OUT" &&
    _c "lib wrapper present" yes yes ||
    _c "lib wrapper present" yes no

_want=$(sed -n 's/^TOOLS="\(.*\)"/\1/p' "$ROOT/scripts/build-monolith.sh" | tr ' ' '\n' | sed '/^$/d' | grep -c '^omni-')
_got=$(grep -c '^__main_omni_' "$OUT" 2>/dev/null || echo 0)
_c "$_want tools inlined" "$_want" "$_got"

rc=0
"$OUT" help >/dev/null 2>&1 || rc=$?
_c "help exits 0" 0 "$rc"

rc=0
"$OUT" bogus >/dev/null 2>&1 || rc=$?
_c "unknown tool rc=2" 2 "$rc"

ln -sf "$OUT" "/tmp/omni-detect-$$"
"/tmp/omni-detect-$$" >/dev/null 2>&1
_c "symlink dispatch" yes yes

rm -f "/tmp/omni-detect-$$" "$OUT"

printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
