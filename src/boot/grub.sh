#!/bin/sh
# grub.sh — GRUB bootloader backend.

_grub_cfg() {
    for _p in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
        _f="$(_sysfile "$_p")"
        [ -r "$_f" ] && { printf '%s' "$_f"; return 0; }
    done
    return 1
}

boot_list_entries() {
    _cfg="$(_grub_cfg)" || { log_error "grub.cfg not found"; return 1; }
    awk -F"'" '/^menuentry / {print $2}' "$_cfg"
}

boot_get_default() {
    _cfg="$(_grub_cfg)" || return 1
    awk -F'"' '/set default=/ && NF>=3 {print $2; exit}' "$_cfg"
}

boot_entry_count() {
    _cfg="$(_grub_cfg)" || { echo 0; return 1; }
    grep -c '^menuentry ' "$_cfg"
}

boot_verify_entry() {
    _id="$1"
    _cfg="$(_grub_cfg)" || return 1
    grep -q "menuentry.*--id $_id" "$_cfg" && return 0
    grep -q "menuentry.*'$_id'" "$_cfg" && return 0
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
