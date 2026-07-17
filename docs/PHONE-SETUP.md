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
ssh -o ConnectTimeout=5 127.0.0.1 -p 18022 echo "TUNNEL OK"
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

## Current State (v0.30.0)

- Dual-agent: alive (tunnel UP, tmux watchdog running on phone)
- Scripts deployed: omni-project-start.sh, uom-tmux-watchdog.sh, uom-reverse-ssh.sh, uom-status.sh
- Aliases: 14 UOM aliases installed in `~/.bashrc`
- Boot: Termux:Boot starts SSH + tunnel + watchdog + orchestrator
- Tunnel port: 18022 (laptop) ↔ 8022 (phone)

## Next Steps

1. Start: `bash ~/bin/omni-project-start.sh` — interactive menu
2. Or direct: `bash ~/bin/uom-tmux-watchdog.sh --daemon`
3. Verify tunnel: `ssh -p 18022 127.0.0.1 echo OK`
4. Next phase: M31 — Network Switching Stress Test

<!-- last-sync: 2026-07-17T18:00:00Z -->