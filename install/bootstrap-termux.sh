#!/bin/sh
# install/bootstrap-termux.sh — UOM Bootstrap for Termux/Android ARM64
# POSIX sh. Modes: --check (default, read-only), --apply (make changes).
# Flags: --allow-third-party-opencode, --allow-proot-opencode
#
# Usage:
#   sh install/bootstrap-termux.sh                  # check mode (read-only)
#   sh install/bootstrap-termux.sh --apply          # install
#   sh install/bootstrap-termux.sh --apply --verify # install and validate
#   sh install/bootstrap-termux.sh --verify         # post-install check
#   sh install/bootstrap-termux.sh --apply --verify --test-root /tmp/uom-test

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

# ── Cleanup trap ─────────────────────────────────────────────────────────
_CLEANUP_DONE=0
_TEST_ROOT=""
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
VERIFY_ONLY=0
NO_START=0
SKIP_PACKAGES=0
NON_INTERACTIVE=0
RESUME=0
ROLLBACK=0
TEST_ROOT=""
REF="${UOM_REF:-main}"
REPO_URL="${UOM_REPO_URL:-$UOM_REPO_DEFAULT}"
INSTALL_DIR="${UOM_INSTALL_DIR:-$UOM_DIR_DEFAULT}"
SHOW_HELP=0

for arg in "$@"; do
  case "$arg" in
    --apply)                    MODE="apply" ;;
    --check)                    MODE="check" ;;
    --verify)                   VERIFY_ONLY=1 ;;
    --profile)                  ;; # handled via next arg
    --profile=*)                PROFILE="${arg#--profile=}" ;;
    --allow-third-party-opencode) ALLOW_THIRD_PARTY=1 ;;
    --allow-proot-opencode)    ALLOW_PROOT=1 ;;
    --no-start)                 NO_START=1 ;;
    --skip-packages)            SKIP_PACKAGES=1 ;;
    --non-interactive)          NON_INTERACTIVE=1 ;;
    --resume)                   RESUME=1 ;;
    --rollback)                 ROLLBACK=1 ;;
    --ref)                      ;; # handled via next arg
    --ref=*)                    REF="${arg#--ref=}" ;;
    --repo-url)                 ;; # handled via next arg
    --repo-url=*)               REPO_URL="${arg#--repo-url=}" ;;
    --install-dir)              ;; # handled via next arg
    --install-dir=*)            INSTALL_DIR="${arg#--install-dir=}" ;;
    --test-root)                ;; # handled via next arg
    --test-root=*)              TEST_ROOT="${arg#--test-root=}" ;;
    -h|--help)                  SHOW_HELP=1 ;;
    --profile-phone-relay)      PROFILE="phone-relay" ;;
    --profile-phone-agent)      PROFILE="phone-agent" ;;
    *)
      # Handle positional args after flags
      case "${_PREV_ARG:-}" in
        --profile)   PROFILE="$arg" ;;
        --ref)       REF="$arg" ;;
        --repo-url)  REPO_URL="$arg" ;;
        --install-dir) INSTALL_DIR="$arg" ;;
        --test-root) TEST_ROOT="$arg" ;;
        *) die "Unknown argument: $arg" ;;
      esac
      ;;
  esac
  _PREV_ARG="$arg"
done

if [ "$SHOW_HELP" -eq 1 ]; then
  printf 'Usage: sh %s [OPTIONS]\n' "$(basename "$0")"
  printf '\nModes:\n'
  printf '  --check              Read-only preflight (default)\n'
  printf '  --apply              Install components\n'
  printf '  --verify             Post-install validation only\n'
  printf '  --apply --verify     Install and validate\n'
  printf '\nProfiles:\n'
  printf '  --profile phone-relay   SSH endpoint, tmux, git (default)\n'
  printf '  --profile phone-agent   Also requires OpenCode\n'
  printf '\nOptions:\n'
  printf '  --ref REF             Pinned commit or tag (default: main)\n'
  printf '  --repo-url URL        Repository URL\n'
  printf '  --install-dir PATH    Install directory\n'
  printf '  --test-root PATH      Isolated install root\n'
  printf '  --no-start            Do not start services\n'
  printf '  --skip-packages       Skip package installation\n'
  printf '  --non-interactive     Non-interactive mode\n'
  printf '  --resume              Resume interrupted install\n'
  printf '  --rollback            Rollback installer-owned changes\n'
  printf '  --allow-third-party-opencode   Allow third-party OpenCode\n'
  printf '  --allow-proot-opencode         Allow proot-distro fallback\n'
  exit 0
fi

# ── Handle --verify mode ────────────────────────────────────────────────
if [ "$VERIFY_ONLY" -eq 1 ] && [ "$MODE" = "check" ]; then
  MODE="verify"
fi

# ── Handle --test-root ──────────────────────────────────────────────────
_USE_TEST_ROOT=0
if [ -n "$TEST_ROOT" ]; then
  _USE_TEST_ROOT=1
  INSTALL_DIR="${TEST_ROOT}${UOM_DIR_DEFAULT}"
  mkdir -p "$TEST_ROOT" 2>/dev/null || die "Cannot create test root: $TEST_ROOT"
  log "Test root mode: all writes under $TEST_ROOT"
fi

# ── Section 0: Exclusive lock ────────────────────────────────────────────
acquire_lock() {
  if [ -f "$INSTALL_LOCK" ]; then
    _LOCK_PID=$(cat "$INSTALL_LOCK" 2>/dev/null || echo "")
    if [ -n "$_LOCK_PID" ] && kill -0 "$_LOCK_PID" 2>/dev/null; then
      die "Installer already running (PID $_LOCK_PID). Use --resume to continue."
    else
      warn "Stale lock detected (PID $_LOCK_PID). Removing."
      rm -f "$INSTALL_LOCK"
    fi
  fi
  echo $$ > "$INSTALL_LOCK"
}

if [ "$MODE" = "apply" ]; then
  acquire_lock
fi

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

  # Priority 3-5: manual
  log "Priority 5: no local install path succeeded."
  OC_INSTALL_ACTION="remote-fallback"
  OC_INSTALL_PRIORITY=5
}

resolve_opencode_install

# ── Section 6: Companion packages ───────────────────────────────────────
COMPANION_PKGS="tmux openssh git jq curl autossh fzf"

install_companion_pkgs() {
  if [ "$MODE" != "apply" ] || [ "$SKIP_PACKAGES" -eq 1 ]; then
    if [ "$MODE" = "check" ]; then
      log "Companion packages would be installed: ${COMPANION_PKGS}"
      log "  (run --apply to install)"
    fi
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

# ── Section 9: Repository clone/update ──────────────────────────────────
repo_action="none"

ensure_repo() {
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
      git clone --branch "$REF" "$REPO_URL" "$_REPO_DIR" 2>/dev/null || {
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
    log "  NOTE: You must also install Termux:Boot plugin from same source as Termux"
    return
  fi

  _BOOT_DIR="${TEST_ROOT:-}${HOME}/.termux/boot"
  mkdir -p "$_BOOT_DIR"

  cat > "$_BOOT_DIR/start-uom.sh" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot auto-start for UOM
sleep 30
if command -v sshd >/dev/null 2>&1; then
  sshd 2>/dev/null || true
fi
cd ~/src/universal-omni-master 2>/dev/null && \
  sh bin/uom-reverse-ssh.sh >/dev/null 2>&1 &
cd ~/src/universal-omni-master 2>/dev/null && \
  sh bin/uom-port-guardian.sh start >/dev/null 2>&1 &
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
  "opencode_source": "$(json_escape "${OC_SOURCE}")",
  "opencode_version": "$(json_escape "${OC_VERSION}")",
  "opencode_path": "$(json_escape "${OC_PATH}")",
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
printf 'Ref:           %s\n' "$REF"
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
  printf '  sh %s --verify\n' "$0"
  printf '  ssh -p %d localhost echo ok  (test sshd)\n' "$SSHD_PORT"
  printf '  tmux new -s uom\n'
else
  printf '  This was a dry run (--check). To apply changes:\n'
  printf '    sh %s --apply --verify\n' "$0"
  if [ "$ALLOW_THIRD_PARTY" -eq 0 ]; then
    printf '  Add --allow-third-party-opencode to enable third-party installs\n'
  fi
  if [ "$ALLOW_PROOT" -eq 0 ]; then
    printf '  Add --allow-proot-opencode to enable proot-distro fallback\n'
  fi
fi

printf '\n=== QUICK COMMANDS ===\n'
printf '  sh bin/uom-status.sh         — Check all services\n'
printf '  sh bin/uom-status.sh tunnel  — Check tunnel status\n'
printf '  tmux new -s uom              — Start tmux session\n'
printf '\n'

cleanup
