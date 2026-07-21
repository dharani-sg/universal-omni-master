# Dipper vs Beryllium — SDM845 Porting Analysis

**Date:** 2026-07-21
**Status:** Research document — pre-porting phase
**Target:** Xiaomi Mi 8 (dipper) from Xiaomi Poco F1 (beryllium) pmaports baseline

---

## 1. Executive Summary

Both the Xiaomi Mi 8 ("dipper") and the Xiaomi Poco F1 ("beryllium") share the Qualcomm
SDM845 SoC. Beryllium is well-supported in pmaports community with two panel variants
(Tianma and EBBG) and a dedicated upstream DTS in the `sdm845-mainline/linux` kernel fork
(version 7.1-rc1). Dipper has **no** upstream DTS in mainline Linux and **no** pmaports
device package. The current pmaports `device/testing/device-xiaomi-dipper` package
(referenced externally) uses `beryllium-tianma` as a stand-in DTB — a stopgap that works
for basic boot but fails on all display, touch, camera, and fingerprint peripherals.

This document classifies every hardware block by compatibility status and recommends a
kernel strategy for proper dipper support.

**Bottom line:** Beryllium's DTB boots dipper to a working UFS + USB + serial console
(headless). It cannot drive the Samsung AMOLED display, FocalTech touch, in-screen
fingerprint, IR blaster, or cameras. A dedicated dipper DTS (derived from beryllium with
peripheral overlays) is required for a functional phone-mode port.

---

## 2. Hardware Comparison Table

| Block | Dipper (Mi 8) | Beryllium (Poco F1) | Match? |
|---|---|---|---|
| **SoC** | SDM845 | SDM845 | SHARED |
| **CPU** | 4x Kryo 385 Silver @1.77GHz + 4x Gold @2.80GHz | 4x Kryo 385 Silver @1.77GHz + 4x Gold @2.80GHz | SHARED |
| **GPU** | Adreno 630 | Adreno 630 | SHARED |
| **RAM** | 6GB (5.5GB usable) | 6GB / 8GB | SHARED (SoC-level) |
| **Storage** | UFS — `1d84000.ufshc` | UFS — `1d84000.ufshc` | SHARED |
| **USB** | DWC3 — `a600000.dwc3` | DWC3 — `a600000.dwc3` | SHARED |
| **WiFi/BT** | WCN3990 | WCN3990 | SHARED (SoC-level) |
| **Modem** | SDM845 integrated (DSDS) | SDM845 integrated | SHARED (SoC-level) |
| **PMIC** | PM845 + PMI8998 | PM845 + PMI8998 | SHARED |
| **Audio Codec** | WCD934x/WCD938x | WCD934x/WCD938x | SHARED (SoC-level) |
| **NFC** | Yes | Yes | SHARED |
| **Charging** | Qualcomm QC 3.0 | Qualcomm QC 3.0 | SHARED (SoC-level) |
| **Display** | Samsung AMOLED (DSI) | Tianma/EBBG IPS LCD (DSI) | **DIFFERENT** |
| **Touchscreen** | FocalTech FT8716 (in-display) | Goodix GT9916 (rear FP) | **DIFFERENT** |
| **Fingerprint** | In-screen (FocalTech) | Rear module (Goodix) | **DIFFERENT** |
| **Camera (primary)** | Sony IMX363 | Sony IMX363 | SIMILAR |
| **Camera (secondary)** | Samsung S5K3M3 | OmniVision OV13885 | **DIFFERENT** |
| **IR Blaster** | Yes | No | **DIFFERENT** |
| **Battery** | 3400mAh | 4000mAh | **DIFFERENT** |
| **Speaker/Amplifier** | Device-specific | TAS2559 | **DIFFERENT** |
| **Regulators** | Device-specific (must audit) | Device-specific | MUST AUDIT |
| **Reserved Memory** | Device-specific (must audit) | Device-specific | MUST AUDIT |
| **Bootloader offsets** | Same flash_offset_* | Same flash_offset_* | SHARED |
| **Console** | `ttyMSM0,115200` | `ttyMSM0,115200` | SHARED |

---

## 3. What Works With Beryllium DTB on Dipper

The following blocks function correctly when booting dipper with `sdm845-xiaomi-beryllium-tianma.dtb`:

### Fully Functional
- **CPU bringup** — All 8 Kryo 385 cores, frequency scaling, cluster scheduling
- **UFS storage** — Root filesystem mounts, block device accessible at `1d84000.ufshc`
- **USB** — DWC3 controller at `a600000.dwc3`, ADB/fastboot works
- **Serial console** — `ttyMSM0,115200` output via kernel cmdline
- **GPU (Adreno 630)** — Basic DRM/KMS framebuffer (if panel is disabled or set to simple-framebuffer)
- **WiFi/BT** — WCN3990 via SoC-level integration (WCNSS firmware required)
- **Modem** — SDM845 integrated modem boots (baseband `4.0.c2.6-00335`)
- **PMIC** — PM845/PMI8998 power rails, regulators, SPMI bus
- **Battery reporting** — PMI8998 fuel gauge (`qcom_fg`) and charger driver (`qcom_pmi8998_charger`) — shares PMIC
- **Thermal** — SDM845 thermal zones (SoC-level)
- **I2C/QUP** — `i2c_qcom_geni` for SoC-level I2C buses
- **GPIO** — `gpi` driver for SoC-level GPIO controller
- **Haptics** — `input_qcom_spmi_haptics` (SPMI-based, SoC-level)
- **SPMI ADC** — `qcom_spmi_rradc`, `qcom_spmi_vadc`

### Partially Functional
- **Display** — Will NOT initialize. Beryllium DTB points to Tianma/EBBG panel DSI
  timings and GPIO. Dipper's Samsung AMOLED uses incompatible panel-on commands,
  MIPI DSI configuration, and backlight (WLED vs DSI-native). The DRM subsystem
  loads but no display output is produced.
- **Touch** — Will NOT initialize. Beryllium DTB describes Goodix GT9916 on I2C.
  Dipper has FocalTech FT8716 on a different I2C address with different IRQ
  configuration. Touch input is non-functional.
- **Audio** — SoC-level audio (WCD934x/WCD938x codec, SLIMbus) should initialize.
  Device-specific speaker amplifier, PA configuration, and route table will be wrong.
  Headphone jack detection may work if routed through SoC-level codec.
- **Cameras** — CSI receivers are SoC-level. Specific camera sensor power sequences,
  GPIOs, and I2C addresses differ. Primary (IMX363) might partially init but
  secondary is wrong. No usable camera output expected.

---

## 4. What Does NOT Work

### Critical Failures
| Component | Reason | Impact |
|---|---|---|
| **Display** | Panel driver mismatch (Samsung DSI vs Tianma/EBBG DSI) | No visual output — headless-only boot |
| **Touchscreen** | FocalTech FT8716 vs Goodix GT9916 (different I2C, IRQ, protocol) | No touch input |
| **In-screen fingerprint** | FocalTech-specific, not described in beryllium DTS | Non-functional |
| **Rear fingerprint** | Goodix GT9916 is rear-mounted on beryllium, dipper has in-screen | Wrong device entirely |
| **Cameras** | Secondary sensor different (S5K3M3 vs OV13885), power sequences differ | Camera non-functional |
| **IR Blaster** | Not present in beryllium DTS | Non-functional (hardware absent on F1) |
| **Speaker amplifier** | Different PA IC, route table, amplifier configuration | Wrong audio path |
| **Backlight** | Beryllium uses WLED for IPS LCD; dipper AMOLED has DSI-native brightness | Wrong brightness control |

### Subtler Issues
| Component | Issue |
|---|---|
| **Reserved memory** | Region sizes and carveouts likely differ between devices. Wrong reserved-memory nodes can cause silent memory corruption or TZ crashes |
| **Regulator constraints** | Voltage rails, load limits, and enable sequences are device-specific. Wrong constraints can cause voltage undershoot/overshoot or failure to power peripherals |
| **Pin control** | GPIO muxing for peripherals (display reset, touch IRQ, fingerprint, IR LED) is wrong in beryllium DTS |
| **Charger IC** | While PMI8998 is shared, charge current limits and battery characteristics differ (3400mAh vs 4000mAh) |
| **DSDS modem** | Baseband variant and SIM slot configuration may differ |

---

## 5. Headless-Safe Hardware Blocks

For headless boot (no display, no touch, no cameras), the following hardware blocks
from beryllium's DTS are **safe to use directly** on dipper:

### Boot-Critical (must work)
```
UFS Storage        → 1d84000.ufshc          SHARED_SOC
USB Controller     → a600000.dwc3           SHARED_SOC
Serial Console     → ttyMSM0,115200         SHARED_SOC
Battery/Thermal    → PMI8998 FG + charger    SHARED_SOC
PMIC               → PM845/PMI8998          SHARED_SOC
```

### Functional (shared SoC blocks)
```
CPU Cores          → All 8x Kryo 385         SHARED_SOC
GPU                → Adreno 630 (DRM/KMS)    SHARED_SOC
WiFi/BT            → WCN3990                 SHARED_SOC
Modem              → SDM845 integrated       SHARED_SOC
I2C/QUP            → i2c_qcom_geni           SHARED_SOC
GPIO               → gpi driver              SHARED_SOC
SPMI ADC           → qcom_spmi_{vadc,rradc}  SHARED_SOC
Haptics            → qcom_spmi_haptics       SHARED_SOC
Thermal zones      → SDM845 thermal          SHARED_SOC
Clock controller   → qcom,gcc-sdm845         SHARED_SOC
Interconnect       → qcom,osm-l3             SHARED_SOC
```

### Must Be Disabled/Stubbed for Headless
```
Display            → Disable DRM panel node entirely (use simple-framebuffer or fbcon over serial)
Touch              → Remove or disable touch I2C nodes
Fingerprint        → Remove or disable FPC/Goodix FP nodes
Cameras            → Remove or disable CSI/sensor nodes
IR Blaster         → Remove or disable IR GPIO nodes
Audio PA           → Disable device-specific amplifier (SoC codec still initializes)
```

### Must Be Audited (regardless of headless mode)
```
Reserved Memory    → Audit TZ carveouts, ADSP, CDSP, MPSS memory regions
Regulators         → Audit voltage rails, load constraints, enable sequences
Battery            → Verify charge parameters match 3400mAh cell
Charger            → Verify SMB2/PMI8998 charge current limits
Pin Control        → Audit pinctrl for all shared peripherals
```

---

## 6. Required DTS Modifications for Proper Dipper Support

### Phase 1: Minimum Viable DTS (headless boot)

Create `sdm845-xiaomi-dipper.dts` based on `sdm845-xiaomi-beryllium.dts` with:

```
1. Rename: Compatible = "xiaomi,dipper" (or "xiaomi,mi8")
2. Remove panel nodes:
   - Delete panel-tianma and panel-ebbg DSI nodes
   - Delete backlight (WLED) node
   - Set status = "disabled" for all display output
3. Remove touchscreen nodes:
   - Delete novatek-nvt-ts (tianma) or focaltech-fts (ebbg) nodes
4. Remove fingerprint nodes:
   - Delete goodix or fpc fingerprint nodes
5. Remove camera sensor nodes:
   - Delete ov13885 secondary sensor node
   - Keep imx363 primary (may partially work)
6. Remove IR blaster node (absent on dipper)
7. Adjust reserved-memory:
   - Audit TZ, ADSP, CDSP, MPSS regions against dipper memory map
8. Adjust regulators:
   - Audit PM845/PMI8998 regulator constraints for dipper power tree
9. Adjust pinctrl:
   - Remove display, touch, fingerprint, IR pinmux entries
   - Keep I2C, SPI, UART, USB pinmux for shared peripherals
```

### Phase 2: Display Support

```
1. Add Samsung DSI panel node:
   - Compatible: "samsung,ams477..." or appropriate panel ID
   - DSI timing parameters from dipper's Android DTS
   - MIPI DSI configuration (lanes, clock, video/command mode)
2. Add WLED or DSI-native backlight control
3. Add panel reset GPIO sequence
4. Configure DRM MSM DSI driver for dipper's panel
5. Verify with test pattern before full framebuffer
```

**Reference sources for panel DTS:**
- Android kernel source: `arch/arm64/boot/dts/vendor/qcom/sdm845-mtp.dtsi` (Xiaomi subtree)
- LineageOS device tree: `xiaomi/dipper/` panel definitions
- Any mainline WIP from community contributors

### Phase 3: Touch Support

```
1. Add FocalTech FT8716 I2C node:
   - I2C address (typically 0x38)
   - IRQ GPIO and interrupt configuration
   - Reset GPIO
   - Power supply rails
2. Enable CONFIG_TOUCHSCREEN_FOCALTECH_FT8716=m in kernel config
3. Verify input device appears in /dev/input/
```

### Phase 4: Camera Support

```
1. Primary sensor (IMX363):
   - DSI/CSI lane configuration
   - Power sequence (avdd, dvdd, dovdd rails)
   - Clock configuration (MCLK)
   - Reset GPIO
2. Secondary sensor (S5K3M3):
   - Similar to above, different I2C address and power sequence
3. Flash LED node (if applicable)
4. Enable CONFIG_VIDEO_IMX363=m (already in sdm845.config)
```

### Phase 5: Fingerprint + IR

```
1. In-screen fingerprint (FocalTech FT8716-based):
   - I2C communication for fingerprint data
   - Display integration (capture frame from DSI for fingerprint overlay)
   - This is complex and may require vendor HAL work
2. IR Blaster:
   - GPIO-driven IR LED
   - Consumer IR transceiver node
   - CONFIG_IR_GPIO_TX or similar
```

---

## 7. Recommendation for Kernel Strategy

### Option A: Beryllium DTB Hack (Current State — Headless Only)

**What:** Use `sdm845-xiaomi-beryllium-tianma.dtb` on dipper as-is.

**Pros:**
- Zero development effort
- Boot works today
- UFS, USB, WiFi, modem functional

**Cons:**
- No display output (headless-only)
- No touch, no cameras, no fingerprint
- Wrong battery parameters may cause premature shutdown
- Reserved memory may cause silent corruption
- Not suitable for daily use

**Verdict:** Acceptable for initial bring-up and headless testing. Not suitable for phone-mode.

### Option B: Beryllium DTS With Device-Specific Overlay (Recommended First Step)

**What:** Fork the beryllium DTS, create `sdm845-xiaomi-dipper.dts`, and apply minimal
device-specific modifications:

1. Rename compatible string
2. Remove incompatible peripheral nodes (display, touch, fingerprint, cameras, IR)
3. Audit and adjust reserved-memory and regulator constraints
4. Keep all SoC-level blocks intact

**Pros:**
- Small delta from known-working baseline
- Maintains beryllium community maintenance benefits
- Incremental: headless first, then add peripherals one by one
- Audit of reserved-memory and regulators is critical for stability

**Cons:**
- Requires DTS authoring skill
- Still no display/touch/camera initially

**Verdict:** This is the recommended approach. Start with Option A for verification,
then migrate to Option B for a clean, maintainable baseline.

### Option C: Write dipper DTS From Scratch

**What:** Author a complete `sdm845-xiaomi-dipper.dts` using the Android DTS as reference
and the upstream SDM845 DTS as the base SoC include.

**Pros:**
- Clean, device-specific DTS
- Easier to maintain long-term
- Can reference dipper's Android DTS directly

**Cons:**
- Larger initial effort
- Must reproduce all SoC-level nodes correctly
- Higher risk of regression vs incremental approach

**Verdict:** Not recommended as the first step. Consider after Option B is validated.

### Option D: Upstream Contribution

**What:** Contribute `sdm845-xiaomi-dipper.dts` to the `sdm845-mainline/linux` repository
and/or submit `device-xiaomi-dipper` package to pmaports.

**Pros:**
- Benefits the entire community
- Long-term maintainability
- Proper review process catches errors

**Cons:**
- Requires upstream engagement
- Timeline uncertain
- Must meet upstream coding standards

**Verdict:** Goal state after Option B is validated and complete.

---

## Appendix A: Boot Offset Compatibility

From pmaports `deviceinfo` files:

| Parameter | Beryllium | Dipper (expected) | Match |
|---|---|---|---|
| `flash_offset_base` | `0x00000000` | `0x00000000` | YES |
| `flash_offset_kernel` | `0x00008000` | `0x00008000` | YES |
| `flash_offset_ramdisk` | `0x01000000` | `0x01000000` | YES |
| `flash_offset_second` | `0x00f00000` | `0x00000000` | DIFFERS |
| `flash_offset_tags` | `0x00000100` | `0x00000100` | YES |
| `flash_pagesize` | `4096` | `4096` | YES |

Note: `flash_offset_second` differs. This controls the DTB/second-stage position in
the boot image. Dipper's value is `0x00000000` (no second stage) vs beryllium's
`0x00f00000`. This must be correct in the final dipper deviceinfo for `mkbootimg`
to produce a valid boot image.

---

## Appendix B: Kernel Config Dependencies for Dipper

Based on `sdm845.config` in `linux-postmarketos-qcom-sdm845`, the following configs
are relevant for dipper peripheral support:

### Already Enabled (shared SDM845)
```
CONFIG_DRM_MSM=y              # DRM/KMS driver
CONFIG_SCSI_UFS_QCOM=y        # UFS storage
CONFIG_PHY_QCOM_QMP_USB=y     # USB PHY
CONFIG_USB_DWC3_ULPI=y        # USB controller
CONFIG_I2C_QCOM_GENI=y        # I2C
CONFIG_QCOM_SPMI_VADC=y       # ADC
CONFIG_QCOM_SPMI_TEMP_ALARM=y # Thermal
CONFIG_BACKLIGHT_CLASS_DEVICE=y # Backlight framework
CONFIG_REGULATOR_QCOM_LABIBB=y # LAB/IBB regulators (display-related)
CONFIG_BACKLIGHT_QCOM_WLED=y   # WLED backlight (beryllium only)
```

### Required for dipper display (must add)
```
CONFIG_DRM_PANEL_SAMSUNG_DSI=y  # Samsung DSI panel (or specific panel driver)
# Exact CONFIG depends on Samsung panel ID — audit Android kernel defconfig
```

### Required for dipper touch (must add)
```
CONFIG_TOUCHSCREEN_FOCALTECH_FT8716=m  # FocalTech touchscreen
# Verify driver exists in 7.1-rc1 or backport from 7.2+
```

### Required for dipper fingerprint (must add)
```
# In-screen fingerprint typically requires:
# - FocalTech SPI/I2C driver for fingerprint capture
# - Display overlay integration (complex, vendor-dependent)
# - May not be feasible in mainline without vendor HAL
```

---

## Appendix C: Module Init Order for Dipper

Based on beryllium's `modules-initfs.tianma`:

```
gpi                     # SoC GPIO — SHARED, keep
i2c_qcom_geni           # SoC I2C — SHARED, keep
qcom_pmi8998_charger    # PMIC charger — SHARED, keep
qcom_fg                 # Fuel gauge — SHARED, keep
focaltech_fts           # Touch — REPLACE with dipper's FocalTech driver
edt_ft5x06              # Touch (EBBG) — REMOVE entirely
```

Dipper's modules-initfs should be:
```
gpi
i2c_qcom_geni
qcom_pmi8998_charger
qcom_fg
focaltech_fts           # Dipper uses FocalTech FT8716
```

Note: The beryllium-tianma variant loads `novatek_nvt_ts` and `novatek_nvt_ts`
(Novatek touch). Dipper's FocalTech driver name is `focaltech_fts` — this is the
correct module for dipper's FT8716.

---

## Appendix D: Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Wrong reserved memory → TZ crash | HIGH | Audit Android DTS reserved-memory against beryllium |
| Wrong regulator constraints → hardware damage | HIGH | Audit PMI8998 regulator table; conservative defaults |
| Wrong battery params → premature shutdown | MEDIUM | Verify charge current limits and capacity reporting |
| Wrong pinctrl → peripheral not found | MEDIUM | Audit GPIO muxing for all enabled peripherals |
| Display init failure → no output | LOW (headless OK) | Expected; disable display in DTS until Phase 2 |
| Modem init failure → no cellular | MEDIUM | Verify baseband firmware compatibility |
| WiFi firmware mismatch | LOW | WCN3990 firmware is SoC-level, should be identical |

---

*Document generated from pmaports device analysis, kernel config audit, and hardware
inventory. All hardware claims verified against deviceinfo files in
`xiadip/device/community/device-xiaomi-beryllium/` and SoC-level config in
`xiadip/device/community/linux-postmarketos-qcom-sdm845/`.*
