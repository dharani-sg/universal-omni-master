#!/bin/sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0
FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"
        PASS=$((PASS+1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"
        FAIL=$((FAIL+1))
    fi
}

echo "=== M24 AI-Patcher Tests ==="

sh -n "$ROOT/src/ai/patcher.sh" && _c "syntax: patcher.sh" ok ok || _c "syntax: patcher.sh" ok fail
sh -n "$ROOT/bin/omni-patcher" && _c "syntax: omni-patcher" ok ok || _c "syntax: omni-patcher" ok fail

. "$ROOT/src/ai/patcher.sh"

WORK="${TMPDIR:-/tmp}/omni-m24-$$"
mkdir -p "$WORK"

# 1. Context capture
printf '#!/bin/sh\necho "hello"\n' > "$WORK/bad.sh"
printf 'Error on line 2\n' > "$WORK/log.txt"
patcher_capture_context "$WORK/bad.sh" "1" "$WORK/log.txt" "$WORK/ctx.txt"
_c "context captures script and log" yes "$(grep -q 'Error on line 2' "$WORK/ctx.txt" && echo yes || echo no)"

# 2. Safe apply (syntax pass)
printf '#!/bin/sh\nexit 0\n' > "$WORK/good_patch.sh"
printf 'y\n' | patcher_apply_safe "$WORK/bad.sh" "$WORK/good_patch.sh" >/dev/null 2>&1
_c "apply safe patch succeeds" yes "$(grep -q 'exit 0' "$WORK/bad.sh" && echo yes || echo no)"
_c "backup (.bak) file created" yes "$([ -f "$WORK/bad.sh.bak" ] && echo yes || echo no)"

# 3. Safe apply (syntax fail)
printf '#!/bin/sh\nif [ ; then\n' > "$WORK/bad_patch.sh"
rc=0
patcher_apply_safe "$WORK/bad.sh" "$WORK/bad_patch.sh" >/dev/null 2>&1 || rc=$?
_c "apply bad patch rejected (126)" 126 "$rc"

# 4. OMNI_SYSROOT guard
rc=0
OMNI_SYSROOT=/tmp/fx patcher_apply_safe "$WORK/bad.sh" "$WORK/good_patch.sh" >/dev/null 2>&1 || rc=$?
_c "apply guarded by OMNI_SYSROOT" 126 "$rc"

# 5. CLI help
rc=0
"$ROOT/bin/omni-patcher" help >/dev/null 2>&1 || rc=$?
_c "cli help exits 0" 0 "$rc"

# 6. Cloud API key lifecycle and extraction
export OMNI_AI_API_KEY="test-key-123"
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" << 'MOCK_CURL'
#!/bin/sh
printf '%s\n' '{"candidates":[{"content":{"parts":[{"text":"#!/bin/sh\nexit 0\n"}]}}]}'
MOCK_CURL
chmod +x "$WORK/bin/curl"

OLDPATH="$PATH"
PATH="$WORK/bin:$PATH"
export PATH

rc=0
patcher_query_llm "$WORK/ctx.txt" "$WORK/llm_out.sh" >/dev/null 2>&1 || rc=$?
_c "cloud query returns 0" 0 "$rc"
_c "ephemeral API key unset after use" no "$([ -n "${OMNI_AI_API_KEY:-}" ] && echo yes || echo no)"
_c "cloud patch file created" yes "$([ -s "$WORK/llm_out.sh" ] && echo yes || echo no)"
_c "cloud patch file contains exit 0" yes "$(grep -q 'exit 0' "$WORK/llm_out.sh" && echo yes || echo no)"

PATH="$OLDPATH"
export PATH

rm -rf "$WORK"

printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
