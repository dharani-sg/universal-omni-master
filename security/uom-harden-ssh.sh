#!/bin/sh
# security/uom-harden-ssh.sh — Idempotent SSH hardening for UOM
# Run on laptop (Alpine) or phone (Termux).
# Safe to re-run — only appends/replaces config settings.

set -u

_log() { printf '[harden-ssh] %s\n' "$*"; }

_harden_laptop() {
    _log "Hardening laptop sshd_config..."
    SSHD_CFG="/etc/ssh/sshd_config"
    if [ ! -f "$SSHD_CFG" ]; then
        _log "sshd_config not found at ${SSHD_CFG}"
        return 1
    fi

    _ensure_setting() {
        _key="$1"; _val="$2"
        if grep -qE "^\s*#?\s*${_key}\s+" "$SSHD_CFG" 2>/dev/null; then
            doas sed -i "s/^#\?\(${_key}\)\s\+.*/\1 ${_val}/" "$SSHD_CFG"
        else
            printf '%s %s\n' "${_key}" "${_val}" | doas tee -a "$SSHD_CFG" >/dev/null
        fi
    }

    doas cp "$SSHD_CFG" "${SSHD_CFG}.uom-backup-$(date +%Y%m%d)" 2>/dev/null || true

    _ensure_setting "PasswordAuthentication" "no"
    _ensure_setting "PubkeyAuthentication" "yes"
    _ensure_setting "AuthorizedKeysFile" ".ssh/authorized_keys"
    _ensure_setting "PermitRootLogin" "no"
    _ensure_setting "MaxAuthTries" "3"
    _ensure_setting "MaxSessions" "5"
    _ensure_setting "ClientAliveInterval" "60"
    _ensure_setting "ClientAliveCountMax" "3"
    _ensure_setting "X11Forwarding" "no"
    _ensure_setting "AllowTcpForwarding" "yes"
    _ensure_setting "Banner" "none"

    doas rc-service sshd restart 2>/dev/null || true
    _log "Laptop SSH hardened"
}

_harden_phone() {
    _log "Hardening phone sshd_config..."
    SSHD_CFG="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh/sshd_config"
    if [ ! -f "$SSHD_CFG" ]; then
        _log "Phone sshd_config not found — termux may not have openssh installed"
        return 1
    fi

    _ensure_setting() {
        _key="$1"; _val="$2"
        if grep -qE "^\s*#?\s*${_key}\s+" "$SSHD_CFG" 2>/dev/null; then
            sed -i "s/^#\?\(${_key}\)\s\+.*/\1 ${_val}/" "$SSHD_CFG"
        else
            printf '%s %s\n' "${_key}" "${_val}" >> "$SSHD_CFG"
        fi
    }

    cp "$SSHD_CFG" "${SSHD_CFG}.uom-backup-$(date +%Y%m%d)" 2>/dev/null || true

    _ensure_setting "PasswordAuthentication" "no"
    _ensure_setting "PubkeyAuthentication" "yes"
    _ensure_setting "PermitRootLogin" "no"
    _ensure_setting "MaxAuthTries" "3"
    _ensure_setting "X11Forwarding" "no"
    _ensure_setting "AllowTcpForwarding" "yes"

    pkill -x sshd 2>/dev/null || true
    sleep 1
    sshd 2>/dev/null || _log "sshd restart failed — start manually"
    _log "Phone SSH hardened"
}

# ── File mode enforcement ──
_enforce_modes() {
    _log "Enforcing SSH file modes..."
    chmod 700 "${HOME}/.ssh" 2>/dev/null || true
    chmod 600 "${HOME}/.ssh/authorized_keys" 2>/dev/null || true
    chmod 600 "${HOME}/.ssh/id_ed25519" 2>/dev/null || true
    chmod 600 "${HOME}/.ssh/config" 2>/dev/null || true
    chmod 644 "${HOME}/.ssh/id_ed25519.pub" 2>/dev/null || true
    chmod 644 "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    _log "File modes enforced"
}

if [ -d "/data/data/com.termux" ] || echo "${PREFIX:-}" | grep -q termux 2>/dev/null; then
    _harden_phone
else
    _harden_laptop
fi
_enforce_modes
_log "SSH hardening complete"
