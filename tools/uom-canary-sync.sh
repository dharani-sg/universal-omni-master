#!/bin/sh
# DEPRECATED — superseded by tools/uom-smoke-sync.sh (3-node, no queue.json sync).
# Kept for historical reference: original 2-node bidirectional sync with queue sync.
# Minimal sync loop for phone↔laptop canary
set -u

PHONE_SSH="bin/uom-ssh-phone.sh"
POLL="${3:-5}"

cd "$(dirname "$0")/.." 2>/dev/null || exit 1

_safe_sleep() { sleep "$1" & wait $! 2>/dev/null; }

_cycle=0
while true; do
  _cycle=$((_cycle + 1))

  # 1. Pull generated/ from phone → laptop
  $PHONE_SSH "tar czf - -C ${1} generated/ 2>/dev/null" 2>/dev/null \
    | tar xzf - -C "${2}" 2>/dev/null || true

  # 2. Push verified/ from laptop → phone
  tar czf - -C "${2}" verified/ 2>/dev/null \
    | $PHONE_SSH "tar xzf - -C ${1}" 2>/dev/null || true

  # 3. Push feedback/ from laptop → phone
  tar czf - -C "${2}" feedback/ 2>/dev/null \
    | $PHONE_SSH "tar xzf - -C ${1}" 2>/dev/null || true

  # 4. Sync queue.json: phone → laptop (generator writes)
  $PHONE_SSH "cat ${1}/queue.json" 2>/dev/null > "${2}/queue.json" 2>/dev/null || true

  # 5. Sync queue.json: laptop → phone (verifier updates status)
  if [ -f "${2}/queue.json" ]; then
    $PHONE_SSH "cat > ${1}/queue.json" < "${2}/queue.json" 2>/dev/null || true
  fi

  if [ $((_cycle % 6)) -eq 0 ]; then
    _ts=$(date -u '+%H:%M:%S')
    echo "[sync] ${_ts} cycle ${_cycle}"
  fi

  _safe_sleep "$POLL"
done
