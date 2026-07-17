#!/data/data/com.termux.boot/files/usr/bin/bash
# install/bootstrap-termux.sh — UOM Bootstrap for Termux/Android ARM64
# Usage: curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-termux.sh | bash
set -euo pipefail

UOM_REPO="https://github.com/dharani-sg/universal-omni-master.git"
UOM_DIR="$HOME/src/universal-omni-master"
UOM_USER_DIR="$HOME/.uom-termux-user"
GOPATH="$HOME/go"

echo "=== UOM Bootstrap for Termux/Android ARM64 ==="
echo "=== $(date) ==="

pkg update -y
pkg install -y tmux openssh git golang curl jq autossh mosh

export GOPATH="$GOPATH"
export PATH="$GOPATH/bin:$PATH"

if ! command -v opencode >/dev/null 2>&1; then
  echo "[*] Building opencode from source (Go)..."
  go install github.com/opencode-ai/opencode@latest
fi

mkdir -p "$HOME/src"
if [ -d "$UOM_DIR/.git" ]; then
  echo "[*] Repo exists — pulling latest..."
  git -C "$UOM_DIR" stash --include-untracked 2>/dev/null || true
  git -C "$UOM_DIR" pull --ff-only
  git -C "$UOM_DIR" stash pop 2>/dev/null || true
else
  echo "[*] Cloning UOM repo..."
  git clone "$UOM_REPO" "$UOM_DIR"
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  echo "[*] Generating ed25519 SSH key..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "uom-phone-$(date +%Y%m%d)"
  echo "PUBLIC KEY (add to laptop ~/.ssh/authorized_keys):"
  cat "$HOME/.ssh/id_ed25519.pub"
fi

cat > "$HOME/.ssh/config" << 'EOF'
Host uom-laptop-rev
  HostName 127.0.0.1
  Port 18022
  User alpine
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 30
  ServerAliveCountMax 3
  StrictHostKeyChecking no

Host uom-laptop-lan
  HostName 192.168.40.90
  Port 22
  User alpine
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 30

Host uom-laptop-mdns
  HostName hp-pavilion.local
  Port 22
  User alpine
  IdentityFile ~/.ssh/id_ed25519
EOF
chmod 600 "$HOME/.ssh/config"

cat > "$HOME/.tmux.conf" << 'EOF'
set -g default-terminal "screen-256color"
set -g history-limit 50000
set -g mouse on
set -g status-left "[UOM] #H "
set -g status-right " %H:%M %d-%b"
set -g status-style "bg=colour235,fg=colour214"
bind u split-window -v -p 25 "watch -n5 cat $HOME/src/universal-omni-master/.uom-agent/state.json"
bind r source-file ~/.tmux.conf \; display "Reloaded"
EOF

mkdir -p "$UOM_USER_DIR"
[ -f "$UOM_USER_DIR/state.json" ] || \
  cp "$UOM_DIR/.uom-agent/state.json" "$UOM_USER_DIR/state.json" 2>/dev/null || \
  echo '{"schema":1,"active_agent":"none","task_status":"idle"}' > "$UOM_USER_DIR/state.json"

PROFILE="$HOME/.bashrc"
grep -q 'go/bin' "$PROFILE" 2>/dev/null || \
  echo 'export PATH="$HOME/go/bin:$HOME/bin:$PATH"' >> "$PROFILE"

mkdir -p "$HOME/bin"
cp "$UOM_DIR/bin/uom-reverse-ssh.sh" "$HOME/bin/" 2>/dev/null || true
echo "[*] Starting reverse tunnel (non-fatal if laptop offline)..."
bash "$HOME/bin/uom-reverse-ssh.sh" 2>/dev/null || echo "[!] Tunnel deferred — start laptop first"

echo ""
echo "=== UOM BOOTSTRAP COMPLETE ==="
echo "opencode: $(command -v opencode && opencode --version 2>/dev/null || echo 'built, check PATH')"
echo "tmux:     $(tmux -V)"
echo "ssh key:  $(cat $HOME/.ssh/id_ed25519.pub | cut -d' ' -f1-2)"
echo ""
echo "NEXT: Run 'tmux new -s uom' then 'cd ~/src/universal-omni-master && opencode'"
