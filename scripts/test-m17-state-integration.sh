#!/bin/sh
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
PASS=0
FAIL=0

_check()
{
    _label=$1
    _expected=$2
    _actual=$3

    if [ "$_expected" = "$_actual" ]; then
        printf '  PASS %-52s = %s\n' "$_label" "$_actual"
        PASS=$((PASS + 1))
    else
        printf '  FAIL %-52s want=%s got=%s\n' \
            "$_label" "$_expected" "$_actual"
        FAIL=$((FAIL + 1))
    fi
}

printf '%s\n' '=== M17.2 State Integration Tests ==='

for _file in \
    "$ROOT/src/deploy/common.sh" \
    "$ROOT/src/deploy/state.sh" \
    "$ROOT/src/deploy/orchestrate.sh" \
    "$ROOT/bin/omni-deploy"
do
    if sh -n "$_file"; then
        _check "syntax: ${_file##*/}" 0 0
    else
        _check "syntax: ${_file##*/}" 0 1
    fi
done

_legacy=$(grep -c '^deploy_state_.*()' "$ROOT/src/deploy/common.sh" 2>/dev/null)
[ -z "$_legacy" ] && _legacy=0
_check "no legacy state functions in common.sh" 0 "$_legacy"

_sources=$(grep -c 'src/deploy/state.sh' "$ROOT/bin/omni-deploy")
_check "state.sh sourced exactly once" 1 "$_sources"

_orch_sources=$(grep -c 'src/deploy/orchestrate.sh' "$ROOT/bin/omni-deploy")
_check "orchestrate.sh sourced exactly once" 1 "$_orch_sources"

_steps=$(sed -n 's/^OMNI_DEPLOY_STEPS="\(.*\)"/\1/p' "$ROOT/src/deploy/state.sh")
_check "phase vocabulary aligned" \
    "partitioning mounting bootstrap chroot_setup configure desktop policies initramfs bootloader verify" \
    "$_steps"

grep -q 'deploy_state_summary' "$ROOT/bin/omni-deploy"
_check "status uses state summary" 0 "$?"

grep -q -- '--resume' "$ROOT/bin/omni-deploy"
_check "resume option present" 0 "$?"

grep -q -- '--fresh' "$ROOT/bin/omni-deploy"
_check "fresh option present" 0 "$?"

grep -q 'deploy_install_execute' "$ROOT/bin/omni-deploy"
_check "install path uses deploy_install_execute" 0 "$?"

WORK="${TMPDIR:-/tmp}/omni-m17-state-$$"
mkdir -p "$WORK"

OMNI_DATA="$WORK" "$ROOT/bin/omni-deploy" status > "$WORK/status.out" 2>&1
_check "status with no active state exits zero" 0 "$?"
grep -q 'no active deployment state' "$WORK/status.out"
_check "status reports no active state" 0 "$?"

. "$ROOT/src/core/logging.sh" 2>/dev/null || true
. "$ROOT/src/deploy/state.sh"
. "$ROOT/src/deploy/orchestrate.sh"

OMNI_STATE_FILE="$WORK/state.conf"
OMNI_STATE_LOCK="$WORK/state.lock"
export OMNI_STATE_FILE OMNI_STATE_LOCK

deploy_state_init alpine sda btrfs

_mock_count=0
_mock_phase()
{
    _mock_count=$((_mock_count + 1))
    return 0
}

# First run marks partitioning done
deploy_phase_run partitioning _mock_phase
_check "phase handler executes once" 1 "$_mock_count"
_check "successful phase recorded done" done "$(deploy_state_get partitioning)"

# Stub validator so the skip path is deterministic and host-independent.
# We are testing orchestration wiring, not real block-device presence.
deploy_phase_validate()
{
    case "$1" in
        partitioning) return 0 ;;
        *) return 1 ;;
    esac
}

# Second run should skip because validator says partitioning is valid.
deploy_phase_run partitioning _mock_phase
_check "validated completed phase skipped" 1 "$_mock_count"

_mock_fail()
{
    return 7
}

_rc=0
deploy_phase_run mounting _mock_fail >/dev/null 2>&1 || _rc=$?
_check "failed handler preserves exit status" 7 "$_rc"
_check "failed phase recorded failed" failed "$(deploy_state_get mounting)"

rm -rf "$WORK"

printf '%s\n' '=================================================='
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"

[ "$FAIL" -eq 0 ]
