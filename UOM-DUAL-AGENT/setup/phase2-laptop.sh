#!/bin/sh
# phase2-laptop.sh — UOM Dual-Agent Phase 2 (Alpine laptop)
set -u
REPO="/home/alpine/src/universal-omni-master"
SETUP="$REPO/UOM-DUAL-AGENT/setup"
HOME_DIR="/home/alpine"
TERMUX_USER="${UOM_TERMUX_USER:-$(cat $HOME_DIR/.uom-termux-user 2>/dev/null || echo u0_a608)}"

_log() { printf '[PHASE2] %s\n' "$*"; }
_die() { _log "FATAL: $*"; exit 1; }
command -v doas >/dev/null 2>&1 || _die "doas required"

_log "Installing packages..."
doas apk add --no-cache openssh git curl jq tmux avahi avahi-tools nss-mdns nmap nodejs npm

_log "Enabling avahi-daemon..."
doas rc-update add avahi-daemon default 2>/dev/null || true
doas rc-service avahi-daemon start 2>/dev/null || doas rc-service avahi-daemon restart 2>/dev/null || true

if ! grep -q 'mdns4_minimal' /etc/nsswitch.conf 2>/dev/null; then
  _log "Patching nsswitch for mDNS..."
  doas sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
else
  _log "nsswitch already has mdns4_minimal"
fi

_log "Installing if-up + local.d announce hooks..."
doas cp "$SETUP/uom-announce.if-up" /etc/network/if-up.d/uom-announce
doas chmod +x /etc/network/if-up.d/uom-announce

doas tee /etc/local.d/uom-announce.start >/dev/null << 'EOF'
#!/bin/sh
sleep 15
/etc/network/if-up.d/uom-announce
EOF
doas chmod +x /etc/local.d/uom-announce.start

doas tee /etc/local.d/uom-resume.start >/dev/null << 'EOF'
#!/bin/sh
sleep 20
/etc/network/if-up.d/uom-announce
EOF
doas chmod +x /etc/local.d/uom-resume.start
doas rc-update add local default 2>/dev/null || true

# Ensure user tools present
mkdir -p "$HOME_DIR/bin"
[ -x "$HOME_DIR/bin/uom-announce" ] || true
chmod +x "$REPO"/tools/*.sh 2>/dev/null || true

_log "Announcing laptop IP..."
"$HOME_DIR/bin/uom-announce" || true

_log "=== Phase 2 system install done ==="
_log "avahi: $(doas rc-service avahi-daemon status 2>&1 | tr -d '\n')"
_log "hosts: $(grep '^hosts:' /etc/nsswitch.conf)"
_log "laptop.ip=$(cat $REPO/.uom-agent/laptop.ip 2>/dev/null)"
_log "Termux user for SSH: $TERMUX_USER"
