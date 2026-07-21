# MR !102 DTS Audit — Xiaomi Mi 8 (dipper/equuleus/ursa)

**Date:** 2026-07-21
**Status:** Draft audit — pre-headless-build review
**Source:** sdm845-mainline!102 (Kreyren fork, branch `add-xiaomi-ursa`)

---

## 1. Source Information

| Field | Value |
|---|---|
| MR ID | !102 |
| Title | Draft: Add Xiaomi Mi 8 DTS (dipper,equuleus,ursa) |
| Author | Kreyren |
| State | opened (2024-08-21) |
| Target branch | sdm845/6.11-dev |
| Source branch | add-xiaomi-ursa |
| Source fork | https://gitlab.com/krey_glsux2/sdm845-mainline.git |
| Cloned HEAD | e064845bc |
| HEAD subject | "Sync" |
| License | GPL-2.0 |

## 2. DTS Files

| File | Size | SHA-256 | Status |
|---|---|---|---|
| sdm845-xiaomi-mi8-common.dtsi | 1367 lines | 2642b978... | DRAFT |
| sdm845-xiaomi-mi8-dipper.dts | 47 lines | b408580a... | DRAFT |
| sdm845-xiaomi-mi8-equuleus.dts | 254 lines | 3f794278... | DRAFT |
| sdm845-xiaomi-mi8-ursa.dts | 21 lines | * | DRAFT |

**File hierarchy:**
- `sdm845-xiaomi-mi8-common.dtsi` — base (includes sdm845.dtsi + PMIC includes)
- `sdm845-xiaomi-mi8-dipper.dts` — dipper (standard Mi 8): common + board-id + display + touch
- `sdm845-xiaomi-mi8-equuleus.dts` — equuleus (Mi 8 Pro): common + regulators + display + touch + audio
- `sdm845-xiaomi-mi8-ursa.dts` — ursa (Mi 8 Explorer): includes equuleus DTS

## 3. DIPPER DTS Content (sdm845-xiaomi-mi8-dipper.dts)

```
model = "Xiaomi Technologies, Inc. Dipper new MP v2.1";
compatible = "xiaomi,dipper", "qcom,sdm845-mtp", "qcom,sdm845", "qcom,mtp";
board-id = <55 0>;       // REVIEW(Krey): from LineageOS kernel

display_panel:            // enabled, samsung,ea8074 (AMOLED)
touchscreen@49:            // i2c14, focaltech,ft8719, GPIO 31/32
```

The dipper DTS is **minimal** (47 lines). It enables only:
- Display panel (Samsung EA8074 AMOLED)
- Touchscreen (FocalTech FT8719)

All other devices are configured in the common.dtsi.

## 4. REVIEW Markers (Safety Critical)

Found **~50 REVIEW markers** in common.dtsi. Classified by risk:

### HIGH RISK — Regulators with uncertain values (must audit before production)

| Line | Regulator | Issue |
|---|---|---|
| 208 | General | TODO: Check all min and max volts |
| 298 | vreg_s2a | Uses 1.1V instead of schematic value; uncertain |
| 393 | vreg_display_bob | Used values from Ref.2 without verification |
| 422 | vreg_l2a | FIXME: No datasheet; 80% of 4V may be unsafe |
| 447 | vreg_l1a | Uncertain; re-used from beryllium |
| 561 | VDDA_MIPI_DSI | Two LDOs connected by resistor; handling uncertain |
| 859-869 | PMIC regulators | "Needed? Used by beryllium" — uncertain |
| 985 | Charger | QC 4.0 vs QC 3.0 difference uncertain |

### MEDIUM RISK — Reserved memory / ramoops

| Line | Issue |
|---|---|
| 80 | UART GPIO assignments marked REVIEW |
| 180 | Ramoops region size marked as wrong |
| 185 | Ramoops region marked as likely wrong |

### LOW RISK — Taken from beryllium (likely correct for shared SoC blocks)

| Lines | Description |
|---|---|
| 930-973 | Audio, WCD, SLIMbus (beryllium-derived) |
| 1061 | USB configuration |
| 1176-1277 | UFS, USB PHY, PCIe, Bluetooth (beryllium/5.12.8-derived) |
| 1311 | IMX363 camera (beryllium-derived) |

## 5. Headless Safety Assessment

### Boot-Critical (SAFE for headless)
- CPU: 8x Kryo 385 (SDM845 SoC-level) — OK
- PSCI: Standard ARM PSCI — OK
- GIC: SoC-level — OK
- UFS: `ufs_mem_hc` + `ufs_mem_phy` with proper regulators — OK
- USB: `usb_1` + `usb_1_dwc3` host mode, USB2 — OK
- Serial: `uart9` at 115200, stdout-path set — OK
- PMIC: PM845/PMI8998/PM8005 with RPMh — **mostly OK, but some regulator values uncertain**
- RAM: SoC-level — OK

### Risky for First Boot (set to disabled)
- Display panel: `display_panel` / `samsung,ea8074` — DISABLE (not needed headless)
- Backlight: WLED or DSI-native — DISABLE
- Touchscreen: `focaltech,ft8719` — DISABLE (not needed headless)
- Camera: IMX363 + S5K3M3 — DISABLE (not needed headless)
- Audio: WCD9340 + TAS2559 — DISABLE (not needed headless)
- Fingerprint: not present in dipper DTS — OK

### Unknown / Requires Bootloader Verification
- Board-ID: `qcom,board-id = <55 0>` — must match dipper bootloader
- Reserved memory carveouts — from actual device dump, **should be correct**
- Regulator voltages for UFS/USB rails — should be OK if derived from beryllium

## 6. Action Items for Safe Headless Boot

1. [ ] Clone full kernel tree (not shallow) for proper build
2. [ ] Add missing Makefile entry for mi8 DTS files if needed
3. [ ] Create headless overlay or modified DTS that disables: display, touch, audio, camera, fingerprint
4. [ ] Audit all `REVIEW` regulator nodes for safe headless defaults
5. [ ] Test-compile DTS
6. [ ] Compare with the current pmaports kernel config (7.1-rc1) for DTS compatibility
7. [ ] Merge with pmaports device-xiaomi-dipper package
8. [ ] Build and analyze boot image

## 7. Classification

**Current state:** DRAFT — usable for headless build after disabling display/touch/audio/camera.

**Verification needed before first boot:**
- Compile DTB and verify compatible string is "xiaomi,dipper"
- Boot image must use correct offsets from bootimg_analyze
- Board-ID matching must be validated
