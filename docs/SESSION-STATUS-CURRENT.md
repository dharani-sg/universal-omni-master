# Session Status — Dipper L0 USB Gadget Bringup
## Last Updated: 2026-07-24

### Current Phase
- **Phase**: L0 — USB Gadget Enumeration
- **Status**: **T1 FAIL** — D4 PASS, no host gadget; phone auto-recovered
- **Focus**: Xiaomi Mi 8 (dipper) NCM USB enumeration
- **Git SHA**: 22ed446

### Device State
- **ADB**: device (af4aa323)
- **Fastboot**: working
- **Last test**: T1 NCM boot — FASTBOOT OK, no `18d1:d001`, no `usb0`

### Key Results
| Test | Result | Evidence |
|------|--------|----------|
| ACM init | DWC3 lockup (100%) | Marked HARDWARE_INCOMPATIBLE |
| NCM T1 | D4 PASS, no host gadget | 54s USB dark, ABL recovery |
| Mobian boot | PASS — usb0 enumerates | Built-in gadget drivers |

### Next Actions
1. T1b: RNDIS-first / force modprobe before configfs
2. Stock pmOS baseline with headless DTB
3. Kernel rebuild with built-in composite+NCM
4. pstore/ramoops for post-mortem

### Active Artifacts
- `/tmp/l0_t1_ncm_boot.img` — T1 NCM boot image
- `tools/init_l0_ncm_t1.sh` — T1 init script
- `tools/uom-build-l0-t1.sh` — boot image builder
- `tools/uom-host-ncm-watch.sh` — host USB observer
