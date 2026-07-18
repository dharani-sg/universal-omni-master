# Android 13+ QEMU Setup Guide

## Prerequisites

| Requirement | Minimum | Tested |
|-------------|---------|--------|
| Android SDK | 33 (Android 13) | 35 (Android 15) |
| Architecture | aarch64 | aarch64 (Mi 8) |
| RAM | 4 GB | 5.5 GB |
| Storage | 10 GB free | 36 GB free |
| Termux | Google Play or F-Droid | Google Play 2026.06.21 |

## Step 1: Install Termux

Install from **Google Play** (recommended) or F-Droid. Do NOT mix sources.

## Step 2: Install Packages

```sh
pkg update && pkg upgrade
pkg install qemu-system-aarch64 git curl jq openssh tmux
```

## Step 3: Create VM Directory

```sh
mkdir -p ~/uom-vm/images ~/uom-vm/logs ~/uom-vm/shared
```

## Step 4: Download Alpine

```sh
cd ~/uom-vm
curl -LO https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-virt-3.21.3-aarch64.iso
```

## Step 5: Create Disk

```sh
qemu-img create -f qcow2 ~/uom-vm/images/uom-phone.qcow2 12G
```

## Step 6: Get UEFI Firmware

```sh
# From Termux QEMU package
cp ~/../usr/share/qemu/edk2-aarch64-code.fd ~/uom-vm/
cp ~/../usr/share/qemu/edk2-aarch64-vars.fd ~/uom-vm/
```

## Step 7: Boot from ISO

```sh
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2048 -smp 2 \
  -L ~/../usr/share/qemu \
  -drive if=pflash,format=raw,readonly=on,file=~/uom-vm/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=~/uom-vm/edk2-aarch64-vars.fd \
  -drive file=~/uom-vm/images/uom-phone.qcow2,if=virtio,format=qcow2 \
  -cdrom ~/uom-vm/alpine-virt-3.21.3-aarch64.iso \
  -boot d -nographic \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=net0
```

## Step 8: Install Alpine

In the QEMU console:
```sh
setup-alpine
# Hostname: uom-phone-qemu
# Create user: uom
# Disk: /dev/vda (sys mode)
# Reboot when prompted, but poweroff instead
poweroff
```

## Step 9: Boot from Disk

Remove `-cdrom` and `-boot d` flags. Boot normally.

## Step 10: Post-Install

```sh
# SSH into guest
ssh -p 2222 uom@127.0.0.1

# Install packages
doas apk add git curl jq openssh tmux

# Clone UOM repo
git clone https://github.com/dharani-sg/universal-omni-master.git ~/src/universal-omni-master

# Install OpenCode
curl -fsSL https://opencode.ai/install | sh
```

## Security Notes

- All QEMU networking is user-mode (no TAP/bridge)
- SSH forwarded to localhost only (127.0.0.1:2222)
- No root required for QEMU (runs as Termux UID)
- Disk in Termux private storage (not world-readable)
- No SELinux changes, no KernelSU integration required

## Troubleshooting

### QEMU Hangs on Boot
- Add `earlycon=pl011,mmio,0x09000000` to kernel cmdline
- Use `-serial stdio` or `-serial file:` (not both)
- Increase timeout to 60s+ for ISO boot

### SSH Connection Refused
- Check QEMU is running: `ps -A | grep qemu`
- Check port forwarding: `netstat -tlnp | grep 2222`
- Restart QEMU: `~/bin/uom-qemu-phone restart`

### Slow Performance
- TCG emulation is ~0.1x native speed
- Expected on phone hardware
- Reduce VM RAM if host is memory-constrained
- Use `-smp 1` if 2 vCPU causes issues
