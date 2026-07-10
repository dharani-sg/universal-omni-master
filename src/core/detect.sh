#!/bin/sh
# detect.sh — distro / init / libc / arch / pkgmgr / priv detection. SYSROOT-aware.

detect_arch() { uname -m 2>/dev/null || echo unknown; }

detect_distro() {
    _osr="$(_sysfile /etc/os-release)"
    _id=""
    [ -r "$_osr" ] && _id="$(_osrel_field "$_osr" ID)"
    [ -z "$_id" ] && { _osr2="$(_sysfile /usr/lib/os-release)"; [ -r "$_osr2" ] && _id="$(_osrel_field "$_osr2" ID)"; }
    [ -z "$_id" ] && _have /etc/alpine-release && _id="alpine"
    printf '%s' "${_id:-unknown}"
}

detect_init() {
    _comm="$(_read /proc/1/comm | tr -d '\n')"
    case "$_comm" in
        systemd)    echo systemd; return 0 ;;
        runit)      echo runit;   return 0 ;;
        s6-svscan)  echo s6;      return 0 ;;
        dinit)      echo dinit;   return 0 ;;
    esac
    # Fallback via marker paths (also covers busybox 'init' -> openrc)
    _have /run/systemd/system && { echo systemd; return 0; }
    { _have /run/openrc || _have /sbin/openrc || _have /etc/init.d/. ; } && { echo openrc; return 0; }
    _have /etc/runit && { echo runit; return 0; }
    _have /etc/s6    && { echo s6; return 0; }
    { _have /etc/dinit.d || _have /sbin/dinit ; } && { echo dinit; return 0; }
    echo unknown
}

detect_libc() {
    # musl ships /lib/ld-musl-<arch>.so.1
    _root="$(_sysfile /lib)"
    if ls "$_root"/ld-musl-* >/dev/null 2>&1; then echo musl; return 0; fi
    if _have /lib64/ld-linux-x86-64.so.2 || _have /lib/x86_64-linux-gnu/libc.so.6; then echo glibc; return 0; fi
    # Live fallback
    if [ -z "$OMNI_SYSROOT" ] && command -v ldd >/dev/null 2>&1; then
        if ldd --version 2>&1 | grep -qi musl; then echo musl; return 0; fi
        if ldd --version 2>&1 | grep -qi 'gnu\|glibc'; then echo glibc; return 0; fi
    fi
    echo unknown
}

detect_pkgmgr() {
    resolve_bin apk            /sbin/apk /usr/bin/apk           >/dev/null 2>&1 && { echo apk; return 0; }
    resolve_bin xbps-install   /usr/bin/xbps-install            >/dev/null 2>&1 && { echo xbps; return 0; }
    resolve_bin pacman         /usr/bin/pacman                  >/dev/null 2>&1 && { echo pacman; return 0; }
    resolve_bin dnf            /usr/bin/dnf                     >/dev/null 2>&1 && { echo dnf; return 0; }
    resolve_bin apt-get        /usr/bin/apt-get                 >/dev/null 2>&1 && { echo apt; return 0; }
    resolve_bin zypper         /usr/bin/zypper                  >/dev/null 2>&1 && { echo zypper; return 0; }
    resolve_bin emerge         /usr/bin/emerge                  >/dev/null 2>&1 && { echo emerge; return 0; }
    resolve_bin nix-env        /usr/bin/nix-env /run/current-system/sw/bin/nix-env >/dev/null 2>&1 && { echo nix; return 0; }
    echo none
}

detect_priv() {
    resolve_bin doas /usr/bin/doas >/dev/null 2>&1 && { echo doas; return 0; }
    resolve_bin sudo /usr/bin/sudo >/dev/null 2>&1 && { echo sudo; return 0; }
    echo none
}

detect_bootloader() {
    _have /boot/grub/grub.cfg          && { echo grub; return 0; }
    _have /boot/grub2/grub.cfg         && { echo grub; return 0; }
    _have /boot/loader/loader.conf     && { echo systemd-boot; return 0; }
    { _have /boot/limine.conf || _have /boot/limine.cfg ; } && { echo limine; return 0; }
    _have /boot/EFI/refind/refind.conf && { echo refind; return 0; }
    echo unknown
}

# Seat/session model — the Part-A2 corrected matrix.
detect_seat_model() {
    _init="$(detect_init)"
    if [ "$_init" = "systemd" ]; then echo "logind"; return 0; fi
    _seatd=no; _elogind=no
    { _have /usr/bin/seatd || _have /run/seatd.sock ; } && _seatd=yes
    { _have /usr/bin/elogind || _have /usr/libexec/elogind/elogind || _have /run/user ; } && _elogind=yes
    if [ "$_seatd" = yes ] && [ "$_elogind" = yes ]; then echo "seatd+elogind"; return 0; fi
    [ "$_seatd" = yes ] && { echo "seatd"; return 0; }
    [ "$_elogind" = yes ] && { echo "elogind"; return 0; }
    echo "none"
}
