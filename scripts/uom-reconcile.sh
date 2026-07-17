#!/bin/sh
exec "$(cd "$(dirname "$0")/.." && pwd)/orchestrators/uom-reconcile.sh" "$@"
