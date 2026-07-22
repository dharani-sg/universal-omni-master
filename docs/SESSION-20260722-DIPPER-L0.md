# Session Report — 2026-07-22 Dipper L0 USB Gadget Debug

**Date:** 2026-07-22
**Focus:** L0 USB gadget enumeration on Xiaomi Mi 8 (dipper)

---

## Tests Performed

### 1. Fixed init_uom (ACM) — boot-dipper-diag-20260722-fixed.img
- Result: D4 PASS, D5 FAIL (hard hang)
- DWC3 lockup confirmed: ACM function + UDC write = 100% hang
- Root cause documented in STAGE-REPORT-L0.md

### 2. NCM vs ACM comparison tests
- Empty ramdisk: boots, panics, returns ~2s
- Sleep forever: boots, disconnects ~7s, returns ~51s
- Stock pmOS: boots, disconnects ~5s, returns ~198s
- ACM init_uom: boots, hard hang at ~13s

### 3. NCM configfs attempts (2 builds)
- Build 1: full pmOS ramdisk + rdinit=/init_uom with ECM → 196s fastboot stall
- Build 2: minimal ramdisk + init=NCM v2.1 → 21s disconnect, no `usb0`

### 4. g_ether test
- `CONFIG_USB_ETH` not set — module not available

---

## Key Discoveries

1. ACM causes irreversible DWC3 lockup on this hardware — must use NCM/ECM/RNDIS
2. All gadget function drivers are modules (=m), not built-in
3. Module loading via kmod+zstd in initramfs is unverified on target
4. No debug output mechanism exists (no UART, no framebuffer console, no pstore)

---

## Open Issues for Tomorrow

### Priority 1: Verify module loading works
- Build a test init that loads a simple module (e.g., `evdev`) and signals success via LED/vibrator
- Check if kmod can find and decompress zstd modules in initramfs

### Priority 2: Get USB gadget working
- Option A: Rebuild kernel with `CONFIG_USB_LIBCOMPOSITE=y` and `CONFIG_USB_F_NCM=y` (built-in)
- Option B: Verify DWC3 PHY init — check `dr_mode` in DTB, extcon drivers
- Option C: Try RNDIS instead of NCM (usb_f_rndis.ko.zst exists)
- Option D: Check if `g_serial` (usb_f_serial) works without lockup

### Priority 3: Add debug visibility
- Enable framebuffer console (CONFIG_FB_SIMPLE + CONFIG_FRAMEBUFFER_CONSOLE)
- Configure pstore/ramoops to capture kernel logs across reboots
- Check if UART pins are accessible on the Mi 8

### Priority 4: Hardware watchdog
- Enable `CONFIG_QCOM_WDT` in kernel config
- Wire watchdog in DTB
- Add userspace watchdog daemon

---

## Images Ready for Testing

| Image | Path | Purpose |
|-------|------|---------|
| `l0_ncm_v2_boot.img` | `/tmp/l0_ncm_v2_boot.img` | NCM configfs test (need modprobe debug) |
| `l0_ecm_boot.img` | `/tmp/l0_ecm_boot.img` | ECM configfs test (usb_f_ecm missing) |
