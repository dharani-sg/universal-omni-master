#!/bin/sh
# install/bootstrap.sh — Universal bootstrap: auto-detects platform
# curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash

set -eu
BASE="https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install"

if [ -d "/data/data/com.termux" ] || echo "${PREFIX:-}" | grep -q termux 2>/dev/null; then
  echo "[UOM] Detected: Termux/Android"
  curl -fsSL "$BASE/bootstrap-termux.sh" | bash
elif [ -f "/etc/alpine-release" ]; then
  echo "[UOM] Detected: Alpine Linux"
  curl -fsSL "$BASE/bootstrap-laptop.sh" | sh
else
  echo "[UOM] Unknown platform. Supported: Termux (Android), Alpine Linux"
  echo "Manual: https://github.com/dharani-sg/universal-omni-master"
  exit 1
fi
