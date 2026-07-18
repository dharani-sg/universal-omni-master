# New Laptop Recovery Guide

## Overview

If your laptop is lost or replaced, recover UOM operation using GitHub as the canonical source.

## Prerequisites

- New laptop with SSH client
- GitHub account access
- Phone still running (or QEMU disk backup)

## Recovery Steps

### 1. Clone from GitHub

```sh
git clone -b refactor/structure-audit-2026-07-17 \
  https://github.com/dharani-sg/universal-omni-master.git \
  ~/src/universal-omni-master
```

### 2. Verify SHA

```sh
cd ~/src/universal-omni-master
git log --oneline -1
# Should show: f0d8110 feat(sync): add git sync tools and architecture doc
```

### 3. Install Dependencies

```sh
# Debian/Ubuntu
sudo apt install qemu-system-aarch64 git curl jq openssh-client tmux

# Alpine
doas apk add qemu-system-aarch64 git curl jq openssh tmux

# macOS (Homebrew)
brew install qemu git curl jq tmux
```

### 4. Connect to Phone (if available)

```sh
# Add SSH key to phone
ssh-copy-id -p 8022 u0_a608@PHONE_IP

# Test connection
ssh -p 8022 u0_a608@PHONE_IP 'echo OK'
```

### 5. Verify Phone State

```sh
ssh -p 8022 u0_a608@PHONE_IP 'cd ~/src/universal-omni-master && git log --oneline -1'
# Should show: f0d8110 (same as laptop)
```

### 6. Resume Operations

```sh
cd ~/src/universal-omni-master
sh bin/uom-sync verify
# Should show: PASS (local == GitHub)
```

## No Phone Available

If the phone is also lost:

1. Clone repo from GitHub (all code is there)
2. VM disk is NOT in GitHub (back it up elsewhere)
3. Follow `docs/ANDROID-13-PLUS-QEMU.md` to recreate VM
4. Reinstall Alpine and UOM in guest
5. Re-deploy scripts to phone

## Preventing Data Loss

- Regular `git push` to GitHub
- VM disk backup to external storage
- SSH key backup (encrypted)
- Document phone IP and SSH config
