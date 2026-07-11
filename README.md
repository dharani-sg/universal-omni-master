# 🛰️ Universal Omni-Master

**A distribution-agnostic, self-healing Linux deployment & orchestration framework**

![Shell](https://img.shields.io/badge/shell-POSIX%20%2F%20sh-1f6feb?logo=gnubash&logoColor=white)
![BusyBox](https://img.shields.io/badge/busybox-ash--safe-3fb950)
![License](https://img.shields.io/badge/license-MIT-a371f7)
![Tests](https://img.shields.io/badge/tests-M10--A%20gate%20green-3fb950)
![Milestone](https://img.shields.io/badge/milestone-M10--A%20complete-1f6feb)
![Release](https://img.shields.io/badge/release-v0.10.0-a371f7)

> **One framework. Any distro. Any init. Any bootloader. Any GPU. Any libc.**

---

## 🎯 What is this?

**Universal Omni-Master (UOM)** is a POSIX-shell framework that detects, deploys, manages, and heals Linux systems across the entire heterogeneous ecosystem — from **musl-based Alpine** to **glibc-based Void/Arch/Debian**, from **systemd** to **runit / OpenRC / s6 / dinit**, from **GRUB** to **systemd-boot**. Born from taming a degraded dual-boot HP Pavilion (muxless AMD dGPU, failing SATA cable at UDMA_CRC baseline 5360, AC-only power), it generalizes every hard-won fix into a universal, testable abstraction — and now installs entire systems from scratch across all four distros with a single command.

---

## ✨ Core Principles

- 🐚 **POSIX-first** — `#!/bin/sh` everywhere; BusyBox ash-safe; zero bashisms (no `local`, no `**`, no arrays). Fish is confined to interactive TUIs only.
- 🧪 **Fixture-driven testing** — every detector runs against simulated sysroots (`OMNI_SYSROOT`) so 5 inits × 4 distros are validated on one machine, offline.
- 🛡️ **Mutation safety guard** — any state-changing action hard-refuses (exit 126) when running against a fixture, cleanly separating simulation from real mutation.
- 🔍 **Honest detection** — reports `unknown_state` rather than faking live daemon queries that filesystem inspection cannot answer.
- 📉 **Baseline-relative telemetry** — a stable non-zero SMART value (like UDMA_CRC = 5360) is not a failure; alerts only on Δ from `/var/lib/omni-master/baseline.<dev>`.
- 🧩 **Modular-in-source, monolithic-in-delivery** — clean per-domain modules build into a single portable self-extracting script.
- 🧬 **Cross-libc correctness** — chroot from musl → glibc target with hardcoded `.interp` (`/lib64/ld-linux-x86-64.so.2`) resolution; per-arch link name (x86_64/aarch64); efivarfs bridging for UEFI NVRAM writes.

---

## 🗺️ Roadmap

| #   | Milestone                                                    | Status                | Tests |
| :-: | ------------------------------------------------------------ | :-------------------: | :---: |
|  1  | 🔎 Hardware/software detection                               | ✅ Complete           |  31   |
|  2  | ⚙️  Init/service abstraction (systemd · OpenRC · runit · s6 · dinit) | ✅ Complete           |  16   |
|  3  | 🥾 Bootloader abstraction (GRUB · systemd-boot · Limine · EFI sim) | ✅ Complete           |  14   |
|  4  | 🎮 GPU policy engine (Intel · AMD · NVIDIA hybrid, muxless override) | ✅ Complete           |  22   |
|  5  | 💾 Storage telemetry (SMART · NVMe critical_warning · Btrfs · LUKS · cable-watch) | ✅ Complete           |   ✓   |
|  6  | 🩺 Unified diagnostics + audit (structured JSON events)      | ✅ Complete           |   ✓   |
|  7  | 🚀 Deploy/bootstrap installer (cross-libc chroot · pacstrap -K · debootstrap · rollback) | ✅ Complete           |  21   |
|  8  | 🤖 Self-healing watchdog daemon (`omni-healer` — storage · services · GPU) | ✅ Complete           |  13   |
|  9  | 🔌 Healer service integration (per-init units + enablement)  | ✅ Complete           |  40   |
| 10  | 📸 Btrfs snapshot lifecycle (`omni-snapshot` create/list/prune/hooks) | ✅ Complete (**v0.10.0**) |  20   |
| 11  | ⏪ Atomic rollback + bootloader boot-to-snapshot entries      | 🚧 Next               |   —   |
| 12  | 🖥️ Fish TUI frontend (interactive control plane)              | 📋 Planned            |   —   |

**Scoping note:** M10 dual-track (“lifecycle **or** TUI”) is closed as **M10-A lifecycle only**. Atomic restore is **not** M10-B — it spans M3 bootloaders + M10-A snaps + new restore semantics, so it ships as **M11**. Fish TUI moves to **M12**.

### M11 scope (next)

Atomic rollback with bootloader entry generation for **boot-to-snapshot**:

| Phase | Deliverable | Builds on |
| ----- | ----------- | --------- |
| **M11-A** | Boot entry generation for selected snapshots (systemd-boot BLS + GRUB menuentry) | M3 `omni-boot`, M10-A `snap_list_*` |
| **M11-B** | Live atomic restore (RO snap → RW `@` swap or `btrfs send/receive` path; pre-restore safety snap) | M10-A engine, M7 `rollback.sh` is *install-time only* — do not overload it |
| **M11-C** | One-shot “boot this snapshot once” (EFI LoaderEntryOneShot / GRUB `saved_entry` + next-boot clear) | M3 EFI helpers, M11-A |
| **M11-D** | Deploy wiring + fixture gate (`test-m11-rollback.sh`) | M7 deploy, mutation guard |

**Out of M11:** Fish TUI (M12), Limine-first polish (guidance only until requested), non-Btrfs restore (graceful skip, same R5 policy as M10-A).

**CLI surface (planned):** extend `omni-snapshot` with `boot-entry`, `rollback`, `boot-once` — keep `omni-boot` as the low-level backend (entry write/verify), not a second UX.

See detailed work breakdown in the M11 section of the project notes / commit that lands `src/snapshot/boot_entry.sh` + `src/snapshot/restore.sh`.

---

## 🛠️ Tooling

| Command             | Role                                                           |
| ------------------- | -------------------------------------------------------------- |
| `omni-detect`       | Hardware/software discovery (M1)                               |
| `omni-service`      | Init-agnostic service control across 5 backends (M2)           |
| `omni-boot`         | Bootloader inspect/install/repair (M3)                         |
| `omni-gpu`          | GPU policy + hybrid switching + muxless dGPU override (M4)     |
| `omni-storage`      | SMART / NVMe / Btrfs scrub / cable-watch policy engine (M5)    |
| `omni-audit`        | Unified structured event log (JSON) (M6)                       |
| `omni-deploy`       | Full-disk install: partition → bootstrap → chroot → boot (M7)  |
| `omni-healer`       | Parallel self-healing watchdog daemon (M8-M9)                  |
| `omni-snapshot`     | Btrfs snapshot lifecycle: create/list/prune/sweep/periodic (M10-A) |

Each command is a thin CLI over a swappable backend layer, auto-selecting the correct implementation from runtime discovery.

---

## 🧬 Validated Against

🏔️  **Alpine** (musl · OpenRC · apk · doas) · 🌀 **Void** (glibc · runit · xbps) · 🏹 **Arch** (systemd · pacman) · 🌀 **Debian** (systemd · apt · debootstrap) · 📦 **BusyBox-minimal** · 🌿 **Chimera** (dinit)

---

## 🚦 Quick Start

```sh
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master

# Detect this system
./bin/omni-detect

# Deploy a fresh system (dry-run by default — no changes made)
./bin/omni-deploy install --distro alpine --disk sda --fs btrfs

# Run the full-stack gate (M1–M10-A)
./scripts/compat-check.sh
./scripts/test-deploy.sh
./scripts/test-healer.sh
./scripts/test-m9-healer-install.sh
./scripts/test-m10-snapshot.sh
