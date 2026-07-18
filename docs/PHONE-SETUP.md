# UOM Phone Setup Guide (v0.30.0)

## Quick Bootstrap (Phone)

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

The bootstrap auto-detects Termux/Android and:
1. Installs packages: tmux, openssh, git, golang, curl, jq, autossh, mosh
2. Builds opencode from Go source (npm is rejected on ARM64)
3. Clones the UOM repo (handles dirty state via `git stash`)
4. Generates ed25519 SSH key
5. Configures SSH config with laptop aliases (tunnel/LAN/mDNS)
6. Sets up tmux with UOM 5-window layout (orchestrator, opencode, monitor, laptop, status)
7. Installs reverse tunnel script + tmux watchdog + omni-project-start menu
8. Starts reverse tunnel (best-effort — laptop may be offline)
9. Starts tmux watchdog: `bash ~/bin/uom-tmux-watchdog.sh --daemon`
10. Installs 14 UOM aliases into `~/.bashrc`

## Manual Setup (if bootstrap fails)

### 1. Prerequisites
```sh
pkg update && pkg upgrade
pkg install tmux openssh git golang curl jq autossh mosh
```

### 2. Build opencode
```sh
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH
go install github.com/opencode-ai/opencode@latest
```

### 3. Termux:Boot (Auto-start on phone reboot)

**Requires:** Termux:Boot app installed from F-Droid.

Create `~/.termux/boot/uom-boot.sh`:
```sh
#!/data/data/com.termux.boot/files/usr/bin/bash
sleep 5
sshd                              # start SSH server (port 8022)
sleep 2
bash ~/bin/uom-reverse-ssh.sh     # open reverse tunnel to laptop
bash ~/bin/uom-tmux-watchdog.sh --daemon  # start tmux watchdog
bash ~/bin/uom-orch-phone.sh --daemon      # start phone orchestrator
```
```sh
chmod +x ~/.termux/boot/uom-boot.sh
```

### 4. Reverse Tunnel

```sh
bash ~/bin/uom-reverse-ssh.sh
```

Verify from laptop:
```sh
ssh -o ConnectTimeout=5 127.0.0.1 -p 31415 echo "TUNNEL OK"
```

### 5. Start tmux Session

```sh
tmux new -s uom
cd ~/src/universal-omni-master
```

## Agent Modes on Phone

| Mode | Trigger | Behavior |
|------|---------|----------|
| `phone-solo` | Laptop unreachable >15 min | Phone runs opencode + commits/pushes |
| `dual-pending` | Laptop recovered | Waits for manual handoff confirmation |

## Watchdog

The watchdog runs every 60s, checking laptop reachability via `discover_laptop_ip()`. After 3 consecutive failures (~15 min), it triggers solo orchestrator. When laptop recovers, sets `dual-pending` — requires explicit confirmation to resume dual mode.

## Current State (v0.32.0 — 2026-07-18)

### Working Environments (ranked)

| Environment | opencode | node | npm | Method |
|---|---|---|---|---|
| **Termux host (preferred)** | **v1.2.13** | v24.17.0 | v11.18.0 | Termux pkg (has Android bionic TBI fix) |
| **Debian proot (fallback)** | v1.18.3 | v22.23.1 | v10.9.8 | npm `opencode-ai` package |
| **QEMU Alpine VM (optional)** | — | — | — | Direct kernel boot, serial works |

### opencode Configuration
- Model: `opencode/big-pickle` (free tier, no API key needed)
- Config: `~/.config/opencode/opencode.json`
- Wrapper: `~/bin/opencode` (handles Android bionic heap tagging via LD_PRELOAD)
- Denied providers: openai, anthropic, google, openrouter

### Package State (2026-07-18 post-upgrade)
- Termux: 114 packages upgraded, dpkg/apt clean
- Debian proot: 239 packages, clean
- Openssh: 10.4p1 (port 8022)
- tmux: 3.7b
- QEMU: 10.2.1

### QEMU (WORKING)
```bash
# Direct kernel boot with serial:
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 512 -smp 2 \
  -accel tcg,thread=multi \
  -kernel ~/uom-vm/vmlinuz-virt -initrd ~/uom-vm/initramfs-virt \
  -append "console=ttyAMA0,115200n8 earlycon=pl011,mmio,0x09000000 loglevel=8 panic=5" \
  -drive file=~/uom-vm/alpine-disk.qcow2,if=virtio,format=qcow2 \
  -display none -monitor none -serial stdio
```

### Quick Start Commands
```bash
# Start opencode in Termux:
bash ~/uom-repair/scripts/phone-opencode.sh termux

# Start opencode in Debian proot:
bash ~/uom-repair/scripts/phone-opencode.sh proot

# Attach to tmux session:
tmux attach -t uom-opencode

# Start QEMU VM:
bash ~/uom-repair/scripts/run-qemu-best.sh

# Project status:
omni-status
```

### Recovery Commands
```bash
# If SSH dies after pkg upgrade:
pkill sshd; sleep 1; sshd

# If apt lock stuck:
ps -ef | grep apt | grep -v grep
dpkg --configure -a && apt-get -f install

# Start tunnel:
bash ~/bin/uom-reverse-ssh.sh
```

### Tunnel
- Port: 31415 (laptop) ↔ 8022 (phone)
- Status: DOWN (not started this session)
- Start: `bash ~/bin/uom-reverse-ssh.sh` (from phone)

### Known Issues
1. **ENOSYS statx():** kernel 4.9.337 does not implement statx(); use proot-debian for ls
2. **Tunnel port 18022:** old references cause "remote port forwarding failed" — use 31415
3. **Queue.json corruption:** phone jq parse errors from 2026-07-17, may need manual cleanup
4. **py3compile errors:** harmless, caused by non-interactive SSH context

### Audit Reports
- `~/uom-repair/reports/audit-phase0-*.log` — Raw audit output
- `~/uom-repair/reports/final-audit-report-*.md` — Consolidated report
- `~/audit/phase0.log`, `phase1-findings.md`, `qemu-verdict.md` — Previous audit session

### Scripts
| Script | Location | Purpose |
|--------|----------|---------|
| phone-opencode.sh | ~/uom-repair/scripts/ | Launch opencode (termux/proot) |
| run-qemu-best.sh | ~/uom-repair/scripts/ | Start QEMU Alpine VM |
| omni-project-start.sh | ~/bin/ | Interactive menu + dashboard |
| uom-tmux-watchdog.sh | ~/bin/ | Tmux session auto-recovery |
| uom-reverse-ssh.sh | ~/bin/ | Reverse SSH tunnel to laptop |
| uom-status.sh | ~/src/universal-omni-master/bin/ | Orchestrator status |

<!-- last-sync: 2026-07-18T09:30:00+05:30 -->