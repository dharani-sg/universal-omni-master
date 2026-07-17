#!/bin/sh
# install/bootstrap-laptop.sh — UOM Bootstrap for Alpine Linux
# Usage: curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-laptop.sh | sh
set -eu

UOM_REPO="https://github.com/dharani-sg/universal-omni-master.git"

echo "=== UOM Bootstrap for Alpine Linux ==="

doas apk update
doas apk add --no-cache tmux openssh git curl jq autossh avahi nss-mdns \
  go openssl bash fish neovim

export PATH="$HOME/go/bin:$PATH"
command -v opencode >/dev/null 2>&1 || go install github.com/opencode-ai/opencode@latest

mkdir -p "$HOME/src"
if [ -d "$HOME/src/universal-omni-master/.git" ]; then
  git -C "$HOME/src/universal-omni-master" pull --ff-only
else
  git clone "$UOM_REPO" "$HOME/src/universal-omni-master"
fi

[ -f "$HOME/.ssh/id_ed25519" ] || \
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "uom-laptop-$(date +%Y%m%d)"

doas rc-update add sshd default
doas rc-update add avahi-daemon default
doas rc-service sshd start
doas rc-service avahi-daemon start

cd "$HOME/src/universal-omni-master"
[ -x install/setup-laptop.sh ] && sh install/setup-laptop.sh || true

echo "=== Bootstrap complete. Run: cd ~/src/universal-omni-master && tmux new -s uom ==="
