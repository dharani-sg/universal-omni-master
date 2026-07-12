#!/bin/sh
# deploy/common.sh — shared deploy utilities.

# All deploy operations require real root — no fixture mode.
deploy_require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "omni-deploy must run as root"
        return 1
    fi
    return 0
}

# Refuse to deploy if OMNI_SYSROOT is set (deploy is ALWAYS live)
deploy_guard() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        log_error "REFUSING: omni-deploy does not run in fixture mode."
        return 126
    fi
    return 0
}

# State tracking — each phase writes its status to a state file
DEPLOY_TARGET="${DEPLOY_TARGET:-/mnt}"




# Confirmation gate — requires explicit user input before destructive actions
deploy_confirm() {
    _msg="$1"
    printf '\n\033[1;33m⚠ WARNING:\033[0m %s\n' "$_msg"
    printf 'Type YES to proceed, anything else to abort: '
    read -r _answer
    [ "$_answer" = "YES" ] && return 0
    log_info "user aborted at: $_msg"
    return 1
}

# Supported distros and their bootstrap methods
deploy_list_distros() {
    printf '  alpine     apk add --root --initdb\n'
    printf '  void       xbps-install -S -r -R\n'
    printf '  arch       pacstrap\n'
    printf '  debian     debootstrap\n'
    printf '  artix      pacstrap (+ non-systemd init)\n'
}

# Supported filesystems
deploy_list_filesystems() {
    printf '  ext4       Simple, robust, universal\n'
    printf '  btrfs      Snapshots, subvolumes, compression\n'
    printf '  xfs        High-performance, large files\n'
    printf '  f2fs       Flash-optimized (SSD/eMMC)\n'
}

# Supported bootloaders
deploy_list_bootloaders() {
    printf '  grub           BIOS + UEFI, most flexible\n'
    printf '  systemd-boot   UEFI only, simple, fast\n'
    printf '  limine         UEFI + BIOS, lightweight\n'
}

# Supported init systems
deploy_list_inits() {
    printf '  systemd    Arch, Debian, Fedora, Ubuntu\n'
    printf '  openrc     Alpine, Gentoo, Artix-openrc\n'
    printf '  runit      Void, Artix-runit\n'
    printf '  dinit      Chimera, Artix-dinit\n'
    printf '  s6         Artix-s6, Obarun\n'
}

# Auto-detect best init system for a distro
deploy_auto_detect_init() {
    case "${1:-}" in
        alpine)  echo openrc ;;
        void)    echo runit ;;
        arch)    echo systemd ;;
        artix)   echo "${DEPLOY_INIT:-openrc}" ;;
        debian|ubuntu|fedora) echo systemd ;;
        chimera) echo dinit ;;
        *) echo systemd ;;
    esac
}
