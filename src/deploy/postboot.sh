#!/bin/sh
# src/deploy/postboot.sh
# M27-C: post-reboot interactive DISPLAY_OK verification.
# Pure POSIX shell. BusyBox ash-safe. No dynamic command execution.

POSTBOOT_SSH="${POSTBOOT_SSH:-ssh}"
POSTBOOT_SSH_CONNECT_TIMEOUT="${POSTBOOT_SSH_CONNECT_TIMEOUT:-5}"
POSTBOOT_TIMEOUT="${POSTBOOT_TIMEOUT:-60}"

_postboot_valid_uint() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# postboot_wait_ssh <host> <timeout_seconds>
# Returns 0 when reachable, 124 on timeout, and 2 for invalid arguments.
postboot_wait_ssh() {
    _pb_host=${1:-}
    _pb_timeout=${2:-}

    if [ -z "$_pb_host" ] || ! _postboot_valid_uint "$_pb_timeout"; then
        printf '%s\n' 'postboot_wait_ssh: usage: <host> <timeout>' >&2
        return 2
    fi

    _pb_connect_timeout=${POSTBOOT_SSH_CONNECT_TIMEOUT:-5}
    if ! _postboot_valid_uint "$_pb_connect_timeout"; then
        _pb_connect_timeout=5
    fi

    _pb_elapsed=0
    while [ "$_pb_elapsed" -lt "$_pb_timeout" ]; do
        if "$POSTBOOT_SSH" -o BatchMode=yes -o ConnectTimeout="$_pb_connect_timeout" "$_pb_host" true >/dev/null 2>&1; then
            return 0
        fi

        sleep 1
        _pb_elapsed=$((_pb_elapsed + 1))
    done

    return 124
}

# postboot_probe_display <host>
# Checks environment, Xorg/Xwayland and compositor processes, then logind.
# Returns 0 with a DISPLAY_* token or 1 with DISPLAY_NONE.
postboot_probe_display() {
    _pb_host=${1:-}

    if [ -z "$_pb_host" ]; then
        printf '%s\n' 'postboot_probe_display: usage: <host>' >&2
        return 2
    fi

    _pb_script='
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
    echo DISPLAY_ENV
    exit 0
fi

if command -v pgrep >/dev/null 2>&1; then
    for _pb_proc in Xorg Xwayland sway Hyprland niri gnome-shell xfce4-session startplasma-wayland startplasma-x11 awesome fluxbox dwm; do
        if pgrep -x "$_pb_proc" >/dev/null 2>&1; then
            echo DISPLAY_PROC
            exit 0
        fi
    done
fi

if ps 2>/dev/null | grep -v grep | grep -E "Xorg|Xwayland|sway|Hyprland|niri|gnome-shell|xfce4-session|startplasma-wayland|startplasma-x11|awesome|fluxbox|dwm" >/dev/null 2>&1; then
    echo DISPLAY_PROC
    exit 0
fi

if command -v loginctl >/dev/null 2>&1; then
    _pb_sessions=$(loginctl list-sessions --no-legend 2>/dev/null | awk "{print \$1}")

    if [ -z "$_pb_sessions" ]; then
        _pb_sessions=$(loginctl list-sessions 2>/dev/null | awk "NR > 1 {print \$1}")
    fi

    for _pb_sid in $_pb_sessions; do
        _pb_info=$(loginctl show-session "$_pb_sid" -p State -p Type 2>/dev/null)
        _pb_state=$(printf "%s\n" "$_pb_info" | sed -n "s/^State=//p")
        _pb_type=$(printf "%s\n" "$_pb_info" | sed -n "s/^Type=//p")

        case "$_pb_state:$_pb_type" in
            active:wayland|active:x11)
                echo DISPLAY_LOGIND
                exit 0
                ;;
        esac
    done
fi

echo DISPLAY_NONE
exit 1
'

    _pb_out=$(
        "$POSTBOOT_SSH" \
            -o BatchMode=yes \
            -o ConnectTimeout="${POSTBOOT_SSH_CONNECT_TIMEOUT:-5}" \
            "$_pb_host" "$_pb_script" 2>/dev/null
    )
    _pb_rc=$?

    case "$_pb_out" in
        DISPLAY_ENV|DISPLAY_PROC|DISPLAY_LOGIND)
            printf '%s\n' "$_pb_out"
            return 0
            ;;
        *)
            printf '%s\n' 'DISPLAY_NONE'
            [ "$_pb_rc" -eq 2 ] && return 2
            return 1
            ;;
    esac
}

# Internal POSIX timeout implementation.
# The read occurs in a child process and is polled once per second.
_postboot_read_timed() (
    _pb_limit=${1:-60}

    if ! _postboot_valid_uint "$_pb_limit"; then
        _pb_limit=60
    fi

    _pb_file="${TMPDIR:-/tmp}/omni-postboot-read-$$"
    _pb_reader=

    trap 'rm -f "$_pb_file"' 0
    trap '
        if [ -n "${_pb_reader:-}" ]; then
            kill "$_pb_reader" 2>/dev/null || true
            wait "$_pb_reader" 2>/dev/null || true
        fi
        exit 130
    ' 1 2 15

    rm -f "$_pb_file"

    (
        if [ -r /dev/tty ]; then
            IFS= read -r _pb_line </dev/tty || exit 1
        else
            IFS= read -r _pb_line || exit 1
        fi

        printf '%s\n' "$_pb_line" >"$_pb_file"
    ) &
    _pb_reader=$!

    _pb_elapsed=0
    while kill -0 "$_pb_reader" 2>/dev/null; do
        if [ "$_pb_elapsed" -ge "$_pb_limit" ]; then
            kill "$_pb_reader" 2>/dev/null || true
            wait "$_pb_reader" 2>/dev/null || true
            exit 124
        fi

        sleep 1
        _pb_elapsed=$((_pb_elapsed + 1))
    done

    wait "$_pb_reader" 2>/dev/null
    _pb_reader_rc=$?

    if [ "$_pb_reader_rc" -eq 0 ] && [ -f "$_pb_file" ]; then
        cat "$_pb_file"
        exit 0
    fi

    exit 124
)

# postboot_prompt_display_ok [timeout_seconds]
# Returns 0 for yes, 1 for no, 124 for timeout and 130 on interruption.
postboot_prompt_display_ok() {
    case "${POSTBOOT_ASSUME:-}" in
        ok|OK|yes|YES|Yes|y|Y) return 0 ;;
        fail|FAIL|no|NO|No|n|N) return 1 ;;
        timeout|TIMEOUT) return 124 ;;
    esac

    _pb_timeout=${1:-${POSTBOOT_TIMEOUT:-60}}
    if ! _postboot_valid_uint "$_pb_timeout"; then
        _pb_timeout=60
    fi

    _pb_columns=${COLUMNS:-80}
    if ! _postboot_valid_uint "$_pb_columns"; then
        _pb_columns=80
    fi

    if [ "$_pb_columns" -lt 50 ]; then
        printf '%s\n' '+---------------+'
        printf '%s\n' '| DISPLAY CHECK |'
        printf '%s\n' '+---------------+'
        printf '%s\n' 'Desktop session'
        printf '%s\n' 'visible and OK?'
        printf '%s\n' '[y] yes'
        printf '%s\n' '[n] no'
        printf 'Timeout: %ss\n' "$_pb_timeout"
        printf '%s' '> '
    else
        printf 'DISPLAY_OK? Desktop session visible and correct? [y/N] (%ss): ' "$_pb_timeout"
    fi

    _pb_answer=$(_postboot_read_timed "$_pb_timeout")
    _pb_read_rc=$?

    if [ "$_pb_read_rc" -ne 0 ]; then
        printf '\n'
        return "$_pb_read_rc"
    fi

    case "$_pb_answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

_postboot_json_escape() {
    printf '%s' "${1:-}" |
        tr '\015\012' '  ' |
        sed 's/\\/\\\\/g; s/"/\\"/g'
}

# postboot_emit_result <host> <phase> <status> [detail]
# Returns 126 whenever OMNI_SYSROOT is set.
postboot_emit_result() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        return 126
    fi

    _pb_host=${1:-}
    _pb_phase=${2:-}
    _pb_status=${3:-}
    _pb_detail=${4:-}

    if [ -z "$_pb_host" ] || [ -z "$_pb_phase" ] || [ -z "$_pb_status" ]; then
        printf '%s\n' 'postboot_emit_result: usage: <host> <phase> <status> [detail]' >&2
        return 2
    fi

    _pb_timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
    if [ -z "$_pb_timestamp" ]; then
        _pb_timestamp=1970-01-01T00:00:00Z
    fi

    printf '{"ts":"%s","tool":"omni-deploy","phase":"%s","host":"%s","status":"%s","detail":"%s"}\n' \
        "$(_postboot_json_escape "$_pb_timestamp")" \
        "$(_postboot_json_escape "$_pb_phase")" \
        "$(_postboot_json_escape "$_pb_host")" \
        "$(_postboot_json_escape "$_pb_status")" \
        "$(_postboot_json_escape "$_pb_detail")"

    return 0
}

_postboot_emit_and_return() {
    _pb_return_code=${1:-1}
    _pb_host=${2:-}
    _pb_status=${3:-}
    _pb_detail=${4:-}

    postboot_emit_result "$_pb_host" postboot "$_pb_status" "$_pb_detail"
    _pb_emit_rc=$?

    if [ "$_pb_emit_rc" -ne 0 ]; then
        return "$_pb_emit_rc"
    fi

    return "$_pb_return_code"
}

# postboot_verify <host> <profile> [ssh_timeout]
# Returns 0 for OK, 1 for FAIL, 124 for TIMEOUT and 126 for the guard.
postboot_verify() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        return 126
    fi

    _pb_host=${1:-}
    _pb_profile=${2:-none}
    _pb_ssh_timeout=${3:-120}

    if [ -z "$_pb_host" ]; then
        printf '%s\n' 'postboot_verify: usage: <host> <profile> [ssh_timeout]' >&2
        return 2
    fi

    postboot_wait_ssh "$_pb_host" "$_pb_ssh_timeout"
    _pb_wait_rc=$?

    case "$_pb_wait_rc" in
        0)
            ;;
        124)
            _postboot_emit_and_return 124 "$_pb_host" ssh_timeout "$_pb_profile"
            return $?
            ;;
        *)
            return "$_pb_wait_rc"
            ;;
    esac

    if postboot_probe_display "$_pb_host" >/dev/null 2>&1; then
        _pb_probe=display_detected
    else
        _pb_probe=display_absent
    fi

    postboot_prompt_display_ok "${POSTBOOT_TIMEOUT:-60}"
    _pb_prompt_rc=$?

    case "$_pb_prompt_rc" in
        0)
            _postboot_emit_and_return 0 "$_pb_host" display_ok "$_pb_profile:$_pb_probe"
            return $?
            ;;
        124)
            _postboot_emit_and_return 124 "$_pb_host" display_timeout "$_pb_profile:$_pb_probe"
            return $?
            ;;
        130)
            _postboot_emit_and_return 130 "$_pb_host" display_interrupted "$_pb_profile:$_pb_probe"
            return $?
            ;;
        *)
            _postboot_emit_and_return 1 "$_pb_host" display_fail "$_pb_profile:$_pb_probe"
            return $?
            ;;
    esac
}
