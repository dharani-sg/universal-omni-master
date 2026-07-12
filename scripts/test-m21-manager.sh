#!/bin/sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0

_c() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %-52s = %s\n' "$1" "$3"; PASS=$((PASS+1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1))
    fi
}

echo "=== M21 Central Control Manager Tests ==="
export OMNI_ROOT="$ROOT"

# Syntax
sh -n "$ROOT/src/manager/control.sh" && _c "syntax: control.sh" ok ok || _c "syntax: control.sh" ok fail
sh -n "$ROOT/bin/omni-manager" && _c "syntax: omni-manager" ok ok || _c "syntax: omni-manager" ok fail

# list-clis returns omni-detect (always present)
_clis=$("$ROOT/bin/omni-manager" list-clis 2>/dev/null)
printf '%s\n' "$_clis" | grep -q '^omni-detect$' && \
    _c "list-clis includes omni-detect" yes yes || _c "list-clis includes omni-detect" yes no

# list-tools returns entries from the builder
_tools=$("$ROOT/bin/omni-manager" list-tools 2>/dev/null)
printf '%s\n' "$_tools" | grep -q 'omni-deploy' && \
    _c "list-tools includes omni-deploy" yes yes || _c "list-tools includes omni-deploy" yes no

# audit-sync with current state (should be synced)
rc=0; "$ROOT/bin/omni-manager" audit-sync >/dev/null 2>&1 || rc=$?
_c "audit-sync exits 0 (repo synced)" 0 "$rc"

# unknown command returns 2
rc=0; "$ROOT/bin/omni-manager" bogus >/dev/null 2>&1 || rc=$?
_c "unknown command exits 2" 2 "$rc"

# OMNI_SYSROOT guard on add-tool
rc=0; OMNI_SYSROOT=/tmp/fx "$ROOT/bin/omni-manager" add-tool omni-fake >/dev/null 2>&1 || rc=$?
_c "add-tool OMNI_SYSROOT guard 126" 126 "$rc"

# OMNI_SYSROOT guard on remove-tool
rc=0; OMNI_SYSROOT=/tmp/fx "$ROOT/bin/omni-manager" remove-tool omni-detect >/dev/null 2>&1 || rc=$?
_c "remove-tool OMNI_SYSROOT guard 126" 126 "$rc"

# snapshot creates a directory
_snap=$("$ROOT/bin/omni-manager" snapshot 2>/dev/null)
_c "snapshot creates a directory" yes "$([ -d "$_snap" ] && echo yes || echo no)"
rm -rf "$_snap" 2>/dev/null

# help exits 0
rc=0; "$ROOT/bin/omni-manager" help >/dev/null 2>&1 || rc=$?
_c "help exits 0" 0 "$rc"

echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
