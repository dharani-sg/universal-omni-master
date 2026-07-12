#!/bin/sh
# src/deploy/ui.sh - POSIX shell UI primitives for adaptive TUI (M17)
# Dual-layer UI: portrait (Termux 9:16 / narrow SSH), compact, landscape.
# Pure POSIX, BusyBox ash-safe. NO bashisms, NO eval, NO tput.

TUI_LAYOUT="${TUI_LAYOUT:-}"
TUI_SHOW_LOGS="${TUI_SHOW_LOGS:-0}"
TUI_LOG_FILE="${TUI_LOG_FILE:-/tmp/omni-deploy.log}"

# Honors NO_COLOR (no-color.org), TERM=dumb, and requires a real tty on fd1.
_ui_ansi_ok() {
    if [ -n "${NO_COLOR+x}" ]; then
        return 1
    fi
    if [ "${TERM:-}" = "dumb" ]; then
        return 1
    fi
    if [ ! -t 1 ]; then
        return 1
    fi
    return 0
}

_ui_repeat() {
    _rc_ch="$1"; _rc_n="$2"; _rc_i=0; _rc_out=""
    while [ "$_rc_i" -lt "$_rc_n" ]; do
        _rc_out="${_rc_out}${_rc_ch}"
        _rc_i=$((_rc_i + 1))
    done
    printf '%s' "$_rc_out"
}

ui_detect_layout() {
    _dl_cols=""
    if command -v stty >/dev/null 2>&1; then
        _dl_size=$(stty size 2>/dev/null)
        [ -n "$_dl_size" ] && _dl_cols=$(printf '%s\n' "$_dl_size" | awk '{print $2}')
    fi
    [ -z "$_dl_cols" ] && [ -n "${COLUMNS:-}" ] && _dl_cols="$COLUMNS"
    [ -z "$_dl_cols" ] && _dl_cols=80
    case "$_dl_cols" in ''|*[!0-9]*) _dl_cols=80 ;; esac

    if [ "$_dl_cols" -lt 60 ]; then
        TUI_LAYOUT=portrait
    elif [ "$_dl_cols" -lt 100 ]; then
        TUI_LAYOUT=compact
    else
        TUI_LAYOUT=landscape
    fi
    export TUI_LAYOUT
    printf '%s\n' "$TUI_LAYOUT"
}

ui_banner() {
    _bn_text="$1"
    [ -z "${TUI_LAYOUT:-}" ] && ui_detect_layout >/dev/null

    case "$TUI_LAYOUT" in
        portrait|compact)
            printf '=== %s ===\n' "$_bn_text"
            return 0
            ;;
    esac

    _bn_len=$(printf '%s' "$_bn_text" | wc -c | tr -d ' ')
    _bn_pad=$((_bn_len + 4))
    _bn_bar=$(_ui_repeat '=' "$_bn_pad")

    if _ui_ansi_ok; then
        printf '\033[1m%s\033[0m\n' "$_bn_bar"
        printf '\033[1m= %s =\033[0m\n' "$_bn_text"
        printf '\033[1m%s\033[0m\n' "$_bn_bar"
    else
        printf '%s\n'     "$_bn_bar"
        printf '= %s =\n' "$_bn_text"
        printf '%s\n'     "$_bn_bar"
    fi
}

ui_menu() {
    _mn_title="$1"; shift
    [ -z "${TUI_LAYOUT:-}" ] && ui_detect_layout >/dev/null

    {
        printf '=== %s ===\n' "$_mn_title"
        _mn_i=1
        for _mn_opt in "$@"; do
            printf ' %d) %s\n' "$_mn_i" "$_mn_opt"
            _mn_i=$((_mn_i + 1))
        done
        printf 'Select: '
    } >&2

    read -r _mn_choice || return 1
    case "$_mn_choice" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$_mn_choice" -lt 1 ] || [ "$_mn_choice" -gt "$#" ]; then
        return 1
    fi

    _mn_i=1
    for _mn_opt in "$@"; do
        if [ "$_mn_i" -eq "$_mn_choice" ]; then
            printf '%s\n' "$_mn_opt"
            return 0
        fi
        _mn_i=$((_mn_i + 1))
    done
    return 1
}

ui_progress() {
    _pg_label="$1"; _pg_pct="$2"
    [ -z "${TUI_LAYOUT:-}" ] && ui_detect_layout >/dev/null

    case "$_pg_pct" in ''|*[!0-9]*) _pg_pct=0 ;; esac
    [ "$_pg_pct" -gt 100 ] && _pg_pct=100
    [ "$_pg_pct" -lt 0 ]   && _pg_pct=0

    case "$TUI_LAYOUT" in
        portrait) _pg_w=10 ;;
        compact)  _pg_w=20 ;;
        *)        _pg_w=40 ;;
    esac

    _pg_filled=$(( _pg_pct * _pg_w / 100 ))
    _pg_empty=$((  _pg_w - _pg_filled ))
    _pg_fbar=$(_ui_repeat '#' "$_pg_filled")
    _pg_ebar=$(_ui_repeat '.' "$_pg_empty")

    case "$TUI_LAYOUT" in
        portrait) printf '[%s%s] %d%%\n' "$_pg_fbar" "$_pg_ebar" "$_pg_pct" ;;
        *)        printf '%-20s [%s%s] %3d%%\n' "$_pg_label" "$_pg_fbar" "$_pg_ebar" "$_pg_pct" ;;
    esac
}

ui_log_toggle() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        return 126
    fi
    if [ "${TUI_SHOW_LOGS:-0}" = "1" ]; then
        TUI_SHOW_LOGS=0
    else
        TUI_SHOW_LOGS=1
    fi
    export TUI_SHOW_LOGS
    if [ "$TUI_SHOW_LOGS" = "1" ] && [ ! -e "$TUI_LOG_FILE" ]; then
        : > "$TUI_LOG_FILE" 2>/dev/null || true
    fi
    printf '%s\n' "$TUI_SHOW_LOGS"
}


# ui_log MESSAGE...
# Always records the line. When disclosure is enabled it also prints
# to stderr. File writes remain fixture-guarded.
ui_log() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        return 126
    fi

    _lg_msg="$*"
    _lg_dir=${TUI_LOG_FILE%/*}
    [ "$_lg_dir" = "$TUI_LOG_FILE" ] && _lg_dir=.

    mkdir -p "$_lg_dir" 2>/dev/null || return 1
    printf '%s\n' "$_lg_msg" >> "$TUI_LOG_FILE" || return 1

    if [ "${TUI_SHOW_LOGS:-0}" = "1" ]; then
        printf '%s\n' "$_lg_msg" >&2
    fi
    return 0
}

ui_confirm() {
    _cf_msg="$1"; _cf_word="$2"
    [ -z "${TUI_LAYOUT:-}" ] && ui_detect_layout >/dev/null

    case "$TUI_LAYOUT" in
        portrait|compact)
            printf '%s [type "%s" to confirm]: ' "$_cf_msg" "$_cf_word" >&2
            ;;
        *)
            _cf_len=$(printf '%s' "$_cf_msg" | wc -c | tr -d ' ')
            _cf_pad=$((_cf_len + 4))
            _cf_bar=$(_ui_repeat '!' "$_cf_pad")
            {
                if _ui_ansi_ok; then
                    printf '\033[33m%s\033[0m\n' "$_cf_bar"
                    printf '\033[33m! %s !\033[0m\n' "$_cf_msg"
                    printf '\033[33m%s\033[0m\n' "$_cf_bar"
                else
                    printf '%s\n'     "$_cf_bar"
                    printf '! %s !\n' "$_cf_msg"
                    printf '%s\n'     "$_cf_bar"
                fi
                printf 'Type "%s" exactly to confirm: ' "$_cf_word"
            } >&2
            ;;
    esac

    read -r _cf_ans || return 1
    [ "$_cf_ans" = "$_cf_word" ] && return 0
    return 1
}
