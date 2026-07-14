#!/bin/sh
# scripts/test-m27c-postboot.sh
# M27-C gate. POSIX, BusyBox ash-safe. Validates OK / FAIL / TIMEOUT paths.

_fail=0
_check() {
    if [ "$2" = "$3" ]; then
        echo "  PASS $1 ($3)"
    else
        echo "  FAIL $1 expected=$2 actual=$3"
        _fail=1
    fi
}

_here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$_here/src/deploy/postboot.sh"

_mock=$(mktemp -d "${TMPDIR:-/tmp}/m27c.XXXXXX")
{
    echo '#!/bin/sh'
    echo 'case "${MOCK_SSH_MODE:-up}" in'
    echo '  up)   exit 0 ;;'
    echo '  down) exit 255 ;;'
    echo '  proc) echo DISPLAY_PROC; exit 0 ;;'
    echo '  none) echo DISPLAY_NONE; exit 1 ;;'
    echo 'esac'
} > "$_mock/ssh"
chmod +x "$_mock/ssh"
POSTBOOT_SSH="$_mock/ssh"
export POSTBOOT_SSH

echo '=== M27-C: postboot verification gate ==='

# --- postboot_wait_ssh -----------------------------------------------------
export MOCK_SSH_MODE=up
if postboot_wait_ssh h 3; then _r=ok; else _r=fail; fi
_check wait_ssh_reachable ok "$_r"

export MOCK_SSH_MODE=down
if postboot_wait_ssh h 2; then _r=ok; else _r=timeout; fi
_check wait_ssh_timeout timeout "$_r"

# --- postboot_probe_display ------------------------------------------------
export MOCK_SSH_MODE=proc
_out=$(postboot_probe_display h); _rc=$?
_check probe_ok_status 0 "$_rc"
_check probe_ok_token DISPLAY_PROC "$_out"

export MOCK_SSH_MODE=none
_out=$(postboot_probe_display h); _rc=$?
_check probe_none_status 1 "$_rc"
_check probe_none_token DISPLAY_NONE "$_out"

# --- postboot_prompt_display_ok  (OK / FAIL / TIMEOUT) ---------------------
export POSTBOOT_ASSUME=ok
postboot_prompt_display_ok </dev/null >/dev/null 2>&1; _r=$?
_check prompt_ok 0 "$_r"

export POSTBOOT_ASSUME=fail
postboot_prompt_display_ok </dev/null >/dev/null 2>&1; _r=$?
_check prompt_fail 1 "$_r"

unset POSTBOOT_ASSUME
export POSTBOOT_TIMEOUT=1
postboot_prompt_display_ok </dev/null >/dev/null 2>&1; _r=$?
_check prompt_timeout 124 "$_r"
unset POSTBOOT_TIMEOUT

# --- postboot_emit_result  (format + mutation guard) -----------------------
_line=$(unset OMNI_SYSROOT; postboot_emit_result host1 postboot display_ok "niri:detected")
case "$_line" in
    *'"tool":"omni-deploy"'*'"host":"host1"'*'"status":"display_ok"'*) _r=ok ;;
    *) _r=fail ;;
esac
_check emit_ndjson_shape ok "$_r"

( OMNI_SYSROOT=/mnt; export OMNI_SYSROOT; postboot_emit_result host1 postboot display_ok x >/dev/null 2>&1 ); _r=$?
_check emit_mutation_guard 126 "$_r"

# --- postboot_verify  (aggregate OK + SSH-timeout paths) -------------------
( export MOCK_SSH_MODE=up; export POSTBOOT_ASSUME=ok; postboot_verify host1 niri 3 </dev/null >/dev/null 2>&1 ); _r=$?
_check verify_display_ok 0 "$_r"

( export MOCK_SSH_MODE=down; postboot_verify host1 niri 2 </dev/null >/dev/null 2>&1 ); _r=$?
_check verify_ssh_timeout 1 "$_r"

rm -rf "$_mock"
if [ "$_fail" -ne 0 ]; then
    echo 'M27-C: FAIL'
    exit 1
fi
echo 'M27-C: PASS'
exit 0
