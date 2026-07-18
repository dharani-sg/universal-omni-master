# Phone-Only Operations Guide

## Overview

UOM runs entirely on the Xiaomi Mi 8 (dipper) with crDroid Android 15 inside a rootless QEMU VM. No laptop required for daily operation after initial setup.

## Architecture

```
Phone (Termux)
  └─ QEMU (rootless, TCG)
       └─ Alpine 3.21.3 aarch64 (musl/OpenRC)
            ├─ opencode-zen-smart (curl wrapper, primary transport)
            ├─ opencode-zen-free (basic rotation)
            └─ UOM repo (~/src/universal-omni-master)
```

## Daily Operations

### Start Everything
Tap `10-UOM-Start` in Termux:Widget (or run manually):
```sh
sh ~/.shortcuts/tasks/10-UOM-Start
```

### Check Status
Tap `00-UOM-Status`:
```sh
sh ~/.shortcuts/00-UOM-Status
```

### Open Guest Shell
Tap `20-UOM-Guest-Shell`:
```sh
ssh -p 2222 uom@127.0.0.1
```

### Zen Loop Console
Tap `30-UOM-Zen-Console` (after Phase 10):
```sh
ssh -tt -p 2222 uom@127.0.0.1 "tmux new-session -A -s uom-zen-phone"
```

### View Logs
Tap `50-UOM-Logs`:
```sh
sh ~/.shortcuts/50-UOM-Logs 50
```

### Stop Everything
Tap `90-UOM-Stop`, type `STOP` to confirm:
```sh
sh ~/.shortcuts/90-UOM-Stop
```

## SSH Routes

| Route | Command |
|-------|---------|
| Phone → Guest | `ssh -p 2222 uom@127.0.0.1` |
| Laptop → Phone | `ssh -p 8022 u0_a608@192.168.40.207` |
| Phone → GitHub | `git fetch origin` (HTTPS, no auth for public) |

## Key Files

| Path | Purpose |
|------|---------|
| `~/bin/uom-qemu-phone` | QEMU launcher (start/stop/status/console/ssh) |
| `~/uom-vm/` | VM disk, firmware, kernel, logs |
| `~/.shortcuts/` | Termux:Widget scripts |
| `~/.config/uom/` | Zen state, usage logs, cooldown |
| `~/.termux/boot/start-uom.sh` | Auto-start on boot (Phase 12) |

## Known Limitations

1. **No KVM** — TCG emulation only (slow, ~0.1x native speed)
2. **No IPv6 in QEMU** — opencode binary hangs, curl uses `-4` flag
3. **No native OpenCode** — curl wrapper is primary transport
4. **Widget not installed** — Manual Termux:Widget install required
5. **No GitHub push auth** — Read-only fetch until deploy key configured

## Recovery

### QEMU Won't Start
```sh
# Check for stale PID
rm -f ~/uom-vm/uom-qemu.pid ~/uom-vm/uom-qemu.lock
# Try again
~/bin/uom-qemu-phone start
```

### Guest Unreachable
```sh
# Check QEMU process
ps -A | grep qemu
# Check port forwarding
netstat -tlnp | grep 2222
# Restart QEMU
~/bin/uom-qemu-phone restart
```

### SSH Dead After Package Upgrade
```sh
pkill sshd; sleep 1; sshd
```

### Disk Corrupted
```sh
# Validate
qemu-img info ~/uom-vm/images/uom-phone.qcow2
# If corrupted, restore from backup
cp ~/uom-vm/alpine-disk.qcow2.bak ~/uom-vm/images/uom-phone.qcow2
```
