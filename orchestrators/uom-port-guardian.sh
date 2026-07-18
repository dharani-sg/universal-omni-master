#!/bin/sh
# bin/uom-port-guardian.sh — Thin wrapper to orchestrators/uom-port-guardian.sh
exec "$(cd "$(dirname "$0")/.." && pwd)/orchestrators/uom-port-guardian.sh" "$@"
