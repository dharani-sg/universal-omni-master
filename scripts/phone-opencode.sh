#!/bin/bash
# phone-opencode.sh — Launch opencode in Termux host or Debian proot
# Usage: phone-opencode.sh [termux|proot] [project-dir]

MODE="${1:-termux}"
PROJECT_DIR="${2:-$HOME/src/universal-omni-master}"
SESSION_NAME="uom-opencode"
LOG_DIR="$HOME/uom-repair/logs"

mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/opencode-$TS.log"

case "$MODE" in
  termux)
    echo "Starting opencode in Termux host..."
    echo "Node: $(node --version 2>/dev/null || echo missing)"
    echo "opencode: $(opencode --version 2>/dev/null || echo missing)"
    cd "$PROJECT_DIR" 2>/dev/null || cd "$HOME"
    tmux new-session -d -s "$SESSION_NAME"       "cd $PROJECT_DIR && node --version && npm --version && opencode 2>&1 | tee $LOG"
    echo "Session: $SESSION_NAME"
    echo "Attach: tmux attach -t $SESSION_NAME"
    echo "Log: $LOG"
    ;;
  proot)
    echo "Starting opencode in Debian proot..."
    tmux new-session -d -s "$SESSION_NAME"       "proot-distro login debian -- bash -lc cd\ \$PROJECT_DIR\ \&\&\ node\ --version\ \&\&\ npm\ --version\ \&\&\ opencode 2>&1 | tee $LOG"
    echo "Session: $SESSION_NAME"
    echo "Attach: tmux attach -t $SESSION_NAME"
    echo "Log: $LOG"
    ;;
  *)
    echo "Usage: $0 [termux|proot] [project-dir]"
    exit 1
    ;;
esac
