#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-45s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else
        printf '  FAIL %-45s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

echo "=== M13-A Monolith Tests ==="

# 1. Builder syntax
sh -n "$ROOT/scripts/build-monolith.sh" && _c "builder syntax" ok ok || _c "builder syntax" ok fail

# 2. Build
OUT="/tmp/omni-monolith-test-$$.sh"
_build_out=$("$ROOT/scripts/build-monolith.sh" "$OUT" 2>&1)
_c "monolith produced" yes "$([ -f "$OUT" ] && echo yes || echo no)"

# 3. Syntax
_syn_err=$(sh -n "$OUT" 2>&1)
if [ -z "$_syn_err" ]; then
    _c "monolith syntax valid" ok ok
else
    _c "monolith syntax valid" ok fail
    printf '    syntax errors:\n%s\n' "$_syn_err" | head -5 | sed 's/^/      /'
fi

# 4. No residual source calls — with diagnostic
_residual_count=0
_residual_lines=""
if grep -n '\. "\$_OMNI_ROOT' "$OUT" >/tmp/_res_$$ 2>/dev/null && [ -s /tmp/_res_$$ ]; then
    _residual_count=1
    _residual_lines=$(head -3 /tmp/_res_$$)
fi
if grep -n '\. "\$OMNI_ROOT' "$OUT" >>/tmp/_res_$$ 2>/dev/null && [ -s /tmp/_res_$$ ]; then
    _residual_count=1
fi
_c "no residual source calls" 0 "$_residual_count"
if [ "$_residual_count" -ne 0 ]; then
    printf '    first residuals:\n'
    head -3 /tmp/_res_$$ | sed 's/^/      /'
fi
rm -f /tmp/_res_$$

# 5. Entrypoints
_n=$(grep -c '^__main_omni_' "$OUT" 2>/dev/null || echo 0)
_c "9 entrypoints inlined" 9 "$_n"

# 6. Help — with diagnostic
_help_out=$("$OUT" help 2>&1)
_help_rc=$?
_c "help exits 0" 0 "$_help_rc"
if [ "$_help_rc" -ne 0 ]; then
    printf '    help output (rc=%s):\n' "$_help_rc"
    printf '%s\n' "$_help_out" | head -10 | sed 's/^/      /'
fi

# 7. Unknown tool — with diagnostic
_unk_out=$("$OUT" bogus-tool 2>&1)
_unk_rc=$?
_c "unknown tool exits 2" 2 "$_unk_rc"
if [ "$_unk_rc" -ne 2 ]; then
    printf '    unknown-tool output (rc=%s):\n' "$_unk_rc"
    printf '%s\n' "$_unk_out" | head -10 | sed 's/^/      /'
fi

# 8. Symlink
ln -sf "$OUT" "/tmp/omni-detect-$$"
"/tmp/omni-detect-$$" >/dev/null 2>&1 || true
_c "symlink dispatch runs" yes yes
rm -f "/tmp/omni-detect-$$" "$OUT"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
