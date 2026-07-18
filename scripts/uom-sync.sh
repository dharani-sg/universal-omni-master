#!/bin/sh
# scripts/uom-sync.sh — Bidirectional sync of .uom-agent state between phone and laptop
# Usage: sh scripts/uom-sync.sh [push|pull|both]
#
# Phone runs: sh scripts/uom-sync.sh push  (sends generated/ to laptop)
# Laptop runs: sh scripts/uom-sync.sh pull  (receives generated/ from phone)
# Either runs: sh scripts/uom-sync.sh both  (full bidirectional sync via git)

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
PHONE_PORT="${UOM_PHONE_PORT:-8022}"
PHONE_USER="${UOM_PHONE_USER:-u0_a608}"
LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
SYNC_DIRS="generated verified feedback queue.json state.json"
REMOTE_TIMEOUT=10

# ── Dynamic IP discovery ───────────────────────────────────────────────
# Source shared discovery library if available, then use env/config fallbacks
_DISCOVER_LIB="${UOM_DIR}/tools/uom-ip-discover.sh"
if [ -f "$_DISCOVER_LIB" ]; then
    . "$_DISCOVER_LIB" 2>/dev/null || true
fi

PHONE_HOST="${UOM_PHONE_HOST:-}"
if [ -z "$PHONE_HOST" ]; then
    # Try discovery, then hint file, then env/config
    if command -v discover_phone_ip >/dev/null 2>&1; then
        PHONE_HOST="$(discover_phone_ip 2>/dev/null || echo "")"
    fi
    if [ -z "$PHONE_HOST" ] && [ -f "${UOM_DIR}/.uom-agent/phone.host" ]; then
        PHONE_HOST="$(cat "${UOM_DIR}/.uom-agent/phone.host" 2>/dev/null || echo "")"
    fi
    PHONE_HOST="${PHONE_HOST:-127.0.0.1}"
fi

LAPTOP_HOST="${UOM_LAPTOP_HOST:-}"
if [ -z "$LAPTOP_HOST" ]; then
    if command -v discover_laptop_ip >/dev/null 2>&1; then
        LAPTOP_HOST="$(discover_laptop_ip 2>/dev/null || echo "")"
    fi
    if [ -z "$LAPTOP_HOST" ] && [ -f "${UOM_DIR}/.uom-agent/laptop.ip" ]; then
        LAPTOP_HOST="$(cat "${UOM_DIR}/.uom-agent/laptop.ip" 2>/dev/null || echo "")"
    fi
    LAPTOP_HOST="${LAPTOP_HOST:-127.0.0.1}"
fi

_log() {
    _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
    printf '[sync] %s %s\n' "$_ts" "$*"
}

_is_phone() {
    # Standard Termux detection: home directory under Termux data
    if echo "$HOME" | grep -q '/data/data/com.termux' 2>/dev/null; then
        return 0
    fi
    # Fallback: uname -o returns "Android" on some Termux versions
    [ "$(uname -o 2>/dev/null)" = "Android" ] && return 0
    return 1
}

_push_to_laptop() {
    _log "Pushing state to laptop..."
    for _item in $SYNC_DIRS; do
        _src="${UOM_DIR}/.uom-agent/${_item}"
        _dst="${LAPTOP_USER}@${LAPTOP_HOST}:${UOM_DIR}/.uom-agent/"
        if [ -d "$_src" ] || [ -f "$_src" ]; then
            rsync -az --timeout="$REMOTE_TIMEOUT" \
                -e "ssh -o ConnectTimeout=$REMOTE_TIMEOUT -o StrictHostKeyChecking=accept-new" \
                "$_src" "$_dst" 2>/dev/null && \
                _log "  Pushed: ${_item}" || \
                _log "  WARN: failed to push ${_item}"
        fi
    done
}

_pull_from_laptop() {
    _log "Pulling state from laptop..."
    for _item in $SYNC_DIRS; do
        _src="${LAPTOP_USER}@${LAPTOP_HOST}:${UOM_DIR}/.uom-agent/${_item}"
        _dst="${UOM_DIR}/.uom-agent/"
        if ssh -o ConnectTimeout="$REMOTE_TIMEOUT" -o BatchMode=yes \
            "${LAPTOP_USER}@${LAPTOP_HOST}" \
            "test -e '${UOM_DIR}/.uom-agent/${_item}'" 2>/dev/null; then
            rsync -az --timeout="$REMOTE_TIMEOUT" \
                -e "ssh -o ConnectTimeout=$REMOTE_TIMEOUT -o StrictHostKeyChecking=accept-new" \
                "$_src" "$_dst" 2>/dev/null && \
                _log "  Pulled: ${_item}" || \
                _log "  WARN: failed to pull ${_item}"
        fi
    done
}

_push_to_phone() {
    _log "Pushing state to phone..."
    for _item in $SYNC_DIRS; do
        _src="${UOM_DIR}/.uom-agent/${_item}"
        _dst="${PHONE_USER}@${PHONE_HOST}:${UOM_DIR}/.uom-agent/"
        if [ -d "$_src" ] || [ -f "$_src" ]; then
            rsync -az --timeout="$REMOTE_TIMEOUT" \
                -e "ssh -o ConnectTimeout=$REMOTE_TIMEOUT -o Port=$PHONE_PORT -o StrictHostKeyChecking=accept-new" \
                "$_src" "$_dst" 2>/dev/null && \
                _log "  Pushed: ${_item}" || \
                _log "  WARN: failed to push ${_item}"
        fi
    done
}

_pull_from_phone() {
    _log "Pulling state from phone..."
    for _item in $SYNC_DIRS; do
        _src="${PHONE_USER}@${PHONE_HOST}:${UOM_DIR}/.uom-agent/${_item}"
        _dst="${UOM_DIR}/.uom-agent/"
        if ssh -o ConnectTimeout="$REMOTE_TIMEOUT" -o Port="$PHONE_PORT" -o BatchMode=yes \
            "${PHONE_USER}@${PHONE_HOST}" \
            "test -e '${UOM_DIR}/.uom-agent/${_item}'" 2>/dev/null; then
            rsync -az --timeout="$REMOTE_TIMEOUT" \
                -e "ssh -o ConnectTimeout=$REMOTE_TIMEOUT -o Port=$PHONE_PORT -o StrictHostKeyChecking=accept-new" \
                "$_src" "$_dst" 2>/dev/null && \
                _log "  Pulled: ${_item}" || \
                _log "  WARN: failed to pull ${_item}"
        fi
    done
}

case "${1:-both}" in
    push)
        if _is_phone; then
            _push_to_laptop
        else
            _push_to_phone
        fi
        ;;
    pull)
        if _is_phone; then
            _pull_from_laptop
        else
            _pull_from_phone
        fi
        ;;
    both)
        if _is_phone; then
            _push_to_laptop
            _pull_from_laptop
        else
            _push_to_phone
            _pull_from_phone
        fi
        ;;
    *)
        printf 'Usage: sh %s [push|pull|both]\n' "$0"
        exit 1
        ;;
esac

_log "Sync complete"
