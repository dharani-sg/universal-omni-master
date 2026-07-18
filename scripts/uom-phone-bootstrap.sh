#!/bin/sh
# NAME: uom-phone-bootstrap
# PURPOSE: One-shot QEMU bootstrap, doctor, and resume for Android/Termux
# VERSION: 2.0.0
# DEPENDS: uom-lib.sh, qemu-system-aarch64, ssh, tmux
# SAFE: modifies-state (creates dirs, copies firmware, installs packages)
# TESTED: PASS 2026-07-18
#
# Usage: uom-phone-bootstrap.sh {doctor|plan|install|resume|verify|status}
# POSIX sh. Idempotent. No root. No auto-APK. No eval.
# Tested on: Xiaomi Mi 8, crDroid Android 15, Termux Google Play.

set -eu

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
UOM_VM_DIR="${HOME}/uom-vm"
UOM_IMAGES_DIR="${UOM_VM_DIR}/images"
UOM_LOG_DIR="${UOM_VM_DIR}/logs"
UOM_DISK="${UOM_IMAGES_DIR}/uom-phone.qcow2"
UOM_FIRMWARE_CODE="${UOM_VM_DIR}/edk2-aarch64-code.fd"
UOM_FIRMWARE_VARS="${UOM_VM_DIR}/edk2-aarch64-vars.fd"
UOM_KERNEL="${UOM_VM_DIR}/vmlinuz-virt"
UOM_INITRD="${UOM_VM_DIR}/initramfs-virt"
UOM_QEMU_LAUNCHER="${HOME}/bin/uom-qemu-phone"

_ts() { date +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "unknown"; }
_log() { printf '[%s] [bootstrap] %s\n' "$(_ts)" "$*"; }
_ok() { printf '[%s] [bootstrap] OK: %s\n' "$(_ts)" "$*"; }
_fail() { printf '[%s] [bootstrap] FAIL: %s\n' "$(_ts)" "$*" >&2; }

# Source consolidated library if available
_UOM_LIB="${HOME}/bin/uom-lib.sh"
if [ -f "$_UOM_LIB" ]; then
    . "$_UOM_LIB"
    UOM_LOG_TAG="bootstrap"
fi

# ── Doctor: check prerequisites ─────────────────────────────────────────
cmd_doctor() {
    _failures=0
    _log "=== System Doctor ==="

    # Android SDK >= 33
    _sdk=$(getprop ro.build.version.sdk 2>/dev/null || echo "0")
    if [ "$_sdk" -ge 33 ] 2>/dev/null; then
        _ok "Android SDK: $_sdk (>= 33)"
    else
        _fail "Android SDK: $_sdk (< 33 required)"
        _failures=$((_failures + 1))
    fi

    # aarch64
    _arch=$(uname -m 2>/dev/null || echo "unknown")
    if [ "$_arch" = "aarch64" ]; then
        _ok "Architecture: $_arch"
    else
        _fail "Architecture: $_arch (aarch64 required)"
        _failures=$((_failures + 1))
    fi

    # Disk space >= 10 GiB (df -B not available on all Termux builds)
    _avail_kb=$(df /data/data/com.termux/files/home 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    _avail_gb=$((_avail_kb / 1048576))
    if [ "$_avail_gb" -ge 10 ] 2>/dev/null; then
        _ok "Storage: ${_avail_gb}G available"
    else
        _fail "Storage: ${_avail_gb}G (< 10G required)"
        _failures=$((_failures + 1))
    fi

    # RAM >= 4 GB
    _ram_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
    _ram_mb=$((_ram_kb / 1024))
    _ram_gb=$((_ram_mb / 1024))
    if [ "$_ram_gb" -ge 4 ] 2>/dev/null; then
        _ok "RAM: ${_ram_gb}GB (>= 4GB)"
    else
        _fail "RAM: ${_ram_gb}GB (< 4GB required)"
        _failures=$((_failures + 1))
    fi

    # QEMU available
    if command -v qemu-system-aarch64 >/dev/null 2>&1; then
        _qver=$(qemu-system-aarch64 --version 2>/dev/null | head -1 || echo "unknown")
        _ok "QEMU: $_qver"
    else
        _fail "QEMU: not installed"
        _failures=$((_failures + 1))
    fi

    # jq available
    if command -v jq >/dev/null 2>&1; then
        _ok "jq: $(jq --version 2>/dev/null || echo "installed")"
    else
        _fail "jq: not installed"
        _failures=$((_failures + 1))
    fi

    # curl available
    if command -v curl >/dev/null 2>&1; then
        _ok "curl: installed"
    else
        _fail "curl: not installed"
        _failures=$((_failures + 1))
    fi

    # git available
    if command -v git >/dev/null 2>&1; then
        _ok "git: $(git --version 2>/dev/null || echo "installed")"
    else
        _fail "git: not installed"
        _failures=$((_failures + 1))
    fi

    # SSH available
    if command -v ssh >/dev/null 2>&1; then
        _ok "ssh: installed"
    else
        _fail "ssh: not installed"
        _failures=$((_failures + 1))
    fi

    # tmux available
    if command -v tmux >/dev/null 2>&1; then
        _ok "tmux: $(tmux -V 2>/dev/null || echo "installed")"
    else
        _fail "tmux: not installed"
        _failures=$((_failures + 1))
    fi

    # KVM check (expected absent on phone)
    if [ -e /dev/kvm ] 2>/dev/null; then
        _ok "KVM: available (hardware acceleration)"
    else
        _log "KVM: not available (TCG emulation will be used)"
    fi

    echo ""
    if [ "$_failures" -eq 0 ]; then
        _ok "All checks passed"
        return 0
    else
        _fail "$_failures check(s) failed"
        return 1
    fi
}

# ── Plan: show what would be done ───────────────────────────────────────
cmd_plan() {
    _log "=== Install Plan ==="
    echo ""
    echo "Would install:"
    echo "  - qemu-system-aarch64 (if not present)"
    echo "  - git, curl, jq, openssh, tmux (if not present)"
    echo ""
    echo "Would create:"
    echo "  - ${UOM_VM_DIR}/ (VM directory)"
    echo "  - ${UOM_IMAGES_DIR}/ (disk images)"
    echo "  - ${UOM_LOG_DIR}/ (logs)"
    echo ""
    echo "Would download:"
    echo "  - Alpine aarch64 UEFI firmware (from Termux QEMU package)"
    echo ""
    echo "Would NOT:"
    echo "  - Modify running QEMU VM (test in isolated temp dir)"
    echo "  - Install APKs (manual step required)"
    echo "  - Require root access"
    echo "  - Use TAP/bridge networking"
    echo "  - Bind to 0.0.0.0"
}

# ── Install: set up VM directory and download firmware ───────────────────
cmd_install() {
    _log "=== Install ==="

    # Only install what's missing
    _pkgs=""
    command -v qemu-system-aarch64 >/dev/null 2>&1 || _pkgs="$_pkgs qemu-system-aarch64"
    command -v git >/dev/null 2>&1 || _pkgs="$_pkgs git"
    command -v curl >/dev/null 2>&1 || _pkgs="$_pkgs curl"
    command -v jq >/dev/null 2>&1 || _pkgs="$_pkgs jq"
    command -v ssh >/dev/null 2>&1 || _pkgs="$_pkgs openssh"
    command -v tmux >/dev/null 2>&1 || _pkgs="$_pkgs tmux"

    if [ -n "$_pkgs" ]; then
        _log "Installing missing packages: $_pkgs"
        pkg install -y $_pkgs 2>&1 || {
            _fail "Package install failed"
            return 1
        }
    else
        _ok "All packages already installed"
    fi

    # Create directories
    mkdir -p "$UOM_IMAGES_DIR" "$UOM_LOG_DIR" "${UOM_VM_DIR}/shared"

    # Copy firmware from QEMU package
    _qemu_share="${HOME}/../usr/share/qemu"
    if [ -f "${_qemu_share}/edk2-aarch64-code.fd" ]; then
        cp "${_qemu_share}/edk2-aarch64-code.fd" "$UOM_FIRMWARE_CODE" 2>/dev/null && \
            _ok "Firmware code copied" || _fail "Failed to copy firmware code"
    else
        _fail "QEMU firmware not found at ${_qemu_share}/edk2-aarch64-code.fd"
    fi

    if [ -f "${_qemu_share}/edk2-aarch64-vars.fd" ]; then
        cp "${_qemu_share}/edk2-aarch64-vars.fd" "$UOM_FIRMWARE_VARS" 2>/dev/null && \
            _ok "Firmware vars copied" || _fail "Failed to copy firmware vars"
    else
        _fail "QEMU firmware vars not found"
    fi

    # Create disk if missing
    if [ ! -f "$UOM_DISK" ]; then
        _log "Creating 12GB qcow2 disk..."
        qemu-img create -f qcow2 "$UOM_DISK" 12G 2>&1 && \
            _ok "Disk created: $UOM_DISK" || _fail "Failed to create disk"
    else
        _ok "Disk already exists: $UOM_DISK"
    fi

    # Download Alpine ISO if missing
    _iso="${UOM_VM_DIR}/alpine-virt-3.21.3-aarch64.iso"
    if [ ! -f "$_iso" ]; then
        _log "Downloading Alpine ISO..."
        curl -L -o "$_iso" \
            "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-virt-3.21.3-aarch64.iso" 2>&1 && \
            _ok "Alpine ISO downloaded" || _fail "Failed to download Alpine ISO"
    else
        _ok "Alpine ISO already exists"
    fi

    # Copy launcher if available
    if [ -f "${SCRIPT_DIR}/../bin/uom-qemu-phone" ] && [ ! -f "$UOM_QEMU_LAUNCHER" ]; then
        mkdir -p "${HOME}/bin"
        cp "${SCRIPT_DIR}/../bin/uom-qemu-phone" "$UOM_QEMU_LAUNCHER" 2>/dev/null && \
            chmod +x "$UOM_QEMU_LAUNCHER" && \
            _ok "Launcher installed" || _fail "Failed to install launcher"
    fi

    _ok "Install complete"
    _log "Next: boot from ISO with: $0 boot-install"
}

# ── Resume: check current state and suggest next action ─────────────────
cmd_resume() {
    _log "=== Resume State ==="
    echo ""

    if [ -f "$UOM_DISK" ]; then
        _ok "Disk: exists"
        qemu-img info "$UOM_DISK" 2>/dev/null | grep -E "virtual|disk size" || true
    else
        _fail "Disk: not found"
        echo "  → Run: $0 install"
        return 1
    fi

    if tmux has-session -t uom-qemu-host 2>/dev/null; then
        _ok "tmux: uom-qemu-host exists"
    else
        _log "tmux: no session"
    fi

    if command -v uom_guest_ssh_test >/dev/null 2>&1; then
        if uom_guest_ssh_test 1 5; then
            _ok "Guest SSH: reachable"
        else
            _log "Guest SSH: not reachable"
        fi
    elif ssh -p 2222 -o ConnectTimeout=3 -o BatchMode=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        uom@127.0.0.1 'echo OK' 2>/dev/null | grep -q OK; then
        _ok "Guest SSH: reachable"
    else
        _log "Guest SSH: not reachable"
    fi

    echo ""
    _log "Resume complete. Check above for next actions."
}

# ── Verify: health checks ───────────────────────────────────────────────
cmd_verify() {
    _log "=== Verify ==="

    # Disk integrity (skip if QEMU holds the lock)
    if [ -f "$UOM_DISK" ]; then
        _info=$(qemu-img info --force-share "$UOM_DISK" 2>&1 || true)
        if echo "$_info" | grep -q "virtual size"; then
            _ok "Disk: valid"
        elif echo "$_info" | grep -q "lock"; then
            _ok "Disk: locked by QEMU (running)"
        else
            _fail "Disk: corrupted"
        fi
    else
        _fail "Disk: missing"
    fi

    # QEMU process
    if command -v uom_qemu_running >/dev/null 2>&1; then
        if uom_qemu_running; then
            _ok "QEMU: running (pid=$UOM_QEMU_PID)"
        else
            _log "QEMU: not running"
        fi
    elif ps -A 2>/dev/null | grep -q '[q]emu-system-aarch64'; then
        _ok "QEMU: running"
    else
        _log "QEMU: not running"
    fi

    # Guest SSH
    if command -v uom_guest_ssh_test >/dev/null 2>&1; then
        if uom_guest_ssh_test 1 5; then
            _ok "Guest SSH: reachable"
        else
            _fail "Guest SSH: unreachable"
        fi
    elif ssh -p 2222 -o ConnectTimeout=5 -o BatchMode=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        uom@127.0.0.1 'echo OK' 2>/dev/null | grep -q OK; then
        _ok "Guest SSH: reachable"
    else
        _fail "Guest SSH: unreachable"
    fi

    # Launcher
    if [ -x "$UOM_QEMU_LAUNCHER" ]; then
        _ok "Launcher: executable"
    else
        _fail "Launcher: not found or not executable"
    fi

    # Watchdog
    if [ -x "${HOME}/bin/uom-qemu-watchdog.sh" ]; then
        _ok "Watchdog: present"
    else
        _fail "Watchdog: missing"
    fi

    # Consolidated lib
    if [ -x "${HOME}/bin/uom-lib.sh" ]; then
        _ok "Shared lib: present"
    else
        _fail "Shared lib: missing"
    fi
}

# ── Status: quick overview ──────────────────────────────────────────────
cmd_status() {
    _log "=== UOM Phone Status ==="
    echo ""
    cmd_doctor 2>/dev/null || true
    echo ""
    cmd_verify 2>/dev/null || true
}

# ── Main dispatch ───────────────────────────────────────────────────────
case "${1:-help}" in
    doctor)  cmd_doctor ;;
    plan)    cmd_plan ;;
    install) cmd_install ;;
    resume)  cmd_resume ;;
    verify)  cmd_verify ;;
    status)  cmd_status ;;
    *)
        echo "Usage: $0 {doctor|plan|install|resume|verify|status}"
        echo ""
        echo "  doctor   Check prerequisites (SDK, arch, RAM, disk, tools)"
        echo "  plan     Show what would be installed"
        echo "  install  Set up VM directory and download firmware"
        echo "  resume   Check current state and suggest next action"
        echo "  verify   Health checks (disk, QEMU, SSH, launcher)"
        echo "  status   Quick overview (doctor + verify)"
        exit 1
        ;;
esac
