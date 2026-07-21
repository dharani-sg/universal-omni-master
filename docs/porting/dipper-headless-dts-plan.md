# Dipper Headless DTS Build Plan

**Date:** 2026-07-21
**Status:** Plan — ready to execute after approval

---

## Strategy

Use MR !102 DTS as source, create a headless variant that disables non-essential
peripherals and keeps only boot-critical hardware.

## Two Approaches

### Approach A: Modified DTS (Safe, Recommended)

Create `sdm845-xiaomi-mi8-dipper-headless.dts` based on the original dipper DTS
but with display, touch, audio, and camera disabled.

Changes from original:
```
- Set display_panel status = "disabled" 
- Remove/comment touchscreen node
- Disable WCD9340 audio codec
- Disable camera sensors
- Keep UFS, USB, serial, PMIC, thermal
```

### Approach B: Bootloader-level disable (if DTS cannot be modified)

Use the existing DTS but rely on bootloader to disable faulty nodes.
**Not recommended** — less control, harder to debug.

## Chosen: Approach A

## DTS Changes Required

In `sdm845-xiaomi-mi8-dipper.dts`:

```dts
// SPDX-License-Identifier: GPL-2.0
/dts-v1/;
#include "sdm845-xiaomi-mi8-common.dtsi"

/ {
    model = "Xiaomi Technologies, Inc. Dipper new MP v2.1";
    compatible = "xiaomi,dipper", "qcom,sdm845-mtp", "qcom,sdm845", "qcom,mtp";
    qcom,board-id = <55 0>;
};

/* HEADLESS: disable display panel */
&display_panel {
    status = "disabled";
};

/* HEADLESS: disable touchscreen */
&i2c14 {
    status = "disabled";
};
```

In `sdm845-xiaomi-mi8-common.dtsi`, the following should be disabled
or set to status = "disabled" via the dipper DTS:

| Node | Reason |
|---|---|
| display_panel | No display needed |
| &i2c14 + touchscreen | No touch needed |
| &wcd9340 | Audio not needed for headless |
| &tas2559 | Speaker amp not needed (if present) |
| Camera sensors (imx363, s5k3m3, s5k3t1) | Not needed |
| &pmi8998_charger | Keep for safety monitoring |
| Modem/MPSS | Keep if safe, can monitor |

## Kernel Config Needed

Based on the current `linux-postmarketos-qcom-sdm845` config:

Required:
- CONFIG_ARCH_QCOM=y — SoC
- CONFIG_SCSI_UFS_QCOM=y — UFS storage
- CONFIG_USB_DWC3=y — USB
- CONFIG_SERIAL_MSM_GENI=y — Serial console
- CONFIG_REGULATOR_QCOM_RPMH=y — PMIC
- CONFIG_QRTR=y
- CONFIG_QCOM_SMEM=y

Can be disabled for headless:
- CONFIG_DRM_MSM (or keep for simple fb)
- CONFIG_TOUCHSCREEN — disable all
- CONFIG_SND_SOC — disable audio
- CONFIG_VIDEO_* — disable cameras

## Build Steps

1. Add DTS entry to Makefile in `arch/arm64/boot/dts/qcom/`
2. Compile DTB with `make dtbs`
3. Verify compatible string
4. Package with existing rootfs
5. Generate boot image with correct offsets
6. Analyze boot image before test

## Validation

Before fastboot boot:
- [ ] DTB compiles without errors
- [ ] compatible = "xiaomi,dipper"
- [ ] board-id matches bootloader
- [ ] Boot image offsets verified
- [ ] Rollback plan documented
