# L0 Progress Report — 2026-07-22

## Session: Dipper USB Gadget Debug (Day 2)

**Device:** Xiaomi Mi 8 (dipper, SDM845)
**Kernel:** 7.1.0-rc1-sdm845 (mainline via pmOS)
**Host:** Alpine Linux laptop (10.118.201.90)
**Phone1:** CRDROID 11.6 (Android 15), kernel 4.9.337-perf

---

## Test Images Built

| Image | Size | SHA256 | Status |
|-------|------|--------|--------|
| `boot-dipper-diag-20260722-fixed.img` | 28.6MB | `6198baab` | **Boots** — D4 PASS, D5 FAIL (ACM → DWC3 lockup) |
| `boot-dipper-l0-ncm.img` | 28.6MB | `733b48f5` | Boots — module metadata present but no gadget |
| `l0_g_ether_boot.img` | 27.9MB | `60db8e1a` | Boots — g_ether not built in kernel |
| `l0_ecm_boot.img` | 30.9MB | (new) | Built with full pmOS initramfs + ECM init |
| `l0_ncm_v2_boot.img` | 30.2MB | (new) | Minimal ramdisk + NCM init v2.1 |

---

## Test Results

### 1. ACM init_uom (FIXED image) 
**Verdict: STAGE_FAIL_HARD_HANG**
- D4 PASS (fastboot boot OK)
- D5 FAIL — writing ACM function to UDC causes DWC3 hardware lockup
- Phone requires PMIC power cycle (hold power ~2s) to recover
- Root cause: `usb_f_acm` + UDC bind → DWC3 register lockup → warm reset insufficient

### 2. Stock pmOS init (baseline)
**Verdict: PASS (no gadget test)**
- USB disconnects ~5s, phone returns ~198s (180s watchdog)
- pmOS uses NCM (not ACM), clears UDC first — no lockup

### 3. Sleep forever (minimal init)
**Verdict: PASS (no gadget test)**
- USB disconnects ~7s, phone returns ~51s (ABL watchdog)
- Confirms kernel boots correctly with minimal init

### 4. NCM via configfs (NCM images x2)
**Verdict: FAIL — no gadget enumeration**
- First image (full pmOS ramdisk + rdinit=): 196s ABL timeout, phone stays in fastboot
- Second image (minimal ramdisk, NCM v2.1): 21s disconnect, phone returns to Android
- `usb0` never appears on host
- Suspected issues:
  - Device tree: `CONFIG_USB_DWC3` may need `dma-coherent` or `dr_mode="peripheral"` 
  - Module loading: kmod + zstd may fail silently
  - DWC3 PHY init may need extcon or USB role switch

### 5. g_ether legacy module test
**Verdict: FAIL — module not available**
- `CONFIG_USB_ETH` is not set in kernel config
- No g_ether.ko in modules directory

---

## Kernel Config Findings

```
CONFIG_USB_GADGET=y              (built-in)
CONFIG_USB_LIBCOMPOSITE=m        (module)
CONFIG_USB_CONFIGFS=m            (module)
CONFIG_USB_F_NCM=m               (module)
CONFIG_USB_F_ECM=m               (module, but .ko not in initramfs)
CONFIG_USB_F_ACM=m               (module — causes DWC3 lockup)
CONFIG_USB_ETH is not set        (no g_ether)
CONFIG_MODULE_DECOMPRESS=y       (zstd modules supported)
CONFIG_RD_ZSTD=y                 (zstd ramdisk supported)
```

**All USB gadget function drivers are modules (=m), NOT built-in.**

---

## Key Blockers

1. **ACM → DWC3 lockup (100% reproducible)** — Cannot use usb_f_acm on this hardware
2. **Module loading in initramfs untested** — kmod + zstd decompress path unverified on target
3. **No debug output** — No UART breakout, no framebuffer console, no pstore/ramoops configured
4. **NCM gadget never enumerates** — Either modules don't load or DWC3 PHY isn't initialized for peripheral mode

---

## Artifacts

| File | Path |
|------|------|
| STAGE-REPORT-L0.md (corrected) | `~uom-artifact-vault/dipper-unattended/20260722-164523/artifacts/gates/STAGE-REPORT-L0.md` |
| dipper-hardware-limits.md | `docs/porting/dipper-hardware-limits.md` |
| init_uom (NCM v2.1) | `tools/init_uom-fixed.sh` |
| L0 images | `/tmp/l0_*.img` |
| Kernel config | `pmaports/.../linux-postmarketos-qcom-sdm845/config-...`
