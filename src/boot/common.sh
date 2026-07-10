#!/bin/sh
# boot/common.sh — bootloader EAL: detection, EFI variable simulation, mutation guard.

_boot_guard_mutation() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        log_error "REFUSING boot mutation: OMNI_SYSROOT is set (fixture/offline mode)."
        return 126
    fi
    return 0
}

_efi_vardir() { printf '%s' "$(_sysfile /sys/firmware/efi/efivars)"; }

_efi_read() {
    _vname="$1"
    _guid="${2:-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f}"
    _f="$(_efi_vardir)/${_vname}-${_guid}"
    [ -r "$_f" ] || return 1
    dd if="$_f" bs=1 skip=4 2>/dev/null | tr -d '\000'
}

_efi_write_fixture() {
    [ -n "${OMNI_SYSROOT:-}" ] || { log_error "_efi_write_fixture: fixture mode only"; return 1; }
    _vname="$1"; _guid="$2"; _val="$3"
    _dir="$(_efi_vardir)"; mkdir -p "$_dir"
    _f="$_dir/${_vname}-${_guid}"
    printf '\007\000\000\000' > "$_f"
    printf '%s' "$_val" | sed 's/./&\n/g' | while read -r c; do
        printf '%s\000' "$c"
    done >> "$_f"
}

_esp_path() {
    for _p in /boot/efi /boot /efi; do
        _have "${_p}/EFI" && { printf '%s' "$(_sysfile "$_p")"; return 0; }
    done
    # Fallback: check for grub.cfg directly under /boot (no EFI subdir)
    _have "/boot/grub/grub.cfg" && { printf '%s' "$(_sysfile /boot)"; return 0; }
    return 1
}

boot_detect() {
    # systemd-boot: loader.conf or EFI/systemd/ on ESP
    { _have "/boot/loader/loader.conf" || _have "/boot/efi/loader/loader.conf" || \
      _have "/boot/EFI/systemd" || _have "/boot/efi/EFI/systemd"; } && { echo "systemd-boot"; return 0; }

    # GRUB: grub.cfg under /boot/grub or /boot/grub2
    { _have "/boot/grub/grub.cfg" || _have "/boot/grub2/grub.cfg"; } && { echo "grub"; return 0; }

    # Limine: limine.conf at ESP root or /boot/limine/
    { _have "/boot/limine.conf" || _have "/boot/limine/limine.conf" || \
      _have "/boot/efi/limine.conf"; } && { echo "limine"; return 0; }

    # rEFInd: refind.conf
    _have "/boot/efi/EFI/refind/refind.conf" && { echo "refind"; return 0; }

    echo "unknown"; return 1
}

boot_is_uefi() {
    _have "/sys/firmware/efi" && return 0
    return 1
}

boot_is_secureboot() {
    _sb="$(_sysfile /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c)"
    [ -r "$_sb" ] || return 1
    _val=$(dd if="$_sb" bs=1 skip=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' ')
    [ "$_val" = "01" ] && return 0
    return 1
}
