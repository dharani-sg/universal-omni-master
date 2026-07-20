#!/usr/bin/env bash
# orchestrators/uom-git-sync.sh — triple-device hub-and-spoke git bundle sync
# NO git push to origin. Hub is laptop. Phones bundle→laptop. Laptop bundles→phones.
# Supports dual-network: LAN (192.168.40.x) + reverse tunnels (127.0.0.1:3141x)
set -euo pipefail

REPO="${UOM_DIR:-$HOME/src/universal-omni-master}"
BUNDLE_DIR="$REPO/.uom-agent/bundles"
KEY="${HOME}/.ssh/id_ed25519_phone"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# Phone SSH helper: try LAN first, then reverse tunnel
# Returns 0 on success, 1 on failure
phone_ssh() {
  local label="$1"; shift
  local ssh_base=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no)
  local LAN_HOST LAN_PORT TUN_PORT TUN_USER
  case "$label" in
    phone1) LAN_HOST="u0_a608@192.168.40.207"; LAN_PORT=8022; TUN_PORT=31415; TUN_USER="u0_a608" ;;
    phone2) LAN_HOST="u0_a217@192.168.40.157"; LAN_PORT=8022; TUN_PORT=31416; TUN_USER="u0_a217" ;;
    *) return 1 ;;
  esac
  # Try LAN
  if timeout 7 ssh "${ssh_base[@]}" -p "$LAN_PORT" "$LAN_HOST" "$@" 2>/dev/null; then
    return 0
  fi
  # Try reverse tunnel
  if timeout 7 ssh "${ssh_base[@]}" -p "$TUN_PORT" "${TUN_USER}@127.0.0.1" "$@" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Phone SCP helper: try LAN first, then reverse tunnel
phone_scp() {
  local label="$1" src="$2" dst="$3"
  local scp_base=(-i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5)
  local LAN_HOST LAN_PORT TUN_PORT TUN_USER
  case "$label" in
    phone1) LAN_HOST="u0_a608@192.168.40.207"; LAN_PORT=8022; TUN_PORT=31415; TUN_USER="u0_a608" ;;
    phone2) LAN_HOST="u0_a217@192.168.40.157"; LAN_PORT=8022; TUN_PORT=31416; TUN_USER="u0_a217" ;;
    *) return 1 ;;
  esac
  # Try LAN
  if timeout 10 scp "${scp_base[@]}" -P "$LAN_PORT" "$src" "${LAN_HOST}:${dst}" 2>/dev/null; then
    return 0
  fi
  # Try reverse tunnel
  if timeout 10 scp "${scp_base[@]}" -P "$TUN_PORT" "$src" "${TUN_USER}@127.0.0.1:${dst}" 2>/dev/null; then
    return 0
  fi
  return 1
}

mkdir -p "$BUNDLE_DIR/inbox" "$BUNDLE_DIR/outbox"

case "${1:-status}" in
  status)
    log "=== TRIPLE GIT SYNC STATUS ==="
    cd "$REPO"
    log "--- Laptop ---"
    log "  branch: $(git branch --show-current 2>/dev/null || echo 'detached')"
    log "  HEAD:   $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    log "  dirty:  $(git diff --quiet 2>/dev/null && echo 'no' || echo 'yes')"

    for device in phone1 phone2; do
      log "--- $device ---"
      SHA=$(phone_ssh "$device" "cd $REPO 2>/dev/null && git rev-parse --short HEAD 2>/dev/null" 2>/dev/null || echo 'ssh-fail')
      BRANCH=$(phone_ssh "$device" "cd $REPO 2>/dev/null && git branch --show-current 2>/dev/null" 2>/dev/null || echo 'ssh-fail')
      log "  branch: $BRANCH"
      log "  HEAD:   $SHA"
    done

    BUNDLES=$(ls "$BUNDLE_DIR/inbox/"*.bundle 2>/dev/null | wc -l)
    log "  bundles pending: $BUNDLES"
    ;;

  create-hub-bundle)
    cd "$REPO"
    BUNDLE="$BUNDLE_DIR/outbox/hub-$(date +%s).bundle"
    git bundle create "$BUNDLE" --all 2>/dev/null || \
      git bundle create "$BUNDLE" HEAD 2>/dev/null || {
        log "WARN: bundle create failed"
        exit 1
      }
    log "Hub bundle created: $BUNDLE ($(du -h "$BUNDLE" | cut -f1))"
    echo "$BUNDLE"
    ;;

  push-to-phones)
    cd "$REPO"
    BUNDLE="$BUNDLE_DIR/outbox/hub-$(date +%s).bundle"
    git bundle create "$BUNDLE" --all 2>/dev/null || \
      git bundle create "$BUNDLE" HEAD 2>/dev/null || {
        log "WARN: bundle create failed"
        exit 1
      }
    for device in phone1 phone2; do
      log "Pushing bundle to $device..."
      phone_scp "$device" "$BUNDLE" "/tmp/uom-hub-bundle.bundle" 2>/dev/null && \
      phone_ssh "$device" \
        "cd $REPO 2>/dev/null && git fetch /tmp/uom-hub-bundle.bundle 'refs/*:refs/uom/hub/*' 2>/dev/null && rm -f /tmp/uom-hub-bundle.bundle && echo FETCHED" \
        2>/dev/null && log "  $device: OK" || log "  $device: FAILED"
    done
    rm -f "$BUNDLE"
    ;;

  pull-device)
    DEVICE="${2:-}"
    if [ -z "$DEVICE" ]; then
      log "Usage: $0 pull-device <phone1|phone2>"
      exit 1
    fi
    case "$DEVICE" in
      phone1|phone2) ;;
      *) log "Unknown device: $DEVICE"; exit 1 ;;
    esac
    log "Pulling bundle from $DEVICE..."
    BUNDLE="$BUNDLE_DIR/inbox/${DEVICE}-$(date +%s).bundle"
    phone_ssh "$DEVICE" \
      "cd $REPO 2>/dev/null && git bundle create /tmp/uom-${DEVICE}.bundle HEAD 2>/dev/null && echo BUNDLE_OK" \
      2>/dev/null && \
    phone_scp "$DEVICE" "/tmp/uom-${DEVICE}.bundle" "$BUNDLE" 2>/dev/null && \
    phone_ssh "$DEVICE" "rm -f /tmp/uom-${DEVICE}.bundle" 2>/dev/null
    if [ -f "$BUNDLE" ]; then
      git bundle verify "$BUNDLE" 2>/dev/null && {
        cd "$REPO"
        git fetch "$BUNDLE" "refs/heads/*:refs/uom/${DEVICE}/*" 2>/dev/null && \
          log "$DEVICE: fetch OK → refs/uom/${DEVICE}/*" || \
          log "$DEVICE: fetch returned no new refs"
        rm -f "$BUNDLE"
      } || {
        log "$DEVICE: bundle verify failed"
        rm -f "$BUNDLE"
      }
    else
      log "$DEVICE: bundle transfer failed"
    fi
    ;;

  sync-status)
    cd "$REPO"
    STATUS_FILE="$REPO/.uom-agent/sync-status.json"
    LAPTOP_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    LAPTOP_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

    P1_SHA=$(phone_ssh phone1 "cd $REPO 2>/dev/null && git rev-parse HEAD 2>/dev/null" 2>/dev/null || echo 'unreachable')
    P2_SHA=$(phone_ssh phone2 "cd $REPO 2>/dev/null && git rev-parse HEAD 2>/dev/null" 2>/dev/null || echo 'unreachable')

    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg laptop_sha "$LAPTOP_SHA" \
      --arg laptop_branch "$LAPTOP_BRANCH" \
      --arg phone1_sha "$P1_SHA" \
      --arg phone2_sha "$P2_SHA" \
      "{timestamp:\$ts,laptop:{sha:\$laptop_sha,branch:\$laptop_branch},phone1:{sha:\$phone1_sha},phone2:{sha:\$phone2_sha}}" \
      > "$STATUS_FILE" 2>/dev/null
    log "Sync status written to $STATUS_FILE"
    cat "$STATUS_FILE"
    ;;

  *)
    echo "Usage: $0 <status|create-hub-bundle|push-to-phones|pull-device <device>|sync-status>"
    exit 1
    ;;
esac
