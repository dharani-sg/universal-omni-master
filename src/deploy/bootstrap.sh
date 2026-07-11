#!/bin/sh
# deploy/bootstrap.sh — distro-specific base system installation.

bootstrap_install() {
    _distro="$1"
    _target="${2:-$DEPLOY_TARGET}"

    log_info "Installing $_distro base system to $_target..."

    case "$_distro" in
        alpine)
            command -v apk >/dev/null 2>&1 || { log_error "apk not found"; return 1; }
            apk add --root "$_target" --initdb \
                --repositories-file /etc/apk/repositories \
                alpine-base || return 1
            ;;
        void)
            command -v xbps-install >/dev/null 2>&1 || { log_error "xbps-install not found"; return 1; }
            mkdir -p "$_target/var/db/xbps/keys"
            cp /var/db/xbps/keys/* "$_target/var/db/xbps/keys/" 2>/dev/null || true
            xbps-install -S -r "$_target" \
                -R https://repo-fastly.voidlinux.org/current -y \
                base-system || return 1
            ;;
        arch|artix)
            command -v pacstrap >/dev/null 2>&1 || { log_error "pacstrap not found"; return 1; }
            pacstrap "$_target" base linux linux-firmware || return 1
            ;;
        debian)
            command -v debootstrap >/dev/null 2>&1 || { log_error "debootstrap not found"; return 1; }
            debootstrap stable "$_target" http://deb.debian.org/debian || return 1
            ;;
        *)
            log_error "unsupported distro: $_distro"
            log_info "supported: $(deploy_list_distros)"
            return 1
            ;;
    esac

    log_info "$_distro base system installed to $_target"
}
