#!/bin/sh
# scripts/test-m27c-wire.sh
# M27-C.1 integration gate: proves the flag reaches the postboot flow.
set -u

_fail=0

_check() {
    if [ "$2" = "$3" ]; then
        printf '  PASS %s (%s)\n' "$1" "$3"
    else
        printf '  FAIL %s expected=%s actual=%s\n' "$1" "$2" "$3"
        _fail=1
    fi
}

_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
_bin="$_root/bin/omni-deploy"

_work="${TMPDIR:-/tmp}/omni-m27c-wire-$$"
umask 077
rm -rf "$_work"
mkdir -p "$_work" || exit 1

trap 'rm -rf "$_work"' 0
trap 'exit 130' 1 2 15

{
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'case "${MOCK_SSH_MODE:-proc}" in'
    printf '%s\n' '    proc) echo DISPLAY_PROC; exit 0 ;;'
    printf '%s\n' '    down) exit 255 ;;'
    printf '%s\n' '    *) exit 1 ;;'
    printf '%s\n' 'esac'
} >"$_work/ssh"
chmod +x "$_work/ssh"

printf '%s\n' '=== M27-C.1: flag-to-dispatch integration ==='

if grep -q 'DEPLOY_POSTBOOT_VERIFY="${DEPLOY_POSTBOOT_VERIFY:-0}"' "$_bin"; then
    _check default_present yes yes
else
    _check default_present yes no
fi

if grep -q 'postboot_verify "$_pb_host"' "$_bin"; then
    _check callsite_present yes yes
else
    _check callsite_present yes no
fi

if "$_bin" help 2>/dev/null | grep -q -- '--postboot-verify'; then
    _check help_advertises_flag yes yes
else
    _check help_advertises_flag yes no
fi

_out=$(
    POSTBOOT_SSH="$_work/ssh" \
    MOCK_SSH_MODE=proc \
    POSTBOOT_ASSUME=ok \
    DEPLOY_POSTBOOT_HOST=host1 \
    DEPLOY_POSTBOOT_TIMEOUT=2 \
    DEPLOY_DESKTOP=niri \
    "$_bin" status --postboot-verify </dev/null 2>/dev/null
)
_status_rc=$?
_check status_verify_exit 0 "$_status_rc"

case "$_out" in
    *'"phase":"postboot"'*'"host":"host1"'*'"status":"display_ok"'*)
        _shape=ok
        ;;
    *)
        _shape=fail
        ;;
esac
_check status_verify_ndjson ok "$_shape"

_without_flag=$(
    POSTBOOT_SSH="$_work/ssh" \
    MOCK_SSH_MODE=proc \
    POSTBOOT_ASSUME=ok \
    DEPLOY_POSTBOOT_HOST=host1 \
    "$_bin" status </dev/null 2>/dev/null
)
_without_rc=$?
_check status_without_flag_exit 0 "$_without_rc"

case "$_without_flag" in
    *'"phase":"postboot"'*)
        _leak=detected
        ;;
    *)
        _leak=clean
        ;;
esac
_check no_flag_no_postboot clean "$_leak"

_timeout_out=$(
    POSTBOOT_SSH="$_work/ssh" \
    MOCK_SSH_MODE=down \
    POSTBOOT_ASSUME=ok \
    DEPLOY_POSTBOOT_HOST=host1 \
    DEPLOY_POSTBOOT_TIMEOUT=1 \
    DEPLOY_DESKTOP=niri \
    "$_bin" status --postboot-verify </dev/null 2>/dev/null
)
_timeout_rc=$?
_check status_timeout_exit 124 "$_timeout_rc"

case "$_timeout_out" in
    *'"status":"ssh_timeout"'*)
        _timeout_shape=ok
        ;;
    *)
        _timeout_shape=fail
        ;;
esac
_check status_timeout_ndjson ok "$_timeout_shape"

if [ "$_fail" -ne 0 ]; then
    printf '%s\n' 'M27-C.1: FAIL'
    exit 1
fi

printf '%s\n' 'M27-C.1: PASS'
exit 0
