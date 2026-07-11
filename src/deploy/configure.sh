#!/bin/sh
# deploy/configure.sh — post-bootstrap system configuration.

deploy_set_hostname() {
    _hostname="$1"
    _target="${2:-$DEPLOY_TARGET}"
    printf '%s\n' "$_hostname" > "$_target/etc/hostname"
    log_info "hostname set: $_hostname"
}

deploy_set_locale() {
    _locale="${1:-en_US.UTF-8}"
    _target="${2:-$DEPLOY_TARGET}"

    # systemd-based
    if [ -d "$_target/etc/locale.conf" ] || [ -d "$_target/usr/lib/systemd" ]; then
        printf 'LANG=%s\n' "$_locale" > "$_target/etc/locale.conf"
    fi

    # musl-based (Alpine)
    if [ -f "$_target/etc/profile.d/locale.sh" ] || [ -d "$_target/etc/profile.d" ]; then
        mkdir -p "$_target/etc/profile.d"
        printf 'export LANG=%s\nexport LC_ALL=%s\n' "$_locale" "$_locale" \
            > "$_target/etc/profile.d/omni-locale.sh"
    fi

    log_info "locale set: $_locale"
}

deploy_create_user() {
    _user="$1"
    _target="${2:-$DEPLOY_TARGET}"

    chroot_exec "$_target" "
        adduser -D '$_user' 2>/dev/null || useradd -m '$_user' 2>/dev/null
        # Add to wheel/sudo group
        addgroup '$_user' wheel 2>/dev/null || usermod -aG wheel '$_user' 2>/dev/null || true
    "
    log_info "user created: $_user (in wheel group)"
}

deploy_copy_resolv() {
    _target="${1:-$DEPLOY_TARGET}"
    cp /etc/resolv.conf "$_target/etc/resolv.conf" 2>/dev/null || true
}
