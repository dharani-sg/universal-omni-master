#!/bin/sh
# src/security/sbat.sh — M14: SBAT (Secure Boot Advanced Targeting) auditing.
# Prevents Secure Boot rollback attacks by verifying component_generation
# in the .sbat ELF/PE section meets a minimum baseline. Read-only; degrades
# gracefully if the binary has no .sbat section or tools are absent.

# security_sbat_extract <path> — print raw .sbat CSV content to stdout.
# Returns 0 with empty output if the section is absent (not an error state
# on this legacy-BIOS host, since GRUB here predates SBAT enforcement).
security_sbat_extract() {
    _bin="${1:?security_sbat_extract: path required}"
    [ -f "$_bin" ] || { printf 'sbat: file not found: %s\n' "$_bin" >&2; return 1; }

    if command -v objdump >/dev/null 2>&1; then
        objdump -s -j .sbat "$_bin" 2>/dev/null | \
            sed -n 's/^ [0-9a-f]* \([0-9a-f ]*\).*/\1/p' | \
            tr -d ' \n' | sed 's/\(..\)/\1\n/g' | \
            awk 'BEGIN{ORS=""} {printf "%c", strtonum("0x" $0)}' 2>/dev/null
        return 0
    fi

    if command -v readelf >/dev/null 2>&1; then
        readelf -x .sbat "$_bin" 2>/dev/null | \
            sed -n 's/^  0x[0-9a-f]* \([0-9a-f ]*\).*/\1/p' | \
            tr -d ' \n' | sed 's/\(..\)/\1\n/g' | \
            awk 'BEGIN{ORS=""} {printf "%c", strtonum("0x" $0)}' 2>/dev/null
        return 0
    fi

    printf 'sbat: neither objdump nor readelf available — cannot extract\n' >&2
    return 0
}

# security_sbat_audit <path> <component-name> <min-generation>
# CSV format per SBAT spec: component,generation,vendor,vendor_url,...
# Returns: 0=meets-or-exceeds baseline / no-section (audit-only host),
#          1=below baseline (rollback risk).
security_sbat_audit() {
    _bin="${1:?path required}"
    _component="${2:?component name required}"
    _min_gen="${3:?minimum generation required}"

    _sbat_csv=$(security_sbat_extract "$_bin" 2>/dev/null)

    if [ -z "$_sbat_csv" ]; then
        printf 'sbat_audit: no .sbat section found in %s — cannot verify (host has no Secure Boot enforcement)\n' "$_bin" >&2
        printf 'status=no_sbat_section audit=skipped\n'
        return 0
    fi

    _line=$(printf '%s' "$_sbat_csv" | grep "^${_component}," | head -1)
    if [ -z "$_line" ]; then
        printf 'sbat_audit: component "%s" not found in SBAT data\n' "$_component" >&2
        printf 'status=component_not_found audit=skipped\n'
        return 0
    fi

    _gen=$(printf '%s' "$_line" | cut -d, -f2)
    case "$_gen" in
        ''|*[!0-9]*)
            printf 'sbat_audit: non-numeric generation field: %s\n' "$_gen" >&2
            printf 'status=parse_error audit=skipped\n'
            return 0 ;;
    esac

    if [ "$_gen" -ge "$_min_gen" ]; then
        printf 'status=ok generation=%s minimum=%s\n' "$_gen" "$_min_gen"
        return 0
    else
        printf 'sbat_audit: ROLLBACK RISK — %s generation %s is below minimum %s\n' \
            "$_component" "$_gen" "$_min_gen" >&2
        printf 'status=below_baseline generation=%s minimum=%s\n' "$_gen" "$_min_gen"
        return 1
    fi
}
