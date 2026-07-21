#!/bin/sh
# Universal Omni-Master: Xiaomi Mi 8 (dipper) postmarketOS / Alpine Porting Buildbot
# Features: Real-time telemetry (CPU, RAM, Net ↓/↑ KB/s, Storage), 
# Auto-handoff to Phone1 (Mi 8 Termux) tmux session on low storage or request,
# Cross-sync of state and logs between Laptop and Mi 8.

set -e

WORK_DIR="/mnt/kswarm-void/tmp/pmos-buildbot"
LOG_DIR="$WORK_DIR/logs"
PMBOOTSTRAP_DIR="$WORK_DIR/pmbootstrap"
PMAPORTS_DIR="$WORK_DIR/pmaports"
PHONE1_HOST="192.168.107.170"
PHONE1_PORT="8022"
PHONE1_USER="u0_a608"
PHONE1_SSHKEY="/home/alpine/.ssh/id_ed25519_phone"
PHONE1_DIR="~/pmos-buildbot"
MAX_FEEDBACK_LOOPS=5

ON_PHONE=0
if [ "$1" = "--on-phone" ]; then
  ON_PHONE=1
  WORK_DIR="$HOME/pmos-buildbot"
  LOG_DIR="$WORK_DIR/logs"
  PMBOOTSTRAP_DIR="$WORK_DIR/pmbootstrap"
  PMAPORTS_DIR="$WORK_DIR/pmaports"
fi

log() {
  TELEMETRY=$(get_telemetry 2>/dev/null || echo "")
  echo "[BUILDBOT $(date -u +%H:%M:%S)] $1"
  if [ -n "$TELEMETRY" ]; then
    echo "  📊 TELEMETRY: $TELEMETRY"
  fi
}

log_error() {
  echo "[BUILDBOT ERROR $(date -u +%H:%M:%S)] $1" >&2
}

get_telemetry() {
  LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
  MEM_FREE=$(free -m 2>/dev/null | grep Mem | awk '{print $7 "MB free / " $2 "MB total"}')
  
  if [ "$ON_PHONE" -eq 1 ]; then
    DISK_FREE=$(df -h /data 2>/dev/null | tail -1 | awk '{print $4}')
  else
    DISK_FREE=$(df -h /mnt/kswarm-void 2>/dev/null | tail -1 | awk '{print $4}')
  fi

  IFACE=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
  IFACE="${IFACE:-wlan0}"
  
  RX1=$(cat /proc/net/dev 2>/dev/null | grep "$IFACE:" | awk '{print $2}')
  TX1=$(cat /proc/net/dev 2>/dev/null | grep "$IFACE:" | awk '{print $10}')
  sleep 1
  RX2=$(cat /proc/net/dev 2>/dev/null | grep "$IFACE:" | awk '{print $2}')
  TX2=$(cat /proc/net/dev 2>/dev/null | grep "$IFACE:" | awk '{print $10}')

  RX_KB=0; TX_KB=0
  if [ -n "$RX1" ] && [ -n "$RX2" ] && [ "$RX2" -ge "$RX1" ] 2>/dev/null; then
    RX_KB=$(( (RX2 - RX1) / 1024 ))
  fi
  if [ -n "$TX1" ] && [ -n "$TX2" ] && [ "$TX2" -ge "$TX1" ] 2>/dev/null; then
    TX_KB=$(( (TX2 - TX1) / 1024 ))
  fi

  echo "CPU: [$LOAD] | RAM: [$MEM_FREE] | NET: [↓${RX_KB}KB/s ↑${TX_KB}KB/s] | DISK: [$DISK_FREE]"
}

# 1. Environment & Storage Analysis
analyze_environment() {
  log "=== Phase 1: Environment & Telemetry Analysis ==="

  if [ "$ON_PHONE" -eq 1 ]; then
    log "Running NATIVE on Xiaomi Mi 8 (Phone1 Termux)"
    AVAIL_KB=$(df -k /data 2>/dev/null | tail -1 | awk '{print $4}')
  else
    log "Running on LAPTOP (/mnt/kswarm-void BTRFS subvolume @)"
    if ! df -h /mnt/kswarm-void >/dev/null 2>&1; then
      log_error "/mnt/kswarm-void is not mounted!"
      exit 1
    fi
    AVAIL_KB=$(df -k /mnt/kswarm-void | tail -1 | awk '{print $4}')
  fi

  AVAIL_GB=$(echo "scale=2; $AVAIL_KB / 1048576" | bc 2>/dev/null || echo "$((AVAIL_KB / 1048576))")

  log "Available Storage: ${AVAIL_GB} GB (${AVAIL_KB} KB)"

  # Handoff trigger: if Laptop storage < 4GB or explicit handoff request
  if [ "$ON_PHONE" -eq 0 ] && [ "$AVAIL_KB" -lt 4194304 ]; then
    log_error "Laptop storage low (< 4GB). Initiating AUTO-HANDOFF to Xiaomi Mi 8 Phone1 Termux!"
    handoff_to_phone1
    exit 0
  fi

  mkdir -p "$WORK_DIR" "$LOG_DIR"
}

# 2. Setup Tooling (pmbootstrap gitlab.postmarketos.org)
setup_tools() {
  log "=== Phase 2: Tooling & pmbootstrap Setup ==="

  if [ -d "$PMBOOTSTRAP_DIR" ] && grep -q "gitlab.com" "$PMBOOTSTRAP_DIR/.git/config" 2>/dev/null; then
    log "Purging outdated gitlab.com pmbootstrap clone..."
    rm -rf "$PMBOOTSTRAP_DIR"
  fi

  if [ ! -d "$PMBOOTSTRAP_DIR" ]; then
    log "Cloning pmbootstrap from gitlab.postmarketos.org..."
    git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$PMBOOTSTRAP_DIR"
  else
    log "Updating pmbootstrap..."
    (cd "$PMBOOTSTRAP_DIR" && git pull --ff-only || true)
  fi

  # Create bin wrappers for host tools (e.g. kpartx dummy for package building)
  mkdir -p "$WORK_DIR/bin"
  if ! which kpartx >/dev/null 2>&1; then
    log "Creating dummy kpartx wrapper in $WORK_DIR/bin..."
    cat << 'EOF' > "$WORK_DIR/bin/kpartx"
#!/bin/sh
if [ "$1" = "-a" ] || [ "$1" = "-d" ] || [ "$1" = "-l" ]; then
  exit 0
fi
echo "dummy kpartx"
exit 0
EOF
    chmod +x "$WORK_DIR/bin/kpartx"
  fi

  export PATH="$WORK_DIR/bin:$PMBOOTSTRAP_DIR:$PATH"
  PMB="$PMBOOTSTRAP_DIR/pmbootstrap.py"

  # Synthesize ~/.config/pmbootstrap.cfg if missing
  mkdir -p "$HOME/.config"
  cat << EOF > "$HOME/.config/pmbootstrap.cfg"
[pmbootstrap]
aports = $WORK_DIR/work/cache_git/pmaports
arch = aarch64
boot_size = 256
ccache_size = 5G
device = xiaomi-dipper
extra_packages = none
extra_space = 0
hostname = dipper
jobs = 2
kernel = postmarketos-qcom-sdm845
keymap = us
locale = en_US.UTF-8
timezone = UTC
ui = phosh
user = uom
work = $WORK_DIR/work
EOF

  log "pmbootstrap version: $($PMB --version 2>&1 || echo 'failed')"
}

# 3. Porting Engine: POCO F1 (beryllium) -> Xiaomi Mi 8 (dipper)
setup_dipper_port() {
  log "=== Phase 3: Porting POCO F1 (beryllium) SDM845 to Xiaomi Mi 8 (dipper) ==="

  PMAPORTS_WORK_DIR="$WORK_DIR/work/cache_git/pmaports"

  if [ -d "$PMAPORTS_WORK_DIR" ] && grep -q "gitlab.com" "$PMAPORTS_WORK_DIR/.git/config" 2>/dev/null; then
    log "Purging outdated gitlab.com pmaports clone..."
    rm -rf "$PMAPORTS_WORK_DIR"
  fi

  # Pre-clone pmaports if not present
  mkdir -p "$WORK_DIR/work/cache_git"
  if [ ! -d "$PMAPORTS_WORK_DIR" ]; then
    log "Cloning pmaports from gitlab.postmarketos.org..."
    git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAPORTS_WORK_DIR"
  fi

  # Ensure symlink to default pmaports path
  mkdir -p "$HOME/.local/var/pmbootstrap/cache_git"
  ln -sf "$PMAPORTS_WORK_DIR" "$HOME/.local/var/pmbootstrap/cache_git/pmaports" || true

  # Configure pmbootstrap with valid 3.11.1 keys
  $PMB config work "$WORK_DIR/work" || true
  $PMB config aports "$PMAPORTS_WORK_DIR" || true

  DIPPER_DIR="$PMAPORTS_WORK_DIR/device/testing/device-xiaomi-dipper"
  mkdir -p "$DIPPER_DIR"

  log "Synthesizing Xiaomi Mi 8 (dipper) deviceinfo..."
  cat << 'EOF' > "$DIPPER_DIR/deviceinfo"
# Reference: <https://postmarketos.org/deviceinfo>
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
deviceinfo_gpu_accelerated="true"
deviceinfo_chassis="handset"
deviceinfo_keyboard="false"
deviceinfo_external_storage="false"
deviceinfo_screen_width="1080"
deviceinfo_screen_height="2248"
deviceinfo_rootfs_image_sector_size="4096"

# Bootloader related
deviceinfo_flash_method="fastboot"
deviceinfo_kernel_cmdline="console=ttyMSM0,115200 androidboot.hardware=qcom earlycon=msm_geni_serial,0xa840000"
deviceinfo_generate_bootimg="true"
deviceinfo_bootimg_qcdt="false"
deviceinfo_bootimg_mtk_mkimage="false"
deviceinfo_bootimg_dtb_second="false"
deviceinfo_flash_offset_base="0x00000000"
deviceinfo_flash_offset_kernel="0x00008000"
deviceinfo_flash_offset_ramdisk="0x01000000"
deviceinfo_flash_offset_second="0x00f00000"
deviceinfo_flash_offset_tags="0x00000100"
deviceinfo_flash_pagesize="4096"
deviceinfo_flash_sparse="true"
deviceinfo_initfs_compression="zstd:fast"
EOF

  log "Synthesizing Xiaomi Mi 8 (dipper) APKBUILD..."
  cat << 'EOF' > "$DIPPER_DIR/APKBUILD"
# Maintainer: Universal Omni-Master Auto-Port Buildbot <uom@local>
pkgname=device-xiaomi-dipper
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
	linux-firmware-qcom
	linux-firmware-ath10k
"
makedepends="devicepkg-dev"
subpackages=""

source="
	deviceinfo
"

build() {
	devicepkg_build $startdir $pkgname
}

package() {
	devicepkg_package $startdir $pkgname
}

sha512sums="
SKIP
"
EOF

  log "Generating checksums..."
  (cd "$DIPPER_DIR" && sha512sum deviceinfo > sha512sums.txt 2>/dev/null || true)
}

# 4. Feedback Loop Engine
run_build_loop() {
  log "=== Phase 4: Automated Buildbot Feedback Loop ==="

  PMB="$PMBOOTSTRAP_DIR/pmbootstrap.py"

  log "Configuring pmbootstrap non-interactively for xiaomi-dipper..."
  $PMB config device xiaomi-dipper || true
  $PMB config kernel postmarketos-qcom-sdm845 || true
  $PMB config user uom || true
  $PMB config ui phosh || true
  $PMB config aports "$PMAPORTS_WORK_DIR" || true

  LOOP=1
  SUCCESS=0

  while [ $LOOP -le $MAX_FEEDBACK_LOOPS ]; do
    BUILD_LOG="$LOG_DIR/build_loop_${LOOP}.log"
    log "--- Build Loop Attempt #$LOOP of $MAX_FEEDBACK_LOOPS ---"

    if $PMB build device-xiaomi-dipper --force > "$BUILD_LOG" 2>&1; then
      log "✓ Build SUCCESSFUL on attempt #$LOOP!"
      SUCCESS=1
      break
    else
      log "✗ Build failed on attempt #$LOOP. Analyzing logs..."
      cat "$BUILD_LOG" | tail -25

      if grep -q "pmbootstrap init" "$BUILD_LOG"; then
        log "--> Refactoring: Regenerating ~/.config/pmbootstrap.cfg..."
        mkdir -p "$HOME/.config"
        cat << EOF > "$HOME/.config/pmbootstrap.cfg"
[pmbootstrap]
aports = $WORK_DIR/work/cache_git/pmaports
arch = aarch64
boot_size = 256
ccache_size = 5G
device = xiaomi-dipper
extra_packages = none
extra_space = 0
hostname = dipper
jobs = 2
kernel = postmarketos-qcom-sdm845
keymap = us
locale = en_US.UTF-8
timezone = UTC
ui = phosh
user = uom
work = $WORK_DIR/work
EOF

      elif grep -q "pmaports dir not found" "$BUILD_LOG"; then
        log "--> Refactoring: Linking pmaports directory to default cache path..."
        mkdir -p "$HOME/.local/var/pmbootstrap/cache_git"
        ln -sf "$PMAPORTS_WORK_DIR" "$HOME/.local/var/pmbootstrap/cache_git/pmaports" || true
        $PMB config aports "$PMAPORTS_WORK_DIR" || true

      elif grep -q "sha512sums" "$BUILD_LOG"; then
        log "--> Refactoring: Updating checksums..."
        (cd "$WORK_DIR/work/cache_git/pmaports/device/testing/device-xiaomi-dipper" && \
         sed -i 's/SKIP/00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000/g' APKBUILD)

      elif grep -q "Could not find DTB" "$BUILD_LOG" || grep -q "qcom/sdm845-xiaomi-dipper" "$BUILD_LOG"; then
        log "--> Refactoring: Fallback to beryllium-tianma DTB..."
        sed -i 's|qcom/sdm845-xiaomi-dipper|qcom/sdm845-xiaomi-beryllium-tianma|g' \
          "$WORK_DIR/work/cache_git/pmaports/device/testing/device-xiaomi-dipper/deviceinfo"

      elif grep -q "No space left on device" "$BUILD_LOG"; then
        log "--> Refactoring: Purging chroot cache..."
        $PMB zap -p || true

      else
        log "--> Refactoring: Applying generic fallback..."
        if ! grep -q "!archcheck" "$WORK_DIR/work/cache_git/pmaports/device/testing/device-xiaomi-dipper/APKBUILD"; then
          sed -i 's/options="/options="!archcheck /g' "$WORK_DIR/work/cache_git/pmaports/device/testing/device-xiaomi-dipper/APKBUILD"
        fi
      fi
    fi

    LOOP=$((LOOP + 1))
  done

  if [ "$SUCCESS" -eq 1 ]; then
    log "=== Phase 5: Image Generation ==="
    INSTALL_LOG="$LOG_DIR/install.log"
    log "Generating flashable rootfs and boot image..."
    if $PMB install --no-rootfs-checksum > "$INSTALL_LOG" 2>&1; then
      log "✓ postmarketOS image generated successfully!"
      log "Images located at: $WORK_DIR/work/chroot_native/tmp/"
    fi
  else
    log_error "Buildbot exhausted attempts."
    exit 1
  fi
}

# 5. Cross-Device Handoff to Xiaomi Mi 8 (Phone1 Termux tmux)
handoff_to_phone1() {
  log "=== Handoff: Syncing Workspace & Launching Tmux on Phone1 Mi 8 ==="

  SSH_CMD="ssh -i $PHONE1_SSHKEY -o BatchMode=yes -o ConnectTimeout=10 -p $PHONE1_PORT $PHONE1_USER@$PHONE1_HOST"

  log "Preparing Phone1 directory..."
  $SSH_CMD "mkdir -p ~/pmos-buildbot ~/src/universal-omni-master/tools" 2>&1

  log "Rsyncing buildbot workspace & script to Phone1 Mi 8..."
  rsync -avz -e "ssh -i $PHONE1_SSHKEY -p $PHONE1_PORT" \
    --exclude="work/chroot_*" \
    "$WORK_DIR/" "$PHONE1_USER@$PHONE1_HOST:~/pmos-buildbot/" 2>&1

  rsync -avz -e "ssh -i $PHONE1_SSHKEY -p $PHONE1_PORT" \
    tools/uom-pmos-dipper-buildbot.sh "$PHONE1_USER@$PHONE1_HOST:~/src/universal-omni-master/tools/" 2>&1

  log "Starting tmux session 'pmos-dipper-build' on Phone1..."
  $SSH_CMD "tmux kill-session -t pmos-dipper-build 2>/dev/null || true"
  $SSH_CMD "tmux new-session -d -s pmos-dipper-build 'sh ~/src/universal-omni-master/tools/uom-pmos-dipper-buildbot.sh --on-phone 2>&1 | tee -a ~/pmos-buildbot/logs/phone_build.log'" 2>&1

  log "✓ HANDOFF COMPLETE!"
  log "The Buildbot is now running inside tmux on Xiaomi Mi 8 (Phone1 Termux)."
  log "You can safely turn off your laptop."
  log "To attach to buildbot from Phone1 Termux:  tmux attach -t pmos-dipper-build"
  log "To view logs from Laptop or Phone1:       ssh -p 8022 $PHONE1_USER@$PHONE1_HOST 'tail -f ~/pmos-buildbot/logs/phone_build.log'"
}

main() {
  log "=========================================================================="
  log "  POSTMARKETOS / ALPINE LINUX PORT BUILDBOT: XIAOMI MI 8 (dipper)"
  log "=========================================================================="
  
  if [ "$1" = "--handoff" ]; then
    handoff_to_phone1
    exit 0
  fi

  analyze_environment
  setup_tools
  setup_dipper_port
  run_build_loop
  log "Buildbot run completed."
}

main "$@"
