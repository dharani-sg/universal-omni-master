# Phone VM Agent Profile — Design Document

**Date:** 2026-07-19
**Branch:** `fix/phone-bootstrap-release-gate-20260719`

---

## 1. Default One-Liner — UNCHANGED

The public curl one-liner remains **phone-relay** (lightweight, ~25KB, fast, safe):

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/main/install/bootstrap.sh | sh
```

This installs: companion packages (tmux, git, openssh, jq, fzf, autossh), SSH key, managed SSH config, Termux:Boot script, and clones the repo. **No QEMU, no Alpine, no VM.**

---

## 2. New Profile: `phone-vm-agent` (OPT-IN ONLY)

The heavy QEMU + Alpine VM path is triggered ONLY when ALL of the following are provided:

```sh
curl -fsSL <immutable-SHA-URL> | sh -s -- \
  --apply --verify --profile phone-vm-agent \
  --allow-large-download --allow-vm --allow-opencode-install
```

### 2.1 Consent Flags (all required, none inferred)

| Flag | Purpose |
|------|---------|
| `--profile phone-vm-agent` | Selects the VM profile |
| `--allow-large-download` | Consents to downloading Alpine ISO/rootfs + QEMU packages (multi-GiB) |
| `--allow-vm` | Consents to booting an emulated VM on the phone |
| `--allow-opencode-install` | Consents to installing OpenCode inside the VM guest |
| `--allow-metered` | (optional) Consents to download on metered/cellular data. Default: OFF — abort if network detected as metered |

**Missing any required flag → immediate exit with clear message listing what's needed.**

### 2.2 Resource Guardrails (hard-fail before any download)

| Check | Default | Behavior |
|-------|---------|----------|
| Free storage | ≥ 6 GiB | `df` check before download. Abort with "insufficient storage" if below threshold |
| Battery | ≥ 30% and charging (best-effort) | Read `/sys/class/power_supply/Battery/capacity` and `/sys/class/power_supply/Battery/status`. If battery < 30% AND not charging, abort. If sysfs unavailable, warn but proceed |
| Metered network | Wi-Fi required | Check `dumpsys connectivity` for metered flag. Abort if metered unless `--allow-metered` |
| Download timeout | 300s per file, 600s total | Abort + cleanup on timeout |
| Retry budget | 3 retries, exponential backoff | For downloads only |

### 2.3 Package Dependencies

Under `--profile phone-vm-agent` only, the installer installs:

| Package | Termux name | Purpose |
|---------|-------------|---------|
| ca-certificates | `ca-certificates` | HTTPS/TLS (fix for git clone root cause) |
| curl | `curl` | HTTP downloads |
| git | `git` | Repo clone |
| tar | `tar` | Archive extraction |
| openssh | `openssh` | SSH daemon |
| QEMU | `qemu-system-x86_64` | x86_64 VM emulation |

**The phone-relay profile does NOT install QEMU or any VM packages.**

---

## 3. Alpine Guest

### 3.1 Pinned Version

- **Alpine version:** 3.20 (latest stable as of 2026-07-19)
- **ISO:** `alpine-virt-3.20.0-x86_64.iso` (minimal footprint, ~60 MiB)
- **SHA256:** Fetched from Alpine release page, verified before boot
- **URL:** `https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-virt-3.20.0-x86_64.iso`

### 3.2 VM Configuration

```
qemu-system-x86_64 \
  -m 512 \
  -smp 1 \
  -nographic \
  -drive file=<alpine.qcow2>,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::HOSTPORT-:22 \
  -device virtio-net-pci,netdev=net0 \
  -cdrom <alpine-virt-3.20.0-x86_64.iso> \
  -boot d
```

- RAM: 512 MiB (bounded)
- CPU: 1 core
- Disk: qcow2, 2 GiB max (grown on demand)
- Network: user-mode with SSH port-forward to `localhost:HOSTPORT` on phone
- Boot: ISO initially, then installed disk
- **HOSTPORT:** Random available port in range 22000-22999

### 3.3 Automated Setup (non-interactive)

The installer performs unattended Alpine setup:

1. Boot from ISO
2. Auto-partition and install to qcow2 disk
3. Create `uom` user with sudo
4. Configure SSH server
5. Install OpenCode inside guest (if `--allow-opencode-install`)
6. Verify `opencode --version` inside guest
7. Record guest SSH connection details in metadata

### 3.4 All VM Artifacts Under Lab Dir

```
$HOME/.cache/uom-phone2-vm-lab/<RUN_ID>/
├── evidence/
├── logs/
├── vm/
│   ├── alpine-virt-3.20.0-x86_64.iso    (~60 MiB)
│   ├── alpine-virt-3.20.0-x86_64.iso.sha256
│   ├── alpine-disk.qcow2                  (grows to ≤2 GiB)
│   ├── qemu.pid
│   └── boot.log
└── download/
```

---

## 4. In-VM OpenCode

### 4.1 Installation

OpenCode is installed inside the Alpine guest using its official install method (e.g., `curl | sh` from the OpenCode releases). This is only attempted when `--allow-opencode-install` is provided.

### 4.2 Auth Detection

The installer checks if OpenCode is authenticated inside the VM:
- Run `opencode --version` → confirm binary present
- Run `opencode auth status` (or equivalent) → detect auth state
- **Do NOT hardcode or invent credentials**
- **Do NOT make LLM calls during install**

### 4.3 Auth Status

| State | Action |
|-------|--------|
| Authed | Record in metadata. Ready for agentic smoke. |
| Not authed | Print clear manual auth instructions. Mark `OPENCODE_IN_VM_NEEDS_AUTH` in metadata. |
| Check fails | Mark `OPENCODE_AUTH_CHECK_FAILED` in metadata. Warn user. |

---

## 5. Rollback

`--rollback` with `--profile phone-vm-agent`:

1. Stop QEMU process (SIGTERM, then SIGKILL after 10s)
2. Remove VM artifacts from lab dir:
   - `alpine-virt-*.iso`
   - `alpine-disk.qcow2`
   - `qemu.pid`
   - `boot.log`
3. Remove only UOM-owned artifacts:
   - `id_ed25519_uom` key
   - Managed SSH config block
   - Termux:Boot script
   - UOM repo (if created by this installer run)
4. **LEAVE installed base packages** (tmux, openssh, git, qemu, etc.) — they may be wanted or shared
5. **NEVER** uninstall packages, factory reset, format, clear app data, touch DCIM/Downloads/shared storage, run su/adb/reboot

---

## 6. Metadata Extension

The `opencode-install.json` metadata is extended with VM-specific fields:

```json
{
  "profile": "phone-vm-agent",
  "vm_alpine_version": "3.20.0",
  "vm_alpine_iso_sha256": "<verified hash>",
  "vm_host_port": 22000,
  "vm_artifacts_dir": "<lab>/vm/",
  "vm_opencode_installed": true,
  "vm_opencode_authed": false,
  "vm_opencode_auth_status": "OPENCODE_IN_VM_NEEDS_AUTH"
}
```

---

## 7. Helper Scripts

The installer creates in `bin/` (or lab dir):

| Script | Purpose |
|--------|---------|
| `uom-vm-start.sh` | Start QEMU VM, wait for guest SSH |
| `uom-vm-stop.sh` | Graceful stop (SIGTERM → SIGKILL) |
| `uom-vm-status.sh` | Check if VM is running, report PID and port |
| `uom-vm-ssh.sh` | SSH into guest as `uom` user |

---

## 8. Security

- All VM network traffic is user-mode (NAT) — no host network exposure
- SSH port-forwarded to localhost only
- Guest `uom` user has no root access (sudo requires password)
- No credentials stored in plaintext
- VM images isolated in lab dir, not shared storage
- QEMU run with minimal privileges (no KVM required on phone)
