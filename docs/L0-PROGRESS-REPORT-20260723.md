# L0 Progress Report — 2026-07-23

## Session: Dipper USB Gadget Bringup (Day 3)

**Device:** Xiaomi Mi 8 (dipper, SDM845)
**Kernel:** 7.1.0-rc1-sdm845 (mainline via pmOS, tag sdm845-7.1-rc1-r0)
**Host:** Alpine Linux laptop (10.118.201.90)
**Phone base:** crDroid 11.6 (Android 15), kernel 4.9.337-perf
**DTB:** Custom headless sdm845-xiaomi-mi8-dipper-headless (board-id 0x37 / 55)

---

## What We've Done So Far

### Phase 0: Artifact Extraction & Analysis
- Extracted stock pmOS initramfs from `dipper-20260721` artifacts → `/tmp/pmos-initfs-stock/`
- Documented exact NCM gadget configfs sequence from stock `init_functions.sh`
- Identified USB gadget driver config: all function drivers are **=m** (modules), not built-in

### Phase 1: ACM Testing → HARDWARE_INCOMPATIBLE
- Built and tested `usb_f_acm` init image
- **Result: DWC3 register lockup (100% reproducible)**
- Writing `usb_f_acm` to UDC causes DWC3 to hang — PMIC power cycle required to recover
- Marked ACM as DEAD in `docs/porting/dipper-hardware-limits.md`
- Killed software watchdog from all init variants (ABL handles safety)

### Phase 2: NCM Boot Image (T1)
- Created `tools/init_l0_ncm_t1.sh` — exact pmOS NCM configfs sequence with kmsg logging
- Built `/tmp/l0_t1_ncm_boot.img` (45.6 MB, SHA 00020b63)
  - Kernel: `vmlinuz` + headless DTB appended (from dipper-20260721 artifacts)
  - Ramdisk: stock pmOS initramfs with `/init` replaced by T1 script
  - Cmdline: `console=ttyMSM0,115200 earlycon=msm_geni_serial,0xa840000 panic=15 loglevel=8`
- Committed and pushed: `tools/init_l0_ncm_t1.sh`, `tools/init_uom-fixed.sh`, `docs/porting/dipper-hardware-limits.md`

### Phase 3: Source Investigation
- **Upstream sdm845-mainline**: does NOT include dipper (only OnePlus 6/6T, Poco F1)
- **woaiyuzi/postmarketos (GitHub)**: community dipper pmaports, source-only, 12 commits
  - Kernel 6.5.0 from `evil-hero/linux` (very old, not sdm845-mainline)
  - Actually depends on `linux-postmarketos-qcom-sdm845`, not custom kernel
  - **No prebuilt images, no releases, no CI**
  - Not useful without `pmbootstrap` build from source
- **Poco F1 (beryllium)**: boot images available at `images.postmarketos.org`
  - Two panel variants (ebbg, tianma), ~27.4 MiB each
  - Uses `linux-postmarketos-qcom-sdm845` — likely no dipper DTB included
  - Could modify by replacing kernel+DTB with our dipper headless kernel

---

## Current Status

| Item | Status |
|------|--------|
| T1 boot image | ✅ Ready at `/tmp/l0_t1_ncm_boot.img` |
| Phone connection | ✅ ADB mode (af4aa323) |
| Fastboot mode | ❌ Not yet — need `adb reboot bootloader` |
| NCM test | ⏳ Pending |
| Poco F1 image approach | 🔍 Explored — ready if needed |

---

## Roadblocks

1. **ACM → DWC3 lockup** (HARDWARE_INCOMPATIBLE) — NCM is the only viable gadget path
2. **No serial console** — No debug UART breakout on dipper hardware
3. **No pstore/ramoops** — RAM cleared on `fastboot boot`, no crashlog retention
4. **All USB gadget drivers = modules** — Initramfs module loading path unproven on target
5. **No upstream dipper support** — Not in sdm845-mainline device list; community port is stale (kernel 6.5.0)
6. **Phone charging pins damaged** — Slow charging, may affect extended test sessions
7. **Phone in ADB mode** — Must transition to fastboot before boot image can be loaded

---

## Immediate Next Steps

1. `adb reboot bootloader` → enter fastboot mode
2. `fastboot boot /tmp/l0_t1_ncm_boot.img` → boot T1 image
3. Observe host side:
   - `dmesg -w` for USB enumeration events
   - `lsusb` for new device VID/PID
   - `ip link` for `usb0` NCM interface
4. If NCM works: `ssh user@172.16.42.1` → `dmesg` for full kernel log
5. If NCM fails: let ABL watchdog auto-reboot (~51-198s), analyze failure mode
6. Fallback: modify Poco F1 boot image (replace kernel+DTB with dipper headless)

---

## Relevant Files

| File | Description |
|------|-------------|
| `/tmp/l0_t1_ncm_boot.img` | T1 NCM boot image (SHA 00020b63) |
| `tools/init_l0_ncm_t1.sh` | T1 NCM init script |
| `tools/init_uom-fixed.sh` | Legacy ACM init (watchdog killed) |
| `docs/porting/dipper-hardware-limits.md` | Hardware limits doc (ACM=DEAD, watchdog notes) |
| `/tmp/pmos-initfs-stock/` | Extracted stock pmOS initramfs |
| `/home/alpine/uom-artifact-vault/dipper-20260721/` | Kernel, DTB, initramfs artifacts |
| `https://gitlab.com/sdm845-mainline/linux` | Upstream kernel (tag sdm845-7.1-rc1-r0) |
| `https://github.com/woaiyuzi/postmarketos` | Community dipper pmaports (stale, 6.5.0) |
| `https://images.postmarketos.org/bpo/v26.06/xiaomi-beryllium/` | Poco F1 boot images (for reference) |

---

## Day 3 Continuation (same day, progress/refactor)

### Refactor delivered
| Artifact | Purpose |
|----------|---------|
| `tools/init_l0_ncm_t1.sh` | Hardened T1 init: depmod, pmOS mount flags, full gadget cleanup, RNDIS fallback, unudhcpd, KEY_* diagnostics |
| `tools/uom-build-l0-t1.sh` | Reproducible T1 boot.img builder (stock initramfs + T1 init + headless DTB) |
| `tools/uom-host-ncm-watch.sh` | Host USB/NCM observer + auto iface config + ping |

### Rebuilt image
- Path: `/tmp/l0_t1_ncm_boot.img`
- Size: 45678592 bytes
- SHA256: `f085ace7f9a024a649879dc0eab25f0d63e710f3498f3b561a56eccc0718d714`
- Cmdline: `console=ttyMSM0,115200 androidboot.hardware=qcom earlycon=msm_geni_serial,0xa840000 panic=15 printk.time=1 loglevel=8 log_buf_len=1M`

### Hardware gate
- Phone **not connected** at refactor time (last dmesg: af4aa323 disconnect; port occupied by mouse)
- DTB check: both DWC3 nodes `dr_mode = "peripheral"` on headless dipper DTB
- Modules present in initramfs: `usb_f_ncm.ko.zst`, `usb_f_rndis.ko.zst`, `libcomposite.ko.zst`, `u_ether.ko.zst`

### Still pending
1. ~~Reconnect phone → `adb reboot bootloader`~~
2. ~~`fastboot boot /tmp/l0_t1_ncm_boot.img` + host watch~~
3. Record pass/fail timing and host enumeration evidence — **DONE (FAIL)**

---

## T1 Boot Result (2026-07-23 22:18 IST) — FAIL

**Log:** `/tmp/uom-t1-test-20260723-221836.log`  
**Image:** `/tmp/l0_t1_ncm_boot.img` SHA `f085ace7…`  
**Command:** `fastboot boot` → OKAY (1.079s)

| Phase | Evidence | Verdict |
|-------|----------|---------|
| D4 boot handoff | `Sending boot.img OKAY / Booting OKAY` | **PASS** |
| Host gadget `18d1:d001` | never appeared | **FAIL** |
| Host `usb0` / NCM / RNDIS | never appeared | **FAIL** |
| Ping `172.16.42.1` | never | **FAIL** |
| Recovery | ADB `af4aa323` back at **+62s** (Android) | ABL reclaim |

### Timeline (host)
| t | USB |
|---|-----|
| 0s | `fastboot boot` OKAY |
| +1…+6s | still `18d1:d00d` (fastboot) briefly |
| +7s | USB disconnect (kernel took over; no gadget) |
| +7…+61s | **no USB device at all** |
| +62s | `18d1:4ee7` ADB — Android recovered |

### Timing diagnosis
- **~54s dark window** after disconnect → classic **idle ABL watchdog (~51s)**, not the USB-active ~198s path.
- Stock pmOS previously extended to ~198s with USB activity; T1 did **not** produce host-visible USB.
- Implies: kernel likely booted, but **gadget never bound/enumerated** (module load, UDC, or configfs path still broken) — *or* init died before UDC bind (no host signal either way).

### Not a DWC3 lockup
- Phone returned to Android automatically (no PMIC power-cycle needed).
- ACM-style hard hang ruled out for this image.

### Next (priority order)
1. **T1b — force-load modules + longer pre-UDC logging** via vibrator/LED if available; or try **RNDIS-first** (host already has `rndis_host` from earlier Android tethering event).
2. **Stock pmOS boot.img baseline** with headless DTB — confirm host ever sees `18d1:d001` from unmodified init.
3. **Kernel rebuild** `CONFIG_USB_LIBCOMPOSITE=y` `CONFIG_USB_CONFIGFS=y` `CONFIG_USB_F_NCM=y` (eliminate modprobe/zstd).
4. **pstore/ramoops + simplefb** for any on-device log after reclaim.
