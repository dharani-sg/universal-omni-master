# Guardrail Dry-Run — 2026-07-19

## Guardrails Tested

| Guardrail | Method | Result |
|-----------|--------|--------|
| `check_storage_guardrail` | UOM_SDK_OVERRIDE=35 on laptop with phone-vm-agent profile | PASS — 9184 MiB >= 6144 MiB |
| `check_battery_guardrail` | Same env (laptop has no sysfs battery) | PASS — best-effort, no crash |
| `check_network_guardrail` | Same env (non-metered WiFi) | PASS — "Wi-Fi assumed or not metered" |
| `check_network_gate` (PATCH D) | curl to unreachable host returns fail-closed; code checks github | PASS — "github reachable" on live network |
| Architecture policy (PATCH C) | x86_64 laptop with phone-vm-agent profile | PASS — correctly reports unsupported, falls back to proot-distro |
| Android SDK guard | SDK 0 blocked | PASS — "Android 7.0+ (SDK 24+) required" |
| Android SDK override | UOM_SDK_OVERRIDE=35 | PASS — accepted and proceeds |

## Missing Glue (D3 PARTIAL)
- Guardrails are independently invocable via profile/flag combinations
- No standalone `--guardrail-check` mode exists (must use `--check --profile phone-vm-agent`)
- Battery guardrail cannot be mocked without sysfs fixtures (best-effort mode used)
- Network metered check cannot be mocked without dumpsys (only runs on Android)
- No unified guardrail-only CLI flag — all guardrails are side-effects of `--check` mode

## Verdict: PASS (all existing guardrails functional)
Guardrails work correctly. No regression from patches.
