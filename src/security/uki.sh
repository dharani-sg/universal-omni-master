#!/bin/sh
# src/security/uki.sh — M14: UKI/PE signature validation.
# On this host (legacy BIOS, GRUB, no sbverify), degrades to structural
# integrity checks (MZ magic + PE header offset) via readelf/hexdump.

# security_uki_verify <path-to-efi-or-uki> [cert-path]
# Returns: 0 = verified/structurally-valid, 1 = invalid, 2 = bad args.
# Never crashes; always emits a status= line for machine parsing.
security_uki_verify() {
    _bin="${1:?security_uki_verify: path required}"
    _cert="${2:-}"

    [ -f "$_bin" ] || {
        printf 'uki_verify: file not found: %s\n' "$_bin" >&2
        printf 'status=error reason=missing_file\n'
        return 2
    }

    if command -v sbverify >/dev/null 2>&1; then
        if [ -n "$_cert" ]; then
            if sbverify --cert "$_cert" "$_bin" >/dev/null 2>&1; then
                printf 'status=verified method=sbverify\n'
                return 0
            else
                printf 'uki_verify: sbverify signature check FAILED for %s\n' "$_bin" >&2
                printf 'status=invalid method=sbverify\n'
                return 1
            fi
        else
            printf 'uki_verify: sbverify present but no --cert supplied; skipping crypto check\n' >&2
        fi
    else
        printf 'uki_verify: sbverify not installed — falling back to structural check\n' >&2
    fi

    # BusyBox-safe structural fallback: MZ magic + PE signature offset.
    # DOS header: bytes 0-1 = "MZ"; bytes 0x3C-0x3F = little-endian offset
    # to the PE header, which must contain "PE\0\0".
    _magic=$(dd if="$_bin" bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$_magic" != "4d5a" ]; then
        printf 'uki_verify: no MZ magic — not a valid PE/EFI binary\n' >&2
        printf 'status=invalid method=structural reason=no_mz_magic\n'
        return 1
    fi

    _pe_off_hex=$(dd if="$_bin" bs=1 skip=60 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
    # little-endian 4 bytes -> reverse byte order for arithmetic
    _b1=${_pe_off_hex%??????}
    _rest=${_pe_off_hex#??}
    _b2=${_rest%????}
    _rest=${_rest#??}
    _b3=${_rest%??}
    _b4=${_rest#??}
    _pe_off=$((0x${_b4}${_b3}${_b2}${_b1}))

    _pe_sig=$(dd if="$_bin" bs=1 skip="$_pe_off" count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$_pe_sig" != "50450000" ]; then
        printf 'uki_verify: PE signature not found at computed offset %d\n' "$_pe_off" >&2
        printf 'status=invalid method=structural reason=no_pe_signature\n'
        return 1
    fi

    printf 'uki_verify: structural check passed (MZ + PE header present); NOT a cryptographic guarantee\n'
    printf 'status=structurally_valid method=structural\n'
    return 0
}
