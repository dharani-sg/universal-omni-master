#!/bin/sh
# tools/uom-sync-loop.sh — Bidirectional rsync loop between phone and laptop
# Phone pushes generated/ to laptop.
# Laptop pushes verified/ and feedback/ to phone.
# Runs every 30 seconds. Detects running platform automatically.
#
# Usage: sh tools/uom-sync-loop.sh [--once]

set -u

UOM_DIR="${UOM_DIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
ONCE=0
[ "${1:-}" = "--once" ] && ONCE=1

. "${UOM_DIR}/tools/uom-state-lib.sh"
uom_state_init

LOG_DIR="${UOM_LOG_DIR}"
LOG_FILE="${LOG_DIR}/sync-loop.log"
LOCK_DIR="${UOM_RUNTIME_DIR}/sync-loop.lock"
POLL_INTERVAL=30
SSH_KEY="${HOME}/.ssh/id_ed25519_phone"
PHONE_USER="${UOM_PHONE_USER:-u0_a608}"
PHONE_PORT="${UOM_PHONE_SSH_PORT:-8022}"
LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
LAPTOP_HOST="${UOM_LAPTOP_HOST:-192.168.40.90}"

_is_phone() {
    [ "$(uname -o 2>/dev/null)" = "Android" ]
}

mkdir -p "$LOG_DIR" "$(dirname "$LOCK_DIR")"

_log() {
    _ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u)"
    printf '[sync] %s %s\n' "$_ts" "$*" >> "$LOG_FILE"
    printf '[sync] %s %s\n' "$_ts" "$*"
}

_cleanup() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    _log "stopped"
}
trap '_cleanup' INT TERM EXIT

_acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        exit 0
    fi
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || exit 1
    echo "$$" > "$LOCK_DIR/pid"
}

_phone_ip() {
    _ip_file="${UOM_STATE_DIR}/phone.ip"
    if [ -f "$_ip_file" ]; then
        cat "$_ip_file" | tr -d '[:space:]'
    elif [ -f "${UOM_STATE_DIR}/phone.host" ]; then
        cat "${UOM_STATE_DIR}/phone.host" | tr -d '[:space:]' | cut -d: -f1
    else
        echo "192.168.40.207"
    fi
}

main() {
    _acquire_lock
    _log "sync loop started (poll=${POLL_INTERVAL}s)"

    while true; do
        if _is_phone; then
            # Phone → laptop: push generated/
            _log "phone→laptop: syncing generated/"
            rsync -e "ssh -i ${SSH_KEY} -p ${LAPTOP_PORT:-22} -o ConnectTimeout=10 -o BatchMode=yes" \
                -avz --delete \
                "${UOM_STATE_DIR}/generated/" \
                "${LAPTOP_USER}@${LAPTOP_HOST}:${UOM_STATE_DIR}/generated/" \
                >> "$LOG_FILE" 2>&1 || _log "phone→laptop rsync failed"
        else
            # Laptop → phone: push verified/ and feedback/
            _pip=$(_phone_ip)
            _log "laptop→phone: syncing verified/ + feedback/"
            rsync -e "ssh -i ${SSH_KEY} -p ${PHONE_PORT} -o ConnectTimeout=10 -o BatchMode=yes" \
                -avz --delete \
                "${UOM_STATE_DIR}/verified/" \
                "${PHONE_USER}@${_pip}:${UOM_STATE_DIR}/verified/" \
                >> "$LOG_FILE" 2>&1 || _log "laptop→phone verified rsync failed"

            rsync -e "ssh -i ${SSH_KEY} -p ${PHONE_PORT} -o ConnectTimeout=10 -o BatchMode=yes" \
                -avz --delete \
                "${UOM_STATE_DIR}/feedback/" \
                "${PHONE_USER}@${_pip}:${UOM_STATE_DIR}/feedback/" \
                >> "$LOG_FILE" 2>&1 || _log "laptop→phone feedback rsync failed"
        fi

        [ "$ONCE" -eq 1 ] && break
        sleep "$POLL_INTERVAL"
    done

    _cleanup
}

main "$@"
