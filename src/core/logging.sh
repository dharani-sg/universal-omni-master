#!/bin/sh
# logging.sh — unified, POSIX-safe logging. Logs to STDERR; data stays on STDOUT.
# Level filter via OMNI_LOG_LEVEL: debug<info<warn<error (default: info)

OMNI_LOG_LEVEL="${OMNI_LOG_LEVEL:-info}"

_omni_lvl_num() {
    case "$1" in
        debug) echo 10 ;; info) echo 20 ;;
        warn)  echo 30 ;; error) echo 40 ;;
        *)     echo 20 ;;
    esac
}

_omni_should_log() {
    _want=$(_omni_lvl_num "$1")
    _cur=$(_omni_lvl_num "$OMNI_LOG_LEVEL")
    [ "$_want" -ge "$_cur" ]
}

_omni_log() {
    _lvl="$1"; shift
    _omni_should_log "$_lvl" || return 0
    # Color only if stderr is a tty
    if [ -t 2 ]; then
        case "$_lvl" in
            debug) _c='\033[0;90m' ;; info) _c='\033[0;36m' ;;
            warn)  _c='\033[1;33m' ;; error) _c='\033[1;31m' ;;
        esac
        printf '%b[%s]%b %s\n' "$_c" "$_lvl" '\033[0m' "$*" >&2
    else
        printf '[%s] %s\n' "$_lvl" "$*" >&2
    fi
}

log_debug() { _omni_log debug "$@"; }
log_info()  { _omni_log info  "$@"; }
log_warn()  { _omni_log warn  "$@"; }
log_error() { _omni_log error "$@"; }
