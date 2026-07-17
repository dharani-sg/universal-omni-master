#!/bin/sh
# grub.sh — GRUB bootloader backend.

_grub_cfg_readable() {
    [ -r "$1" ] && return 0
    [ -f "$1" ] && [ "$(id -u)" != "0" ] && [ -x /usr/bin/doas ] && return 0
    [ -f "$1" ] && [ "$(id -u)" != "0" ] && [ -x /usr/bin/sudo ] && return 0
    return 1
}

_grub_cfg_cat() {
    _f="$1"
    if [ -r "$_f" ]; then
        cat "$_f"
    elif command -v doas >/dev/null 2>&1; then
        doas cat "$_f" 2>/dev/null
    elif command -v sudo >/dev/null 2>&1; then
        sudo cat "$_f" 2>/dev/null
    fi
}

_grub_cfg() {
    for _p in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
        _f="$(_sysfile "$_p")"
        _grub_cfg_readable "$_f" && { printf '%s' "$_f"; return 0; }
    done
    return 1
}

boot_list_entries() {
    _cfg="$(_grub_cfg)" || { log_error "grub.cfg not found"; return 1; }
    _grub_cfg_cat "$_cfg" | awk -F"'" '/^menuentry / {print $2}'
}

boot_get_default() {
    _cfg="$(_grub_cfg)" || return 1
    _grub_cfg_cat "$_cfg" | awk -F'"' '/set default=/ && NF>=3 {print $2; exit}'
}

boot_entry_count() {
    _cfg="$(_grub_cfg)" || { echo 0; return 1; }
    _grub_cfg_cat "$_cfg" | grep -c '^menuentry '
}

boot_verify_entry() {
    _id="$1"
    _cfg="$(_grub_cfg)" || return 1
    _grub_cfg_cat "$_cfg" | grep -q "menuentry.*--id $_id" && return 0
    _grub_cfg_cat "$_cfg" | grep -q "menuentry.*'$_id'" && return 0
    return 1
}

boot_regenerate() {
    _boot_guard_mutation || return $?
    if command -v grub-mkconfig >/dev/null 2>&1; then
        run_as_root grub-mkconfig -o /boot/grub/grub.cfg
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        run_as_root grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        log_error "grub-mkconfig not found"; return 1
    fi
}
