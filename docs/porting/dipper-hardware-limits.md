# dipper Hardware Limits — Out-of-Scope Markers

Sources: UBports UT Xenial (Halium 9.0) dipper artifacts, community reports.
Evidence level: ANDROID_RUNTIME or COMMUNITY_REPORT (not NATIVE_TESTED on mainline).

## Unsupported Features (will never work on any OS)

| Feature | Reason | Source |
|---------|--------|--------|
| FM Radio | No FM radio chip in SDM845 | UT deviceinfo |
| Wireless charging | No Qi coil in dipper hardware | UT deviceinfo |
| Wired external monitor | SDM845 DP alt mode not wired on dipper PCB | UT deviceinfo |
| Double-tap-to-wake | Touch controller/firmware limitation | UT deviceinfo |

**Pipeline impact:** Mark these as `OUT_OF_SCOPE` at all stages. Do not spend stage time.

## Mainline Bring-up Ceilings (expected to work but not yet tested)

| Feature | Stage | Notes |
|---------|-------|-------|
| Panel (Samsung AMOLED) | L3 | Panel compatible string TBD from UT HAL |
| Touch (synaptics?) | L4 | Confirm controller part number from UT HAL |
| Battery/charging | L5 | PMIC driver (PMI8998) needed |
| Modem (Sierra EM06?) | L6 | rmtfs, pd-mapper needed |
| WiFi/BT (QCA6174) | L7 | firmware files needed |
| GPU (Adreno 630) | L5 | freedreno + a630 firmware |
| Sensors (BMI160, etc.) | L4 | iio drivers needed |

## L0 Evidence (2026-07-22 — NATIVE_TESTED on mainline 7.1.0-rc1-sdm845)

| Finding | Evidence Level | Detail |
|---------|---------------|--------|
| D4 (boot) | NATIVE_TESTED | Kernel boots on real hardware via `fastboot boot` |
| usb_f_acm | HARDWARE_INCOMPATIBLE | DWC3 register lockup, 100% reproducible on bind to UDC. PMIC power cycle required. |
| usb_f_ncm | CANDIDATE | Stock pmOS init uses NCM successfully (phone returns at ~198s). Custom init path unverified. |
| ABL watchdog | NATIVE_TESTED | ~51s on minimal init (no USB activity). Extends to ~198s with USB enumeration. |
| Software watchdog | OBSOLETE | ABL provides hardware-level safety. Userspace timer cannot survive hard hang. |

**Consequences:**
- ACM is permanently banned from all dipper images
- No software watchdog timer in init (ABL is the real watchdog)
- L0 path: NCM only (T1→T3→T4 per bringup ladder)

## QUEUE R — UT Xenial Reference Harvest

Read-only reference tasks. No build impact. Mine facts from UT dipper artifacts.

- **R1** Obtain UT dipper install artifacts (halium boot.img + system).
- **R2** Parse Android boot header → confirm fastboot offsets/pagesize/boot partition size.
  Diff ONLY against deviceinfo_flash_offset_*.
- **R3** Extract firmware manifest → build authoritative firmware-xiaomi-dipper file list.
- **R4** Extract panel + touch + sensor part numbers → seed L3/L4 DTB nodes.
- **R5** Record unsupported features (above) into this file.

**NOT to import (traps):**
- Kernel (downstream 4.9, incompatible with mainline 6.x/7.x)
- DTB (wrong bindings, wrong compatible strings)
- libhybris/HAL blobs (irrelevant to native mainline)
- Display/graphics stack (hwcomposer ≠ DRM/freedreno)

Evidence level for QUEUE R: ANDROID_RUNTIME only — fact confirmation, never NATIVE_TESTED.
