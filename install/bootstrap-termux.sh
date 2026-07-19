#!/bin/sh
# install/bootstrap-termux.sh — UOM Bootstrap for Termux/Android ARM64
# POSIX sh. Modes: --check (default, read-only), --apply (make changes).
# Profiles: phone-relay (default), phone-vm-agent (opt-in)
# Consent flags: --allow-vm, --allow-large-download, --allow-opencode-install, --allow-metered
#
# Usage:
#   sh install/bootstrap-termux.sh                                    # check mode (phone-relay)
#   sh install/bootstrap-termux.sh --apply                            # apply changes (phone-relay)
#   sh install/bootstrap-termux.sh --apply --allow-third-party-opencode
#   sh install/bootstrap-termux.sh --apply --profile phone-vm-agent \
#     --allow-large-download --allow-vm --allow-opencode-install

set -eu

# ── Constants ────────────────────────────────────────────────────────────
UOM_REPO_DEFAULT="https://github.com/dharani-sg/universal-omni-master.git"
UOM_DIR_DEFAULT="$HOME/src/universal-omni-master"
SSHD_PORT=8022
TUNNEL_PORT=31415
INSTALL_LOCK="${TMPDIR:-/tmp}/uom-install.lock"
MAX_CHILD_SIZE=512000

# ── Helpers ──────────────────────────────────────────────────────────────
log()  { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[FATAL] %s\n' "$*" >&2; exit 1; }
now()  { date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'; }

# JSON-safe string escape (POSIX, no jq dependency)
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}

# Ensure opencode binary path is on PATH (npm installs to ~/.opencode/bin)
OPTDIR="${PREFIX:-$HOME}/.opencode/bin"
case ":${PATH:-}:" in
  *":$OPTDIR:"*) ;;
  *) export PATH="$OPTDIR:$PATH" ;;
esac

# ── Cleanup trap ─────────────────────────────────────────────────────────
_CLEANUP_DONE=0
_TEST_ROOT=""
_USE_TEST_ROOT=0
cleanup() {
  [ "$_CLEANUP_DONE" -eq 1 ] && return
  _CLEANUP_DONE=1
  # Release lock
  rm -f "$INSTALL_LOCK" 2>/dev/null || true
  # Remove temp files
  [ -n "${_SSH_CONFIG_TMP:-}" ] && rm -f "$_SSH_CONFIG_TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

# ── Parse arguments ──────────────────────────────────────────────────────
MODE="check"
PROFILE="phone-relay"
ALLOW_THIRD_PARTY=0
ALLOW_PROOT=0
ALLOW_VM=0
ALLOW_LARGE_DOWNLOAD=0
ALLOW_OPENCODE_INSTALL=0
ALLOW_METERED=0
REF="${UOM_REF:-main}"
REPO_URL="${UOM_REPO_URL:-$UOM_REPO_DEFAULT}"
INSTALL_DIR="${UOM_INSTALL_DIR:-$UOM_DIR_DEFAULT}"
SKIP_PACKAGES=0
NON_INTERACTIVE=0
RESUME=0
ROLLBACK=0
TEST_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)                    MODE="apply"; shift ;;
    --check)                    MODE="check"; shift ;;
    --allow-third-party-opencode) ALLOW_THIRD_PARTY=1; shift ;;
    --allow-proot-opencode)    ALLOW_PROOT=1; shift ;;
    --allow-vm)                ALLOW_VM=1; shift ;;
    --allow-large-download)    ALLOW_LARGE_DOWNLOAD=1; shift ;;
    --allow-opencode-install)  ALLOW_OPENCODE_INSTALL=1; shift ;;
    --allow-metered)           ALLOW_METERED=1; shift ;;
    --profile)
      shift
      [ $# -eq 0 ] && die "--profile requires a value. Usage: --profile phone-vm-agent"
      val="$1"
      case "$val" in
        phone-relay|phone-vm-agent) PROFILE="$val"; shift ;;
        *) die "Unknown profile: $val. Valid: phone-relay, phone-vm-agent" ;;
      esac
      ;;
    --profile=*)
      val="${1#*=}"
      case "$val" in
        phone-relay|phone-vm-agent) PROFILE="$val"; shift ;;
        *) die "Unknown profile: $val. Valid: phone-relay, phone-vm-agent" ;;
      esac
      ;;
    -h|--help)
      cat << HELPEOF
Usage: sh $0 [OPTIONS]

Modes:
  --check                         Dry-run (default)
  --apply                         Apply changes

Profiles:
  --profile phone-relay           Lightweight install (default, ~25KB)
  --profile phone-vm-agent        Full VM install (proot-distro default; QEMU aarch64 experimental, opt-in)

Consent flags (required for --profile phone-vm-agent):
  --allow-large-download          Consent to multi-GiB downloads
  --allow-vm                      Consent to booting an emulated VM
  --allow-opencode-install        Consent to installing OpenCode inside VM guest
  --allow-metered                 Allow download on metered/cellular data (optional)

Existing flags:
  --allow-third-party-opencode    Allow third-party native opencode install
  --allow-proot-opencode          Allow proot-distro fallback

Examples:
  sh $0 --check
  sh $0 --apply
  sh $0 --apply --profile phone-vm-agent --allow-large-download --allow-vm --allow-opencode-install
HELPEOF
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

# ── Consent validation ──────────────────────────────────────────────────
validate_consent() {
  if [ "$PROFILE" != "phone-vm-agent" ]; then
    return
  fi

  missing=""
  [ "$ALLOW_LARGE_DOWNLOAD" -eq 0 ]   && missing="${missing}  --allow-large-download\n"
  [ "$ALLOW_VM" -eq 0 ]               && missing="${missing}  --allow-vm\n"
  [ "$ALLOW_OPENCODE_INSTALL" -eq 0 ] && missing="${missing}  --allow-opencode-install\n"

  if [ -n "$missing" ]; then
    printf '[FATAL] Profile "phone-vm-agent" requires the following consent flags:\n%s' "$missing" >&2
    printf '  (add --allow-metered for metered/cellular networks)\n' >&2
    exit 1
  fi

  log "Profile: phone-vm-agent — all required consent flags present"
  if [ "$ALLOW_METERED" -eq 1 ]; then
    log "  --allow-metered: metered/cellular downloads permitted"
  fi
}

validate_consent

# ── Resource guardrails (phone-vm-agent only) ───────────────────────────
check_storage_guardrail() {
  [ "$PROFILE" != "phone-vm-agent" ] && return

  # Need at least 6 GiB free for VM artifacts
  free_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
  if [ -z "$free_kb" ] || [ "$free_kb" -lt 6291456 ] 2>/dev/null; then
    if [ -n "$free_kb" ]; then
      free_mb=$((free_kb / 1024))
      die "Insufficient storage: ${free_mb} MiB free, need 6144 MiB (6 GiB)"
    fi
    warn "Cannot check free storage — proceeding anyway"
  else
    free_mb=$((free_kb / 1024))
    log "Storage guardrail: ${free_mb} MiB free (>= 6144 MiB)"
  fi
}

check_battery_guardrail() {
  [ "$PROFILE" != "phone-vm-agent" ] && return

  cap=""
  status=""
  [ -r /sys/class/power_supply/Battery/capacity ] && cap=$(cat /sys/class/power_supply/Battery/capacity 2>/dev/null)
  [ -r /sys/class/power_supply/Battery/status ]   && status=$(cat /sys/class/power_supply/Battery/status 2>/dev/null)

  if [ -n "$cap" ]; then
    if [ "$cap" -lt 30 ] 2>/dev/null && [ "$status" != "Charging" ] && [ "$status" != "Full" ]; then
      die "Battery too low (${cap}%) and not charging. Charge to >= 30% or connect charger."
    fi
    log "Battery guardrail: ${cap}% (status=${status:-unknown})"
  else
    warn "Cannot read battery state — proceeding (best-effort)"
  fi
}

check_network_guardrail() {
  [ "$PROFILE" != "phone-vm-agent" ] && return
  [ "$ALLOW_METERED" -eq 1 ] && return

  if command -v dumpsys >/dev/null 2>&1; then
    metered=$(dumpsys connectivity 2>/dev/null | grep -i 'metered' | head -1 || true)
    case "$metered" in
      *METERED*|*m-metered*|*1*)
        die "Metered network detected. Use --allow-metered to proceed."
        ;;
    esac
  fi
  log "Network guardrail: passed (Wi-Fi assumed or not metered)"
}

# ── Section 1: Android detection ────────────────────────────────────────
ANDROID_SDK=0
ANDROID_RELEASE="unknown"

if [ -n "${UOM_SDK_OVERRIDE:-}" ]; then
  ANDROID_SDK="$UOM_SDK_OVERRIDE"
  ANDROID_RELEASE="test-override"
elif command -v getprop >/dev/null 2>&1; then
  sdk_raw="$(getprop ro.build.version.sdk 2>/dev/null || true)"
  rel_raw="$(getprop ro.build.version.release 2>/dev/null || true)"
  [ -n "$sdk_raw" ] && ANDROID_SDK="$sdk_raw" || true
  [ -n "$rel_raw" ] && ANDROID_RELEASE="$rel_raw" || true
fi

if [ "$ANDROID_SDK" -eq 0 ] 2>/dev/null; then
  if [ -d "/data/data/com.termux" ]; then
    ANDROID_SDK=30
    ANDROID_RELEASE="detected-via-termux"
  fi
fi

log "Android SDK: ${ANDROID_SDK} (Release: ${ANDROID_RELEASE})"

if [ "$ANDROID_SDK" -lt 24 ] 2>/dev/null; then
  die "Android 7.0+ (SDK 24+) required. Current: SDK ${ANDROID_SDK}"
fi

# ── Section 2: Termux detection ─────────────────────────────────────────
IS_TERMUX=0
if [ -n "${PREFIX:-}" ] && [ -d "/data/data/com.termux" ]; then
  IS_TERMUX=1
fi

if [ "$IS_TERMUX" -eq 1 ]; then
  log "Termux environment confirmed (PREFIX=${PREFIX:-unset})"
else
  log "Not running in Termux — some features may not apply"
fi

# ── Section 3: Storage safety (check only — no writes) ──────────────────
check_storage_safety() {
  case "${HOME:-}" in
    /sdcard/*|/sdcard|*/storage/emulated/*)
      warn "HOME is under /sdcard — file permissions may be unreliable."
      warn "Recommended: move project to \$HOME/src/universal-omni-master"
      ;;
    */storage/*)
      warn "HOME is under /storage — may have restrictive mount options."
      ;;
  esac
}

check_storage_safety

# ── Section 4: OpenCode inventory (read-only) ───────────────────────────
OC_VERSION=""
OC_PATH=""
OC_SOURCE="not-found"

inventory_opencode() {
  oc_cmd=""
  if command -v opencode >/dev/null 2>&1; then
    oc_cmd="$(command -v opencode)"
    OC_PATH="$oc_cmd"
  fi

  if [ -z "$oc_cmd" ]; then
    for candidate in \
      "${PREFIX:-}/bin/opencode" \
      "$HOME/.opencode/bin/opencode" \
      "$HOME/bin/opencode" \
      "$HOME/.local/bin/opencode" \
      "$HOME/go/bin/opencode"; do
      if [ -x "$candidate" ]; then
        oc_cmd="$candidate"
        OC_PATH="$candidate"
        break
      fi
    done
  fi

  if [ -z "$oc_cmd" ]; then
    OC_SOURCE="not-found"
    return
  fi

  case "$oc_cmd" in
    */go/bin/*)  OC_SOURCE="go-install" ;;
    */bin/opencode)
      npm_prefix="$(npm_config_loglevel=error npm_config_logfile=/dev/null npm prefix -g 2>/dev/null || true)"
      if [ -n "$npm_prefix" ] && case "$oc_cmd" in "$npm_prefix"*) true ;; *) false ;; esac; then
        OC_SOURCE="npm-global"
      else
        OC_SOURCE="termux-package-or-local"
      fi
      ;;
    *) OC_SOURCE="unknown" ;;
  esac

  OC_VERSION="$(opencode --version 2>/dev/null || opencode -v 2>/dev/null || true)"
  [ -z "$OC_VERSION" ] && OC_VERSION="unknown" || true
}

log "Inventorying opencode..."
inventory_opencode
log "opencode status: source=${OC_SOURCE} version=${OC_VERSION} path=${OC_PATH:-none}"

# ── Section 5: Installation priority (check-only mode) ──────────────────
OC_INSTALL_ACTION="none"
OC_INSTALL_PRIORITY=0

resolve_opencode_install() {
  if [ -n "$OC_PATH" ] && [ "$OC_SOURCE" != "not-found" ]; then
    log "Priority 0: existing verified installation at ${OC_PATH}"
    OC_INSTALL_ACTION="none"
    OC_INSTALL_PRIORITY=0
    return
  fi

  if [ "$MODE" != "apply" ]; then
    if command -v pkg >/dev/null 2>&1; then
      log "Priority 1: Termux package 'opencode' available (run --apply to install)"
    elif command -v npm >/dev/null 2>&1; then
      log "Priority 2: npm opencode-ai available (run --apply to install)"
    else
      log "No local install path available."
    fi
    OC_INSTALL_ACTION="not-resolved"
    return
  fi

  # Priority 1: Termux package (apply mode only)
  if command -v pkg >/dev/null 2>&1 && [ "$SKIP_PACKAGES" -eq 0 ]; then
    log "Priority 1: attempting Termux package install..."
    if pkg install -y opencode 2>/dev/null; then
      OC_INSTALL_ACTION="termux-pkg"
      OC_INSTALL_PRIORITY=1
      inventory_opencode
      return
    fi
  fi

  # Priority 2: npm (apply mode only)
  if command -v npm >/dev/null 2>&1 && [ "$SKIP_PACKAGES" -eq 0 ]; then
    log "Priority 2: attempting npm install of opencode-ai..."
    if npm install -g opencode-ai 2>/dev/null; then
      OC_INSTALL_ACTION="npm-global"
      OC_INSTALL_PRIORITY=2
      inventory_opencode
      return
    fi
  fi

  # Priority 3: Go install from archived-but-available OSS repo
  if command -v go >/dev/null 2>&1; then
    log "Priority 3: attempting go install of opencode-ai/opencode..."
    if go install github.com/opencode-ai/opencode@latest 2>/dev/null; then
      OC_INSTALL_ACTION="go-install"
      OC_INSTALL_PRIORITY=3
      inventory_opencode
      return
    fi
  fi

  # Priority 4: opencode.ai official install script (works without Go/npm)
  log "Priority 4: attempting opencode.ai remote installer..."
  if curl -fsSL https://opencode.ai/install 2>/dev/null | sh 2>/dev/null; then
    OC_INSTALL_ACTION="remote-installer"
    OC_INSTALL_PRIORITY=4
    inventory_opencode
    return
  fi

  # Priority 5: exhausted
  log "Priority 5: all install methods exhausted."
  OC_INSTALL_ACTION="failed"
  OC_INSTALL_PRIORITY=5
}

resolve_opencode_install

# ── Run resource guardrails ──────────────────────────────────────────────
check_storage_guardrail
check_battery_guardrail
check_network_guardrail

# ── Architecture detection (experimental QEMU for aarch64 only) ──────────
UOM_ARCH="$(uname -m 2>/dev/null || echo 'unknown')"
DEFAULT_VM_BACKEND="proot"
case "$UOM_ARCH" in
  aarch64|arm64)
    QEMU_ARCH_OK=1
    QEMU_BIN="qemu-system-aarch64"
    VM_BACKEND_MESSAGE="proot-distro (default) or QEMU aarch64 (experimental, opt-in)"
    ;;
  *)
    QEMU_ARCH_OK=0
    QEMU_BIN=""
    VM_BACKEND_MESSAGE="unsupported on this architecture"
    ;;
esac

# ── Section 6: Companion packages ───────────────────────────────────────
COMPANION_PKGS="tmux openssh git jq curl autossh fzf"
if [ "$PROFILE" = "phone-vm-agent" ]; then
  if [ "$QEMU_ARCH_OK" -eq 1 ]; then
    COMPANION_PKGS="$COMPANION_PKGS $QEMU_BIN tar ca-certificates proot-distro"
  else
    warn "Architecture $UOM_ARCH not supported for phone-vm-agent QEMU backend"
    warn "  phone-vm-agent on this device will use proot-distro fallback only"
    COMPANION_PKGS="$COMPANION_PKGS proot-distro"
  fi
fi

install_companion_pkgs() {
  if [ "$MODE" != "apply" ]; then
    log "Companion packages would be installed: ${COMPANION_PKGS}"
    if [ "$PROFILE" = "phone-vm-agent" ]; then
      log "  (VM profile: backend=${VM_BACKEND_MESSAGE})"
    fi
    log "  (run --apply to install)"
    return
  fi

  if ! command -v pkg >/dev/null 2>&1; then
    warn "pkg not available — cannot install companion packages"
    return
  fi

  log "Installing companion packages..."
  _PKG_UPDATE_OK=0
  _RETRIES=3
  while [ "$_RETRIES" -gt 0 ] && [ "$_PKG_UPDATE_OK" -eq 0 ]; do
    if timeout 60 pkg update -y >/dev/null 2>&1; then
      _PKG_UPDATE_OK=1
    else
      _RETRIES=$((_RETRIES - 1))
      [ "$_RETRIES" -gt 0 ] && warn "pkg update failed, retrying (${_RETRIES} left)..."
      sleep 2
    fi
  done
  [ "$_PKG_UPDATE_OK" -eq 0 ] && warn "pkg update failed after 3 attempts — continuing anyway"

  for pkg_name in $COMPANION_PKGS; do
    if command -v "$pkg_name" >/dev/null 2>&1; then
      log "  ${pkg_name}: already installed"
      continue
    fi
    if pkg install -y "$pkg_name" >/dev/null 2>&1; then
      log "  ${pkg_name}: installed"
    else
      warn "  ${pkg_name}: install failed (non-critical)"
    fi
  done
}

install_companion_pkgs

# ── Section 7: SSH key generation ───────────────────────────────────────
ssh_key_generated=0
SSHD_USER="${UOM_SSH_USER:-$(whoami 2>/dev/null || echo "uom")}"

ensure_ssh_key() {
  _KEY_PATH="${INSTALL_DIR:+${TEST_ROOT:-}/}${HOME}/.ssh/id_ed25519_uom"
  # For test-root mode, redirect key into test root
  if [ "$_USE_TEST_ROOT" -eq 1 ]; then
    _KEY_DIR="${TEST_ROOT}${HOME}/.ssh"
    mkdir -p "$_KEY_DIR"
    _KEY_PATH="${_KEY_DIR}/id_ed25519_uom"
  else
    _KEY_DIR="$HOME/.ssh"
    mkdir -p "$_KEY_DIR" 2>/dev/null || true
    _KEY_PATH="${_KEY_DIR}/id_ed25519_uom"
  fi

  if [ -f "$_KEY_PATH" ]; then
    log "SSH key already exists: $_KEY_PATH"
    return
  fi

  if [ "$MODE" != "apply" ]; then
    log "SSH key generation pending (run --apply to generate)"
    return
  fi

  mkdir -p "$_KEY_DIR"
  chmod 700 "$_KEY_DIR"

  log "Generating ed25519 SSH key..."
  ssh-keygen -t ed25519 -f "$_KEY_PATH" -N "" -C "uom-phone-$(date +%Y%m%d)" 2>/dev/null || {
    warn "ssh-keygen failed"
    return
  }
  chmod 600 "$_KEY_PATH"
  ssh_key_generated=1

  printf '\n'
  log "=== ADD THIS PUBLIC KEY TO LAPTOP ==="
  log "Run on laptop:"
  log "  echo '$(cat "${_KEY_PATH}.pub")' >> ~/.ssh/authorized_keys"
  log "====================================="
  printf '\n'
}

ensure_ssh_key

# ── Section 8: SSH config (managed block, not overwrite) ────────────────
ssh_config_written=0
_SSH_CONFIG_TMP=""

install_ssh_config() {
  if [ "$MODE" != "apply" ]; then
    log "SSH config pending (run --apply to write)"
    return
  fi

  _TARGET="${TEST_ROOT:-}${HOME}/.ssh/config"
  _BACKUP="${_TARGET}.bak.$(date +%Y%m%d%H%M%S)"

  mkdir -p "$(dirname "$_TARGET")"

  # Check if managed block already exists
  if [ -f "$_TARGET" ] && grep -q '# UOM-MANAGED-BEGIN' "$_TARGET" 2>/dev/null; then
    log "SSH config already has UOM managed block"
    return
  fi

  # Backup existing config
  if [ -f "$_TARGET" ]; then
    cp "$_TARGET" "$_BACKUP"
    log "Backed up existing SSH config to $_BACKUP"
  fi

  # Append managed block instead of replacing
  {
    if [ -f "$_TARGET" ]; then
      cat "$_TARGET"
    fi
    cat << SSHEOF

# UOM-MANAGED-BEGIN — do not edit between these markers
Host uom-phone-local
  HostName 127.0.0.1
  Port ${SSHD_PORT}
  User ${SSHD_USER}
  IdentityFile ~/.ssh/id_ed25519_uom
  ServerAliveInterval 30
  ServerAliveCountMax 3
  StrictHostKeyChecking accept-new

Host uom-phone-tunnel
  HostName 127.0.0.1
  Port ${TUNNEL_PORT}
  User ${SSHD_USER}
  IdentityFile ~/.ssh/id_ed25519_uom
  ServerAliveInterval 30
  ServerAliveCountMax 3
  StrictHostKeyChecking accept-new
# UOM-MANAGED-END
SSHEOF
  } > "$_TARGET"
  chmod 600 "$_TARGET"
  ssh_config_written=1
  log "SSH config updated (managed block appended)"
}

install_ssh_config

# ── Section 8b: Network gate ─────────────────────────────────────────────
REPO_STATE="unknown"
check_network_gate() {
  _REACHABLE=0
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 5 "https://github.com" >/dev/null 2>&1; then
      _REACHABLE=1
    fi
  fi
  if [ "$_REACHABLE" -eq 1 ]; then
    REPO_STATE="reachable"
    log "Network gate: github reachable"
  else
    REPO_STATE="skipped-network"
    warn "Network gate: github unreachable — repo clone will be skipped"
    if [ "$PROFILE" = "phone-relay" ]; then
      log "  phone-relay can continue without repo (SSH/tmux/keys still set up)"
    fi
  fi
}
check_network_gate

# ── Section 9: Repository clone/update ──────────────────────────────────
repo_action="none"

ensure_repo() {
  if [ "$REPO_STATE" = "skipped-network" ]; then
    log "Network unreachable — skipping repo clone"
    repo_action="skipped-network"
    return
  fi
  if [ "$_USE_TEST_ROOT" -eq 1 ]; then
    _REPO_DIR="${TEST_ROOT}${UOM_DIR_DEFAULT}"
  else
    _REPO_DIR="$UOM_DIR_DEFAULT"
  fi

  if [ -d "$_REPO_DIR/.git" ]; then
    log "Repository exists at ${_REPO_DIR}"
    if [ "$MODE" = "apply" ]; then
      # Check if dirty
      if ! git -C "$_REPO_DIR" diff --quiet 2>/dev/null; then
        warn "Repository is dirty — skipping pull to avoid data loss"
        warn "  Clean manually: cd $_REPO_DIR && git stash"
        repo_action="dirty-skipped"
        return
      fi
      log "Pulling ${REF}..."
      git -C "$_REPO_DIR" fetch origin "$REF" 2>/dev/null \
        && git -C "$_REPO_DIR" checkout FETCH_HEAD 2>/dev/null \
        || warn "Checkout failed — manual merge may be needed"
      repo_action="updated"
    else
      log "Repository update pending (run --apply to pull)"
      repo_action="update-pending"
    fi
  else
    if [ "$MODE" = "apply" ]; then
      log "Cloning UOM repository (ref: ${REF})..."
      if [ -d "$_REPO_DIR" ] && [ -n "$(ls -A "$_REPO_DIR" 2>/dev/null)" ]; then
        warn "Target $_REPO_DIR exists and is not empty — skipping clone"
        repo_action="exists-skipped"
        return
      fi
      _OWNER_REPO="dharani-sg/universal-omni-master"
      _CLONE_SUCCESS=0
      if git clone --depth 1 "$REPO_URL" "$_REPO_DIR" 2>/dev/null; then
        _CLONE_SUCCESS=1
        if [ -n "$REF" ] && ! git -C "$_REPO_DIR" rev-parse --verify "refs/heads/$REF" 2>/dev/null; then
          git -C "$_REPO_DIR" fetch --depth 1 origin "$REF" 2>/dev/null && \
          git -C "$_REPO_DIR" checkout "$REF" 2>/dev/null || \
          warn "Could not fetch/checkout ref $REF — using default branch"
        fi
      fi
      if [ "$_CLONE_SUCCESS" -eq 0 ]; then
        warn "git clone failed — trying tarball fallback"
        _TARBALL_URL="https://codeload.github.com/${_OWNER_REPO}/tar.gz/${REF}"
        _PARENT_DIR="$(dirname "$_REPO_DIR")"
        mkdir -p "$_PARENT_DIR"
        if curl -fsSL "$_TARBALL_URL" -o /tmp/uom-tarball-$$.tar.gz 2>/dev/null; then
          tar xzf "/tmp/uom-tarball-$$.tar.gz" -C "$_PARENT_DIR" 2>/dev/null
          _EXTRACTED=$(ls -d "$_PARENT_DIR/universal-omni-master-"* 2>/dev/null | head -1)
          if [ -n "$_EXTRACTED" ]; then
            mv "$_EXTRACTED" "$_REPO_DIR" 2>/dev/null
            rm -f "/tmp/uom-tarball-$$.tar.gz"
            _CLONE_SUCCESS=1
          fi
        fi
        rm -f "/tmp/uom-tarball-$$.tar.gz" 2>/dev/null || true
      fi
      if [ "$_CLONE_SUCCESS" -eq 0 ]; then
        warn "git clone and tarball fallback both failed"
        return
      fi
      repo_action="cloned"
    else
      log "Repository clone pending (run --apply to clone)"
      repo_action="clone-pending"
    fi
  fi
}

ensure_repo

# ── Section 10: Termux:Boot integration (SDK >= 31) ─────────────────────
boot_script_installed=0

install_termux_boot() {
  if [ "$ANDROID_SDK" -lt 31 ] 2>/dev/null; then
    log "Termux:Boot not applicable (SDK ${ANDROID_SDK} < 31)"
    return
  fi

  if [ "$IS_TERMUX" -ne 1 ]; then
    log "Termux:Boot requires Termux environment"
    return
  fi

  if [ "$MODE" != "apply" ]; then
    log "Termux:Boot script pending (run --apply to install)"
    log "  NOTE: You must also install Termux:Boot plugin from same source as Termux"
    return
  fi

  _BOOT_DIR="${TEST_ROOT:-}${HOME}/.termux/boot"
  mkdir -p "$_BOOT_DIR"

  cat > "$_BOOT_DIR/start-uom.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot auto-start for UOM
# Starts: sshd, reverse tunnel, port guardian, tmux watchdog, phone orchestrator
# QEMU watchdog is auto-started by uom-qemu-phone when QEMU launches

UOM_DIR="${HOME}/src/universal-omni-master"

sleep 30

# 1. SSH daemon
if command -v sshd >/dev/null 2>&1; then
  sshd 2>/dev/null || true
fi

# 2. Reverse SSH tunnel (laptop → phone)
cd "$UOM_DIR" 2>/dev/null && \
  sh bin/uom-reverse-ssh.sh start &>/dev/null &

# 3. Port guardian (IP/port drift detection)
cd "$UOM_DIR" 2>/dev/null && \
  sh bin/uom-port-guardian.sh start &>/dev/null &

# 4. Tmux watchdog (session/process recovery)
cd "$UOM_DIR" 2>/dev/null && \
  nohup sh orchestrators/uom-tmux-watchdog.sh --daemon &>/dev/null &

# 5. Phone orchestrator (task execution)
cd "$UOM_DIR" 2>/dev/null && \
  nohup sh tools/uom-orch-phone.sh &>/dev/null &
BOOTEOF

  chmod 700 "$_BOOT_DIR/start-uom.sh"
  boot_script_installed=1
  log "Termux:Boot script installed at ${_BOOT_DIR}/start-uom.sh"
  log "  IMPORTANT: Install Termux:Boot plugin and launch it once to activate."
}

install_termux_boot

# ── Section 11: Record install metadata ─────────────────────────────────
record_metadata() {
  if [ "$MODE" != "apply" ]; then
    log "Metadata recording pending (run --apply)"
    return
  fi

  if [ "$_USE_TEST_ROOT" -eq 1 ]; then
    _META_DIR="${TEST_ROOT}${UOM_DIR_DEFAULT}/.uom-agent"
  else
    _META_DIR="${UOM_DIR_DEFAULT}/.uom-agent"
  fi

  mkdir -p "$_META_DIR"

  _META_FILE="${_META_DIR}/opencode-install.json"

  # Build JSON using json_escape (POSIX-safe)
  cat > "$_META_FILE" << METAEOF
{
  "schema": 1,
  "timestamp": "$(json_escape "$(now)")",
  "android_sdk": ${ANDROID_SDK},
  "android_release": "$(json_escape "${ANDROID_RELEASE}")",
  "is_termux": ${IS_TERMUX},
  "profile": "${PROFILE}",
  "opencode_source": "${OC_SOURCE}",
  "opencode_version": "${OC_VERSION}",
  "opencode_path": "${OC_PATH}",
  "opencode_priority": ${OC_INSTALL_PRIORITY},
  "opencode_action": "$(json_escape "${OC_INSTALL_ACTION}")",
  "ssh_key_generated": ${ssh_key_generated},
  "ssh_port": ${SSHD_PORT},
  "tunnel_port": ${TUNNEL_PORT},
  "repo_action": "$(json_escape "${repo_action}")",
  "boot_script_installed": ${boot_script_installed},
  "profile": "$(json_escape "${PROFILE}")",
  "ref": "$(json_escape "${REF}")",
  "test_root": "$(json_escape "${TEST_ROOT}")",
  "mode": "$(json_escape "${MODE}")"
}
METAEOF

  log "Install metadata recorded at ${_META_FILE}"
}

record_metadata

# ── Section 12: Verify mode ─────────────────────────────────────────────
run_verify() {
  printf '\n=== UOM INSTALL VERIFICATION ===\n'
  _FAILURES=0

  # Check SSH key
  _KEY="${TEST_ROOT:-}${HOME}/.ssh/id_ed25519_uom"
  if [ -f "$_KEY" ]; then
    log "SSH key: PASS ($_KEY)"
  else
    warn "SSH key: MISSING"
    _FAILURES=$((_FAILURES + 1))
  fi

  # Check SSH config managed block
  _CONF="${TEST_ROOT:-}${HOME}/.ssh/config"
  if [ -f "$_CONF" ] && grep -q 'UOM-MANAGED-BEGIN' "$_CONF" 2>/dev/null; then
    log "SSH config: PASS (managed block present)"
  else
    warn "SSH config: MISSING managed block"
    _FAILURES=$((_FAILURES + 1))
  fi

  # Check repository
  _REPO="${TEST_ROOT:-}${UOM_DIR_DEFAULT}"
  if [ -d "$_REPO/.git" ]; then
    log "Repository: PASS ($_REPO)"
  else
    warn "Repository: MISSING"
    _FAILURES=$((_FAILURES + 1))
  fi

  # Check companion packages
  for pkg_name in tmux openssh git jq curl; do
    if command -v "$pkg_name" >/dev/null 2>&1; then
      log "Package ${pkg_name}: PASS"
    else
      warn "Package ${pkg_name}: MISSING"
      _FAILURES=$((_FAILURES + 1))
    fi
  done

  # Check Termux:Boot
  if [ "$ANDROID_SDK" -ge 31 ] 2>/dev/null; then
    _BOOT="${TEST_ROOT:-}${HOME}/.termux/boot/start-uom.sh"
    if [ -f "$_BOOT" ]; then
      log "Termux:Boot: PASS (script present)"
    else
      warn "Termux:Boot: NOT INSTALLED"
    fi
  fi

  # Check metadata
  _META="${TEST_ROOT:-}${UOM_DIR_DEFAULT}/.uom-agent/opencode-install.json"
  if [ -f "$_META" ]; then
    log "Metadata: PASS ($_META)"
  else
    warn "Metadata: MISSING"
  fi

  if [ "$_FAILURES" -eq 0 ]; then
    printf '\nVERIFY_PASS\n'
    return 0
  else
    printf '\nVERIFY_FAIL (%d issues)\n' "$_FAILURES"
    return 1
  fi
}

if [ "$MODE" = "verify" ]; then
  run_verify
  exit $?
fi

# ── Section 13: Rollback ────────────────────────────────────────────────
run_rollback() {
  log "Rolling back installer-owned changes..."
  # Remove SSH managed block
  _CONF="${TEST_ROOT:-}${HOME}/.ssh/config"
  if [ -f "$_CONF" ] && grep -q 'UOM-MANAGED-BEGIN' "$_CONF" 2>/dev/null; then
    # Extract everything outside the managed block
    sed '/# UOM-MANAGED-BEGIN/,/# UOM-MANAGED-END/d' "$_CONF" > "${_CONF}.rollback"
    mv "${_CONF}.rollback" "$_CONF"
    log "Removed UOM managed SSH block"
  fi

  # Remove boot script
  _BOOT="${TEST_ROOT:-}${HOME}/.termux/boot/start-uom.sh"
  if [ -f "$_BOOT" ]; then
    rm -f "$_BOOT"
    log "Removed Termux:Boot script"
  fi

  # Restore SSH config backup if exists
  _BACKUP=$(ls -t "${TEST_ROOT:-}${HOME}/.ssh/config.bak."* 2>/dev/null | head -1)
  if [ -n "$_BACKUP" ] && [ -f "$_BACKUP" ]; then
    cp "$_BACKUP" "$_CONF"
    log "Restored SSH config from $_BACKUP"
  fi

  log "Rollback complete. Repository and SSH keys NOT removed (manual cleanup required)."
  printf '\nROLLED_BACK\n'
}

if [ "$MODE" = "apply" ] && [ "$ROLLBACK" -eq 1 ]; then
  run_rollback
  cleanup
  exit 0
fi

# ── Section 14: Summary ─────────────────────────────────────────────────
printf '\n'
printf '=== UOM BOOTSTRAP SUMMARY ===\n'
printf 'Mode:          %s\n' "$MODE"
printf 'Profile:       %s\n' "$PROFILE"
printf 'Android:       %s (SDK %s)\n' "$ANDROID_RELEASE" "$ANDROID_SDK"
printf 'Termux:        %s\n' "$([ "$IS_TERMUX" -eq 1 ] && echo 'yes' || echo 'no')"
printf 'opencode:      %s (source=%s, path=%s)\n' "$OC_VERSION" "$OC_SOURCE" "${OC_PATH:-none}"
printf 'Install prio:  %s (action=%s)\n' "$OC_INSTALL_PRIORITY" "$OC_INSTALL_ACTION"

if [ "$MODE" = "apply" ]; then
  printf 'SSH key:       %s\n' "$([ "$ssh_key_generated" -eq 1 ] && echo 'generated' || echo 'existing-or-pending')"
  printf 'SSH config:    %s\n' "$([ "$ssh_config_written" -eq 1 ] && echo 'written' || echo 'existing-or-pending')"
  printf 'Repo:          %s\n' "$repo_action"
  printf 'Termux:Boot:   %s\n' "$([ "$boot_script_installed" -eq 1 ] && echo 'installed' || echo 'skipped-or-pending')"
fi

printf '\n=== VERIFICATION STEPS ===\n'
if [ "$MODE" = "apply" ]; then
  printf '  1. opencode --version\n'
  printf '  2. ssh -p %d localhost echo ok  (test sshd)\n' "$SSHD_PORT"
  printf '  3. tmux new -s uom\n'
  printf '  4. cd %s && sh bin/uom-status.sh\n' "$UOM_DIR_DEFAULT"
  if [ "$PROFILE" = "phone-vm-agent" ]; then
    printf '  5. sh bin/uom-vm-status.sh      (check VM status)\n'
  fi
else
  printf '  This was a dry run (--check). To apply changes:\n'
  printf '    sh %s --apply --verify\n' "$0"
  if [ "$ALLOW_THIRD_PARTY" -eq 0 ]; then
    printf '  Add --allow-third-party-opencode to enable third-party installs\n'
  fi
  if [ "$ALLOW_PROOT" -eq 0 ]; then
    printf '  Add --allow-proot-opencode to enable proot-distro fallback\n'
  fi
  if [ "$PROFILE" = "phone-vm-agent" ]; then
    printf '  Add --allow-large-download --allow-vm --allow-opencode-install for VM profile consent\n'
  fi
fi

printf '\n=== QUICK COMMANDS ===\n'
printf '  sh bin/uom-status.sh         — Check all services\n'
printf '  sh bin/uom-status.sh tunnel  — Check tunnel status\n'
printf '  tmux new -s uom              — Start tmux session\n'
if [ "$PROFILE" = "phone-vm-agent" ]; then
  printf '  sh bin/uom-vm-start.sh     — Start QEMU VM\n'
  printf '  sh bin/uom-vm-stop.sh      — Stop QEMU VM\n'
  printf '  sh bin/uom-vm-status.sh    — Check VM status\n'
  printf '  sh bin/uom-vm-ssh.sh       — SSH into VM guest\n'
fi
printf '\n'

cleanup
