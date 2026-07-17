#!/bin/sh
# bin/uom-phone-provision.sh — Provision proot-distro Debian + OpenCode CLI on the phone
# Runs from the LAPTOP. Connects to the phone via the reverse SSH tunnel
# (laptop:31415 -> phone:8022) and:
#   1. Installs proot-distro Debian (glibc, clean environment)
#   2. Installs OpenCode CLI inside the Debian proot (mirrors laptop binary)
#   3. Mirrors the laptop's OpenCode config/settings (model, permissions, policy)
#   4. Wires opencode into PATH on the phone (Termux + proot)
#
# POSIX sh. No bashisms. Safe to re-run (idempotent).
#
# Usage:
#   sh bin/uom-phone-provision.sh            Interactive (prompts before each phase)
#   sh bin/uom-phone-provision.sh --auto     Non-interactive, runs all phases
#   sh bin/uom-phone-provision.sh --check    Verify what's installed, no changes
#   sh bin/uom-phone-provision.sh --stage N  Run a single stage (1=proot 2=opencode 3=config)

set -u

UOM_DIR="${OMNI_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
PHONE_REV="${PHONE_REV:-uom-phone-rev}"
PHONE_TEST="ssh -o ConnectTimeout=5 -o BatchMode=yes -F ~/.ssh/config ${PHONE_REV} true 2>/dev/null"
PROOT_DISTRO="${UOM_PROOT_DISTRO:-debian}"
OPENCODE_INSTALL_URL="${UOM_OPENCODE_INSTALL_URL:-https://opencode.ai/install.sh}"
LAPTOP_OC_CFG="${HOME}/.config/opencode"

_log() { printf '[provision] %s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
_err() { printf '[provision] ERROR: %s\n' "$*" >&2; }

_auto=0
_check=0
_stage=""
for _a in "$@"; do
    case "$_a" in
        --auto)  _auto=1 ;;
        --check) _check=1 ;;
        --stage) _stage="${2:-}"; shift ;;
        -h|--help)
            printf 'Usage: %s [--auto|--check|--stage N]\n' "$0"; exit 0 ;;
        *) _err "Unknown arg: $_a"; exit 2 ;;
    esac
    shift
done

# ── Reachability ──────────────────────────────────────────────────────────
_require_phone() {
    if ! $PHONE_TEST; then
        _err "Phone not reachable via reverse tunnel ($PHONE_REV)."
        _err "On the phone, run: sh bin/uom-reverse-ssh.sh  (Termux:Boot does this on boot)"
        _err "Then retry. Tunnel maps laptop:31415 -> phone:8022."
        exit 1
    fi
    _log "Phone reachable via $PHONE_REV."
}

# ── Stage 1: proot-distro Debian ─────────────────────────────────────────
stage_proot() {
    _log "Stage 1: ensure proot-distro ${PROOT_DISTRO} on phone"
    ssh -F ~/.ssh/config "$PHONE_REV" '
        set -e
        command -v proot-distro >/dev/null 2>&1 || pkg install -y proot-distro >/dev/null 2>&1
        if proot-distro list 2>/dev/null | grep -q "^debian"; then
            echo "debian already registered"
        fi
        if [ ! -d "$HOME/debian" ]; then
            proot-distro install debian
        else
            echo "debian rootfs present"
        fi
        echo "PROOT_OK"
    '
}

# ── Stage 2: OpenCode CLI inside proot ────────────────────────────────────
stage_opencode() {
    _log "Stage 2: install OpenCode CLI inside ${PROOT_DISTRO} proot"
    ssh -F ~/.ssh/config "$PHONE_REV" "
        proot-distro login ${PROOT_DISTRO} -- bash -c '
            set -e
            export DEBIAN_FRONTEND=noninteractive
            apt-get update >/dev/null 2>&1
            for p in curl ca-certificates git jq; do
                dpkg -s \$p >/dev/null 2>&1 || apt-get install -y \$p >/dev/null 2>&1
            done
            if command -v opencode >/dev/null 2>&1; then
                echo OPENCODE_PRESENT=\$(opencode --version 2>/dev/null || echo unknown)
            else
                curl -fsSL ${OPENCODE_INSTALL_URL} | sh
                echo OPENCODE_INSTALLED
            fi
        '
    "
}

# ── Stage 3: Mirror laptop OpenCode config ───────────────────────────────
stage_config() {
    _log "Stage 3: mirror laptop OpenCode config/settings to phone proot"
    if [ ! -d "$LAPTOP_OC_CFG" ]; then
        _err "Laptop OpenCode config not found at $LAPTOP_OC_CFG — nothing to mirror."
        return 1
    fi

    # Build a tarball of the laptop config, ship it through the tunnel.
    _tmp_tar=$(mktemp "${TMPDIR:-/tmp}/uom-oc-cfg-XXXXXX.tar.gz")
    tar -czf "$_tmp_tar" -C "$LAPTOP_OC_CFG" . 2>/dev/null \
        && _log "Packaged laptop config ($(wc -c < "$_tmp_tar") bytes)"

    # Push tarball to phone, extract into proot's ~/.config/opencode
    scp -F ~/.ssh/config "$_tmp_tar" "${PHONE_REV}:/tmp/uom-oc-cfg.tar.gz" 2>/dev/null \
        && _log "Uploaded config tarball to phone"

    ssh -F ~/.ssh/config "$PHONE_REV" "
        proot-distro login ${PROOT_DISTRO} -- bash -c '
            mkdir -p \$HOME/.config/opencode
            tar -xzf /tmp/uom-oc-cfg.tar.gz -C \$HOME/.config/opencode
            rm -f /tmp/uom-oc-cfg.tar.gz
            echo CONFIG_MIRRORED
        '
    "
    rm -f "$_tmp_tar"

    # Link opencode into Termux PATH so scripts calling bare 'opencode' work
    ssh -F ~/.ssh/config "$PHONE_REV" '
        BIN=/data/data/com.termux/files/home/bin/opencode
        if [ ! -e "$BIN" ] && [ -x "$HOME/debian/usr/local/bin/opencode" ]; then
            ln -sf "$HOME/debian/usr/local/bin/opencode" "$BIN"
            echo LINKED_OPENCODE_TO_TERMUX
        elif [ -e "$BIN" ]; then
            echo OPENCODE_LINK_EXISTS
        else
            echo WARN_OPENCODE_NOT_FOUND_IN_PROOT
        fi
    '
}

# ── Verify ────────────────────────────────────────────────────────────────
stage_verify() {
    _log "Verification: opencode inside proot on phone"
    ssh -F ~/.ssh/config "$PHONE_REV" "
        proot-distro login ${PROOT_DISTRO} -- bash -c '
            command -v opencode >/dev/null 2>&1 && opencode --version 2>/dev/null || echo OPENCODE_MISSING
            [ -f \"\$HOME/.config/opencode/opencode.json\" ] && echo CONFIG_PRESENT || echo CONFIG_MISSING
        '
    "
}

# ── Main ──────────────────────────────────────────────────────────────────
_require_phone

if [ "$_check" -eq 1 ]; then
    stage_verify
    exit 0
fi

if [ -n "$_stage" ]; then
    case "$_stage" in
        1) stage_proot ;;
        2) stage_opencode ;;
        3) stage_config ;;
        *) _err "Unknown stage: $_stage (1=proot 2=opencode 3=config)"; exit 2 ;;
    esac
    stage_verify
    exit 0
fi

stage_proot
[ "$_auto" -eq 1 ] || { printf 'Continue to OpenCode install? [y/N] '; read -r _r; case "$_r" in y|Y) ;; *) _log "Aborted."; exit 0 ;; esac; }
stage_opencode
[ "$_auto" -eq 1 ] || { printf 'Continue to config mirror? [y/N] '; read -r _r; case "$_r" in y|Y) ;; *) _log "Aborted."; exit 0 ;; esac; }
stage_config
stage_verify
_log "=== PROVISION COMPLETE ==="
