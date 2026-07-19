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
UOM_REPO="https://github.com/dharani-sg/universal-omni-master.git"
UOM_DIR="$HOME/src/universal-omni-master"
UOM_AGENT_DIR="$UOM_DIR/.uom-agent"
INSTALL_META="$UOM_AGENT_DIR/opencode-install.json"
SSHD_PORT=8022
TUNNEL_PORT=31415

# ── Helpers ──────────────────────────────────────────────────────────────
log()  { printf '[*] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[FATAL] %s\n' "$*" >&2; exit 1; }
now()  { date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'; }

# ── Parse arguments ──────────────────────────────────────────────────────
MODE="check"
PROFILE="phone-relay"
ALLOW_THIRD_PARTY=0
ALLOW_PROOT=0
ALLOW_VM=0
ALLOW_LARGE_DOWNLOAD=0
ALLOW_OPENCODE_INSTALL=0
ALLOW_METERED=0

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
  --profile phone-vm-agent        Full QEMU + Alpine VM install (requires consent flags below)

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

if command -v getprop >/dev/null 2>&1; then
  sdk_raw="$(getprop ro.build.version.sdk 2>/dev/null || true)"
  rel_raw="$(getprop ro.build.version.release 2>/dev/null || true)"
  [ -n "$sdk_raw" ] && ANDROID_SDK="$sdk_raw"
  [ -n "$rel_raw" ] && ANDROID_RELEASE="$rel_raw"
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

# ── Section 3: Storage safety ───────────────────────────────────────────
check_storage_safety() {
  case "$HOME" in
    /sdcard/*|/sdcard|*/storage/emulated/*)
      warn "HOME is under /sdcard — file permissions may be unreliable."
      warn "Recommended: move project to \$HOME/src/universal-omni-master"
      ;;
    */storage/*)
      warn "HOME is under /storage — may have restrictive mount options."
      warn "Recommended: move project to \$HOME/src/universal-omni-master"
      ;;
  esac
}

storage_warned=0
check_storage_safety

# ── Section 4: OpenCode inventory ───────────────────────────────────────
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
    # Check common non-PATH locations
    for candidate in \
      "$PREFIX/bin/opencode" \
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

  # Determine source
  case "$oc_cmd" in
    */go/bin/*)  OC_SOURCE="go-install" ;;
    */bin/opencode)
      # Check if from npm
      npm_prefix="$(npm prefix -g 2>/dev/null || true)"
      if [ -n "$npm_prefix" ] && case "$oc_cmd" in "$npm_prefix"*) true ;; *) false ;; esac; then
        OC_SOURCE="npm-global"
      else
        OC_SOURCE="termux-package-or-local"
      fi
      ;;
    *) OC_SOURCE="unknown" ;;
  esac

  # Version
  OC_VERSION="$(opencode --version 2>/dev/null || opencode -v 2>/dev/null || true)"
  if [ -z "$OC_VERSION" ]; then
    OC_VERSION="unknown"
  fi

  # Check if binary is actually functional
  if ! opencode help >/dev/null 2>&1 && ! opencode --help >/dev/null 2>&1; then
    warn "opencode found at ${oc_cmd} but help fails — may be broken"
  fi
}

log "Inventorying opencode..."
inventory_opencode
log "opencode status: source=${OC_SOURCE} version=${OC_VERSION} path=${OC_PATH:-none}"

# ── Section 5: Installation priority ────────────────────────────────────
# P0: already installed and functional
# P1: Termux pkg
# P2: npm opencode-ai (if metadata supports Android)
# P3: third-party native (requires --allow-third-party-opencode)
# P4: proot-distro (requires --allow-proot-opencode)
# P5: remote laptop fallback (document only)

resolve_opencode_install() {
  if [ -n "$OC_PATH" ] && [ "$OC_SOURCE" != "not-found" ]; then
    log "Priority 0: existing verified installation at ${OC_PATH}"
    OC_INSTALL_ACTION="none"
    OC_INSTALL_PRIORITY=0
    return
  fi

  # Priority 1: Termux package
  if command -v pkg >/dev/null 2>&1; then
    if [ "$MODE" = "apply" ]; then
      log "Priority 1: attempting Termux package install..."
      if pkg install -y opencode 2>/dev/null; then
        OC_INSTALL_ACTION="termux-pkg"
        OC_INSTALL_PRIORITY=1
        inventory_opencode
        return
      fi
    else
      log "Priority 1: Termux package 'opencode' available (run --apply to install)"
      OC_INSTALL_ACTION="termux-pkg-pending"
      OC_INSTALL_PRIORITY=1
      return
    fi
  fi

  # Priority 2: npm opencode-ai
  if command -v npm >/dev/null 2>&1; then
    if [ "$MODE" = "apply" ]; then
      log "Priority 2: attempting npm install of opencode-ai..."
      if npm install -g opencode-ai 2>/dev/null; then
        OC_INSTALL_ACTION="npm-global"
        OC_INSTALL_PRIORITY=2
        inventory_opencode
        return
      fi
    else
      log "Priority 2: npm opencode-ai available (run --apply to install)"
      OC_INSTALL_ACTION="npm-global-pending"
      OC_INSTALL_PRIORITY=2
      return
    fi
  fi

  # Priority 3: third-party native (requires flag)
  if [ "$ALLOW_THIRD_PARTY" -eq 1 ]; then
    if [ "$MODE" = "apply" ]; then
      warn "Priority 3: third-party native install requested but no verified method available."
      warn "Download from https://github.com/anomalyco/opencode/releases and verify manually."
    else
      log "Priority 3: third-party native — requires --allow-third-party-opencode and --apply"
    fi
    OC_INSTALL_ACTION="third-party-manual"
    OC_INSTALL_PRIORITY=3
    return
  fi

  # Priority 4: proot-distro (requires flag)
  if [ "$ALLOW_PROOT" -eq 1 ]; then
    if [ "$IS_TERMUX" -eq 1 ] && command -v proot-distro >/dev/null 2>&1; then
      if [ "$MODE" = "apply" ]; then
        log "Priority 4: proot-distro fallback — install Ubuntu/Debian, then opencode inside"
        warn "proot-distro is slow. Prefer native methods."
      else
        log "Priority 4: proot-distro fallback available (run --apply to set up)"
      fi
      OC_INSTALL_ACTION="proot-distro"
      OC_INSTALL_PRIORITY=4
      return
    fi
  fi

  # Priority 5: document remote fallback
  log "Priority 5: no local install path succeeded."
  log "  Use reverse SSH tunnel to run opencode on laptop:"
  log "    ssh -R 31415:localhost:31415 alpine@<laptop-ip>"
  OC_INSTALL_ACTION="remote-fallback"
  OC_INSTALL_PRIORITY=5
}

resolve_opencode_install

# ── Run resource guardrails ──────────────────────────────────────────────
check_storage_guardrail
check_battery_guardrail
check_network_guardrail

# ── Section 6: Companion packages ───────────────────────────────────────
COMPANION_PKGS="tmux openssh git jq curl autossh fzf"
[ "$PROFILE" = "phone-vm-agent" ] && COMPANION_PKGS="$COMPANION_PKGS qemu-system-x86_64 tar ca-certificates"

install_companion_pkgs() {
  if [ "$MODE" != "apply" ]; then
    log "Companion packages would be installed: ${COMPANION_PKGS}"
    if [ "$PROFILE" = "phone-vm-agent" ]; then
      log "  (VM profile: includes QEMU, tar, ca-certificates)"
    fi
    log "  (run --apply to install)"
    return
  fi

  if ! command -v pkg >/dev/null 2>&1; then
    warn "pkg not available — cannot install companion packages"
    return
  fi

  log "Installing companion packages..."
  pkg update -y >/dev/null 2>&1 || true

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

ensure_ssh_key() {
  if [ -f "$HOME/.ssh/id_ed25519" ]; then
    log "SSH key already exists: $HOME/.ssh/id_ed25519"
    return
  fi

  if [ "$MODE" != "apply" ]; then
    log "SSH key generation pending (run --apply to generate)"
    return
  fi

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  log "Generating ed25519 SSH key..."
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "uom-phone-$(date +%Y%m%d)" 2>/dev/null || {
    warn "ssh-keygen failed"
    return
  }
  chmod 600 "$HOME/.ssh/id_ed25519"
  ssh_key_generated=1

  printf '\n'
  log "=== ADD THIS PUBLIC KEY TO LAPTOP ==="
  log "Run on laptop:"
  log "  echo '$(cat "$HOME/.ssh/id_ed25519.pub")' >> ~/.ssh/authorized_keys"
  log "====================================="
  printf '\n'
}

ensure_ssh_key

# ── Section 8: SSH config ───────────────────────────────────────────────
ssh_config_written=0

install_ssh_config() {
  if [ "$MODE" != "apply" ]; then
    log "SSH config pending (run --apply to write)"
    return
  fi

  mkdir -p "$HOME/.ssh"

  # Only write if not present or different
  if [ -f "$HOME/.ssh/config" ]; then
    if grep -q 'Port 8022' "$HOME/.ssh/config" 2>/dev/null; then
      log "SSH config already has port ${SSHD_PORT}"
      return
    fi
    warn "Existing SSH config found — backing up to $HOME/.ssh/config.bak"
    cp "$HOME/.ssh/config" "$HOME/.ssh/config.bak"
  fi

  cat > "$HOME/.ssh/config" << SSHEOF
Host uom-phone-local
  HostName 127.0.0.1
  Port ${SSHD_PORT}
  User alpine
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 30
  ServerAliveCountMax 3
  StrictHostKeyChecking no

Host uom-phone-tunnel
  HostName 127.0.0.1
  Port ${TUNNEL_PORT}
  User alpine
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 30
  ServerAliveCountMax 3
  StrictHostKeyChecking no

Host uom-laptop-lan
  HostName 192.168.40.90
  Port 22
  User alpine
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 30

Host uom-laptop-mdns
  HostName hp-pavilion.local
  Port 22
  User alpine
  IdentityFile ~/.ssh/id_ed25519
SSHEOF

  chmod 600 "$HOME/.ssh/config"
  ssh_config_written=1
  log "SSH config written (port ${SSHD_PORT})"
}

install_ssh_config

# ── Section 9: Repository clone/update ──────────────────────────────────
repo_action="none"

ensure_repo() {
  mkdir -p "$HOME/src"

  if [ -d "$UOM_DIR/.git" ]; then
    log "Repository exists at ${UOM_DIR}"
    if [ "$MODE" = "apply" ]; then
      log "Pulling latest..."
      git -C "$UOM_DIR" pull --ff-only 2>/dev/null || warn "Pull failed — manual merge may be needed"
      repo_action="updated"
    else
      log "Repository update pending (run --apply to pull)"
      repo_action="update-pending"
    fi
  else
    if [ "$MODE" = "apply" ]; then
      log "Cloning UOM repository..."
      git clone "$UOM_REPO" "$UOM_DIR" 2>/dev/null || {
        warn "git clone failed"
        return
      }
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
    return
  fi

  boot_dir="$HOME/.termux/boot"
  mkdir -p "$boot_dir"

  cat > "$boot_dir/start-uom.sh" << 'BOOTEOF'
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

  chmod 700 "$boot_dir/start-uom.sh"
  boot_script_installed=1
  log "Termux:Boot script installed at ${boot_dir}/start-uom.sh"
}

install_termux_boot

# ── Section 11: Record install metadata ─────────────────────────────────
record_metadata() {
  if [ "$MODE" != "apply" ]; then
    log "Metadata recording pending (run --apply)"
    return
  fi

  mkdir -p "$UOM_AGENT_DIR"

  # Build JSON without jq dependency
  cat > "$INSTALL_META" << METAEOF
{
  "schema": 1,
  "timestamp": "$(now)",
  "android_sdk": ${ANDROID_SDK},
  "android_release": "${ANDROID_RELEASE}",
  "is_termux": ${IS_TERMUX},
  "profile": "${PROFILE}",
  "opencode_source": "${OC_SOURCE}",
  "opencode_version": "${OC_VERSION}",
  "opencode_path": "${OC_PATH}",
  "opencode_priority": ${OC_INSTALL_PRIORITY},
  "opencode_action": "${OC_INSTALL_ACTION}",
  "ssh_key_generated": ${ssh_key_generated},
  "ssh_port": ${SSHD_PORT},
  "tunnel_port": ${TUNNEL_PORT},
  "repo_action": "${repo_action}",
  "boot_script_installed": ${boot_script_installed},
  "mode": "apply"
}
METAEOF

  log "Install metadata recorded at ${INSTALL_META}"
}

record_metadata

# ── Section 12: Summary ─────────────────────────────────────────────────
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
  printf 'Metadata:      %s\n' "$INSTALL_META"
fi

printf '\n=== VERIFICATION STEPS ===\n'
if [ "$MODE" = "apply" ]; then
  printf '  1. opencode --version\n'
  printf '  2. ssh -p %d localhost echo ok  (test sshd)\n' "$SSHD_PORT"
  printf '  3. tmux new -s uom\n'
  printf '  4. cd %s && sh bin/uom-status.sh\n' "$UOM_DIR"
  if [ "$PROFILE" = "phone-vm-agent" ]; then
    printf '  5. sh bin/uom-vm-status.sh      (check VM status)\n'
  fi
else
  printf '  This was a dry run (--check). To apply changes:\n'
  printf '    sh %s --apply\n' "$0"
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
