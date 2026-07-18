# Security Boundaries

## Overview

UOM enforces strict security boundaries to prevent privilege escalation, data leakage, and unauthorized access.

## Boundaries

### 1. QEMU Process
- Runs as ordinary Termux UID (u0_a608)
- Never runs as root
- No KVM access (TCG only)
- No TAP/bridge networking (user-mode only)

### 2. Guest VM
- Alpine Linux (musl/OpenRC)
- User `uom` (uid 1000)
- SSH key-only authentication
- No password auth
- `doas` for privilege escalation (requires TTY)

### 3. Network
- QEMU user-mode networking (no host network access)
- SSH forwarded to 127.0.0.1:2222 only (never 0.0.0.0)
- Guest internet via QEMU user-net (NAT)
- No port forwarding to external interfaces

### 4. Storage
- VM disk in Termux private storage (`~/uom-vm/`)
- No world-readable permissions
- No VM files in shared storage
- Logs redact credentials

### 5. AI Models
- Anonymous access only (no API keys)
- Zero cost (verified before use)
- No secrets in prompts
- No auth headers sent
- Curl wrapper redacts prompts in logs

### 6. Git
- GitHub is canonical transport
- No laptop private keys on phone/guest
- Deploy keys for push access (future)
- No secrets in committed files

### 7. Termux
- Widget scripts in `~/.shortcuts/` (user-accessible)
- Boot scripts in `~/.termux/boot/` (auto-start)
- No root access required
- Battery = Unrestricted (for background operation)

## Prohibited Actions

1. Never run QEMU as root
2. Never bind services to 0.0.0.0
3. Never disable SSL/TLS verification
4. Never commit secrets, keys, or credentials
5. Never copy private SSH keys between devices
6. Never use `NODE_TLS_REJECT_UNAUTHORIZED=0`
7. Never auto-install Android APKs
8. Never mix Termux plugin sources (Google Play only)
9. Never rotate models to evade 429/quota controls
10. Never send secrets to AI models

## Verification

Run `scripts/uom-phone-bootstrap.sh doctor` to verify security boundaries:

- QEMU process owner ≠ root
- SSH bound to 127.0.0.1 only
- No world-readable VM files
- No secrets in git history
- TLS verification enabled everywhere
