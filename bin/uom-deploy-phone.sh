#!/bin/sh
# bin/uom-deploy-phone.sh — Deploy UOM configs + aliases to phone
# Updates phone-side .bashrc, ~/bin/ scripts, and Termux:Boot.
# Usage: sh bin/uom-deploy-phone.sh [--dry-run]
# Run from laptop; expects SSH access to phone.

set -u

UOM_DIR="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
DRY_RUN=false

_log() { printf '[deploy] %s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    _log "DRY RUN — no changes will be made"
fi

# ── Discover phone target ──────────────────────────────────────────────
if ssh -F ~/.ssh/config -o ConnectTimeout=3 -o BatchMode=yes uom-phone-rev true 2>/dev/null; then
    PHONE_SSH="ssh -F ~/.ssh/config uom-phone-rev"
    _log "Phone reachable via reverse tunnel"
elif ssh -F ~/.ssh/config -o ConnectTimeout=5 -o BatchMode=yes uom-phone-lan true 2>/dev/null; then
    PHONE_SSH="ssh -F ~/.ssh/config uom-phone-lan"
    _log "Phone reachable via LAN"
else
    _log "ERROR: Phone not reachable"
    _log "Try: ssh u0_a608@192.168.40.207 -p 8022"
    exit 1
fi

# ── 1. Create ~/bin/ scripts on phone ──────────────────────────────────
_log "=== Deploying ~/bin/ scripts ==="

for _script in omni-project-start.sh uom-tmux-watchdog.sh uom-status.sh uom-reverse-ssh.sh uom-ssh-phone.sh; do
    if [ -f "${UOM_DIR}/bin/${_script}" ]; then
        $DRY_RUN || $PHONE_SSH "mkdir -p ~/bin"
        _log "  Copying ${_script} to phone ~/bin/"
        $DRY_RUN || scp -F ~/.ssh/config "${UOM_DIR}/bin/${_script}" uom-phone-rev:~/bin/ 2>/dev/null
        $DRY_RUN || $PHONE_SSH "chmod +x ~/bin/${_script}"
    fi
done

# ── 1b. Create ~/bin/ scripts from tools/ and scripts/ ────────────────
_log "=== Deploying tools/ and scripts/ ==="

for _script in uom-model-rotate.sh uom-state-lib.sh; do
    if [ -f "${UOM_DIR}/tools/${_script}" ]; then
        $DRY_RUN || scp -F ~/.ssh/config "${UOM_DIR}/tools/${_script}" "uom-phone-rev:~/bin/" 2>/dev/null && \
            _log "  Synced tools/${_script}"
    fi
done

for _script in uom-qemu-watchdog.sh uom-lib.sh uom-dryrun.sh; do
    if [ -f "${UOM_DIR}/scripts/${_script}" ]; then
        $DRY_RUN || scp -F ~/.ssh/config "${UOM_DIR}/scripts/${_script}" "uom-phone-rev:~/bin/" 2>/dev/null && \
            _log "  Synced scripts/${_script}"
    fi
done

# ── 2. Update .bashrc with aliases ──────────────────────────────────────
_log "=== Updating phone .bashrc ==="

$DRY_RUN || $PHONE_SSH 'grep -q "omni-project-start" ~/.bashrc 2>/dev/null || {
    cat >> ~/.bashrc << '\''EOF'\''

# ── UOM Project Start Menu ─────────────────────────────────────────────
alias omni-project-start="sh ~/bin/omni-project-start.sh"
alias omni-start="sh ~/bin/omni-project-start.sh"
alias omni="sh ~/bin/omni-project-start.sh status"
alias omni-menu="sh ~/bin/omni-project-start.sh --menu"
alias omni-status="sh ~/src/universal-omni-master/bin/uom-status.sh"
alias omni-detach="sh ~/bin/omni-project-start.sh detach"
alias omni-aware="sh ~/bin/omni-project-start.sh aware"
alias omni-test="sh ~/bin/omni-project-start.sh test"
alias omni-recover="sh ~/bin/omni-project-start.sh recover"
alias uom-tmux-watchdog="sh ~/bin/uom-tmux-watchdog.sh"
alias uom-tunnel="sh ~/bin/uom-reverse-ssh.sh"
alias uom-orch-phone="sh ~/src/universal-omni-master/tools/uom-orch-phone.sh"
alias uom-tmux="sh ~/bin/omni-project-start.sh tmux"
alias uom-shell="tmux new-session -A -s uom"
alias uom-status="sh ~/bin/omni-project-start.sh status"
EOF
    echo "aliases appended"
}'
_log "Phone .bashrc aliases deployed"

# ── 3. Update Termux:Boot script ───────────────────────────────────────
_log "=== Updating Termux:Boot ==="

$DRY_RUN || $PHONE_SSH 'mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-uom.sh << '\''EOF'\''
#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot auto-start for UOM
# Starts SSH, tunnel, tmux watchdog, and orchestrator on device boot
sleep 30

# Start SSH on port 8022
sshd -p 8022 2>/dev/null || true

# Wait for network
for i in 1 2 3 4 5; do
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && break
    sleep 5
done

# Source aliases
[ -f ~/.bashrc ] && . ~/.bashrc

# Start reverse tunnel
nohup sh ~/bin/uom-reverse-ssh.sh > ~/.uom-termux-user/tunnel.log 2>&1 &

# Start tmux watchdog (background)
nohup sh ~/bin/uom-tmux-watchdog.sh --daemon > ~/.uom-termux-user/tmux-watchdog.log 2>&1 &

# Start phone orchestrator
nohup sh ~/src/universal-omni-master/tools/uom-orch-phone.sh > ~/.uom-termux-user/phone-orch.log 2>&1 &
EOF
chmod +x ~/.termux/boot/start-uom.sh
echo "Termux:Boot updated"'
_log "Termux:Boot script deployed"

# ── 4. Copy other necessary scripts ───────────────────────────────────
_log "=== Syncing bin/ scripts ==="

for _s in uom-reverse-ssh.sh uom-status.sh omni-project-start.sh uom-tmux-watchdog.sh; do
    $DRY_RUN || scp -F ~/.ssh/config "${UOM_DIR}/bin/${_s}" "uom-phone-rev:~/bin/" 2>/dev/null && \
        _log "  Synced ${_s}"
done

$DRY_RUN || $PHONE_SSH "chmod +x ~/bin/*.sh 2>/dev/null || true"

# ── Summary ────────────────────────────────────────────────────────────
_log ""
_log "=== DEPLOYMENT COMPLETE ==="
_log ""
_log "Aliases added to phone ~/.bashrc:"
_log "  omni-project-start   — Interactive start menu (default)"
_log "  omni-start            — Same"
_log "  omni                  — Quick status"
_log "  omni-menu             — Menu mode"
_log "  omni-status           — Detailed status"
_log "  omni-detach           — Force phone takeover"
_log "  omni-aware            — Situation awareness"
_log "  omni-test             — Connectivity tests"
_log "  omni-recover          — Recover stuck tasks"
_log "  uom-tmux-watchdog     — Tmux session monitor"
_log "  uom-tunnel            — Start reverse tunnel"
_log "  uom-orch-phone        — Start phone orchestrator"
_log "  uom-tmux              — Start project tmux session"
_log "  uom-shell             — Tmux session (simple)"
_log ""
_log "Termux:Boot auto-starts: SSH, tunnel, tmux watchdog, orchestrator"
_log ""
_log "Run 'source ~/.bashrc' on phone to activate aliases"
_log ""
_log "Deployed to phone ~/bin/:"
_log "  bin/: omni-project-start.sh, uom-tmux-watchdog.sh, uom-status.sh, uom-reverse-ssh.sh, uom-ssh-phone.sh"
_log "  tools/: uom-model-rotate.sh, uom-state-lib.sh"
_log "  scripts/: uom-qemu-watchdog.sh, uom-lib.sh, uom-dryrun.sh"
