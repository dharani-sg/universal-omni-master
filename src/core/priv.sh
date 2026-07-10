#!/bin/sh
# priv.sh — privilege abstraction. NEVER edits sudoers/doas.conf. NEVER assumes NOPASSWD.

# Which helper is available? Returns: sudo | doas | none
priv_tool() {
    if [ -z "$OMNI_SYSROOT" ]; then
        if command -v doas >/dev/null 2>&1; then echo doas; return 0; fi
        if command -v sudo >/dev/null 2>&1; then echo sudo; return 0; fi
    else
        _have /usr/bin/doas && { echo doas; return 0; }
        _have /usr/bin/sudo && { echo sudo; return 0; }
    fi
    echo none
}

run_as_root() {
    if [ "$(id -u)" = "0" ]; then "$@"; return $?; fi
    _t=$(priv_tool)
    case "$_t" in
        doas) doas "$@" ;;
        sudo) sudo "$@" ;;
        none) log_error "No privilege helper (sudo/doas) found; cannot elevate."; return 127 ;;
    esac
}

# Credential priming — one prompt per session.
# sudo: refreshes timestamp + optional background keepalive.
# doas: opendoas has NO -v refresh; relies on 'persist' rule. We prime by one call.
OMNI_PRIME_PID=""
prime_privileges() {
    [ "$(id -u)" = "0" ] && return 0
    _t=$(priv_tool)
    case "$_t" in
        sudo)
            sudo -v || return 1
            ( while true; do sudo -n true 2>/dev/null || exit 0; sleep 240; done ) &
            OMNI_PRIME_PID=$!
            ;;
        doas)
            # No active refresh in opendoas; a single successful call arms 'persist'
            # (if the admin configured 'permit persist'). If not persisted, each
            # privileged call will prompt — that is the user's doas.conf policy.
            doas true || return 1
            ;;
        none)
            log_error "No privilege helper available for priming."
            return 127
            ;;
    esac
    return 0
}

end_privileges() {
    [ -n "$OMNI_PRIME_PID" ] && kill "$OMNI_PRIME_PID" 2>/dev/null
    OMNI_PRIME_PID=""
}
