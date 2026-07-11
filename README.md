# 🛰️ Universal Omni-Master

**A distribution-agnostic, self-healing Linux deployment & orchestration framework**

![Shell](https://img.shields.io/badge/shell-POSIX%20%2F%20sh-1f6feb?logo=gnubash&logoColor=white)
![BusyBox](https://img.shields.io/badge/busybox-ash--safe-3fb950)
![License](https://img.shields.io/badge/license-MIT-a371f7)
![Tests](https://img.shields.io/badge/tests-111%2F111%20green-3fb950)
![Milestone](https://img.shields.io/badge/milestone-M9%20complete-1f6feb)
![Release](https://img.shields.io/badge/release-v0.9.0-a371f7)

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
| 10  | 📸 Btrfs snapshot lifecycle **or** 🖥️ Fish TUI frontend         | 🚧 In progress        |   —   |

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

# Run the full-stack gate (111 tests across 5 milestones)
./scripts/compat-check.sh
./scripts/test-deploy.sh
./scripts/test-healer.sh
./scripts/test-m9-healer-install.sh
