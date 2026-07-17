#!/bin/sh
exec "$(cd "$(dirname "$0")/.." && pwd)/orchestrators/uom-tmux-watchdog.sh" "$@"
