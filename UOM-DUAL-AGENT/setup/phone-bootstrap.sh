#!/data/data/com.termux/files/usr/bin/sh
# phone-bootstrap.sh — UOM Dual-Agent phone-side Phase 1 setup (Termux)
# Xiaomi Mi 8 / CrDroid Android 15 / Termux
# Safe to re-run (idempotent).

set -u

LAPTOP_USER="${UOM_LAPTOP_USER:-alpine}"
REV_PORT="${UOM_REV_PORT:-31415}"
PHONE_SSHD_PORT=8022
REPO_URL="${UOM_REPO_URL:-https://github.com/dharani-sg/universal-omni-master.git}"
# Laptop public key (for reverse/direct SSH into Termux)
LAPTOP_PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM7cmwR2AYi2z5ZcF6VeDNKg+dXrVy1iYwoNlcT2vmah alpine-laptop-to-phone'

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
export HOME="$HOME_DIR"
export PATH="$PREFIX/bin:$PATH"

_log() { printf '[PHONE-BOOT] %s\n' "$*"; }
_die() { _log "FATAL: $*"; exit 1; }

# ── Dynamic laptop IP discovery ──────────────────────────────────────────
# Try multiple methods instead of hardcoding
_discover_laptop_ip() {
    # Method 1: mDNS (if avahi is available)
    if command -v avahi-resolve >/dev/null 2>&1; then
        _ip=$(avahi-resolve -n hp-pavilion.local 2>/dev/null | awk '{print $2}' | head -1)
        [ -n "$_ip" ] && [ "$_ip" != "0.0.0.0" ] && echo "$_ip" && return 0
    fi

    # Method 2: check if gateway is the laptop (hotspot mode)
    _gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    if [ -n "$_gw" ]; then
        # Try common laptop IPs in hotspot subnet
        _gw_base=$(echo "$_gw" | sed 's/\.[0-9]*$//')
        for _suffix in 100 101 102 103 104 105 106 107 108 109 110; do
            _cand="${_gw_base}.${_suffix}"
            if ping -c 1 -W 1 "$_cand" >/dev/null 2>&1; then
                if nc -z -w 2 "$_cand" 22 2>/dev/null; then
                    echo "$_cand"; return 0
                fi
            fi
        done
    fi

    # Method 3: last known from env or file
    if [ -n "${UOM_LAPTOP_IP:-}" ]; then
        echo "$UOM_LAPTOP_IP"; return 0
    fi
    if [ -f "$HOME_DIR/.uom-agent/laptop.ip" ]; then
        cat "$HOME_DIR/.uom-agent/laptop.ip" 2>/dev/null && return 0
    fi
    if [ -f "$HOME_DIR/src/universal-omni-master/.uom-agent/laptop.ip" ]; then
        cat "$HOME_DIR/src/universal-omni-master/.uom-agent/laptop.ip" 2>/dev/null && return 0
    fi

    # Method 4: same-subnet scan for port 22
    _my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
    if [ -n "$_my_ip" ] && command -v nmap >/dev/null 2>&1; then
        _subnet=$(echo "$_my_ip" | sed 's/\.[0-9]*$//')
        _found=$(nmap -p 22 --open -T4 "${_subnet}.0/24" 2>/dev/null \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | while read _ip; do
                [ "$_ip" != "$_my_ip" ] && echo "$_ip" && break
            done)
        [ -n "$_found" ] && echo "$_found" && return 0
    fi

    return 1
}

LAPTOP_IP=$(_discover_laptop_ip)
if [ -z "$LAPTOP_IP" ]; then
    _log "WARN: Could not discover laptop IP. Using default 192.168.43.1"
    LAPTOP_IP="${UOM_LAPTOP_IP:-192.168.43.1}"
fi

_log "UOM phone bootstrap starting"
_log "Termux user=$(id -un) uid=$(id -u) home=$HOME_DIR"
_log "Laptop target=${LAPTOP_USER}@${LAPTOP_IP} reverse port=${REV_PORT}"

# ── 1. Storage + packages ─────────────────────────────────────────────────
if command -v termux-setup-storage >/dev/null 2>&1; then
    termux-setup-storage 2>/dev/null || true
fi

_log "pkg update/upgrade..."
pkg update -y || true
pkg upgrade -y || true

_log "Installing packages..."
pkg install -y \
    nodejs-lts \
    git \
    openssh \
    tmux \
    curl \
    wget \
    jq \
    python \
    iproute2 \
    nmap \
    coreutils \
    termux-api \
    2>&1 | tail -20

# ── 2. SSH host keys + authorized_keys ────────────────────────────────────
mkdir -p "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"

if [ ! -f "$PREFIX/etc/ssh/ssh_host_ed25519_key" ] && [ ! -f "$HOME_DIR/.ssh/ssh_host_ed25519_key" ]; then
    _log "Generating ssh host keys..."
    ssh-keygen -A 2>/dev/null || true
fi

if ! grep -qF "alpine-laptop-to-phone" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null; then
    printf '%s\n' "$LAPTOP_PUBKEY" >> "$HOME_DIR/.ssh/authorized_keys"
    _log "Installed laptop public key into authorized_keys"
else
    _log "Laptop public key already present"
fi
chmod 600 "$HOME_DIR/.ssh/authorized_keys"

SSHD_CFG="$PREFIX/etc/ssh/sshd_config"
if [ -f "$SSHD_CFG" ]; then
    if ! grep -q '^Port 8022' "$SSHD_CFG" 2>/dev/null; then
        printf '\nPort 8022\nPubkeyAuthentication yes\nPasswordAuthentication yes\n' >> "$SSHD_CFG"
    fi
fi

# ── 3. Phone GitHub keypair ───────────────────────────────────────────────
if [ ! -f "$HOME_DIR/.ssh/id_ed25519_github" ]; then
    ssh-keygen -t ed25519 -C "dharani-phone-mi8" -f "$HOME_DIR/.ssh/id_ed25519_github" -N ""
    _log "Generated GitHub deploy key"
fi

if [ ! -f "$HOME_DIR/.ssh/id_ed25519_laptop" ]; then
    ssh-keygen -t ed25519 -C "phone-to-laptop" -f "$HOME_DIR/.ssh/id_ed25519_laptop" -N ""
    _log "Generated phone→laptop key (add pub to laptop authorized_keys later)"
fi

# ── SSH config with dynamic laptop IP ─────────────────────────────────────
cat > "$HOME_DIR/.ssh/config" << EOF
Host github.com
    HostName github.com
    IdentityFile ~/.ssh/id_ed25519_github
    User git
    StrictHostKeyChecking accept-new

Host uom-laptop
    HostName ${LAPTOP_IP}
    Port 22
    User ${LAPTOP_USER}
    IdentityFile ~/.ssh/id_ed25519_laptop
    StrictHostKeyChecking accept-new
    ConnectTimeout 5
    ServerAliveInterval 30
    ServerAliveCountMax 6
EOF
chmod 600 "$HOME_DIR/.ssh/config"

# ── 4. Start sshd ─────────────────────────────────────────────────────────
_log "Starting Termux sshd on port ${PHONE_SSHD_PORT}..."
pkill -x sshd 2>/dev/null || true
sleep 1
sshd || _die "sshd failed to start"
sleep 1
if ! ps -A 2>/dev/null | grep -q '[s]shd'; then
    pgrep sshd >/dev/null 2>&1 || _die "sshd not running after start"
fi
_log "sshd OK"

TERMUX_USER=$(id -un)
printf '%s\n' "$TERMUX_USER" > "$HOME_DIR/.uom-termux-user"
printf '%s\n' "$TERMUX_USER" > "$HOME_DIR/.termux-user"
_log "Termux SSH user: $TERMUX_USER"

# ── 5. opencode (best effort) ─────────────────────────────────────────────
if ! command -v opencode >/dev/null 2>&1; then
    _log "Installing opencode (try install script)..."
    if curl -fsSL https://opencode.ai/install | sh 2>/dev/null; then
        export PATH="$HOME_DIR/.opencode/bin:$PATH"
    else
        _log "install script failed; trying npm..."
        npm install -g opencode-ai 2>&1 | tail -10 || _log "WARN: opencode install failed (can retry later)"
    fi
fi
if command -v opencode >/dev/null 2>&1; then
    _log "opencode: $(opencode --version 2>/dev/null || echo present)"
else
    _log "WARN: opencode not on PATH yet — Phase 1.4 retry later"
    _log "FALLBACK: You can use 'aider' or build opencode from Go source"
    _log "  pkg install golang && go install github.com/opencode-ai/opencode@latest"
fi

# ── 6. Clone / update UOM repo ────────────────────────────────────────────
mkdir -p "$HOME_DIR/src"
cd "$HOME_DIR/src" || _die "cannot cd ~/src"

if [ -d universal-omni-master/.git ]; then
    _log "Repo exists — fetch/pull..."
    cd universal-omni-master || exit 1
    git pull --rebase origin main 2>/dev/null || git pull 2>/dev/null || true
else
    _log "Cloning UOM (HTTPS first; switch to SSH after GitHub key added)..."
    git clone --depth=50 "$REPO_URL" universal-omni-master || \
        _die "git clone failed — check network"
    cd universal-omni-master || exit 1
fi

git config user.email "dharani.phone@local"
git config user.name "Dharani-Phone-Mi8"
mkdir -p tools .uom-agent/context
chmod +x tools/*.sh 2>/dev/null || true

# Announce phone IP
MY_IP=$(get_my_ip 2>/dev/null || ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')
[ -z "$MY_IP" ] && MY_IP=$(ip -4 addr show 2>/dev/null | awk '/inet / && $2 !~ /^127\./ {sub(/\/.*/,"",$2); print $2; exit}')
if [ -n "$MY_IP" ]; then
    echo "$MY_IP" > .uom-agent/phone.ip
    _log "phone.ip=$MY_IP"
fi

# ── 7. tmux session helper ────────────────────────────────────────────────
mkdir -p "$HOME_DIR/bin"
cat > "$HOME_DIR/bin/uom-session.sh" << 'SESS'
#!/data/data/com.termux/files/usr/bin/sh
SESSION="uom"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x 120 -y 40
tmux rename-window -t "$SESSION:0" "orchestrator"
tmux send-keys -t "$SESSION:0" "cd ~/src/universal-omni-master && sh tools/uom-orch-phone.sh 2>&1 | tee ~/.uom-phone.log" ""
tmux new-window -t "$SESSION" -n "opencode"
tmux send-keys -t "$SESSION:1" "cd ~/src/universal-omni-master" ""
tmux new-window -t "$SESSION" -n "git"
tmux send-keys -t "$SESSION:2" "cd ~/src/universal-omni-master && watch -n 30 'git log --oneline -5; echo; cat .uom-agent/state.json 2>/dev/null'" ""
tmux new-window -t "$SESSION" -n "laptop-ssh"
tmux select-window -t "$SESSION:0"
tmux attach-session -t "$SESSION"
SESS
chmod +x "$HOME_DIR/bin/uom-session.sh"

# ── 8. Termux:Boot auto-start ─────────────────────────────────────────────
mkdir -p "$HOME_DIR/.termux/boot"
cat > "$HOME_DIR/.termux/boot/start-uom.sh" << BOOT
#!/data/data/com.termux/files/usr/bin/sh
sleep 10
sshd
# Keep reverse tunnel alive to laptop (dynamic IP discovery)
(
  LAPTOP_IP=""
  # Try mDNS first
  if command -v avahi-resolve >/dev/null 2>&1; then
    LAPTOP_IP=\$(avahi-resolve -n hp-pavilion.local 2>/dev/null | awk '{print \$2}' | head -1)
  fi
  # Fallback: try known hotspot gateway range
  if [ -z "\$LAPTOP_IP" ] || [ "\$LAPTOP_IP" = "0.0.0.0" ]; then
    _gw=\$(ip route 2>/dev/null | awk '/^default/{print \$3; exit}')
    if [ -n "\$_gw" ]; then
      _base=\$(echo "\$_gw" | sed 's/\.[0-9]*\$//')
      for _s in 100 101 102 103 104 105 106 107 108 109 110; do
        _c="\${_base}.\${_s}"
        if ping -c 1 -W 1 "\$_c" >/dev/null 2>&1 && nc -z -w 2 "\$_c" 22 2>/dev/null; then
          LAPTOP_IP="\$_c"; break
        fi
      done
    fi
  fi
  # Final fallback: check env / state file
  if [ -z "\$LAPTOP_IP" ] || [ "\$LAPTOP_IP" = "0.0.0.0" ]; then
    LAPTOP_IP=\$(cat ~/src/universal-omni-master/.uom-agent/laptop.ip 2>/dev/null)
  fi
  LAPTOP_IP="\${LAPTOP_IP:-${LAPTOP_IP}}"
  while true; do
    ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \\
      -o StrictHostKeyChecking=accept-new \\
      -R ${REV_PORT}:127.0.0.1:${PHONE_SSHD_PORT} \\
      ${LAPTOP_USER}@\${LAPTOP_IP} 2>/dev/null || sleep 15
  done
) &
cd /data/data/com.termux/files/home/src/universal-omni-master 2>/dev/null || exit 0
tmux new-session -d -s uom -x 120 -y 40 2>/dev/null || true
tmux send-keys -t uom "sh tools/uom-orch-phone.sh 2>&1 | tee ~/.uom-phone.log" "" 2>/dev/null || true
BOOT
chmod +x "$HOME_DIR/.termux/boot/start-uom.sh"

# ── 9. Reverse SSH tunnel helper (dynamic IP) ─────────────────────────────
cat > "$HOME_DIR/bin/uom-reverse-ssh.sh" << REV
#!/data/data/com.termux/files/usr/bin/sh
# Persistent reverse tunnel: laptop:31415 -> phone:8022
# Dynamically discovers laptop IP

LAPTOP_USER="${LAPTOP_USER}"
REV_PORT="${REV_PORT}"

_discover_laptop() {
    # Method 1: mDNS
    if command -v avahi-resolve >/dev/null 2>&1; then
        _ip=\$(avahi-resolve -n hp-pavilion.local 2>/dev/null | awk '{print \$2}' | head -1)
        [ -n "\$_ip" ] && [ "\$_ip" != "0.0.0.0" ] && echo "\$_ip" && return 0
    fi
    # Method 2: gateway range scan
    _gw=\$(ip route 2>/dev/null | awk '/^default/{print \$3; exit}')
    if [ -n "\$_gw" ]; then
        _base=\$(echo "\$_gw" | sed 's/\.[0-9]*\$//')
        for _s in 100 101 102 103 104 105 106 107 108 109 110; do
            _c="\${_base}.\${_s}"
            if ping -c 1 -W 1 "\$_c" >/dev/null 2>&1 && nc -z -w 2 "\$_c" 22 2>/dev/null; then
                echo "\$_c"; return 0
            fi
        done
    fi
    # Method 3: state file
    [ -f ~/src/universal-omni-master/.uom-agent/laptop.ip ] && \
        cat ~/src/universal-omni-master/.uom-agent/laptop.ip && return 0
    # Method 4: env fallback
    echo "\${UOM_LAPTOP_IP:-192.168.43.1}"
}

sshd 2>/dev/null || true
LAPTOP_IP=\$(_discover_laptop)
echo "[uom-rev] forwarding laptop:\${REV_PORT} -> phone:8022 as \${LAPTOP_USER}@\${LAPTOP_IP}"
echo "[uom-rev] Termux user: \$(id -un)"
printf '%s\n' "\$(id -un)" > "\$HOME/.uom-termux-user"

while true; do
    # Re-discover on each reconnect (IP may have changed)
    LAPTOP_IP=\$(_discover_laptop)
    ssh -N \\
        -o ExitOnForwardFailure=yes \\
        -o ServerAliveInterval=20 \\
        -o ServerAliveCountMax=3 \\
        -o StrictHostKeyChecking=accept-new \\
        -o ConnectTimeout=10 \\
        -R \${REV_PORT}:127.0.0.1:8022 \\
        \${LAPTOP_USER}@\${LAPTOP_IP}
    echo "[uom-rev] tunnel dropped — re-discovering laptop in 10s"
    sleep 10
done
REV
chmod +x "$HOME_DIR/bin/uom-reverse-ssh.sh"

# ── 10. Write verify marker ───────────────────────────────────────────────
cat > "$HOME_DIR/.uom-phone-ready" << MARK
ready=1
user=$TERMUX_USER
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
sshd_port=$PHONE_SSHD_PORT
rev_port=$REV_PORT
laptop=${LAPTOP_USER}@${LAPTOP_IP}
phone_ip=${MY_IP:-unknown}
MARK

_log "=========================================="
_log "BOOTSTRAP COMPLETE"
_log "Termux user : $TERMUX_USER"
_log "sshd port   : $PHONE_SSHD_PORT"
_log "phone IP    : ${MY_IP:-unknown}"
_log "laptop IP   : ${LAPTOP_IP} (auto-discovered)"
_log "=========================================="
_log "GitHub pubkey (add at github.com/settings/keys):"
cat "$HOME_DIR/.ssh/id_ed25519_github.pub" 2>/dev/null || true
_log "=========================================="
_log "Phone→laptop pubkey (add to laptop authorized_keys for key auth):"
cat "$HOME_DIR/.ssh/id_ed25519_laptop.pub" 2>/dev/null || true
_log "=========================================="
_log "NEXT: start reverse tunnel (keep this running):"
_log "  sh ~/bin/uom-reverse-ssh.sh"
_log "Or one-shot:"
_log "  ssh -N -R ${REV_PORT}:127.0.0.1:8022 ${LAPTOP_USER}@${LAPTOP_IP}"
_log "=========================================="
