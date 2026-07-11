#!/bin/sh
# test-deploy.sh — deploy module syntax + dry-run validation.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

check() {
    label="$1"; want="$2"; got="$3"
    if [ "$want" = "$got" ]; then
        printf '  \033[0;32mPASS\033[0m %-40s = %s\n' "$label" "$got"
        PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-40s want=%s got=%s\n' "$label" "$want" "$got"
        FAIL=$((FAIL+1))
    fi
}

echo "=== M7 Deploy Module Tests ==="

# 1. All deploy scripts pass syntax check
for f in "$ROOT"/src/deploy/*.sh; do
    sh -n "$f" && check "syntax: $(basename "$f")" "ok" "ok" || check "syntax: $(basename "$f")" "ok" "fail"
done
sh -n "$ROOT/bin/omni-deploy" && check "syntax: omni-deploy" "ok" "ok" || check "syntax: omni-deploy" "ok" "fail"

# 2. Help flag works
"$ROOT/bin/omni-deploy" --help >/dev/null 2>&1
check "help flag exits cleanly" "0" "$?"

# 3. Dry-run as non-root should fail at preflight (requires root)
rc=0
"$ROOT/bin/omni-deploy" --dry-run --distro alpine --fs ext4 --disk sda >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && check "dry-run as non-root fails" "yes" "yes" || check "dry-run as non-root fails" "yes" "no"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
