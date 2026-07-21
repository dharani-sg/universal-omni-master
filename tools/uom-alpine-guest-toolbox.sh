#!/bin/sh
# tools/uom-alpine-guest-toolbox.sh — idempotent Alpine guest toolchain installer
# Detects Alpine version, uses doas -n, installs curated guest packages.
# Only for headless Alpine/musl aarch64 QEMU guests.
set -u

LOGFILE="${LOGFILE:-/tmp/guest-toolbox.log}"
DRYRUN="${DRYRUN:-0}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"; }

_sudo() {
  if [ "$DRYRUN" -eq 1 ]; then
    log "[DRYRUN] would run: $*"
    return 0
  fi
  doas -n "$@" 2>&1 | tee -a "$LOGFILE"
  return $?
}

log "=== Alpine Guest Toolbox Installer ==="
log "OS: $(uname -a)"
log "Alpine: $(cat /etc/alpine-release 2>/dev/null || echo unknown)"

# --- Core packages ---
CORE="
  bash
  curl
  jq
  git
  rsync
  tmux
  openssh
  openssh-client
  openssh-server
  coreutils
  util-linux
  procps
  iproute2
  bind-tools
  busybox-extras
  file
  findutils
  grep
  sed
  gawk
  tar
  xz
  tree
  ripgrep
  python3
  py3-pip
  strace
  lsof
  htop
  ncdu
  socat
  e2fsprogs
  dosfstools
  ca-certificates
  openssl
  gnupg
  vim
  nano
  less
  pv
"

# --- Update + install ---
log "[*] TIME TO WAIT: approximately 5-10 min for apk update + install"
log "[*] MAXIMUM WAIT: 20 min"
log "[*] SUCCESS CONDITION: all packages installed with no errors"

_sudo apk update || { log "FAIL: apk update"; exit 1; }

for pkg in $CORE; do
  if [ -z "$pkg" ]; then continue; fi
  log "Installing $pkg..."
  _sudo apk add --no-cache "$pkg" || log "WARN: $pkg installation had issues"
done

# --- Python pip upgrade ---
log "Upgrading pip..."
_sudo python3 -m pip install --upgrade pip 2>/dev/null || \
  python3 -m pip install --upgrade pip --break-system-packages 2>/dev/null || \
  log "WARN: pip upgrade skipped"

# --- Profile setup ---
log "Configuring profile..."
mkdir -p "$HOME/bin"

cat >> "$HOME/.profile" << 'PEOF'
export PATH="$HOME/bin:$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
export EDITOR=vim
export PAGER=less
PEOF

grep -q 'source.*\.profile' "$HOME/.bashrc" 2>/dev/null || \
  echo '[ -f "$HOME/.profile" ] && . "$HOME/.profile"' >> "$HOME/.bashrc"

log "Toolbox installation complete"
log "Run tools/uom-alpine-guest-verify.sh to verify"
exit 0
