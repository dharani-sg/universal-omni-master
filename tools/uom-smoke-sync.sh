#!/bin/sh
# 3-node sync loop: laptop ↔ phone ↔ guest
# Uses direct SSH (not uom-ssh-phone.sh) to preserve stdin in pipes.
set -u

LAPTOP_SMOKE="$1"
GUEST_SMOKE="$2"
POLL="${3:-5}"

PHONE_IP="192.168.40.207"
PHONE_PORT=8022
PHONE_USER="u0_a608"
PHONE_KEY="${HOME}/.ssh/id_ed25519_phone"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i ${PHONE_KEY} -p ${PHONE_PORT}"

cd "$(dirname "$0")/.." 2>/dev/null || exit 1

_safe_sleep() { sleep "$1" & wait $! 2>/dev/null; }

# Cache phone IP via wrapper once (side effect: warms connection)
bin/uom-ssh-phone.sh 'echo UOM_SYNC_START' >/dev/null 2>&1

_cycle=0
while true; do
  _cycle=$((_cycle + 1))

  # 1. Push generated/ from laptop → guest (via phone relay)
  #    tar on laptop → pipe → phone (direct SSH) → pipe → guest (inner SSH)
  tar czf - -C "${LAPTOP_SMOKE}" generated/ 2>/dev/null \
    | ssh ${SSH_OPTS} "${PHONE_USER}@${PHONE_IP}" \
      "ssh -p 2222 -o StrictHostKeyChecking=accept-new -o BatchMode=yes uom@127.0.0.1 'cd ~/src/universal-omni-master && tar xzf - -C ${GUEST_SMOKE}'" \
      2>/dev/null || true

  # 2. Pull verified/ from guest → laptop (via phone relay)
  ssh ${SSH_OPTS} "${PHONE_USER}@${PHONE_IP}" \
    "ssh -p 2222 -o StrictHostKeyChecking=accept-new -o BatchMode=yes uom@127.0.0.1 'cd ~/src/universal-omni-master && tar czf - -C ${GUEST_SMOKE} verified/'" \
    2>/dev/null \
    | tar xzf - -C "${LAPTOP_SMOKE}" 2>/dev/null || true

  # 3. Pull feedback/ from guest → laptop
  ssh ${SSH_OPTS} "${PHONE_USER}@${PHONE_IP}" \
    "ssh -p 2222 -o StrictHostKeyChecking=accept-new -o BatchMode=yes uom@127.0.0.1 'cd ~/src/universal-omni-master && tar czf - -C ${GUEST_SMOKE} feedback/ 2>/dev/null'" \
    2>/dev/null \
    | tar xzf - -C "${LAPTOP_SMOKE}" 2>/dev/null || true

  # NOTE: queue.json is NOT synced between nodes.
  # Generator (laptop) and verifier (guest) each manage their own local copy.
  # Both start with identical initial queue contents from sandbox setup.

  if [ $((_cycle % 6)) -eq 0 ]; then
    _ts=$(date -u '+%H:%M:%S')
    _gcnt=$(ls "${LAPTOP_SMOKE}/generated/" 2>/dev/null | wc -l)
    _vcnt=$(ls "${LAPTOP_SMOKE}/verified/" 2>/dev/null | wc -l)
    echo "[sync] ${_ts} cycle=${_cycle} gen=${_gcnt} ver=${_vcnt}"
  fi

  _safe_sleep "$POLL"
done
