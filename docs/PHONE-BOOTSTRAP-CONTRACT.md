# Phone Bootstrap Contract — 2026-07-19

Defines the supported interface for UOM Termux/Android phone installation.

---

## 1. Modes

### A. `--check` (default, read-only preflight)

Run without arguments or with `--check`.

Requirements:
- No package installation or update
- No repository clone or pull
- No SSH key creation
- No SSH config change
- No Termux:Boot writes
- No service start
- No persistent cache/config creation
- No execution of OpenCode that could initialize a user profile
- Exit 0 when environment is compatible enough to proceed
- Nonzero exit with documented code when incompatible

### B. `--apply` (install)

Makes all changes required for the selected profile.

### C. `--apply --verify` (install and validate)

Runs `--apply` then immediately runs post-install validation.

### D. `--verify` (standalone validation)

Post-install check only. Reports component status.

### E. `--apply --verify --test-root PATH`

All writes directed under PATH. Package installation disabled or shimmed.

---

## 2. Profiles

### `--profile phone-relay` (default)

Installs phone as:
- Termux SSH endpoint (sshd on port 8022)
- tmux workspace
- Git checkout of UOM repository
- Sync/relay/orchestration node
- Optional reverse tunnel node

Must NOT require local OpenCode binary.

### `--profile phone-agent`

Requires functional local or PRoot OpenCode.

Rules:
- Existing functional OpenCode may be used
- Do not blindly install standard Linux aarch64 binary into Termux
- PRoot fallback requires `--allow-proot-opencode`
- Third-party binaries require `--allow-third-party-opencode` + checksum
- If phone-agent cannot be supported, fail clearly while leaving
  phone-relay usable

---

## 3. Mandatory Overrides

| Flag | Description | Default |
|------|-------------|---------|
| `--ref REF` | Pinned commit or tag | `main` |
| `--repo-url URL` | Repository URL | `https://github.com/dharani-sg/universal-omni-master.git` |
| `--install-dir PATH` | Installation directory | `$HOME/src/universal-omni-master` |
| `--test-root PATH` | Isolated install root | (none) |
| `--profile NAME` | Install profile | `phone-relay` |
| `--check` | Read-only preflight | default |
| `--apply` | Make changes | — |
| `--verify` | Validate install | — |
| `--no-start` | Do not start services | — |
| `--skip-packages` | Skip package installation | — |
| `--non-interactive` | Non-interactive mode | — |
| `--resume` | Resume interrupted install | — |
| `--rollback` | Rollback installer-owned changes | — |
| `--help` | Show usage | — |

Environment equivalents (CLI takes precedence):
- `UOM_REF`, `UOM_REPO_URL`, `UOM_INSTALL_DIR`, `UOM_TEST_ROOT`, `UOM_PROFILE`

---

## 4. Supported Android Matrix

| Requirement | Status |
|---|---|
| Android 13 / SDK 33 | Required, tested |
| Android 14 / SDK 34 | Required, tested |
| Android 15 / SDK 35 | Required, tested |
| Android 16 / SDK 36 | Required, tested |
| aarch64 native Termux | Required |
| x86_64 | Unsupported — fail early |
| armv7/arm | Unsupported — fail early |

Unsupported architectures must fail early with actionable output.

---

## 5. Installation States

| State | Meaning |
|---|---|
| `CHECK_PASS` | Environment compatible |
| `CHECK_FAIL` | Environment incompatible |
| `INSTALL_PASS` | Installation completed |
| `INSTALL_PARTIAL` | Partial install — manual intervention needed |
| `VERIFY_PASS` | All components validated |
| `VERIFY_FAIL` | Validation found issues |
| `READY_PHONE_RELAY` | Phone relay profile fully configured |
| `READY_PHONE_AGENT` | Phone agent profile fully configured |
| `NEEDS_LAPTOP_PAIRING` | SSH key must be added to laptop |
| `NEEDS_TERMUX_BOOT_ACTIVATION` | User must install/launch Termux:Boot plugin |
| `NEEDS_BATTERY_CONFIGURATION` | User must disable battery optimization |
| `UNSUPPORTED_ARCH` | Architecture not supported |
| `UNSUPPORTED_TERMUX_SOURCE` | Termux not from official source |
| `ROLLED_BACK` | Changes rolled back |

Do not print "fully ready" if pairing, Termux:Boot activation, OpenCode auth,
or Android settings remain manual.

---

## 6. Safe One-Line Command

```sh
curl -fsSL https://raw.githubusercontent.com/dharani-sg/universal-omni-master/<SHA>/install/bootstrap.sh -o /tmp/uom-install.sh && sh /tmp/uom-install.sh --apply --verify --profile phone-relay && rm -f /tmp/uom-install.sh
```

Sequence:
1. Create safe temporary file
2. Download with failure propagation
3. Validate shebang and syntax
4. Execute with `--apply --verify --profile phone-relay`
5. Remove temporary file
6. Return actual exit status
