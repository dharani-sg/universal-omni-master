#!/bin/sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-52s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M27-B Deploy Desktop Integration Tests ==="
sh -n "$ROOT/bin/omni-deploy" && _c "syntax: omni-deploy" 0 0 || _c "syntax: omni-deploy" 0 1
sh -n "$ROOT/src/deploy/orchestrate.sh" && _c "syntax: orchestrate.sh" 0 0 || _c "syntax: orchestrate.sh" 0 1

. "$ROOT/src/deploy/state.sh"
. "$ROOT/src/deploy/orchestrate.sh"

WORK="${TMPDIR:-/tmp}/omni-m27b-$$"
mkdir -p "$WORK/bin" "$WORK/target"
export OMNI_ROOT="$WORK"
export DEPLOY_TARGET="$WORK/target"
export DEPLOY_DISTRO="alpine"
export DEPLOY_INIT="openrc"
export OMNI_DESKTOP_ARGLOG="$WORK/args.log"

cat > "$WORK/bin/omni-desktop" << 'MOCK'
#!/bin/sh
printf '%s\n' "$@" > "${OMNI_DESKTOP_ARGLOG:-/dev/null}"
exit "${OMNI_DESKTOP_MOCK_RC:-0}"
MOCK
chmod +x "$WORK/bin/omni-desktop"

# Test 1: No desktop
rm -f "$OMNI_DESKTOP_ARGLOG"
DEPLOY_DESKTOP=""
_deploy_phase_desktop >/dev/null 2>&1
_c "no desktop returns 0" 0 "$?"
_c "no desktop skips engine" no "$([ -f "$OMNI_DESKTOP_ARGLOG" ] && echo yes || echo no)"

# Test 2: Desktop set, no user
rm -f "$OMNI_DESKTOP_ARGLOG"
DEPLOY_DESKTOP="niri"
DEPLOY_DESKTOP_USER=""
DEPLOY_USER=""
_deploy_phase_desktop >/dev/null 2>&1
_c "desktop without user returns 2" 2 "$?"

# Test 3: Full call, no experimental
rm -f "$OMNI_DESKTOP_ARGLOG"
DEPLOY_DESKTOP="niri"
DEPLOY_DESKTOP_USER="alice"
DEPLOY_LOGIN_MANAGER="greetd"
DEPLOY_ALLOW_EXPERIMENTAL_DESKTOP=0
_deploy_phase_desktop >/dev/null 2>&1
_c "full install returns 0" 0 "$?"
_args=$(cat "$OMNI_DESKTOP_ARGLOG" 2>/dev/null)
echo "$_args" | grep -q -- "install" && _c "args contain install" yes yes || _c "args contain install" yes no
echo "$_args" | grep -q -- "--apply" && _c "args contain --apply" yes yes || _c "args contain --apply" yes no
echo "$_args" | grep -q -- "--allow-experimental" && _c "args NO --allow-experimental" no yes || _c "args NO --allow-experimental" no no

# Test 4: Experimental enabled
rm -f "$OMNI_DESKTOP_ARGLOG"
DEPLOY_ALLOW_EXPERIMENTAL_DESKTOP=1
_deploy_phase_desktop >/dev/null 2>&1
_args=$(cat "$OMNI_DESKTOP_ARGLOG" 2>/dev/null)
echo "$_args" | grep -q -- "--allow-experimental" && _c "args contain --allow-experimental" yes yes || _c "args contain --allow-experimental" yes no

# Test 5: OMNI_SYSROOT guard
rm -f "$OMNI_DESKTOP_ARGLOG"
OMNI_SYSROOT="$WORK"
DEPLOY_TARGET="$WORK/target"
DEPLOY_ALLOW_EXPERIMENTAL_DESKTOP=0
_deploy_phase_desktop >/dev/null 2>&1
_c "OMNI_SYSROOT guard returns 126" 126 "$?"

rm -rf "$WORK"
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
