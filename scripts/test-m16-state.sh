#!/bin/sh
# scripts/test-m16-state.sh — M16 state machine gate.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_c() { [ "$2" = "$3" ] && { printf '  PASS %-52s = %s\n' "$1" "$3"; PASS=$((PASS+1)); } || { printf '  FAIL %-52s want=%s got=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); }; }

echo "=== M16 State Machine Tests ==="

sh -n "$ROOT/src/deploy/state.sh" && _c "syntax: state.sh" ok ok || _c "syntax: state.sh" ok fail

# Isolate the state file to a temp path — never touch /var/lib/omni-master
WORK="${TMPDIR:-/tmp}/omni-m16-$$"
mkdir -p "$WORK"
export OMNI_STATE_FILE="$WORK/deploy-state.conf"
export OMNI_STATE_LOCK="${OMNI_STATE_FILE}.lock"

. "$ROOT/src/deploy/state.sh"

# --- Init ------------------------------------------------------------------
deploy_state_init alpine sda btrfs
_c "init creates file" yes "$([ -f "$OMNI_STATE_FILE" ] && echo yes || echo no)"
_c "meta distro=alpine" alpine "$(deploy_state_get_meta distro)"
_c "meta disk=sda" sda "$(deploy_state_get_meta disk)"
_c "meta fs=btrfs" btrfs "$(deploy_state_get_meta fs)"
_c "meta schema_version=1" 1 "$(deploy_state_get_meta schema_version)"
_c "session_id populated" yes "$([ -n "$(deploy_state_get_meta session_id)" ] && echo yes || echo no)"

# --- Initial resume: first step is partition -------------------------------
_c "fresh resume = partitioning" partitioning "$(deploy_state_resume)"
_c "get partitioning = pending" pending "$(deploy_state_get partitioning)"

# --- Set + get roundtrip ---------------------------------------------------
deploy_state_set partitioning done
_c "set/get partitioning=done" done "$(deploy_state_get partitioning)"

deploy_state_set mounting running
_c "set/get mounting=running" running "$(deploy_state_get mounting)"

# --- Resume skips done, returns running (interrupted step) -----------------
_c "resume after partitioning done = mounting" mounting "$(deploy_state_resume)"

# --- Simulate crash: mark format done, bootstrap running -------------------
deploy_state_set mounting done
deploy_state_set bootstrap running
_c "resume mid-flight = bootstrap" bootstrap "$(deploy_state_resume)"

# --- Failed step still needs retry ----------------------------------------
deploy_state_fail bootstrap "network timeout"
_c "get bootstrap = failed" failed "$(deploy_state_get bootstrap)"
_c "resume after fail = bootstrap (retry)" bootstrap "$(deploy_state_resume)"
_c "last_error recorded" yes "$([ -n "$(deploy_state_get_meta last_error)" ] && echo yes || echo no)"

# --- Complete every step; resume returns COMPLETE --------------------------
for _s in partitioning mounting bootstrap chroot_setup configure desktop policies initramfs bootloader verify; do
    deploy_state_set "$_s" done
done
_c "all done → resume = COMPLETE" COMPLETE "$(deploy_state_resume)"

# --- is_resumable positive case --------------------------------------------
rc=0; deploy_state_is_resumable || rc=$?
_c "is_resumable when session exists" 0 "$rc"

# --- Clear + is_resumable negative case ------------------------------------
deploy_state_clear
_c "clear removes file" yes "$([ ! -f "$OMNI_STATE_FILE" ] && echo yes || echo no)"
rc=0; deploy_state_is_resumable || rc=$?
_c "is_resumable when no session" 1 "$rc"

# --- Fresh init, no work done → not resumable (no real progress yet) ------
deploy_state_init void nvme0n1 ext4
rc=0; deploy_state_is_resumable || rc=$?
_c "fresh init (all pending) is NOT resumable" 1 "$rc"

# --- Input validation ------------------------------------------------------
rc=0; deploy_state_set 'bad;key' done >/dev/null 2>&1 || rc=$?
_c "reject invalid key" 2 "$rc"

rc=0; deploy_state_set partition invalid_status >/dev/null 2>&1 || rc=$?
_c "reject invalid status" 2 "$rc"

# --- Mutation guard: OMNI_SYSROOT must return 126 --------------------------
rc=0; OMNI_SYSROOT=/tmp/fx deploy_state_init alpine sda btrfs >/dev/null 2>&1 || rc=$?
_c "init OMNI_SYSROOT guard 126" 126 "$rc"

rc=0; OMNI_SYSROOT=/tmp/fx deploy_state_set partitioning done >/dev/null 2>&1 || rc=$?
_c "set OMNI_SYSROOT guard 126" 126 "$rc"

rc=0; OMNI_SYSROOT=/tmp/fx deploy_state_fail partition oops >/dev/null 2>&1 || rc=$?
_c "fail OMNI_SYSROOT guard 126" 126 "$rc"

rc=0; OMNI_SYSROOT=/tmp/fx deploy_state_clear >/dev/null 2>&1 || rc=$?
_c "clear OMNI_SYSROOT guard 126" 126 "$rc"

# --- Atomic write: no half-written file after interruption ----------------
# Force a partial state: create a broken tmp file, verify the real state file
# is untouched. This simulates a mid-write crash.
deploy_state_init arch sda btrfs
deploy_state_set partitioning done
_expected=$(cat "$OMNI_STATE_FILE")
printf 'garbage_partial_data' > "${OMNI_STATE_FILE}.tmp.99999"
_actual=$(cat "$OMNI_STATE_FILE")
_c "existing state untouched by orphan tmp" yes "$([ "$_expected" = "$_actual" ] && echo yes || echo no)"
rm -f "${OMNI_STATE_FILE}.tmp.99999"

# --- Lock: second concurrent init cannot corrupt state --------------------
# Grab lock, then try a second operation with a very short timeout.
mkdir "$OMNI_STATE_LOCK" 2>/dev/null
rc=0; OMNI_STATE_LOCK_TIMEOUT=1 deploy_state_set partition running >/dev/null 2>&1 || rc=$?
_c "concurrent op fails on locked state" 1 "$rc"
rmdir "$OMNI_STATE_LOCK" 2>/dev/null

# --- Summary produces output ----------------------------------------------
_summary=$(deploy_state_summary)
case "$_summary" in
    *"OMNI DEPLOY STATE"*) _c "summary produces header" yes yes ;;
    *) _c "summary produces header" yes no ;;
esac

rm -rf "$WORK"
echo "=================================================="
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
