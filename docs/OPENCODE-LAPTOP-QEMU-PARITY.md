# OpenCode Laptop ↔ QEMU Guest Parity Report

Generated: 2026-07-18

## Laptop OpenCode Installation

| Property | Value |
|----------|-------|
| Version | 1.18.3 |
| Binary | ELF 64-bit LSB executable, x86-64, dynamically linked (musl) |
| Path | ~/.opencode/bin/opencode |
| Shell | /usr/bin/fish |
| Config | ~/.config/opencode/opencode.json |
| Model | opencode/big-pickle |
| Small model | opencode/north-mini-code-free |
| Enabled providers | opencode only |
| Denied providers | openai, anthropic, google, openrouter |
| NODE_EXTRA_CA_CERTS | /etc/ssl/certs/ca-certificates.crt |
| Permissions | bash: git=allow, doas/sudo=ask, rm -rf=deny, *=ask; edit=ask; write=ask; webfetch=allow |

### Laptop Anonymous Models (verified)

| Model ID | Free | Auth Required |
|----------|------|---------------|
| opencode/big-pickle | Yes | No |
| opencode/deepseek-v4-flash-free | Yes | No |
| opencode/mimo-v2.5-free | Yes | No |
| opencode/north-mini-code-free | Yes | No |
| opencode/nemotron-3-ultra-free | Yes | No |
| opencode/hy3-free | Yes (verify before use) | No |

### Laptop Native Transport

- `opencode run` works directly on laptop (x86-64 musl)
- No PTY workaround needed
- Native transport = primary

## QEMU Guest OpenCode Installation

| Property | Value |
|----------|-------|
| Version | 1.18.3 |
| Binary | ELF 64-bit LSB executable, ARM aarch64, dynamically linked (musl) |
| Path | /home/uom/.opencode/bin/opencode |
| Shell | sh (POSIX) |
| Config | Not configured (zen.env in ~/.config/uom/) |
| Model (zen) | deepseek-v4-flash-free (good pool), big-pickle (normal pool) |

### QEMU Guest Anonymous Models (verified via curl)

Same 5 free models available via `https://opencode.ai/zen/v1/models`:
big-pickle, deepseek-v4-flash-free, mimo-v2.5-free, north-mini-code-free, nemotron-3-ultra-free.
Plus hy3-free (present but not cost-verified).

### QEMU Guest Native Transport: BLOCKED

**Root cause:** opencode binary hangs on startup in QEMU user-mode networking.

**Evidence:**
1. `opencode version` hangs (exit 124 on timeout) even with `CI=1 NO_COLOR=1 NO_UPDATE_CHECK=1 OPENCODE_TELEMETRY=0 TERM=dumb`
2. `opencode --help` hangs (exit 124 on timeout)
3. `opencode models` hangs
4. strace shows network writes + SIGALRM (timeout) — binary tries to connect via IPv6
5. QEMU user-mode networking has no IPv6 support (IPv6 addresses unreachable)
6. curl works because it falls back to IPv4 (`curl -4` succeeds)
7. `opencode serve` cannot be tested (binary hangs before reaching serve logic)
8. `opencode run --attach` cannot be tested (binary hangs)

**Transport decision:** `UOM_OPENCODE_TRANSPORT=anonymous-api-fallback`
Record: `NATIVE_OPENCODE_RUN_BLOCKED`

### QEMU Guest Curl Wrapper: WORKING

- `~/bin/opencode-zen-free` — basic 5-model rotation
- `~/bin/opencode-zen-smart` — good/normal pools, retry, anti-exhaustion
- Both use `curl -4` (IPv4-only) to bypass QEMU IPv6 limitation
- Cost: $0 (all free models, no auth)
- Concurrency: 1 (singleton lock)

## Transport Comparison

| Property | Laptop | QEMU Guest |
|----------|--------|------------|
| Native CLI | Working | BLOCKED (IPv6 hang) |
| serve+attach | Available | Untestable (binary hang) |
| Curl wrapper | Diagnostic only | PRIMARY transport |
| PTY required | No | Yes (for native, but blocked) |
| IPv6 | Working | Broken (QEMU user-net) |
| IPv4 | Working | Working |

## Implications for Phase 10

- Guest Zen Loop MUST use curl wrapper (`anonymous-api-fallback`)
- Do NOT call the curl wrapper "the OpenCode CLI"
- Keep native OpenCode for future if IPv6 issue is resolved (e.g., QEMU config change)
- Laptop can use native OpenCode directly
- Transport path: curl → opencode.ai/zen/v1/chat/completions → free models

## Known Limitations

1. Native OpenCode blocked in QEMU guest (IPv6 hang)
2. hy3-free model present but not cost-verified (do not use until verified)
3. No opencode config file in guest (uses zen.env + curl wrappers)
4. Guest has no python3 (cannot parse JSON without jq)
5. Guest `doas` requires TTY (cannot install packages non-interactively)

## Security Notes

- All anonymous access is $0 cost, no auth headers
- Never send secrets, keys, or private data to any model
- Curl wrapper redacts prompts in normal logs
- Exponential backoff on 429/5xx (honor Retry-After)
- No rotation-to-evade quota controls
