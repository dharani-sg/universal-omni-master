#!/usr/bin/env bash
# tools/uom-device-bundle-push.sh — push a device's local changes to laptop hub
# Called from phone side or from laptop for a remote phone
set -euo pipefail

REPO="${UOM_DIR:-$HOME/src/universal-omni-master}"
KEY="${HOME}/.ssh/id_ed25519_phone"
LAPTOP_USER="alpine"
LAPTOP_IP="192.168.40.90"
LAPTOP_PORT=22
BUNDLE_DIR="$REPO/.uom-agent/bundles"

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  echo "Usage: $0 <phone1|phone2|laptop> (from laptop; or no arg from device itself)"
  exit 1
fi

mkdir -p "$BUNDLE_DIR/outbox" "$BUNDLE_DIR/inbox"

cd "$REPO"

# Create bundle
case "$DEVICE" in
  phone1|phone2)
    # Pull from remote phone to laptop
    case "$DEVICE" in
      phone1) REMOTE_HOST="u0_a608@192.168.40.207"; REMOTE_PORT=8022 ;;
      phone2) REMOTE_HOST="u0_a217@192.168.40.157"; REMOTE_PORT=8022 ;;
    esac
    BUNDLE="/tmp/uom-${DEVICE}-$(date +%s).bundle"
    timeout 25 ssh -i "$KEY" -p "$REMOTE_PORT" -o BatchMode=yes "$REMOTE_HOST" \
      "cd $REPO 2>/dev/null && git bundle create $BUNDLE HEAD 2>/dev/null && echo OK" 2>/dev/null && \
    timeout 25 scp -i "$KEY" -P "$REMOTE_PORT" -o StrictHostKeyChecking=no \
      "$REMOTE_HOST:$BUNDLE" "$BUNDLE_DIR/inbox/$(basename $BUNDLE)" 2>/dev/null && \
    timeout 25 ssh -i "$KEY" -p "$REMOTE_PORT" -o BatchMode=yes "$REMOTE_HOST" \
      "rm -f $BUNDLE" 2>/dev/null
    RESULT="$BUNDLE_DIR/inbox/$(basename $BUNDLE)"
    if [ -f "$RESULT" ]; then
      git bundle verify "$RESULT" 2>/dev/null && {
        git fetch "$RESULT" "refs/heads/*:refs/uom/${DEVICE}/*" 2>/dev/null
        echo "OK: $DEVICE → refs/uom/${DEVICE}/*"
        rm -f "$RESULT"
      } || {
        echo "WARN: bundle verify failed for $RESULT"
      }
    else
      echo "FAIL: bundle transfer from $DEVICE"
    fi
    ;;
  laptop)
    # Create hub bundle
    BUNDLE="$BUNDLE_DIR/outbox/hub-$(date +%s).bundle"
    git bundle create "$BUNDLE" --all 2>/dev/null || git bundle create "$BUNDLE" HEAD 2>/dev/null
    echo "Hub bundle: $BUNDLE"
    ;;
  *)
    echo "Unknown device: $DEVICE"
    exit 1
    ;;
esac
