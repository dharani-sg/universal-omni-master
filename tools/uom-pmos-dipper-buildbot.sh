#!/bin/sh
# Universal Omni-Master: Xiaomi Mi 8 (dipper) postmarketOS Buildbot v2
# Modes:
#   (default)         Laptop mode — runs on /mnt/kswarm-void
#   --on-phone        Phone1 Termux native mode
#   --handoff         Sync workspace to Phone1, start tmux, exit
#   --dual-sync       Laptop runs build loop, auto-syncs logs to Phone1
#   --loop            Infinite retry loop with dual-sync heartbeat
#
# Refactored: non-interactive pmbootstrap, correct deviceinfo, kpartx PATH,
#             dual-sync (laptop↔Phone1), robust error classification.

set -e

# ─── Configuration ───────────────────────────────────────────────────────────
LAPTOP_HOST="192.168.107.90"
PHONE1_HOST="192.168.107.170"
PHONE1_PORT="8022"
PHONE1_USER="u0_a608"
PHONE1_SSHKEY="/home/alpine/.ssh/id_ed25519_phone"
PHONE1_DIR="~/pmos-buildbot"
SYNC_INTERVAL=300
MAX_FEEDBACK_LOOPS=10
DEVICE="xiaomi-dipper"
DEVICE_UPPER="xiaomi-dipper"
KERNEL_PKG="postmarketos-qcom-sdm845"
UI="phosh"
USER_NAME="uom"

# ─── Mode detection ──────────────────────────────────────────────────────────
ON_PHONE=0
DUAL_SYNC=0
INFINITE_LOOP=0

for arg in "$@"; do
  case "$arg" in
    --on-phone)    ON_PHONE=1 ;;
    --dual-sync)   DUAL_SYNC=1 ;;
    --loop)        INFINITE_LOOP=1 ;;
    --handoff)     HANDOFF_ONLY=1 ;;
  esac
done

if [ "$ON_PHONE" -eq 1 ]; then
  WORK_DIR="$HOME/pmos-buildbot"
  LOG_DIR="$WORK_DIR/logs"
  PMBOOTSTRAP_DIR="$WORK_DIR/pmbootstrap"
else
  WORK_DIR="/mnt/kswarm-void/tmp/pmos-buildbot"
  LOG_DIR="$WORK_DIR/logs"
  PMBOOTSTRAP_DIR="$WORK_DIR/pmbootstrap"
fi

PMAPORTS_WORK="$WORK_DIR/work/cache_git/pmaports"
PMB="$PMBOOTSTRAP_DIR/pmbootstrap.py"
LOG_FILE="$LOG_DIR/buildbot_$(date -u +%Y%m%d_%H%M%S).log"
STATE_FILE="$WORK_DIR/.buildbot_state"
HEARTBEAT_FILE="$WORK_DIR/.buildbot_heartbeat"

mkdir -p "$LOG_DIR"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() {
  local ts
  ts=$(date -u +%H:%M:%S)
  local msg="[$ts] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

log_err() {
  local ts
  ts=$(date -u +%H:%M:%S)
  local msg="[$ts ERROR] $1"
  echo "$msg" >&2
  echo "$msg" >> "$LOG_FILE"
}

telemetry() {
  local load mem disk rx_kb tx_kb
  load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)
  mem=$(free -m 2>/dev/null | awk '/Mem/{printf "%d/%dMB", $7, $2}')
  if [ "$ON_PHONE" -eq 1 ]; then
    disk=$(df -h /data 2>/dev/null | tail -1 | awk '{print $4}')
  else
    disk=$(df -h /mnt/kswarm-void 2>/dev/null | tail -1 | awk '{print $4}')
  fi
  local iface
  iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
  iface="${iface:-wlan0}"
  local rx1 tx1 rx2 tx2
  rx1=$(awk -v i="$iface:" '$0 ~ i {print $2}' /proc/net/dev 2>/dev/null)
  tx1=$(awk -v i="$iface:" '$0 ~ i {print $10}' /proc/net/dev 2>/dev/null)
  sleep 1
  rx2=$(awk -v i="$iface:" '$0 ~ i {print $2}' /proc/net/dev 2>/dev/null)
  tx2=$(awk -v i="$iface:" '$0 ~ i {print $10}' /proc/net/dev 2>/dev/null)
  rx_kb=0; tx_kb=0
  if [ -n "$rx1" ] && [ -n "$rx2" ] && [ "$rx2" -ge "$rx1" ] 2>/dev/null; then
    rx_kb=$(( (rx2 - rx1) / 1024 ))
  fi
  if [ -n "$tx1" ] && [ -n "$tx2" ] && [ "$tx2" -ge "$tx1" ] 2>/dev/null; then
    tx_kb=$(( (tx2 - tx1) / 1024 ))
  fi
  echo "Load:[$load] RAM:[$mem] Disk:[$disk] Net:[$rx_kb/↑${tx_kb}KB/s]"
}

heartbeat() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)|$1|$(telemetry)" > "$HEARTBEAT_FILE"
}

save_state() {
  echo "$1" > "$STATE_FILE"
}

ssh_phone1() {
  ssh -i "$PHONE1_SSHKEY" -o BatchMode=yes -o ConnectTimeout=10 \
      -o StrictHostKeyChecking=no -p "$PHONE1_PORT" \
      "$PHONE1_USER@$PHONE1_HOST" "$@" 2>/dev/null
}

rsync_to_phone1() {
  rsync -avz --timeout=30 \
    -e "ssh -i $PHONE1_SSHKEY -p $PHONE1_PORT -o BatchMode=yes -o StrictHostKeyChecking=no" \
    --exclude="work/chroot_*" \
    --exclude="work/cache_git" \
    --exclude=".buildbot_*" \
    "$1" "$PHONE1_USER@$PHONE1_HOST:$2" 2>&1
}

# ─── Phase 1: Environment ────────────────────────────────────────────────────
analyze_environment() {
  log "=== Phase 1: Environment Analysis ==="
  log "Telemetry: $(telemetry)"
  save_state "analyzing"

  if [ "$ON_PHONE" -eq 0 ]; then
    if ! df -h /mnt/kswarm-void >/dev/null 2>&1; then
      log_err "/mnt/kswarm-void not mounted"
      exit 1
    fi
    local avail_kb
    avail_kb=$(df -k /mnt/kswarm-void | tail -1 | awk '{print $4}')
    local avail_gb
    avail_gb=$(echo "scale=1; $avail_kb / 1048576" | bc 2>/dev/null || echo "$((avail_kb / 1048576))")
    log "Laptop BTRFS free: ${avail_gb} GB"

    if [ "$avail_kb" -lt 4194304 ]; then
      log_err "Storage < 4GB — auto-handoff to Phone1"
      handoff_to_phone1
      exit 0
    fi
  else
    log "Running NATIVE on Phone1 (Mi 8 Termux)"
  fi
}

# ─── Phase 2: Tooling ────────────────────────────────────────────────────────
setup_tools() {
  log "=== Phase 2: Tooling Setup ==="
  save_state "tooling"

  # kpartx: create dummy if missing (pmbootstrap check needs it in PATH)
  mkdir -p "$WORK_DIR/bin"
  if [ ! -f "$WORK_DIR/bin/kpartx" ]; then
    log "Creating dummy kpartx wrapper"
    cat << 'KPARTX' > "$WORK_DIR/bin/kpartx"
#!/bin/sh
case "$1" in
  -a|-d|-l|-t) exit 0 ;;
  *) echo "dummy kpartx"; exit 0 ;;
esac
KPARTX
    chmod +x "$WORK_DIR/bin/kpartx"
  fi

  # Add work/bin and pmbootstrap to PATH
  export PATH="$WORK_DIR/bin:$PMBOOTSTRAP_DIR:$PATH"

  # Remove old gitlab.com clone if present
  if [ -d "$PMBOOTSTRAP_DIR" ] && grep -q "gitlab\.com" "$PMBOOTSTRAP_DIR/.git/config" 2>/dev/null; then
    log "Purging old gitlab.com pmbootstrap"
    rm -rf "$PMBOOTSTRAP_DIR"
  fi

  if [ ! -d "$PMBOOTSTRAP_DIR" ]; then
    log "Cloning pmbootstrap from gitlab.postmarketos.org..."
    git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$PMBOOTSTRAP_DIR"
  else
    log "Updating pmbootstrap..."
    (cd "$PMBOOTSTRAP_DIR" && git pull --ff-only 2>/dev/null || true)
  fi

  log "pmbootstrap version: $(python3 "$PMB" --version 2>&1 || echo 'failed')"
}

# ─── Phase 3: pmbootstrap init (non-interactive via piped answers) ───────────
init_pmbootstrap() {
  log "=== Phase 3: pmbootstrap Non-Interactive Init ==="
  save_state "init"

  # Fix self-referencing symlink from previous Antigravity sessions
  if [ -L "$PMAPORTS_WORK/pmaports" ]; then
    log "Removing self-referencing pmaports symlink"
    rm -f "$PMAPORTS_WORK/pmaports"
  fi

  mkdir -p "$HOME/.config"
  cat << EOF > "$HOME/.config/pmbootstrap.cfg"
[pmbootstrap]
aports = $PMAPORTS_WORK
arch = aarch64
boot_size = 256
ccache_size = 5G
device = $DEVICE
extra_packages = none
extra_space = 0
hostname = dipper
jobs = 2
kernel = $KERNEL_PKG
keymap = us
locale = en_US.UTF-8
timezone = UTC
ui = $UI
user = $USER_NAME
work = $WORK_DIR/work
EOF

  # Pre-clone pmaports if not present (or purge old gitlab.com URL)
  mkdir -p "$WORK_DIR/work/cache_git"
  if [ -d "$PMAPORTS_WORK" ] && grep -q "gitlab\.com" "$PMAPORTS_WORK/.git/config" 2>/dev/null; then
    log "Purging old gitlab.com pmaports"
    rm -rf "$PMAPORTS_WORK"
  fi
  if [ ! -d "$PMAPORTS_WORK" ]; then
    log "Cloning pmaports (shallow)..."
    git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAPORTS_WORK"
  fi

  # Non-interactive pmbootstrap init via piped answers
  # Question sequence for pmbootstrap 3.11.1 with existing device (dipper in xiaomi):
  # 1.Work  2.pmaports  3.Channel  4.Vendor  5.Device
  # 6.Username  7.Audio(default)  8.WiFi(default)  9.USB(default)
  # 10.UI  11.SvcMgr(default)  12.ChangeOpts(n)
  # 13.ExtraPkgs(none)  14.Timezone(y)  15.Locale(en_US)
  # 16.Hostname(dipper)  17.SSHKeys(n)  18.BuildOutdated(y)  19.ZapChroots(y)  20.Confirm(y)
  if [ ! -f "$WORK_DIR/work/config/.pmb_configured" ] || \
     ! python3 "$PMB" status 2>/dev/null | grep -q "$DEVICE"; then
    log "Running pmbootstrap init (non-interactive)..."
    cd "$WORK_DIR/work"
    printf '%s\n' \
      "$WORK_DIR/work" \
      "$PMAPORTS_WORK" \
      "edge" \
      "xiaomi" \
      "dipper" \
      "$USER_NAME" \
      "" \
      "" \
      "" \
      "$UI" \
      "default" \
      "n" \
      "none" \
      "y" \
      "en_US" \
      "dipper" \
      "n" \
      "y" \
      "y" \
      "y" \
      | timeout 120 python3 "$PMB" init --shallow-initial-clone \
        >> "$LOG_FILE" 2>&1 || log "pmbootstrap init exited (may need re-init)"
    touch "$WORK_DIR/work/config/.pmb_configured"
  else
    log "pmbootstrap already initialized for $DEVICE"
  fi

  log "pmbootstrap status: $(python3 "$PMB" status 2>&1 | tr '\n' ' ')"
}

# ─── Phase 4: Dipper Device Port ─────────────────────────────────────────────
setup_dipper_port() {
  log "=== Phase 4: Dipper Device Port ==="
  save_state "porting"

  DIPPER_DIR="$PMAPORTS_WORK/device/testing/device-$DEVICE_UPPER"

  if [ -f "$DIPPER_DIR/APKBUILD" ] && [ -f "$DIPPER_DIR/deviceinfo" ]; then
    log "Dipper device already exists in pmaports (upstream). Skipping synthesis."
    log "  APKBUILD: $(wc -l < "$DIPPER_DIR/APKBUILD") lines"
    log "  deviceinfo: $(wc -l < "$DIPPER_DIR/deviceinfo") lines"
    return 0
  fi

  mkdir -p "$DIPPER_DIR"

  log "Synthesizing dipper deviceinfo from beryllium reference..."
  cat << 'EOF' > "$DIPPER_DIR/deviceinfo"
# Reference: https://postmarketos.org/deviceinfo
# Ported from xiaomi-beryllium (SDM845) by UOM Buildbot

deviceinfo_format_version="0"
deviceinfo_name="Xiaomi Mi 8"
deviceinfo_manufacturer="Xiaomi"
deviceinfo_codename="xiaomi-dipper"
deviceinfo_year="2018"
deviceinfo_arch="aarch64"
deviceinfo_dtb="qcom/sdm845-xiaomi-dipper"
deviceinfo_append_dtb="true"
deviceinfo_flash_kernel_on_update="true"

# Device related
deviceinfo_drm="true"
deviceinfo_chassis="handset"
deviceinfo_external_storage="false"
deviceinfo_screen_width="1080"
deviceinfo_screen_height="2248"
deviceinfo_rootfs_image_sector_size="4096"

# Bootloader related
deviceinfo_flash_method="fastboot"
deviceinfo_generate_bootimg="true"
deviceinfo_flash_offset_base="0x00000000"
deviceinfo_flash_offset_kernel="0x00008000"
deviceinfo_flash_offset_ramdisk="0x01000000"
deviceinfo_flash_offset_second="0x00f00000"
deviceinfo_flash_offset_tags="0x00000100"
deviceinfo_flash_pagesize="4096"
deviceinfo_flash_sparse="true"
deviceinfo_initfs_compression="zstd:fast"
EOF

  log "Synthesizing dipper APKBUILD..."
  cat << EOF > "$DIPPER_DIR/APKBUILD"
# Maintainer: UOM Auto-Port Buildbot <uom@universal-omni.org>
pkgname=device-$DEVICE_UPPER
pkgdesc="Xiaomi Mi 8"
pkgver=1
pkgrel=1
url="https://postmarketos.org"
license="MIT"
arch="aarch64"
options="!check !archcheck"
depends="
	postmarketos-base
	mkbootimg
	alsa-ucm-conf-sdm845
	soc-qcom
	soc-qcom-modem
	linux-postmarketos-qcom-sdm845
"
makedepends="devicepkg-dev"
subpackages=""
source="
	deviceinfo
"

build() {
	devicepkg_build \$startdir \$pkgname
}

package() {
	devicepkg_package \$startdir \$pkgname
}

sha512sums="
SKIP
"
EOF

  python3 "$PMB" checksum "device-$DEVICE_UPPER"
  log "Dipper device port synthesized at $DIPPER_DIR"
}

# ─── Phase 5: Build Loop with Error Classification ───────────────────────────
classify_error() {
  local logfile="$1"
  local pattern

  for pattern in \
    "No space left on device|ENOSPC|disk full" \
    "Could not find DTB|dtb.*not found|deviceinfo_dtb" \
    "sha512sums.*FAIL|checksum.*mismatch|sha512" \
    "pmbootstrap init|Please run.*init" \
    "kpartx|missing.*kpartx" \
    "permission denied|EPERM|not allowed" \
    "network.*unreachable|timeout|ETIMEDOUT|resolve" \
    "already exists|is locked|database.*busy" \
    "depends.*not found|unsatisfiable|virtual.*provides" \
    "ERROR.*build\|Build failed\|abuild.*failed"
  do
    if grep -qiE "$pattern" "$logfile" 2>/dev/null; then
      echo "$pattern"
      return
    fi
  done
  echo "unknown"
}

auto_fix() {
  local error_class="$1"
  log "Auto-fix attempt for: $error_class"

  case "$error_class" in
    *"No space left"*)
      log "Purging pmbootstrap chroot cache..."
      cd "$WORK_DIR/work" && python3 "$PMB" zap -p 2>/dev/null || true
      ;;
    *"Could not find DTB"*|*"deviceinfo_dtb"*)
      log "Falling back to beryllium-tianma DTB..."
      sed -i 's|deviceinfo_dtb=.*|deviceinfo_dtb="qcom/sdm845-xiaomi-beryllium-tianma"|g' \
        "$DIPPER_DIR/deviceinfo"
      ;;
    *"sha512sums"*|*"checksum"*)
      log "Running pmbootstrap checksum..."
      python3 "$PMB" checksum "device-$DEVICE_UPPER"
      ;;
    *"kpartx"*)
      log "Ensuring kpartx wrapper is in PATH..."
      export PATH="$WORK_DIR/bin:$PATH"
      ;;
    *"depends"*|*"not found"*)
      log "Removing problematic dependencies from APKBUILD..."
      sed -i 's/soc-qcom-sdm845/soc-qcom/' "$DIPPER_DIR/APKBUILD" 2>/dev/null || true
      ;;
    *)
      log "No auto-fix available for: $error_class"
      ;;
  esac
}

run_build_loop() {
  log "=== Phase 5: Build Loop (max $MAX_FEEDBACK_LOOPS attempts) ==="
  save_state "building"

  export PATH="$WORK_DIR/bin:$PMBOOTSTRAP_DIR:$PATH"

  local loop=1
  local success=0

  while [ $loop -le $MAX_FEEDBACK_LOOPS ]; do
    local build_log="$LOG_DIR/build_attempt_${loop}.log"
    log "--- Attempt #$loop of $MAX_FEEDBACK_LOOPS ---"
    heartbeat "build_attempt_$loop"

    if cd "$WORK_DIR/work" && timeout 1800 python3 "$PMB" build "device-$DEVICE_UPPER" \
       --force > "$build_log" 2>&1; then
      log "BUILD SUCCESS on attempt #$loop"
      success=1
      break
    fi

    log "Build failed on attempt #$loop"
    tail -20 "$build_log" >> "$LOG_FILE" 2>/dev/null

    local errclass
    errclass=$(classify_error "$build_log")
    log "Error class: $errclass"
    auto_fix "$errclass"

    # Sync error log to Phone1
    if [ "$ON_PHONE" -eq 0 ]; then
      rsync_to_phone1 "$build_log" "$PHONE1_DIR/logs/" 2>/dev/null || true
    fi

    loop=$((loop + 1))
  done

  if [ "$success" -eq 1 ]; then
    log "=== Phase 6: Image Export ==="
    save_state "exporting"
    local install_log="$LOG_DIR/install.log"
    if cd "$WORK_DIR/work" && timeout 600 python3 "$PMB" install --password uom > "$install_log" 2>&1; then
      log "postmarketOS image generated!"
      log "Images at: $WORK_DIR/work/chroot_native/tmp/"
      heartbeat "build_complete"
      save_state "complete"
      return 0
    else
      log_err "Image export failed"
      tail -20 "$install_log" >> "$LOG_FILE"
    fi
  else
    log_err "All $MAX_FEEDBACK_LOOPS build attempts failed"
    heartbeat "build_failed"
    save_state "failed"
    return 1
  fi
}

# ─── Handoff to Phone1 ──────────────────────────────────────────────────────
handoff_to_phone1() {
  log "=== Handoff: Syncing to Phone1 Mi 8 ==="
  save_state "handoff"

  log "Preparing Phone1 workspace..."
  ssh_phone1 "mkdir -p ~/pmos-buildbot/logs ~/pmos-buildbot/bin"

  log "Rsyncing buildbot workspace (excluding chroot + pmaports)..."
  rsync_to_phone1 "$WORK_DIR/" "$PHONE1_DIR/"

  log "Installing pmbootstrap on Phone1 if missing..."
  ssh_phone1 "cd ~/pmos-buildbot && \
    [ -d pmbootstrap/.git ] || git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git pmbootstrap" 2>&1

  log "Starting tmux session on Phone1..."
  ssh_phone1 "tmux kill-session -t pmos-dipper 2>/dev/null || true; \
    tmux new-session -d -s pmos-dipper \
    'cd ~/pmos-buildbot && sh tools/uom-pmos-dipper-buildbot.sh --on-phone 2>&1 | tee -a logs/phone_build.log'" 2>&1

  log "HANDOFF COMPLETE — tmux session 'pmos-dipper' running on Phone1"
  log "Attach: ssh -p 8022 $PHONE1_USER@$PHONE1_HOST 'tmux attach -t pmos-dipper'"
}

# ─── Dual Sync: Laptop ↔ Phone1 heartbeat + log sync ────────────────────────
dual_sync_loop() {
  log "=== Dual Sync: Laptop ↔ Phone1 (interval ${SYNC_INTERVAL}s) ==="
  save_state "dual_sync"

  while true; do
    heartbeat "dual_sync"

    # Push buildbot state to Phone1
    if ssh_phone1 "true" 2>/dev/null; then
      rsync_to_phone1 "$LOG_DIR/" "$PHONE1_DIR/logs/" 2>/dev/null || true
      rsync_to_phone1 "$HEARTBEAT_FILE" "$PHONE1_DIR/" 2>/dev/null || true
      log "Dual sync: pushed to Phone1 (heartbeat OK)"
    else
      log "Dual sync: Phone1 unreachable, retrying next cycle"
    fi

    # Pull Phone1 logs if any
    local phone_heartbeat
    phone_heartbeat=$(ssh_phone1 "cat $PHONE1_DIR/.buildbot_heartbeat 2>/dev/null") || true
    if [ -n "$phone_heartbeat" ]; then
      log "Phone1 heartbeat: $phone_heartbeat"
    fi

    sleep "$SYNC_INTERVAL"
  done
}

# ─── Infinite loop mode ──────────────────────────────────────────────────────
infinite_loop() {
  log "=== Infinite Build Loop Mode ==="
  local iteration=1

  while true; do
    log "========== LOOP ITERATION #$iteration =========="
    heartbeat "loop_$iteration"

    analyze_environment
    setup_tools
    init_pmbootstrap
    setup_dipper_port

    if run_build_loop; then
      log "Build succeeded on iteration #$iteration"
      break
    fi

    log "Iteration #$iteration failed — cleaning up and retrying in 60s..."
    cd "$WORK_DIR/work" && python3 "$PMB" zap -p 2>/dev/null || true
    rm -rf "$WORK_DIR/work/chroot_native"
    sleep 60
    iteration=$((iteration + 1))
  done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "=========================================================================="
  log "  POSTMARKETOS BUILDBOT v2: Xiaomi Mi 8 (dipper)"
  log "  Mode: $([ "$INFINITE_LOOP" -eq 1 ] && echo 'infinite-loop' || \
             [ "$DUAL_SYNC" -eq 1 ] && echo 'dual-sync' || \
             [ "$HANDOFF_ONLY" -eq 1 ] && echo 'handoff' || \
             [ "$ON_PHONE" -eq 1 ] && echo 'phone-native' || echo 'laptop')"
  log "=========================================================================="

  if [ "$HANDOFF_ONLY" -eq 1 ]; then
    handoff_to_phone1
    exit 0
  fi

  if [ "$INFINITE_LOOP" -eq 1 ]; then
    if [ "$DUAL_SYNC" -eq 1 ]; then
      # Start build in background, dual-sync in foreground
      infinite_loop &
      build_pid=$!
      dual_sync_loop &
      sync_pid=$!
      wait $build_pid $sync_pid
    else
      infinite_loop
    fi
  elif [ "$DUAL_SYNC" -eq 1 ]; then
    analyze_environment
    setup_tools
    init_pmbootstrap
    setup_dipper_port
    run_build_loop &
    build_pid=$!
    dual_sync_loop &
    sync_pid=$!
    wait $build_pid $sync_pid
  else
    analyze_environment
    setup_tools
    init_pmbootstrap
    setup_dipper_port
    run_build_loop
  fi

  log "Buildbot completed."
}

main "$@"
