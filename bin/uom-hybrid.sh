#!/bin/sh
exec "$(cd "$(dirname "$0")/.." && pwd)/orchestrators/uom-hybrid.sh" "$@"
