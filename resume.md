# Session Resume — Dipper L0 USB Gadget

## Last Updated: 2026-07-23T22:25:00+05:30

### Phase: L0 — USB Gadget Enumeration (Day 3)
### Status: **T1 FAIL** — D4 PASS, no host gadget; phone auto-recovered via ABL ~62s

### Device State
- **ADB**: device (af4aa323) — back on Android after T1
- **Fastboot**: none
- **Last test**: `fastboot boot /tmp/l0_t1_ncm_boot.img` OKAY, no `18d1:d001`, no `usb0`

### T1 Result (one-liner)
`fastboot boot` OK → ~54s USB dark → ADB back at +62s. Idle ABL path. NCM never enumerated.

### Artifacts
| Item | Path |
|------|------|
| Test log | `/tmp/uom-t1-test-20260723-221836.log` |
| Host watch | `/tmp/uom-host-ncm-watch.log` |
| Boot image | `/tmp/l0_t1_ncm_boot.img` (SHA f085ace7…) |
| Report | `docs/L0-PROGRESS-REPORT-20260723.md` |
| Builder | `tools/uom-build-l0-t1.sh` |
| Init | `tools/init_l0_ncm_t1.sh` |

### Next Actions
1. Stock pmOS init baseline with same kernel+headless DTB (does host ever see gadget?)
2. T1b: RNDIS-first / explicit `modprobe usb_f_ncm u_ether` before configfs mkdir
3. Kernel built-in composite+NCM (drop module path)
4. pstore/ramoops for post-mortem

### Key Blockers (updated)
1. ACM → DWC3 lockup (HARDWARE_INCOMPATIBLE)
2. Custom NCM init still produces **zero host USB** (T1 confirmed)
3. No serial / no pstore — blind without host enumeration
4. All gadget function drivers = modules
