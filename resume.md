# UOM Session Resume — 2026-07-20 (Updated 22:30 IST)

Generated from deep research + merged refactor session.

---

## Deep Research Findings

### Root Cause: QMP send-key / GRUB Keyboard Failure

The QMP `send-key` failure is a **UEFI firmware + GRUB configuration issue**, NOT a kernel issue:

```
QMP send-key → QEMU PL050 PS/2 controller → UEFI EDK2 firmware → GRUB
                                              ↑
                                    DISCONNECT IS HERE
                                    (before kernel loads)
```

- EDK2 firmware on aarch64 virt lacks virtio keyboard support
- GRUB's UEFI keyboard handler doesn't properly poll the PS/2 controller on this platform
- GRUB runs BEFORE the kernel loads — no kernel change can fix this
- **Linux 7.2-rc4 does NOT contain a fix** (researched: Dreamcast-only input fixes)

### Proven Fix: GRUB Serial Console

The solution is configuring GRUB to accept input from the **serial console** (which our serial socket connects to):

```grub.cfg
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
```

Plus kernel cmdline: `console=ttyAMA0,115200`

### UEFI Shell Serial Input (PROVEN WORKING)

The serial socket IS bidirectional. We sent ESC through it and the UEFI Setup Browser appeared. The UEFI Interactive Shell v2.2 (EDK2) accepts commands via serial.

**Key UEFI Shell commands for our use case:**
- `FS0:` — switch to FAT boot partition (EFI System Partition)
- `ls` / `dir` — list files
- `cat` — display file contents
- `edit` — text editor (TUI, harder over serial)
- `echo "text" > file` / `echo "text" >> file` — write/append to file
- `cp` / `rm` — copy/delete files
- `bcfg boot add 0 FS0:\EFI\alpine\grubaa64.efi "Alpine"` — add boot entry
- `reset` — reboot system

**UEFI Shell limitations:** Only FAT filesystems (vda1). Cannot access ext4 (vda3).

### Alpine UEFI Boot Layout

From the Alpine wiki:
- Named bootloader: `\EFI\alpine\grubaa64.efi` on ESP
- Fallback bootloader: `\EFI\boot\bootaa64.efi` on ESP (copy)
- `grub.cfg` is embedded with prefix pointing to root partition: `(hd0,gpt3)/boot/grub/grub.cfg`
- GRUB binary searches `$prefix/grub.cfg` on the ext4 root partition

**Critical:** grub.cfg is on vda3 (ext4), NOT on vda1 (FAT/ESP). The UEFI shell cannot directly modify it. BUT we can:
1. Create a NEW `grub.cfg` on the ESP that GRUB will find as fallback
2. OR use the UEFI shell to run `grubaa64.efi` which will read from root partition (with our modifications already applied from a previous session)

### Alternative: Direct Kernel Boot (bypass GRUB entirely)

QEMU supports `-kernel` and `-initrd` to boot directly without GRUB:
```
qemu-system-aarch64 ... -kernel /path/to/vmlinuz -initrd /path/to/initramfs \
  -append "console=ttyAMA0 root=/dev/vda3 rootfstype=ext4 init=/bin/sh modules=sd-mod,usb-storage,ext4,virtio"
```

This bypasses GRUB AND the UEFI boot entry issue. We just need the kernel and initramfs files.

### doas.conf Syntax Bug (Confirmed)

Alpine's doas does NOT recognize `:wheel` group syntax:
```
Current:  permit nopass :wheel as root    ← BROKEN on Alpine doas
Needed:   permit nopass keepenv uom as root  ← explicit username
```

### Offline QCOW2 Modification (BLOCKED)

| Tool | Phone2 Termux | Laptop (Alpine) |
|------|:---:|:---:|
| qemu-nbd | YES (no /dev/nbd*) | NO |
| guestfish | NO | NO |
| mount | YES | YES (no root) |
| modprobe nbd | FAIL (no perms) | FAIL (no perms) |
| root/doas | NO | NO |
| pip install | blocked | blocked |

**Neither machine can mount QCOW2 offline.** The UEFI shell approach is the only viable path.

---

## Device State

| Device | Network | SSH | QEMU | VM Boot |
|--------|---------|-----|------|---------|
| Laptop (Alpine 3.24.1) | 10.155.18.90 | Hub | N/A | N/A |
| Phone1 (MI 8) | 10.155.18.244:8022 | OK | PID 4398, RSS 25MB | OK |
| Phone2 (Redmi 13C) | 10.155.18.131:8022 | OK | DEAD | Drops to UEFI Shell |
| Phone2 VM | 127.0.0.1:22222 | When QEMU up | - | UEFI Shell (vars corrupted) |

**Phone2 VM State:**
- QEMU: STOPPED (needs restart)
- UEFI vars: CORRUPTED (drops to UEFI Shell, not GRUB)
- GRUB config: OK (virtio modules added in V4)
- doas.conf: BROKEN (`:wheel` syntax, needs rewrite)
- Disk: `/dev/vda1`=FAT boot, `/dev/vda2`=swap, `/dev/vda3`=ext4 root
- Kernel: 6.12.95-0-virt (Alpine 3.21.7)

---

## Merged Refactored TODO (Chronological)

### Phase 1: IMMEDIATE — Fix doas.conf via UEFI Shell + Serial (30 min)

```
┌─────────────────────────────────────────────────────────────┐
│ EXECUTION FLOW:                                             │
│                                                             │
│ 1. Start QEMU → drops to UEFI Shell (corrupted vars)       │
│ 2. Connect serial socket (bidirectional)                   │
│ 3. DON'T press ESC → startup.nsh → Shell> prompt           │
│ 4. From Shell>:                                             │
│    a. FS0: → ls → find grub.cfg or create one              │
│    b. Write grub.cfg with serial console + init=/bin/sh     │
│    c. bcfg boot add → fix UEFI boot entry                  │
│    d. Run grubaa64.efi → GRUB → modified config → root     │
│ 5. Root shell: fix doas.conf, restore grub.cfg, reboot     │
│ 6. SSH → verify → V5c gate                                 │
└─────────────────────────────────────────────────────────────┘
```

**Sub-steps:**

- [ ] **P1-1.1** Start QEMU + connect serial socket
  - Kill any existing QEMU
  - Start with `-smp 2 -m 1536` (reduce Phone2 load)
  - Use full paths (never ~), unique chardev IDs (schar, monchar)
  - Connect to serial socket immediately (bidirectional)

- [ ] **P1-1.2** UEFI Shell → explore FAT partition
  - Wait for Shell> prompt (don't press ESC)
  - `FS0:` → `ls` → find directory structure
  - `cat \EFI\alpine\grub.cfg` (if exists on ESP)
  - `cat \EFI\alpine\grubaa64.efi` info (verify binary exists)

- [ ] **P1-1.3** UEFI Shell → write grub.cfg with serial + init=/bin/sh
  - Backup existing: `cp` or just overwrite
  - Write new grub.cfg using `echo` with `>` and `>>`
  - Content: serial terminal, timeout=5, two menu entries (init=/bin/sh + normal)
  - Verify with `cat`

- [ ] **P1-1.4** UEFI Shell → fix boot entry
  - `bcfg boot add 0 FS0:\EFI\alpine\grubaa64.efi "Alpine GRUB"`
  - Verify: `bcfg boot dump`

- [ ] **P1-1.5** Boot GRUB → root shell
  - Run: `FS0:\EFI\alpine\grubaa64.efi`
  - GRUB reads modified config → serial console active
  - Select "init=/bin/sh" entry → root shell on serial
  - Verify: `# ` prompt appears

- [ ] **P1-1.6** Root shell → fix doas.conf + restore grub.cfg
  - `mount -o remount,rw /dev/vda3 /` (if needed)
  - `echo "permit nopass keepenv uom as root" > /etc/doas.conf`
  - `chmod 644 /etc/doas.conf`
  - Restore grub.cfg: `grub-mkconfig -o /boot/grub/grub.cfg` OR
    mount ESP and restore: `mount /dev/vda1 /mnt && cp /mnt/EFI/alpine/grub.cfg.bak /mnt/EFI/alpine/grub.cfg`
  - `sync` → `reboot -f`

- [ ] **P1-1.7** SSH → verify → V5c gate (15 checks)
  - SSH as uom → `doas -n id` → should show uid=0
  - Full 15-check verification
  - **V5c_GATE_PASS** required before continuing

- [ ] **P1-V5d** Boot 2/3 → QMP system_reset → verify identical
- [ ] **P1-V5e** Boot 3/3 → QMP system_reset → verify identical
- [ ] **P1-V6** Clean shutdown → offline qemu-img check + SHA256

### Phase 2: OVERNIGHT — Custom Alpine Kernel Compile (laptop, -j2)

**Goal:** Serial console as primary I/O, all virtio built-in, debug features.
**Blocked by:** Laptop doas fails (need root for `apk add`).
**Priority:** LOW — Phase 1 fixes the immediate blocker.

- [ ] **P2-2.1** Install cross-compile toolchain (if doas available)
  - `doas apk add build-base linux-headers bc flex bison openssl-dev elfutils-dev ccache`
  - If doas unavailable, skip Phase 2 — Phase 1 is sufficient

- [ ] **P2-2.2** Get kernel source + current config
  - `curl` Alpine kernel package or clone aports
  - Extract kernel config from VM: `zcat /proc/config.gz`

- [ ] **P2-2.3** Modify config for QEMU virt
  - Enable: `SERIAL_AMBA_PL011_CONSOLE=y`, `VIRTIO_CONSOLE=y`, all `VIRTIO_*=y`
  - Enable: `DEBUG_FS`, `FTRACE`, `KPROBES`, `PRINTK_TIME`, `SCHED_DEBUG`
  - Enable: `INPUT`, `INPUT_EVDEV`, `SERIO`, `SERIO_AMBAKMI`
  - Disable: `SOUND`, `DRM`, `USB_SUPPORT`, `WIRELESS`, `BLUETOOTH`

- [ ] **P2-2.4** Compile overnight (-j2, ~4-8 hours on i3-3217U)

- [ ] **P2-2.5** Deploy custom kernel to VM + verify serial GRUB
  - SCP kernel + initramfs to Phone2 → into VM
  - Add GRUB entry for custom kernel
  - Test boot with serial console

### Phase 3: Remaining Gates (After Phase 1 + Phase 2)

- [ ] **V7** Create runit service for Phone2 QEMU (-smp 2 -m 1536)
- [ ] **V8** Deploy + verify guest toolbox on Phone2 VM
- [ ] **V9** Phone2 VM OpenCode diagnostic matrix
- [ ] **V10** Phone1 VM smoke/reverifier reconfirm
- [ ] **V11** Git reconciliation with bundle manifests
- [ ] **V12** api_wrapper + model rotation fixture tests
- [ ] **V13** Widget verification on both phones
- [ ] **V14-V17** Bootstrap, final gates, soak, commit+report

---

## Hard Rules (Unchanged)

1. **NO git push** — ever, unless explicitly requested
2. **NO git reset --hard** — use branch/merge instead
3. **NO StrictHostKeyChecking=no** — use accept-new
4. **Bounded SSH timeouts** — ConnectTimeout=10 max
5. **PID+starttime before signal** — verify before kill
6. **No live QCOW2 check/repair** — only offline via qemu-img
7. **No gate PASS without evidence** — must see output
8. **No broad pkill -f** — use exact process matching
9. **No staging runtime/images/bundles/logs** in git
10. **ALWAYS full paths** — never ~ in QEMU/Python arguments
11. **ALWAYS unique chardev IDs** — schar, monchar (not serial0)
12. **Use -smp 2 -m 1536** — reduce Phone2 load (8 cores, 5.6GB)

---

## QEMU Command Template

```bash
qemu-system-aarch64 \
  -M virt -cpu cortex-a72 -smp 2 -m 1536 \
  -L /data/data/com.termux/files/usr/share/qemu \
  -drive file=$HOME/uom-vm/edk2-aarch64-code.fd,if=pflash,format=raw,readonly=on \
  -drive file=$HOME/uom-vm/uom-phone-vars.fd,if=pflash,format=raw \
  -drive file=$HOME/uom-vm/images/uom-phone.qcow2,if=virtio,format=qcow2 \
  -display none \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -chardev socket,id=schar,path=$HOME/.uom-agent/tmp/p2-serial.sock,server=on,wait=off \
  -serial chardev:schar \
  -chardev socket,id=monchar,path=$HOME/.uom-agent/tmp/monitor.sock,server=on,wait=off \
  -mon chardev=monchar,mode=control
```

## GRUB Serial Console Config (permanent fix for grub.cfg)

```grub.cfg
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
set timeout=5
set default=0

menuentry 'Alpine Linux v3.21, with Linux virt' {
    search --no-floppy --fs-uuid --set=root <ROOT_UUID>
    linux /boot/vmlinuz-virt root=UUID=<ROOT_UUID> ro modules=sd-mod,usb-storage,ext4,virtio console=ttyAMA0,115200 quiet rootfstype=ext4
    initrd /boot/initramfs-virt
}
```

## Network Map

| Device | IP | SSH |
|--------|-----|-----|
| Laptop | 10.155.18.90 | Hub |
| Phone1 Termux | 10.155.18.244:8022 | u0_a608 |
| Phone1 VM | 127.0.0.1:2222 | uom |
| Phone2 Termux | 10.155.18.131:8022 | u0_a217 |
| Phone2 VM | 127.0.0.1:22222 | uom |
