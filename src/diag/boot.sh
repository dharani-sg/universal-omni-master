#!/bin/sh
# diag/boot.sh — bootloader and early dmesg timing audit.

audit_boot_timing_gaps() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        audit_emit info boot "fixture mode: dmesg timing skipped"
        return 0
    fi

    command -v dmesg >/dev/null 2>&1 || return 0

    tmp="$OMNI_AUDIT_TMP/dmesg"
    dmesg > "$tmp" 2>/dev/null || return 0

    awk '
    {
        t=$1
        gsub(/\[/,"",t); gsub(/\]/,"",t)
        t+=0
        if (t > 35) exit
        if (prev != "" && (t-prev) > 10)
            printf "%s %s\n", t-prev, $0
        prev=t
    }' "$tmp" > "$OMNI_AUDIT_TMP/dmesg-gaps"

    while read -r gap rest; do
        [ -n "$gap" ] || continue
        audit_emit warn boot "large early dmesg gap ${gap}s: $rest"
    done < "$OMNI_AUDIT_TMP/dmesg-gaps"
}

audit_boot() {
    audit_section "BOOT"

    bl="$(./bin/omni-boot detect 2>/dev/null || echo unknown)"
    audit_emit info boot "bootloader=$bl"

    case "$bl" in
        grub|systemd-boot)
            count="$(./bin/omni-boot count 2>/dev/null || echo 0)"
            def="$(./bin/omni-boot default 2>/dev/null || true)"
            audit_emit info boot "entries=$count default=${def:-unknown}"
            [ "${count:-0}" -eq 0 ] && audit_emit fail boot "bootloader detected but zero entries parsed"
            ;;
        unknown)
            audit_emit warn boot "bootloader unknown"
            ;;
    esac

    audit_boot_timing_gaps
}
