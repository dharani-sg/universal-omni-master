#!/bin/sh
# scripts/omni-seed.sh — M18-A: Universal Omni-Seed bootstrap.
# Safe mode: dry-run/plan only by default. Destructive apply is deferred to M18-B.
set -u

OMNI_SEED_VERSION="0.18.0-a"
OMNI_SEED_STATE="${OMNI_SEED_STATE:-/tmp/omni-seed-state.conf}"
OMNI_SEED_MONOLITH="${OMNI_SEED_MONOLITH:-/tmp/omni-monolith.sh}"
OMNI_SEED_URL="${OMNI_SEED_URL:-https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/omni-monolith.sh}"

SEED_DISTRO=""
SEED_DISK=""
SEED_FS="btrfs"
SEED_TARGET="/mnt"
SEED_RESUME=0
SEED_FRESH=0
SEED_APPLY=0

seed_log() {
    printf '[omni-seed] %s\n' "$*" >&2
}

seed_usage() {
    cat << HELP
omni-seed — Universal Omni-Master live bootstrap

Usage:
  omni-seed.sh [options]

Options:
  --distro NAME      alpine|void|arch|debian|artix
  --disk DISK        target disk, e.g. sda or nvme0n1
  --fs FS            btrfs|ext4|xfs|f2fs (default: btrfs)
  --target DIR       target mountpoint (default: /mnt)
  --resume           resume matching interrupted state
  --fresh            discard interrupted state and start fresh
  --apply            execute real install (M18-A keeps this disabled)
  --help             show help

Default behavior is SAFE: build/download monolith and run deploy plan only.
HELP
}

seed_detect_live_iso() {
    if [ -d /run/archiso ] || [ -d /live ]; then
        printf 'systemrescue-or-archiso\n'
        return 0
    fi
    if [ -f /etc/alpine-release ] || ls /media/*/apks >/dev/null 2>&1; then
        printf 'alpine-live\n'
        return 0
    fi
    if [ -f /.disk/info ]; then
        printf 'debian-ubuntu-live\n'
        return 0
    fi
    printf 'unknown-live\n'
}

seed_network_check() {
    if command -v ping >/dev/null 2>&1; then
        ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 0
        ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fsI https://github.com >/dev/null 2>&1 && return 0
    fi
    return 1
}

seed_state_write() {
    _key="$1"; _val="$2"
    _tmp="${OMNI_SEED_STATE}.tmp.$$"
    if [ -f "$OMNI_SEED_STATE" ]; then
        grep -v "^${_key}=" "$OMNI_SEED_STATE" > "$_tmp" 2>/dev/null || :
    else
        : > "$_tmp"
    fi
    printf '%s=%s\n' "$_key" "$_val" >> "$_tmp"
    mv "$_tmp" "$OMNI_SEED_STATE"
}

seed_state_get() {
    _key="$1"
    [ -f "$OMNI_SEED_STATE" ] || return 1
    _line=$(grep "^${_key}=" "$OMNI_SEED_STATE" 2>/dev/null | head -1)
    [ -z "$_line" ] && return 1
    printf '%s\n' "${_line#${_key}=}"
}

seed_state_init() {
    seed_state_write seed_version "$OMNI_SEED_VERSION"
    seed_state_write started "$(date +%s)"
    seed_state_write live_iso "$(seed_detect_live_iso)"
    seed_state_write distro "$SEED_DISTRO"
    seed_state_write disk "$SEED_DISK"
    seed_state_write fs "$SEED_FS"
    seed_state_write target "$SEED_TARGET"
    seed_state_write step_monolith pending
    seed_state_write step_plan pending
}

seed_state_summary() {
    [ -f "$OMNI_SEED_STATE" ] || { printf 'no seed state\n'; return 0; }
    printf '== OMNI-SEED STATE ==\n'
    for _k in seed_version started live_iso distro disk fs target step_monolith step_plan; do
        _v=$(seed_state_get "$_k" 2>/dev/null || printf '')
        printf '  %-14s %s\n' "$_k:" "$_v"
    done
}

seed_have_repo_builder() {
    _here=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)
    [ -n "$_here" ] && [ -x "$_here/scripts/build-monolith.sh" ]
}

seed_build_or_download_monolith() {
    seed_state_write step_monolith running

    if seed_have_repo_builder; then
        _repo=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)
        seed_log "building monolith from local repo"
        "$_repo/scripts/build-monolith.sh" "$OMNI_SEED_MONOLITH" >/dev/null 2>&1 || return 1
    else
        command -v curl >/dev/null 2>&1 || {
            seed_log "curl missing; cannot download monolith"
            return 1
        }
        seed_log "downloading monolith from $OMNI_SEED_URL"
        curl -fsSL "$OMNI_SEED_URL" -o "$OMNI_SEED_MONOLITH" || return 1
        chmod 755 "$OMNI_SEED_MONOLITH"
    fi

    sh -n "$OMNI_SEED_MONOLITH" || return 1
    seed_state_write step_monolith done
    return 0
}

# PRIORITY: 1) $COLUMNS env var (mocking/Termux/pipes) 2) stty size (real TTY) 3) 80
seed_layout_hint() {
    _cols="${COLUMNS:-}"
    if [ -z "$_cols" ] && command -v stty >/dev/null 2>&1; then
        _sz=$(stty size 2>/dev/null)
        [ -n "$_sz" ] && _cols=$(printf '%s\n' "$_sz" | awk '{print $2}')
    fi
    [ -z "$_cols" ] && _cols=80
    case "$_cols" in ''|*[!0-9]*) _cols=80 ;; esac

    if [ "$_cols" -lt 60 ]; then
        printf 'portrait\n'
    elif [ "$_cols" -lt 100 ]; then
        printf 'compact\n'
    else
        printf 'landscape\n'
    fi
}

seed_parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --distro) shift; SEED_DISTRO="${1:-}" ;;
            --disk) shift; SEED_DISK="${1:-}" ;;
            --fs) shift; SEED_FS="${1:-btrfs}" ;;
            --target) shift; SEED_TARGET="${1:-/mnt}" ;;
            --resume) SEED_RESUME=1 ;;
            --fresh) SEED_FRESH=1 ;;
            --apply) SEED_APPLY=1 ;;
            --help|-h) seed_usage; exit 0 ;;
            *) seed_log "unknown argument: $1"; seed_usage; exit 2 ;;
        esac
        shift
    done
}

seed_main() {
    seed_parse_args "$@"

    seed_log "version: $OMNI_SEED_VERSION"
    seed_log "live environment: $(seed_detect_live_iso)"
    seed_log "terminal layout: $(seed_layout_hint)"

    if [ "$SEED_APPLY" -eq 1 ]; then
        seed_log "M18-A is safe mode only; --apply is deferred to M18-B"
        return 2
    fi

    if [ -f "$OMNI_SEED_STATE" ] && [ "$SEED_FRESH" -ne 1 ]; then
        seed_log "existing seed state found"
        seed_state_summary >&2
        if [ "$SEED_RESUME" -ne 1 ]; then
            seed_log "use --resume to continue or --fresh to discard"
            return 3
        fi
    else
        seed_state_init
    fi

    seed_network_check || seed_log "network check failed; using local builder if available"

    seed_build_or_download_monolith || {
        seed_state_write step_monolith failed
        seed_log "monolith acquisition failed"
        return 1
    }

    if [ -z "$SEED_DISTRO" ] || [ -z "$SEED_DISK" ]; then
        seed_log "distro and disk not supplied; monolith ready, no plan executed"
        seed_state_write step_plan skipped
        return 0
    fi

    seed_state_write step_plan running
    "$OMNI_SEED_MONOLITH" deploy plan \
        --distro "$SEED_DISTRO" \
        --disk "$SEED_DISK" \
        --fs "$SEED_FS" \
        --target "$SEED_TARGET"
    _rc=$?

    if [ "$_rc" -eq 0 ]; then
        seed_state_write step_plan done
    else
        seed_state_write step_plan failed
    fi

    return "$_rc"
}

seed_main "$@"
