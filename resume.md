# Session Resume — Dipper L0 USB Gadget

## Last Updated: 2026-07-23T00:00:00Z

### Phase: L0 — USB Gadget Enumeration
### Status: BLOCKED — No gadget enumerates on host

### Device State
- **ADB**: device (af4aa323)
- **Fastboot**: none
- **Kernel under test**: 7.1.0-rc1-sdm845
- **Phone OS**: CRDROID 11.6 (Android 15), kernel 4.9.337-perf

### Last Image Tested
- `l0_ncm_v2_boot.img` (NCM v2.1, minimal ramdisk)
- fastboot boot OKAY, 21s disconnect, no `usb0`
- Phone returned to Android automatically

### Key Blockers
1. ACM causes 100% reproducible DWC3 lockup — cannot use
2. All gadget function drivers are modules (=m), NOT built-in
3. Module loading (kmod + zstd) in initramfs is unverified on target
4. No debug output — no UART, no framebuffer console, no pstore

### Next Actions (Tomorrow)

**1. Verify module loading works**
- Build minimal init that loads evdev.ko, check success via GPIO/vibrator

**2. Rebuild kernel with built-in gadget drivers**
- Set CONFIG_USB_LIBCOMPOSITE=y, CONFIG_USB_F_NCM=y
- Eliminates modprobe dependency

**3. Add debug visibility**
- Enable CONFIG_FB_SIMPLE, CONFIG_FRAMEBUFFER_CONSOLE
- Configure pstore/ramoops

**4. Try RNDIS**
- usb_f_rndis.ko.zst exists as alternative to NCM

### Session Reports
- L0 progress: `docs/L0-PROGRESS-REPORT-20260722.md`
- Session detail: `docs/SESSION-20260722-DIPPER-L0.md`
- Hardware limits: `docs/porting/dipper-hardware-limits.md`

### Triple Sync Targets
- Laptop: `/home/alpine/src/universal-omni-master/`
- Phone1 (SSH): `u0_a217@10.118.201.92:8022`
- GitHub: `https://github.com/dharani-sg/universal-omni-master.git`
