#!/bin/sh
# diag/session.sh — user session / PipeWire / compositor checks.

audit_audio_session() {
    audit_section "SESSION / AUDIO"

    if [ -n "${OMNI_SYSROOT:-}" ]; then
        audit_emit info session "fixture mode: session checks skipped"
        return 0
    fi

    if [ "$(id -u)" = "0" ]; then
        audit_emit info session "running as root; user-session checks skipped"
        return 0
    fi

    [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] \
        && audit_emit ok session "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
        || audit_emit warn session "XDG_RUNTIME_DIR missing"

    pgrep -x pipewire >/dev/null 2>&1 \
        && audit_emit ok session "pipewire running" \
        || audit_emit warn session "pipewire not running"

    pgrep -x wireplumber >/dev/null 2>&1 \
        && audit_emit ok session "wireplumber running" \
        || audit_emit info session "wireplumber not running"

    pgrep -x niri >/dev/null 2>&1 \
        && audit_emit ok session "niri compositor running" \
        || audit_emit info session "niri not running"

    pgrep -x noctalia >/dev/null 2>&1 \
        && audit_emit ok session "noctalia running" \
        || audit_emit info session "noctalia not running"
}
