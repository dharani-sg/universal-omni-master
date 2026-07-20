#!/bin/sh
# uom-install-alpine.sh — Interactive Alpine install into QEMU disk
# Runs on the phone via SSH. Uses tmux send-keys for interactive install.
# Under TCG emulation on Snapdragon 845, expect ~5-15 minutes total.

set -eu

VM_DIR="${HOME}/uom-vm"
DISK="${VM_DIR}/images/uom-phone.qcow2"
ISO="${VM_DIR}/alpine-virt-3.21.3-aarch64.iso"
KERNEL="${VM_DIR}/vmlinuz-virt"
INITRD="${VM_DIR}/initramfs-virt"
SESSION="uom-install"
LOG="${VM_DIR}/logs/install-$(date +%Y%m%d-%H%M%S).log"
SERIAL_LOG="${VM_DIR}/logs/install-serial.log"

_log() {
    _ts=$(date +"%H:%M:%S")
    printf '[%s] %s\n' "$_ts" "$*" | tee -a "$LOG"
}

if [ ! -f "$DISK" ]; then
    echo "No disk at $DISK. Run 'uom-qemu-phone install' first."
    exit 1
fi

# Kill any existing install session
tmux kill-session -t "$SESSION" 2>/dev/null || true

_log "=== STARTING ALPINE INSTALL ==="
_log "Disk: $DISK"
_log "ISO: $ISO"
_log "Log: $LOG"

# Start QEMU with direct kernel boot + cdrom
# Serial goes to stdio (tmux) for interactive install
_log "Starting QEMU (direct kernel + cdrom)..."

tmux new-session -d -s "$SESSION" -n "install" \
    "cd '$VM_DIR' && exec qemu-system-aarch64 \
    -M virt -cpu cortex-a72 -m 2048 -smp 2 \
    -kernel $KERNEL \
    -initrd $INITRD \
    -append 'console=ttyAMA0' \
    -drive file=${DISK},if=virtio,format=qcow2 \
    -cdrom ${ISO} \
    -nographic \
    -netdev user,id=net0,hostfwd=tcp::8222-:22 \
    -device virtio-net-pci,netdev=net0 \
    2>&1 | tee '$SERIAL_LOG'"

_log "Waiting 30s for kernel boot..."
sleep 30

send() {
    _keys="$1"
    _delay="${2:-3}"
    tmux send-keys -t "$SESSION:install" "$_keys" Enter
    _log ">>> $_keys (wait ${_delay}s)"
    sleep "$_delay"
}

_log "=== Waiting for login prompt ==="
# Capture current state
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-1.txt" 2>/dev/null || true
sleep 10

# Try root login
_log "Sending 'root' to login..."
send "root" 5

# Verify we're in
_log "Checking shell..."
send "" 2
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-2.txt" 2>/dev/null || true

# Setup networking
_log "=== Setting up network ==="
send "ip link set eth0 up" 3
send "udhcpc -i eth0" 8

# Verify network
_log "=== Testing network ==="
send "ping -c 2 -W 5 dl-cdn.alpinelinux.org" 10

# Create answer file
_log "=== Creating answer file ==="
send "cat > /tmp/answers << 'ANSEOF'" 2
send "KEYMAP=us" 1
send "HOSTNAME=uom-phone-qemu" 1
send "INTERFACENAME=eth0" 1
send "INTERFACESOPTS=dhcp" 1
send "TIMEZONE=UTC" 1
send "PROXYOPTS=none" 1
send "APKREPOSOPTS=\"-1\"" 1
send "SSHDOPTS=openssh" 1
send "NTPOPTS=none" 1
send "DISKOPTS=\"-m sys /dev/vda\"" 1
send "ANSEOF" 2

# Show the answer file
send "cat /tmp/answers" 3

# Run setup-alpine
_log "=== RUNNING setup-alpine (this takes several minutes under TCG) ==="
send "setup-alpine -f /tmp/answers" 5

# Wait for password prompts — setup-alpine will ask for root password
_log "=== Waiting for root password prompt (15s) ==="
sleep 15
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-3.txt" 2>/dev/null || true

# Set root password (alpine123)
_log "Setting root password..."
send "" 2
send "alpine123" 2
send "alpine123" 2

# Wait for setup to continue
_log "=== Waiting for install to progress (60s) ==="
sleep 60
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-4.txt" 2>/dev/null || true

# Check if ssh key setup appears
_log "=== Checking for SSH key prompt ==="
sleep 20
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-5.txt" 2>/dev/null || true

# Answer "no" to ssh key
send "" 2

# Wait more for disk install to complete
_log "=== Waiting for disk install (120s) ==="
sleep 120
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-6.txt" 2>/dev/null || true

# Check status
_log "=== Checking install status ==="
sleep 10
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-7.txt" 2>/dev/null || true

# If we see a login prompt or shell prompt, installation may be done
_log "=== Attempting poweroff ==="
send "" 2
send "poweroff" 5

# Wait for QEMU to exit
_log "=== Waiting for QEMU to exit (30s) ==="
sleep 30

# Capture final state
tmux capture-pane -t "$SESSION:install" -p > "${VM_DIR}/logs/install-pane-final.txt" 2>/dev/null || true

_log "=== INSTALL PHASE COMPLETE ==="
_log "Serial log: $SERIAL_LOG"
_log "Pane captures: ${VM_DIR}/logs/install-pane-*.txt"
_log "Verify disk: qemu-img info $DISK"
_log "Next: boot from disk with 'uom-qemu-phone start'"
