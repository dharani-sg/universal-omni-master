<div align="center">

# 🛰️ Universal Omni-Master

### A distribution-agnostic, self-healing Linux deployment & orchestration framework

[![Shell](https://img.shields.io/badge/POSIX-sh-4EAA25?logo=gnubash&logoColor=white)](https://pubs.opengroup.org/onlinepubs/9699919799/)
[![BusyBox](https://img.shields.io/badge/BusyBox-ash%20safe-0A7BBB)](https://busybox.net/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-83%20passing-brightgreen)](scripts/)
[![Milestone](https://img.shields.io/badge/milestone-4%2F10-orange)](#roadmap)

*One framework. Any distro. Any init. Any bootloader. Any GPU.*

</div>

---

## 🎯 What is this?

**Universal Omni-Master (UOM)** is a POSIX-shell framework that detects, manages, and heals Linux systems across the entire heterogeneous ecosystem — from musl-based Alpine to glibc-based Void, from systemd to runit/OpenRC/s6/dinit, from GRUB to systemd-boot. Born from taming a degraded dual-boot HP Pavilion (muxless AMD dGPU, failing SATA cable, AC-only power), it generalizes every hard-won fix into a universal, testable abstraction.

## ✨ Core Principles

- 🐚 **POSIX-first** — `#!/bin/sh` everywhere; BusyBox `ash`-safe; zero bashisms. Fish is confined to interactive TUIs only.
- 🧪 **Fixture-driven testing** — every detector runs against simulated sysroots (`OMNI_SYSROOT`) so 5 distros are validated on one machine, offline.
- 🛡️ **Mutation safety guard** — any state-changing action hard-refuses (`exit 126`) when running against a fixture, cleanly separating simulation from real mutation.
- 🔍 **Honest detection** — reports `unknown_state` rather than faking live daemon queries filesystem inspection cannot answer.
- 🧩 **Modular-in-source, monolithic-in-delivery** — clean per-domain modules build into a single portable self-extracting script.

## 🗺️ Roadmap

| # | Milestone | Status |
|---|-----------|--------|
| 1 | 🔎 Hardware/software detection | ✅ Complete (31 tests) |
| 2 | ⚙️ Init/service abstraction (systemd·OpenRC·runit·s6·dinit) | ✅ Complete (16 tests) |
| 3 | 🥾 Bootloader abstraction (GRUB·systemd-boot·+EFI sim) | ✅ Complete (14 tests) |
| 4 | 🎮 GPU policy engine (Intel·AMD·NVIDIA hybrid) | ✅ Complete (22 tests) |
| 5 | 💾 Storage telemetry (SMART·Btrfs·LUKS·cable-watch) | 🔜 Planned |
| 6 | 🩺 Unified diagnostics | 🔜 Planned |
| 7 | 🚀 Deploy/bootstrap installer | 🔜 Planned |
| 8 | 🤖 Self-healing daemon | 🔜 Planned |
| 9 | 🔌 Plugin ecosystem | 🔜 Planned |
| 10 | 📦 Universal monolith bundler | 🔜 Planned |

## 🛠️ Tooling

`omni-detect` · `omni-service` · `omni-boot` · `omni-gpu` — each a thin CLI over a swappable backend layer, auto-selecting the correct implementation from runtime discovery.

## 🧬 Validated Against

🏔️ Alpine (musl·OpenRC·apk·doas) · 🌀 Void (glibc·runit·xbps) · 🏹 Arch (systemd·pacman) · 🌀 Debian (systemd·apt) · 📦 BusyBox-minimal

## 🚦 Quick Start

```sh
git clone https://github.com/dharani-sg/universal-omni-master.git
cd universal-omni-master
./bin/omni-detect              # discover this system
./scripts/compat-check.sh      # run the full compatibility matrix
