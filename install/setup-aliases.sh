#!/bin/sh
# install/setup-aliases.sh — Install UOM aliases into shell profile
# Usage: sh install/setup-aliases.sh
# Works on both Alpine (laptop) and Termux (phone).
# Run after deploying the repo.

UOM_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

ALIASES=$(cat << 'EOF'

# ── UOM Project Aliases ────────────────────────────────────────────────
alias omni-project-start='sh '"${UOM_DIR}"'/bin/omni-project-start.sh'
alias omni-start='sh '"${UOM_DIR}"'/bin/omni-project-start.sh'
alias omni='sh '"${UOM_DIR}"'/bin/omni-project-start.sh status'
alias omni-menu='sh '"${UOM_DIR}"'/bin/omni-project-start.sh --menu'
alias omni-status='sh '"${UOM_DIR}"'/bin/uom-status.sh'
alias omni-detach='sh '"${UOM_DIR}"'/bin/omni-project-start.sh detach'
alias omni-aware='sh '"${UOM_DIR}"'/bin/omni-project-start.sh aware'
alias omni-test='sh '"${UOM_DIR}"'/bin/omni-project-start.sh test'
alias omni-recover='sh '"${UOM_DIR}"'/bin/omni-project-start.sh recover'
alias uom-tmux-watchdog='sh '"${UOM_DIR}"'/bin/uom-tmux-watchdog.sh'
alias uom-tunnel='sh '"${UOM_DIR}"'/bin/uom-reverse-ssh.sh'
alias uom-orch-laptop='sh '"${UOM_DIR}"'/tools/uom-orch-laptop.sh'
alias uom-orch-phone='sh '"${UOM_DIR}"'/tools/uom-orch-phone.sh'
alias uom-tmux='sh '"${UOM_DIR}"'/bin/omni-project-start.sh tmux'
alias uom-shell='tmux new-session -A -s uom'
alias uom-status='sh '"${UOM_DIR}"'/bin/omni-project-start.sh status'

# ── Tmux watchdog auto-start (interactive shell only) ──────────────────
if [ -z "${TMUX:-}" ] && [ -z "${OPENGINE_TASK:-}" ] && [ -t 0 ]; then
    # Don't auto-start inside tmux or opencode
    :
fi
EOF
)

# ── Detect profile file ────────────────────────────────────────────────
_install_profile() {
    _profile=""
    if [ -f "$HOME/.bashrc" ]; then
        _profile="$HOME/.bashrc"
    elif [ -f "$HOME/.profile" ]; then
        _profile="$HOME/.profile"
    elif [ -f "$HOME/.bash_profile" ]; then
        _profile="$HOME/.bash_profile"
    fi

    if [ -n "$_profile" ] && grep -q 'omni-project-start' "$_profile" 2>/dev/null; then
        echo "Aliases already installed in $_profile"
        return 0
    fi

    # Choose default: .bashrc for Termux (phone), .profile for Alpine (laptop)
    if echo "$HOME" | grep -q '/data/data/com.termux' 2>/dev/null; then
        _profile="$HOME/.bashrc"
    else
        _profile="$HOME/.profile"
    fi

    echo "Installing UOM aliases to $_profile..."
    printf '%s\n' "$ALIASES" >> "$_profile"
    echo "Done. Run: source $_profile"
}

_install_profile
