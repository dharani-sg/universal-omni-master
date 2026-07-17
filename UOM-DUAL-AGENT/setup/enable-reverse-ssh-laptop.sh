#!/bin/sh
# enable-reverse-ssh-laptop.sh — allow phone reverse tunnels on Alpine sshd
# Requires: doas (password once)

set -u
SRC="$(cd "$(dirname "$0")" && pwd)/99-uom-reverse-ssh.conf"
DEST="/etc/ssh/sshd_config.d/99-uom-reverse-ssh.conf"

[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

echo "Installing $DEST (needs doas)..."
doas cp "$SRC" "$DEST"
doas chmod 644 "$DEST"

# Ensure main config does not force-disable after Include
# Alpine ships AllowTcpForwarding no — drop-in Include is processed first on some
# versions; if drop-in is included via Include before the bare directive, bare
# directive wins. Safer: also patch main file if present.
if doas grep -q '^AllowTcpForwarding no' /etc/ssh/sshd_config 2>/dev/null; then
    echo "Patching /etc/ssh/sshd_config AllowTcpForwarding no → yes"
    doas sed -i 's/^AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config
fi
if doas grep -q '^GatewayPorts no' /etc/ssh/sshd_config 2>/dev/null; then
    # keep GatewayPorts no (bind reverse to localhost only) — fine for us
    true
fi

echo "Validating sshd config..."
doas sshd -t || { echo "sshd -t failed"; exit 1; }

echo "Reloading sshd..."
if command -v rc-service >/dev/null 2>&1; then
    doas rc-service sshd reload || doas rc-service sshd restart
else
    doas kill -HUP "$(cat /run/sshd.pid 2>/dev/null || cat /var/run/sshd.pid 2>/dev/null)" 2>/dev/null \
        || doas pkill -HUP sshd
fi

echo "Done. Verify:"
echo "  doas sshd -T | grep -i allowtcpforwarding"
echo "Expected: allowtcpforwarding yes"
