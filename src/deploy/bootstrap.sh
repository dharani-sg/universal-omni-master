#!/bin/sh
# deploy/bootstrap.sh — distro base installation with cross-libc correctness.

bootstrap_install() {
    _distro="${1:-$DEPLOY_DISTRO}"
    _target="${2:-$DEPLOY_TARGET}"
    _mirror="${DEPLOY_MIRROR:-}"

    log_info "=== BOOTSTRAP: $_distro -> $_target ==="
    mkdir -p "$_target"

    case "$_distro" in
        alpine)
            command -v apk >/dev/null 2>&1 || { log_error "apk not found on host"; return 1; }
            _mirror="${_mirror:-https://dl-cdn.alpinelinux.org/alpine/latest-stable/main}"
            apk --arch "$(uname -m)" \
                --root "$_target" \
                --repository "$_mirror" \
                --initdb add alpine-base
            [ -n "${DEPLOY_PACKAGES:-}" ] && apk --root "$_target" add $DEPLOY_PACKAGES
            ;;

        void)
            command -v xbps-install >/dev/null 2>&1 || { log_error "xbps-install not found"; return 1; }
            _mirror="${_mirror:-https://repo-fastly.voidlinux.org/current}"
            xbps-install -S -y -r "$_target" -R "$_mirror" base-system
            [ -n "${DEPLOY_PACKAGES:-}" ] && xbps-install -r "$_target" -y $DEPLOY_PACKAGES
            ;;

        arch)
            command -v pacstrap >/dev/null 2>&1 || { log_error "pacstrap not found"; return 1; }
            # CRITICAL: -K generates a fresh keyring in target, bypassing host's
            # missing/incompatible Arch keys. Without -K, signature verification fails.
            pacstrap -K "$_target" base linux linux-firmware btrfs-progs
            [ -n "${DEPLOY_PACKAGES:-}" ] && pacstrap -K "$_target" $DEPLOY_PACKAGES
            ;;

        artix)
            command -v pacstrap >/dev/null 2>&1 || { log_error "pacstrap not found"; return 1; }
            _init="${DEPLOY_INIT:-openrc}"
            pacstrap -K "$_target" base base-devel linux linux-firmware
            case "$_init" in
                openrc) pacstrap -K "$_target" openrc elogind-openrc ;;
                runit)  pacstrap -K "$_target" runit-rc elogind-runit ;;
                dinit)  pacstrap -K "$_target" dinit elogind-dinit ;;
                s6)     pacstrap -K "$_target" s6-rc ;;
            esac
            ;;

        debian|ubuntu)
            command -v debootstrap >/dev/null 2>&1 || { log_error "debootstrap not found"; return 1; }
            # CRITICAL: musl host returns "musl-linux-amd64" instead of "amd64" from
            # dpkg --print-architecture. Without --arch=amd64, debootstrap looks for
            # a non-existent binary-musl-linux-amd64 Packages file and fails fatally.
            _suite="${DEPLOY_SUITE:-bookworm}"
            _mirror="${_mirror:-https://deb.debian.org/debian}"
            debootstrap --arch=amd64 "$_suite" "$_target" "$_mirror"
            [ -n "${DEPLOY_PACKAGES:-}" ] && chroot "$_target" apt-get install -y $DEPLOY_PACKAGES
            ;;

        fedora)
            command -v dnf >/dev/null 2>&1 || { log_error "dnf not found"; return 1; }
            dnf --installroot="$_target" --releasever=latest install -y \
                fedora-release @core
            ;;

        *)
            log_error "unsupported distro: $_distro"
            return 1
            ;;
    esac

    log_info "Bootstrap complete: $_distro"
}
