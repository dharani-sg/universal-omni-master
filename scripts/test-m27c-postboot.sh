#!/bin/sh
# scripts/test-m27c-postboot.sh
# M27-C unit gate for OK, FAIL, TIMEOUT and mutation-guard paths.
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
. "$_root/src/deploy/postboot.sh"

_work="${TMPDIR:-/tmp}/omni-m27c-test-$$"
umask 077
rm -rf "$_work"
mkdir -p "$_work" || exit 1

trap 'rm -rf "$_work"' 0
trap 'exit 130' 1 2 15

{
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'case "${MOCK_SSH_MODE:-proc}" in'
    printf '%s\n' '    up) exit 0 ;;'
    printf '%s\n' '    proc) echo DISPLAY_PROC; exit 0 ;;'
    printf '%s\n' '    env) echo DISPLAY_ENV; exit 0 ;;'
    printf '%s\n' '    logind) echo DISPLAY_LOGIND; exit 0 ;;'
    printf '%s\n' '    none) echo DISPLAY_NONE; exit 1 ;;'
    printf '%s\n' '    down) exit 255 ;;'
    printf '%s\n' '    *) exit 1 ;;'
    printf '%s\n' 'esac'
} >"$_work/ssh"
chmod +x "$_work/ssh"

POSTBOOT_SSH="$_work/ssh"
export POSTBOOT_SSH

printf '%s\n' '=== M27-C: postboot unit gate ==='

MOCK_SSH_MODE=up
export MOCK_SSH_MODE
postboot_wait_ssh host1 2 >/dev/null 2>&1
_check wait_reachable 0 "$?"

MOCK_SSH_MODE=down
export MOCK_SSH_MODE
postboot_wait_ssh host1 1 >/dev/null 2>&1
_check wait_timeout 124 "$?"

postboot_wait_ssh host1 invalid >/dev/null 2>&1
_check wait_invalid_argument 2 "$?"

MOCK_SSH_MODE=proc
export MOCK_SSH_MODE
_probe=$(postboot_probe_display host1)
_probe_rc=$?
_check probe_process_status 0 "$_probe_rc"
_check probe_process_token DISPLAY_PROC "$_probe"

MOCK_SSH_MODE=none
export MOCK_SSH_MODE
_probe=$(postboot_probe_display host1)
_probe_rc=$?
_check probe_none_status 1 "$_probe_rc"
_check probe_none_token DISPLAY_NONE "$_probe"

POSTBOOT_ASSUME=ok
export POSTBOOT_ASSUME
postboot_prompt_display_ok >/dev/null 2>&1
_check prompt_ok 0 "$?"

POSTBOOT_ASSUME=fail
export POSTBOOT_ASSUME
postboot_prompt_display_ok >/dev/null 2>&1
_check prompt_fail 1 "$?"

POSTBOOT_ASSUME=timeout
export POSTBOOT_ASSUME
postboot_prompt_display_ok >/dev/null 2>&1
_check prompt_timeout 124 "$?"
unset POSTBOOT_ASSUME

_line=$(postboot_emit_result host1 postboot display_ok 'niri:detected')
_emit_rc=$?
_check emit_status 0 "$_emit_rc"

case "$_line" in
    *'"tool":"omni-deploy"'*'"host":"host1"'*'"status":"display_ok"'*)
        _shape=ok
        ;;
    *)
        _shape=fail
        ;;
esac
_check emit_ndjson_shape ok "$_shape"

(
    OMNI_SYSROOT=/mnt
    export OMNI_SYSROOT
    postboot_emit_result host1 postboot display_ok niri >/dev/null 2>&1
)
_check emit_mutation_guard 126 "$?"

MOCK_SSH_MODE=proc
POSTBOOT_ASSUME=ok
export MOCK_SSH_MODE POSTBOOT_ASSUME
postboot_verify host1 niri 2 >/dev/null 2>&1
_check verify_ok 0 "$?"

MOCK_SSH_MODE=proc
POSTBOOT_ASSUME=fail
export MOCK_SSH_MODE POSTBOOT_ASSUME
postboot_verify host1 niri 2 >/dev/null 2>&1
_check verify_fail 1 "$?"

MOCK_SSH_MODE=proc
POSTBOOT_ASSUME=timeout
export MOCK_SSH_MODE POSTBOOT_ASSUME
postboot_verify host1 niri 2 >/dev/null 2>&1
_check verify_prompt_timeout 124 "$?"

MOCK_SSH_MODE=down
POSTBOOT_ASSUME=ok
export MOCK_SSH_MODE POSTBOOT_ASSUME
postboot_verify host1 niri 1 >/dev/null 2>&1
_check verify_ssh_timeout 124 "$?"

(
    OMNI_SYSROOT=/mnt
    export OMNI_SYSROOT
    postboot_verify host1 niri 1 >/dev/null 2>&1
)
_check verify_mutation_guard 126 "$?"

unset POSTBOOT_ASSUME MOCK_SSH_MODE

if [ "$_fail" -ne 0 ]; then
    printf '%s\n' 'M27-C: FAIL'
    exit 1
fi

printf '%s\n' 'M27-C: PASS'
exit 0
