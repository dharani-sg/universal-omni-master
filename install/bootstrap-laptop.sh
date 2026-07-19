#!/bin/sh
# install/bootstrap-laptop.sh — UOM Bootstrap for Alpine Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-laptop.sh | sh
set -eu

UOM_REPO="https://github.com/dharani-sg/universal-omni-master.git"

echo "=== UOM Bootstrap for Alpine Linux ==="

# Guard: doas must be configured
command -v doas >/dev/null 2>&1 || { echo "[FATAL] doas not found or not configured. Set up /etc/doas.conf first."; exit 1; }

doas apk update
doas apk add --no-cache tmux openssh git curl jq autossh avahi nss-mdns \
  go openssl bash fish neovim

export PATH="$HOME/.opencode/bin:$HOME/go/bin:$PATH"
# Install opencode CLI (free/no-auth tier) — npm package maintained and active
# GitHub OSS repo (opencode-ai/opencode) is archived but npm/Go paths still serve
command -v opencode >/dev/null 2>&1 || npm install -g opencode-ai 2>/dev/null \
  || go install github.com/opencode-ai/opencode@latest

# Persist opencode binary path to Fish shell (survives reboot)
if command -v fish >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/fish"
  grep -q 'opencode/bin' "$HOME/.config/fish/config.fish" 2>/dev/null || \
    echo 'fish_add_path $HOME/.opencode/bin' >> "$HOME/.config/fish/config.fish"
fi

mkdir -p "$HOME/src"
if [ -d "$HOME/src/universal-omni-master/.git" ]; then
  git -C "$HOME/src/universal-omni-master" stash --include-untracked 2>/dev/null || true
  git -C "$HOME/src/universal-omni-master" pull --ff-only
  git -C "$HOME/src/universal-omni-master" stash pop 2>/dev/null || true
else
  git clone "$UOM_REPO" "$HOME/src/universal-omni-master"
fi

[ -f "$HOME/.ssh/id_ed25519" ] || \
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "uom-laptop-$(date +%Y%m%d)"

doas rc-update add sshd default
doas rc-update add avahi-daemon default
doas rc-service sshd start
doas rc-service avahi-daemon start

echo "=== Bootstrap complete. Run: cd ~/src/universal-omni-master && tmux new -s uom ==="
