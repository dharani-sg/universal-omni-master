# Architecture Decision Record: Kernel Strategy for Mi 8 (Dipper) Headless

## Status: ACCEPTED
## Date: 2026-07-21
## Decision: Use 7.1-rc1 kernel + 7.2-rc4 USB role switch architecture

---

## Context

We are building a trustable native headless Linux for Phone1 (Xiaomi Mi 8 / dipper). The kernel strategy must:
1. Boot reliably on the device
2. Support USB gadget (ACM serial + RNDIS networking) for headless control
3. Be maintainable and auditable
4. Not require proprietary blobs for basic bring-up

## Triple Kernel Comparison

### 1. Android Kernel (crDroid)
- **Source**: OFOX backup (boot.emmc.win)
- **Version**: 4.9.x (Android 9)
- **Config**: `androidboot.configfs=true`, `androidboot.usbcontroller=a600000.dwc3`
- **USB**: DWC3 dual role, extcon-based
- **Pros**: Full hardware support, proven on device
- **Cons**: Proprietary blobs, not mainline, not auditable

### 2. pmOS Mainline Kernel (7.1-rc1)
- **Source**: LineageOS boot.img extraction + MR !102 DTB
- **Version**: 7.1.0-rc1-sdm845
- **Config**: `CONFIG_USB_GADGET=y`, `CONFIG_USB_DWC3_DUAL_ROLE=y`, `CONFIG_USB_ROLE_SWITCH=y`
- **Modules**: libcomposite, u_ether, u_serial, usb_f_acm, usb_f_rndis, usb_f_ncm
- **Pros**: Mainline, auditable, no proprietary blobs for USB
- **Cons**: Not all hardware working yet, WIP

### 3. Latest Mainline (7.2-rc4)
- **Source**: /home/alpine/Downloads/linux-7.2-rc4.tar.gz
- **Version**: 7.2.0-rc4
- **USB Improvements**:
  - Removed extcon (uses USB role switch instead)
  - Added `glue.h` abstraction layer
  - Cleaner `dwc3_qcom` driver (smaller, -28% code)
  - `current_role` enum instead of extcon notifiers
- **DTS**: No dipper DTS (only beryllium, polaris)
- **Pros**: Cleaner USB architecture, better maintained
- **Cons**: No dipper DTS, risk of regression

## Research Findings

### Ubuntu Touch / UBPorts
- **Device**: Xiaomi Mi 8 (dipper)
- **Status**: Supported on old releases (16.04 xenial)
- **Kernel**: Halium 9.0 (Android 9 based)
- **Source**: https://github.com/ubports-dipper/kernel-xiaomi-sdm845
- **Findings**: Stagnant, no mainline work, relies on Android kernel

### PostmarketOS
- **Device**: Xiaomi Mi 8 (dipper)
- **Status**: WIP, MR !4426 (device firmware)
- **Kernel**: 6.6 mainline (initial testing)
- **MR**: sdm845-mainline/linux!81 (closed)
- **Findings**: Active mainline work, but WIP

### Poco F1 (Beryllium)
- **Status**: Active Ubuntu Touch port
- **Kernel**: Halium 9.0 (Android 9 based)
- **Findings**: Similar to dipper, Android kernel based

## Decision

### Use 7.1-rc1 kernel for boot
**Rationale**:
- Already proven (fastboot boot accepted, kernel started)
- Has all needed USB gadget modules
- No regression risk from 7.2-rc4 changes
- DTS from MR !102 is tested

### Use 7.2-rc4 USB role switch architecture in initramfs
**Rationale**:
- Cleaner code (no extcon dependency)
- Better maintainability
- Uses `usb_role_switch` API (built into 7.1-rc1 kernel)
- Future-proof for kernel upgrades

### Defer 7.2-rc4 full kernel upgrade
**Rationale**:
- No dipper DTS in 7.2-rc4
- Risk of regression in other drivers
- Can upgrade later once USB networking is proven

## Consequences

### Positive
- Reliable boot path (7.1-rc1)
- Clean USB gadget architecture (7.2-rc4 style)
- Auditable, mainline kernel
- No proprietary blobs for USB

### Negative
- Two kernel versions to track (7.1-rc1 boot, 7.2-rc4 arch)
- May need to update initramfs when upgrading to 7.2-rc4

### Risks
- 7.2-rc4 may have USB regressions (mitigated by using 7.1-rc1)
- pmOS initramfs may need updates for newer kernels

## Next Steps
1. Test USB networking with current setup
2. Prove ACM serial + RNDIS work
3. Consider 7.2-rc4 kernel upgrade after USB is stable
4. Add WiFi in initramfs (second layer)
