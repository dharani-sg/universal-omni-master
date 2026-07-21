# UOM Session Resume — 2026-07-21 (Updated 03:20 UTC)

## Device State

| Device | IP | SSH | QEMU | VM Boot | Toolbox | Widgets |
|--------|-----|-----|------|---------|---------|---------|
| Laptop (Alpine 3.24.1) | 192.168.107.90 | Hub | N/A | N/A | N/A | N/A |
| Phone1 (MI 8) | 192.168.107.170:8022 | OK | PID 4398 | OK (16h uptime) | 15/15 PASS | 6/6 OK |
| Phone2 (Redmi 13C) | 192.168.107.157:8022 | OK | Runit-supervised | Direct-kernel boot | 15/15 PASS | 6/6 OK |
| Phone2 VM | 127.0.0.1:22222 | OK | PID varies | 6.12.95-0-virt | 15/15 PASS | N/A |

## Quality Gates Status

| Gate | Status | Evidence |
|------|--------|----------|
| B0-B6 | PASS | Provision checkpoint verified |
| B7 | PASS | Phone2 VM SSH + doas uid=0 confirmed |
| B8 | PASS | 3/3 clean boots via runit, clean poweroff |
| B9 | PASS | 25 old scripts + 128MB firmware archived |
| V6 | PASS | qemu-img check: no errors, corrupt=false |
| V7 | PASS | Runit service with direct-kernel boot |
| V8 | PASS | Phone2 VM 15/15 smoke + toolbox installed |
| V9 | SKIPPED | OpenCode futex hang (musl+QEMU, known) |
| V10 | PASS | Phone1 VM 15/15 smoke |
| V11 | PASS | 4-way git sync at cc31e2d |
| V12 | PASS | api_wrapper import + NETWORK_CODE_POLICY |
| V13 | PASS | 12 widgets (6 per phone), syntax OK |

## Key Technical Decisions

### Direct-Kernel Boot (bypass UEFI/GRUB)
- Phone2 VM uses `-kernel/-initrd/-append` instead of UEFI pflash
- Boot time: ~45s (vs 105s with ext4 recovery)
- No GRUB, no UEFI vars, no EDK2 firmware needed
- QEMU cmd: `qemu-system-aarch64 -M virt -cpu cortex-a72 -smp 2 -m 1536 -kernel vmlinuz-virt -initrd initramfs-virt -append "root=/dev/vda3 rw console=ttyAMA0,115200n8 modules=virtio_pci,virtio_blk,virtio_net,ext4 rootwait"`

### Poweroff Sequence
- `doas -n poweroff` inside VM → OpenRC halts (unmounts, stops services)
- VM halts but QEMU stays running (no ACPI on `-M virt`)
- `kill -TERM QEMU` from Phone2 host → QEMU exits cleanly
- runit auto-restarts → new clean boot
- Ext4 stays clean (no journal recovery needed)

### Phone2 VM doas Fixed
- `/etc/doas.conf`: `permit nopass :wheel as root` + `permit nopass uom as root` (mode 644)
- `/etc/doas.d/doas.conf`: `permit nopass :wheel` (was `permit persist :wheel` requiring password)
- Both fixed via offline QCOW2 modification (qemu-img dd → ext4 extraction → debugfs write → rebuild)

## Network Map (Current)

| Device | IP | SSH Port | User |
|--------|-----|----------|------|
| Laptop | 192.168.107.90 | 22 | alpine |
| Phone1 Termux | 192.168.107.170 | 8022 | u0_a608 |
| Phone1 VM | 127.0.0.1 | 2222 | uom |
| Phone2 Termux | 192.168.107.157 | 8022 | root |
| Phone2 VM | 127.0.0.1 | 22222 | uom |

## Remaining Work

- V14-V17: Bootstrap validation under TEST_ROOT, E2E topology tests, 60-min soak
- OpenCode futex hang (V9): Known musl+QEMU incompatibility, needs glibc guest or relay-only mode
- Kernel 7.2-rc4: Source not yet downloaded, cross-compiler not installed

## Hard Rules (Unchanged)

1. NO git push (except explicit user request)
2. NO git reset --hard
3. NO StrictHostKeyChecking=no — use accept-new
4. Bounded SSH timeouts
5. PID+starttime before signal
6. No live QCOW2 check/repair
7. No gate PASS without evidence
8. No broad pkill -f
9. No staging runtime/images/bundles/logs in git
10. ALWAYS full paths
11. ALWAYS unique chardev IDs
