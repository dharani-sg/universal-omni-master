#!/bin/sh
# scripts/uom-sync.sh — Bidirectional sync of .uom-agent state between phone and laptop
# Usage: sh scripts/uom-sync.sh [push|pull|both]
#
# Phone runs: sh scripts/uom-sync.sh push  (sends generated/ to laptop)
# Laptop runs: sh scripts/uom-sync.sh pull  (receives generated/ from phone)
# Either runs: sh scripts/uom-sync.sh both  (full bidirectional sync via git)

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
PHONE_HOST="${UOM_PHONE_HOST:-192.168.40.207}"
PHONE_PORT="${UOM_PHONE_PORT:-8022}"
PHONE_USER="${UOM_PHONE_USER:-u0_a608}"
LAPTOP_HOST="${UOM_LAPTOP_HOST:-192.168.40.90}"
LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
SYNC_DIRS="generated verified feedback queue.json state.json"
REMOTE_TIMEOUT=10

_log() {
    _ts=$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date)
    printf '[sync] %s %s\n' "$_ts" "$*"
}

_is_phone() {
    [ "$(hostname)" != "alpine" ] && return 0 || return 1
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
