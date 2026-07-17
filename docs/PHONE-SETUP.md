# UOM Phone Setup Guide (v0.29.0)

## Quick Bootstrap (Phone)

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | bash
```

The bootstrap auto-detects Termux/Android and:
1. Installs packages: tmux, openssh, git, golang, curl, jq, autossh, mosh
2. Builds opencode from Go source (npm is rejected on ARM64)
3. Clones the UOM repo
4. Generates ed25519 SSH key
5. Configures SSH config with laptop aliases
6. Sets up tmux with UOM layout
7. Installs reverse tunnel script
8. Starts reverse tunnel (best-effort — laptop may be offline)

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
sshd                            # start SSH server (port 8022)
sleep 2
bash ~/bin/uom-reverse-ssh.sh   # open reverse tunnel to laptop
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

The watchdog runs every 60s, checking laptop reachability. After 3 consecutive failures (~15 min), it triggers solo mode.
<!-- last-sync: 2026-07-17T07:35:34Z -->
