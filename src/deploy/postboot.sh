#!/bin/sh
# src/deploy/postboot.sh
# M27-C: Post-reboot interactive DISPLAY_OK verification.
# Pure POSIX. BusyBox ash-safe. NO bashisms, NO eval, NO set --, NO tput.

# SSH indirection: a single executable name, overridable for tests/mocks.
POSTBOOT_SSH="${POSTBOOT_SSH:-ssh}"

# postboot_wait_ssh <host> <timeout_seconds>
#   Polls SSH once per second until reachable or timeout expires.
#   0 = reachable, 1 = timeout, 2 = usage error.
postboot_wait_ssh() {
    _pb_host=$1
    _pb_to=$2
    if [ -z "$_pb_host" ] || [ -z "$_pb_to" ]; then
        echo "postboot_wait_ssh: usage: <host> <timeout>" >&2
        return 2
    fi
    _pb_n=0
    while [ "$_pb_n" -lt "$_pb_to" ]; do
        if "$POSTBOOT_SSH" -o BatchMode=yes -o ConnectTimeout=5 "$_pb_host" true >/dev/null 2>&1; then
            return 0
        fi
        _pb_n=$((_pb_n + 1))
        sleep 1
    done
    return 1
}

# postboot_probe_display <host>
#   Detects a graphical session on <host>, in order:
#     1. running Xorg/Xwayland process
#     2. WAYLAND_DISPLAY set in the remote environment
#     3. active loginctl session (only if loginctl exists)
#   Degrades gracefully when loginctl is absent (Alpine/OpenRC, Void/runit).
#   Echoes a token; 0 = display present, 1 = none, 2 = usage error.
postboot_probe_display() {
    _pb_host=$1
    if [ -z "$_pb_host" ]; then
        echo "postboot_probe_display: usage: <host>" >&2
        return 2
    fi
    _pb_probe='
        if pgrep -x Xorg >/dev/null 2>&1 || pgrep -x Xwayland >/dev/null 2>&1; then
            echo DISPLAY_PROC; exit 0
        fi
        if [ -n "${WAYLAND_DISPLAY:-}" ]; then
            echo DISPLAY_WAYLAND; exit 0
        fi
        if command -v loginctl >/dev/null 2>&1; then
            if loginctl list-sessions 2>/dev/null | grep -q .; then
                echo DISPLAY_LOGIND; exit 0
            fi
        fi
        echo DISPLAY_NONE; exit 1
    '
    _pb_out=$("$POSTBOOT_SSH" -o BatchMode=yes -o ConnectTimeout=5 "$_pb_host" "$_pb_probe" 2>/dev/null)
    case "$_pb_out" in
        DISPLAY_PROC|DISPLAY_WAYLAND|DISPLAY_LOGIND)
            echo "$_pb_out"
            return 0
            ;;
        *)
            echo DISPLAY_NONE
            return 1
            ;;
    esac
}

# postboot_prompt_display_ok
#   Interactive Y/N confirmation. Default timeout 60s (POSTBOOT_TIMEOUT override).
#   Adaptive layout via COLUMNS: <50 = 9:16 thumb stack (Termux), else wide.
#   CI bypass: POSTBOOT_ASSUME=ok|fail skips the read entirely.
#   0 = confirmed OK, 1 = declined, 124 = timeout/EOF.
postboot_prompt_display_ok() {
    case "${POSTBOOT_ASSUME:-}" in
        ok|OK|yes|y|Y)    return 0 ;;
        fail|FAIL|no|n|N) return 1 ;;
    esac

    _pb_cols=${COLUMNS:-80}
    case "$_pb_cols" in
        ''|*[!0-9]*) _pb_cols=80 ;;
    esac
    _pb_to=${POSTBOOT_TIMEOUT:-60}

    if [ "$_pb_cols" -lt 50 ]; then
        echo '+---------------+'
        echo '| DISPLAY CHECK |'
        echo '+---------------+'
        echo 'Desktop session'
        echo 'visible and OK?'
        echo '[y] yes'
        echo '[n] no'
        printf '%s' '> '
    else
        printf '%s' 'DISPLAY_OK? Desktop session visible and correct? [y/N] (60s): '
    fi

    if read -t "$_pb_to" _pb_ans; then
        case "$_pb_ans" in
            y|Y|yes|YES|Yes) return 0 ;;
            *)               return 1 ;;
        esac
    fi
    echo ''
    return 124
}

# postboot_emit_result <host> <phase> <status> [detail]
#   Emits one NDJSON audit line. Honors the OMNI_SYSROOT mutation guard.
#   0 = emitted, 2 = usage error, 126 = mutation guard tripped.
postboot_emit_result() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        return 126
    fi
    _pb_host=$1
    _pb_phase=$2
    _pb_status=$3
    _pb_detail=${4:-}
    if [ -z "$_pb_host" ] || [ -z "$_pb_phase" ] || [ -z "$_pb_status" ]; then
        echo "postboot_emit_result: usage: <host> <phase> <status> [detail]" >&2
        return 2
    fi
    _pb_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 1970-01-01T00:00:00Z)
    _pb_json=$(printf '{"ts":"%s","tool":"omni-deploy","phase":"%s","host":"%s","status":"%s","detail":"%s"}' "$_pb_ts" "$_pb_phase" "$_pb_host" "$_pb_status" "$_pb_detail")
    echo "$_pb_json"
}

# postboot_verify <host> <profile> [ssh_timeout]
#   High-level M27-C flow: wait SSH -> probe -> prompt -> emit NDJSON.
#   0 = DISPLAY_OK confirmed, 1 = any failure/timeout, 2 = usage error.
postboot_verify() {
    _pb_host=$1
    _pb_profile=$2
    _pb_ssl=${3:-120}
    if [ -z "$_pb_host" ]; then
        echo "postboot_verify: usage: <host> <profile> [ssh_timeout]" >&2
        return 2
    fi

    if ! postboot_wait_ssh "$_pb_host" "$_pb_ssl"; then
        postboot_emit_result "$_pb_host" postboot ssh_timeout "$_pb_profile"
        return 1
    fi

    if postboot_probe_display "$_pb_host" >/dev/null 2>&1; then
        _pb_probe=display_detected
    else
        _pb_probe=display_absent
    fi

    postboot_prompt_display_ok
    _pb_rc=$?
    case "$_pb_rc" in
        0)   _pb_final=display_ok ;;
        124) _pb_final=display_timeout ;;
        *)   _pb_final=display_fail ;;
    esac

    postboot_emit_result "$_pb_host" postboot "$_pb_final" "$_pb_profile:$_pb_probe"
    [ "$_pb_final" = display_ok ] && return 0
    return 1
}
