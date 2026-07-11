#!/bin/sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

check() {
    label="$1"; want="$2"; got="$3"
    if [ "$want" = "$got" ]; then
        printf '  \033[0;32mPASS\033[0m %-45s = %s\n' "$label" "$got"; PASS=$((PASS+1))
    else
        printf '  \033[1;31mFAIL\033[0m %-45s want=%s got=%s\n' "$label" "$want" "$got"; FAIL=$((FAIL+1))
    fi
}

echo "=== M7 Deploy Module Tests ==="

# 1. Syntax
for f in "$ROOT"/src/deploy/*.sh; do
    sh -n "$f" && check "syntax: $(basename "$f")" "ok" "ok" || check "syntax: $(basename "$f")" "ok" "fail"
done
sh -n "$ROOT/bin/omni-deploy" && check "syntax: bin/omni-deploy" "ok" "ok" || check "syntax: bin/omni-deploy" "ok" "fail"

# 2. Help
"$ROOT/bin/omni-deploy" help >/dev/null 2>&1
check "help exits cleanly" "0" "$?"

# 3. Preflight rejects non-root
rc=0
"$ROOT/bin/omni-deploy" install --apply --distro alpine --fs ext4 --disk sda >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && check "non-root install --apply rejected" "yes" "yes" || check "non-root install --apply rejected" "yes" "no"

# 4. Dry-run plan works as non-root
rc=0
"$ROOT/bin/omni-deploy" plan --distro alpine --fs ext4 --disk sda >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && check "plan works as non-root" "yes" "yes" || check "plan works as non-root" "yes" "no(rc=$rc)"

# 5. Auto-detect init per distro
. "$ROOT/src/core/logging.sh" 2>/dev/null; . "$ROOT/src/core/utils.sh" 2>/dev/null
. "$ROOT/src/deploy/common.sh" 2>/dev/null
check "auto-detect alpine -> openrc"  "openrc"  "$(deploy_auto_detect_init alpine)"
check "auto-detect void -> runit"     "runit"   "$(deploy_auto_detect_init void)"
check "auto-detect arch -> systemd"   "systemd" "$(deploy_auto_detect_init arch)"
check "auto-detect debian -> systemd" "systemd" "$(deploy_auto_detect_init debian)"
check "auto-detect chimera -> dinit"  "dinit"   "$(deploy_auto_detect_init chimera)"

# 6. Rollback module syntax
sh -n "$ROOT/src/deploy/rollback.sh" && check "syntax: rollback.sh" "ok" "ok"

# 7. Bootloader module syntax
sh -n "$ROOT/src/deploy/bootloader.sh" && check "syntax: bootloader.sh" "ok" "ok"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
