#!/usr/bin/env bash
# tools/uom-device-bundle-pull.sh — pull latest hub bundle into device's repo
# Called on phone side to fetch laptop's latest state
set -euo pipefail

REPO="${UOM_DIR:-$HOME/src/universal-omni-master}"
BUNDLE_DIR="$REPO/.uom-agent/bundles"

mkdir -p "$BUNDLE_DIR/inbox"

# Find latest hub bundle in inbox
LATEST=$(ls -t "$BUNDLE_DIR/inbox/"hub-*.bundle 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
  echo "No hub bundles pending in $BUNDLE_DIR/inbox/"
  exit 0
fi

cd "$REPO"

echo "Verifying bundle: $LATEST"
if git bundle verify "$LATEST" 2>/dev/null; then
  echo "Fetching..."
  git fetch "$LATEST" "refs/heads/*:refs/uom/hub/*" 2>/dev/null && \
    echo "OK: fetched into refs/uom/hub/*" || \
    echo "WARN: no new refs fetched"
  rm -f "$LATEST"
else
  echo "FAIL: bundle verify failed"
  exit 1
fi
