#!/data/data/com.termux/files/usr/bin/bash
# install/bootstrap-termux.sh — UOM Bootstrap for Termux/Android ARM64
# Auto-detects Android version, installs correct opencode, starts all services
# Usage: curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap-termux.sh | bash

set -euo pipefail

UOM_REPO="https://github.com/dharani-sg/universal-omni-master.git"
UOM_DIR="$HOME/src/universal-omni-master"
UOM_USER_DIR="$HOME/.uom-termux-user"

echo "=== UOM Bootstrap for Termux/Android ==="
echo "=== $(date) ==="

# ── Detect Android version ──────────────────────────────────────────────
ANDROID_SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo "0")
ANDROID_RELEASE=$(getprop ro.build.version.release 2>/dev/null || echo "unknown")
echo "[*] Android SDK: ${ANDROID_SDK} (Release: ${ANDROID_RELEASE})"

if [ "$ANDROID_SDK" -lt 24 ]; then
  echo "[!] Android 7.0+ (SDK 24+) required. Current: SDK ${ANDROID_SDK}"
  echo "    Please upgrade your Android version"
  exit 1
fi

# ── Install base dependencies ───────────────────────────────────────────
echo "[*] Installing base packages..."
pkg update -y 2>&1 | tail -1
pkg install -y tmux openssh git jq curl autossh fzf termux-elf-cleaner patchelf 2>&1 | tail -1

# Ensure sshd is running on port 8022
if ! pgrep -x sshd >/dev/null 2>&1; then
  echo "[*] Starting SSHD on port 8022..."
  sshd -p 8022 2>/dev/null || true
fi

# ── Install opencode ────────────────────────────────────────────────────
install_opencode() {
  # Strategy 1: Try Termux deb package (preferred, works on all Android)
  echo "[*] Trying Termux opencode package..."
  if pkg install -y opencode 2>/dev/null; then
    echo "[*] opencode installed via Termux package"
    return 0
  fi

  # Strategy 2: Download pre-built Termux deb from repo
  echo "[*] Trying pre-built Termux deb..."
  DEB_URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode_1.17.9_aarch64.deb"
  DEB_TMP="$HOME/opencode.deb"
  if wget -q "$DEB_URL" -O "$DEB_TMP" 2>/dev/null && [ -f "$DEB_TMP" ]; then
    if dpkg -i "$DEB_TMP" 2>/dev/null; then
      echo "[*] opencode installed from pre-built deb"
      rm -f "$DEB_TMP"
      return 0
    fi
    rm -f "$DEB_TMP"
  fi

  # Strategy 3: Build from source via Rust (slow but reliable)
  echo "[*] Building opencode from source (this may take 10-30 minutes)..."
  if command -v rustc >/dev/null 2>&1; then
    echo "[*] Cloning opencode source..."
    cd "$HOME" && rm -rf opencode-build 2>/dev/null || true
    git clone --depth 1 --branch v1.18.3 https://github.com/anomalyco/opencode.git opencode-build 2>&1 | tail -1
    cd opencode-build
    echo "[*] Running cargo build --release..."
    cargo build --release 2>&1 | tail -3
    if [ -f target/release/opencode ]; then
      mkdir -p "$HOME/bin"
      cp target/release/opencode "$HOME/bin/opencode"
      chmod +x "$HOME/bin/opencode"
      echo "[*] opencode built from source"
      cd "$HOME" && rm -rf opencode-build
      return 0
    fi
    cd "$HOME"
  fi

  # Strategy 4: Go install (v0.0.55, deprecated but works)
  echo "[!] All package methods failed. Falling back to Go install (v0.0.55)..."
  if command -v go >/dev/null 2>&1; then
    export GOPATH="$HOME/go"
    go install github.com/opencode-ai/opencode@latest 2>&1 | tail -1
    echo "[*] opencode v0.0.55 installed via Go. NOTE: free models require v1.17+"
  else
    echo "[!] Go not available. opencode will not be installed."
    echo "    Run later: pkg install golang && go install github.com/opencode-ai/opencode@latest"
  fi
}

if ! command -v opencode >/dev/null 2>&1; then
  install_opencode
else
  echo "[*] opencode already installed: $(opencode --version 2>/dev/null || opencode -v 2>/dev/null || echo 'check version')"
fi

# ── Clone/update repo ───────────────────────────────────────────────────
mkdir -p "$HOME/src"
if [ -d "$UOM_DIR/.git" ]; then
  echo "[*] Repo exists — pulling latest..."
  git -C "$UOM_DIR" stash --include-untracked 2>/dev/null || true
  git -C "$UOM_DIR" pull --ff-only 2>&1 | tail -1
  git -C "$UOM_DIR" stash pop 2>/dev/null || true
else
  echo "[*] Cloning UOM repo..."
  git clone "$UOM_REPO" "$UOM_DIR" 2>&1 | tail -1
fi

# ── SSH key generation ──────────────────────────────────────────────────
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  echo "[*] Generating ed25519 SSH key..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "uom-phone-$(date +%Y%m%d)"
  echo ""
  echo "=== ADD THIS PUBLIC KEY TO LAPTOP ==="
  echo "echo \"$(cat $HOME/.ssh/id_ed25519.pub)\" >> ~/.ssh/authorized_keys"
  echo "======================================"
  echo ""
fi

# ── SSH config ──────────────────────────────────────────────────────────
cat > "$HOME/.ssh/config" << 'SSHEOF'
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
SSHEOF
chmod 600 "$HOME/.ssh/config"

# ── tmux config ─────────────────────────────────────────────────────────
cat > "$HOME/.tmux.conf" << 'TMUXEOF'
set -g default-terminal "screen-256color"
set -g history-limit 50000
set -g mouse on
set -g status-left "[UOM] #H "
set -g status-right " %H:%M %d-%b"
set -g status-style "bg=colour235,fg=colour214"
bind u split-window -v -p 25 "watch -n5 cat $HOME/src/universal-omni-master/.uom-agent/state.json"
bind r source-file ~/.tmux.conf \; display "Reloaded"
TMUXEOF

# ── UOM user dir ───────────────────────────────────────────────────────
mkdir -p "$UOM_USER_DIR"
[ -f "$UOM_USER_DIR/state.json" ] || \
  cp "$UOM_DIR/.uom-agent/state.json" "$UOM_USER_DIR/state.json" 2>/dev/null || \
  printf '{"schema":1,"active_agent":"none","task_status":"idle"}\n' > "$UOM_USER_DIR/state.json"

# ── Shell profile ───────────────────────────────────────────────────────
PROFILE="$HOME/.bashrc"
grep -q 'go/bin' "$PROFILE" 2>/dev/null || \
  printf 'export PATH="$HOME/go/bin:$HOME/bin:$PATH"\n' >> "$PROFILE"

# ── Deploy tunnel script ────────────────────────────────────────────────
mkdir -p "$HOME/bin"
cp "$UOM_DIR/bin/uom-reverse-ssh.sh" "$HOME/bin/" 2>/dev/null || true
chmod +x "$HOME/bin/uom-reverse-ssh.sh" 2>/dev/null || true

# ── Termux:Boot auto-start (Android 12+) ────────────────────────────────
if [ "$ANDROID_SDK" -ge 31 ]; then
  BOOT_DIR="$HOME/.termux/boot"
  mkdir -p "$BOOT_DIR"
  cat > "$BOOT_DIR/start-uom.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot auto-start for UOM
# Waits for network, then starts orchestrator + tunnel
sleep 30
sshd -p 8022 2>/dev/null || true
cd ~/src/universal-omni-master
sh bin/uom-reverse-ssh.sh &
BOOTEOF
  chmod +x "$BOOT_DIR/start-uom.sh"
  echo "[*] Termux:Boot script installed (auto-start on device reboot)"
fi

# ── Start services ──────────────────────────────────────────────────────
echo "[*] Starting reverse tunnel..."
cd "$UOM_DIR"
if pgrep -f 'autossh.*-R.*18022' >/dev/null 2>&1; then
  echo "[*] Tunnel already running"
else
  nohup sh "$HOME/bin/uom-reverse-ssh.sh" > "$HOME/.uom-tunnel.log" 2>&1 &
  echo "[*] Tunnel started (PID $!)"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "=== UOM BOOTSTRAP COMPLETE ==="
echo "Android:  ${ANDROID_RELEASE} (SDK ${ANDROID_SDK})"
echo "opencode: $(opencode --version 2>/dev/null || opencode -v 2>/dev/null || echo 'check PATH')"
echo "tmux:     $(tmux -V 2>/dev/null || echo 'not found')"
echo "sshd:     port 8022 ($(pgrep -x sshd >/dev/null && echo 'running' || echo 'not running'))"
echo "tunnel:   $(pgrep -f 'autossh.*-R.*18022' >/dev/null && echo 'running' || echo 'starting...')"
echo ""
echo "=== NEXT STEPS ==="
echo "1. Add SSH public key to laptop:"
echo "   ssh-copy-id -i ~/.ssh/id_ed25519.pub alpine@192.168.40.90"
echo "2. Start tmux session:"
echo "   tmux new -s uom"
echo "3. Start orchestrator:"
echo "   cd ~/src/universal-omni-master && sh tools/uom-orch-phone.sh"
echo ""
echo "=== QUICK COMMANDS ==="
echo "  sh bin/uom-status.sh         - Check all services"
echo "  sh bin/uom-status.sh tunnel  - Check tunnel status"
