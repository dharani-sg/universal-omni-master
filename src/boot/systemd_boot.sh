#!/bin/sh
# systemd_boot.sh — systemd-boot backend. BLS Type #1 entry parsing.

_sd_entries_dir() {
    for _p in /boot/loader/entries /boot/efi/loader/entries; do
        _d="$(_sysfile "$_p")"
        [ -d "$_d" ] && { printf '%s' "$_d"; return 0; }
    done
    return 1
}

_sd_loader_conf() {
    for _p in /boot/loader/loader.conf /boot/efi/loader/loader.conf; do
        _f="$(_sysfile "$_p")"
        [ -r "$_f" ] && { printf '%s' "$_f"; return 0; }
    done
    return 1
}

boot_list_entries() {
    _dir="$(_sd_entries_dir)" || { log_error "no loader/entries/ found"; return 1; }
    for _f in "$_dir"/*.conf; do
        [ -r "$_f" ] || continue
        awk '/^title/ { $1=""; sub(/^ /, ""); print }' "$_f"
    done
}

boot_get_default() {
    # Try EFI variable first (authoritative on live systems)
    _def="$(_efi_read LoaderEntryDefault 2>/dev/null)"
    [ -n "$_def" ] && { printf '%s' "$_def"; return 0; }
    # Fallback to loader.conf
    _conf="$(_sd_loader_conf)" || return 1
    awk '/^default/ {print $2; exit}' "$_conf"
}

boot_entry_count() {
    _dir="$(_sd_entries_dir)" || { echo 0; return 1; }
    _count=0
    for _f in "$_dir"/*.conf; do [ -r "$_f" ] && _count=$((_count+1)); done
    echo "$_count"
}

boot_verify_entry() {
    _id="$1"
    _dir="$(_sd_entries_dir)" || return 1
    [ -r "$_dir/$_id" ] || [ -r "$_dir/${_id}.conf" ]
}

boot_regenerate() {
    _boot_guard_mutation || return $?
    run_as_root bootctl update
}
