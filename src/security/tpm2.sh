#!/bin/sh
# src/security/tpm2.sh — M14: TPM2-LUKS binding, probing, and PCR auditing.
# On hardware without a TPM (this host: legacy BIOS, no /sys/class/tpm),
# every function degrades to a structured warning and returns 0 — never
# hard-fails, never crashes callers.

OMNI_DATA="${OMNI_DATA:-/var/lib/omni-master}"
SEC_TPM2_BASELINE="${SEC_TPM2_BASELINE:-$OMNI_DATA/security/tpm2_baseline.json}"

_sec_guard() {
    if [ -n "${OMNI_SYSROOT:-}" ]; then
        printf 'security: REFUSING mutation — OMNI_SYSROOT set\n' >&2
        return 126
    fi
    return 0
}

# security_tpm2_probe — detect TPM2 hardware + required tooling.
# Always returns 0. Emits structured status lines; caller parses if needed.
security_tpm2_probe() {
    _have_dev=no
    _have_tool=no

    [ -e /sys/class/tpm/tpm0 ] && _have_dev=yes
    command -v tpm2_pcrread >/dev/null 2>&1 && _have_tool=yes

    if [ "$_have_dev" = no ]; then
        printf 'tpm2: UNAVAILABLE — /sys/class/tpm/tpm0 missing (no TPM2 hardware detected)\n' >&2
        printf 'status=unavailable device=no tool=%s\n' "$_have_tool"
        return 0
    fi

    if [ "$_have_tool" = no ]; then
        printf 'tpm2: DEGRADED — device present but tpm2_pcrread not installed\n' >&2
        printf 'status=degraded device=yes tool=no\n'
        return 0
    fi

    printf 'status=ready device=yes tool=yes\n'
    return 0
}

# security_tpm2_enroll <luks-device> [pcr-list] — bind LUKS to TPM2 PCRs.
# MUTATING. Requires OMNI_SYSROOT guard. Prefers clevis, falls back to
# raw tpm2-tools + cryptsetup if clevis is absent.
security_tpm2_enroll() {
    _sec_guard || return $?

    _dev="${1:?security_tpm2_enroll: LUKS device required}"
    _pcrs="${2:-0,7}"

    _probe_out=$(security_tpm2_probe)
    case "$_probe_out" in
        *status=unavailable*)
            printf 'tpm2: cannot enroll — hardware unavailable\n' >&2
            return 1 ;;
    esac

    if ! [ -b "$_dev" ]; then
        printf 'tpm2: enroll target is not a block device: %s\n' "$_dev" >&2
        return 1
    fi

    if command -v clevis >/dev/null 2>&1; then
        printf 'tpm2: enrolling %s via clevis (pcrs=%s)\n' "$_dev" "$_pcrs"
        _cfg=$(printf '{"pcr_bank":"sha256","pcr_ids":"%s"}' "$_pcrs")
        clevis luks bind -d "$_dev" tpm2 "$_cfg"
        return $?
    fi

    if command -v tpm2_createprimary >/dev/null 2>&1 && command -v cryptsetup >/dev/null 2>&1; then
        printf 'tpm2: clevis not found — raw tpm2-tools path not yet automated in this release\n' >&2
        printf 'tpm2: manual steps required: tpm2_createprimary, tpm2_policypcr, cryptsetup luksAddKey\n' >&2
        return 1
    fi

    printf 'tpm2: no enrollment tool available (clevis or tpm2-tools+cryptsetup)\n' >&2
    return 1
}

# security_tpm2_audit — read current PCR banks, compare to stored baseline.
# Read-only, no guard needed. Degrades gracefully if hardware/tools absent.
security_tpm2_audit() {
    _probe_out=$(security_tpm2_probe)
    case "$_probe_out" in
        *status=unavailable*|*status=degraded*)
            printf 'tpm2_audit: skipped — %s\n' "$_probe_out"
            printf 'audit=skipped\n'
            return 0 ;;
    esac

    mkdir -p "$(dirname "$SEC_TPM2_BASELINE")" 2>/dev/null || true

    _current=$(tpm2_pcrread sha256:0,7 2>/dev/null) || {
        printf 'tpm2_audit: tpm2_pcrread failed at runtime\n' >&2
        printf 'audit=error\n'
        return 0
    }

    if [ ! -f "$SEC_TPM2_BASELINE" ]; then
        printf '{"pcr_read":"%s"}\n' "$_current" > "$SEC_TPM2_BASELINE" 2>/dev/null
        printf 'tpm2_audit: baseline created (first run)\n'
        printf 'audit=baseline_created\n'
        return 0
    fi

    if grep -qF "$_current" "$SEC_TPM2_BASELINE" 2>/dev/null; then
        printf 'audit=match\n'
    else
        printf 'tpm2_audit: WARNING — PCR values differ from stored baseline\n' >&2
        printf 'audit=mismatch\n'
    fi
    return 0
}
