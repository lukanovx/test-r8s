# r8s-docker-kernel

Kernel build pipeline for the **Samsung Galaxy S20 FE** (Exynos 990, SM-G780F, codename **r8s**) running LineageOS.

This is a **thin orchestration repo** — it does NOT contain the kernel source. It fetches:
- `LineageOS/android_kernel_samsung_universal9830` (depth=1) at build time
- `clang-r416183b` prebuilt toolchain
- `aarch64-linux-android-4.9` AOSP binutils

Adapted from [exynos990-docker-kernel](https://github.com/Emerichek/exynos990-docker-kernel) — validated on real Exynos 990 hardware (SM-G985F/y2s, LineageOS 23.2).

---

## Quick start — GitHub Actions

1. **Fork** (or push) this repo to your GitHub account.
2. Go to **Actions → Build kernel (r8s) → Run workflow**.
3. Use the defaults (or customize):

| Input | Default | Notes |
|---|---|---|
| `branch` | `lineage-23.2` | Must match the LineageOS branch on your phone |
| `clang` | `r416183b` | Clang prebuilt version (from `BoardConfigCommon.mk`) |
| `extra_config` | *(empty)* | Optional fragment: e.g. `config/docker-kernel.config` |
| `release` | `false` | Also publish as a GitHub Release |

4. Wait ~15–20 min. Download the **Image** artifact from the run.

---

## Why this compiles with `LLVM=1 LLVM_IAS=1`

> **TL;DR:** Without `LLVM_IAS=1` the kernel boots to `Starting kernel...` and then freezes — silently, no panic, no pstore record.

`LLVM_IAS=1` tells the build to use **clang's integrated assembler** instead of GNU `as`. Kernels built with GNU `as` (as the LineageOS docs suggest, with only `CC=clang LD=ld.lld`) load but do not execute on this bootloader. This was isolated after four discarded builds in the upstream project. The full investigation is in the upstream [`research/`](https://github.com/Emerichek/exynos990-docker-kernel/tree/main/research).

`LLVM=1` also ensures `ld.lld` is the linker, which is required for `CONFIG_LTO_CLANG`. Without LTO the image grows ~3.4 MB — which also causes a non-boot.

---

## Config merge order

```
exynos9830_defconfig        ← base for all Exynos 990 devices
r8s.config                  ← r8s hardware (QCA WiFi/BT, MHI modem, cameras, display, sensors…)
[extra_config]              ← optional fragment (docker-kernel.config, KSU patch, etc.)
```

The build script validates **each merge step** and aborts if any required option was silently dropped by `olddefconfig`.

---

## Build validation gates

The build script runs three gates and **aborts** if any fails:

| Gate | What it checks |
|---|---|
| **Gate 1** | `CONFIG_LTO_CLANG=y` survived `olddefconfig` |
| **Gate 2** | Key r8s options present: `MODEL_R8S`, `QCA_CLD_WLAN`, `MHI_BUS`, `TOUCHSCREEN_STM_FTS5CU56A`, `CAMERA_RST_V08` |
| **Gate 3** | Image size ≤ 44 MB (larger = LTO missing = will not boot) |

After the build, the workflow also reads the config **from inside the Image binary** (via `extract-ikconfig`) and verifies all options one more time.

---

## Flashing

Requirements: unlocked bootloader, Magisk installed, `adb` on your PC.

```bash
# 1. Push new kernel
adb push out/Image /data/local/tmp/Image

# 2. Push flash helpers
adb push flash/kernel-swap.sh flash/verify-patched.sh /sdcard/Download/
adb shell su -c 'cp /sdcard/Download/*.sh /data/local/tmp/ && chmod 755 /data/local/tmp/*.sh'

# 3. Swap kernel inside existing boot.img (does NOT write to partition yet)
adb shell su -c 'sh /data/local/tmp/kernel-swap.sh'

# 4. Pull the backup — DO NOT SKIP THIS
adb pull /sdcard/Download/boot-original.img .

# 5. (Optional but recommended) Patch through the Magisk app to keep root
#    Magisk app → Install → Select and patch a file → boot-novo.img

# 6. Flash
adb shell su -c 'dd if=/data/local/tmp/boot-novo.img of=/dev/block/by-name/boot bs=4096'
adb shell su -c sync
adb reboot
```

### Recovery

If the device doesn't boot, use your PC backup:

```bash
# Enter recovery: Power+VolDown ~10s → release → VolUp+Power with USB connected
# In recovery: Advanced → Enable ADB
adb push boot-original.img /tmp/boot.img
adb shell dd if=/tmp/boot.img of=/dev/block/by-name/boot bs=4096
adb reboot
```

---

## Check if you need this

Run this on the device to audit the running kernel against Docker requirements:

```bash
adb push flash/docker-check.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/docker-check.sh'
```

---

## Repository structure

```
.github/workflows/
  build-kernel.yml          GitHub Actions pipeline (manual trigger, ~15 min)

build/
  01-deps.sh                Install Ubuntu build dependencies
  02-fontes.sh              Clone kernel source + Clang (depth=1, into ~/kernel/)
  03-gcc.sh                 Clone AOSP aarch64 binutils (into ~/kernel/gcc/)
  04-build.sh               Build with LLVM=1 LLVM_IAS=1 + 3 validation gates

config/
  docker-kernel.config      Enable Docker: namespaces, bridge, netfilter, cgroups
  docker-minimal.config     Minimal Docker (required options only)

flash/
  docker-check.sh           Audit running kernel against Docker requirements
  kernel-swap.sh            Swap kernel inside boot.img using magiskboot
  verify-patched.sh         Verify image integrity before flashing
  flash-kernel.sh           Flash with readback verification
  repack-test.sh            Test magiskboot idempotency
```

---

## Supported devices (upstream kernel tree)

This pipeline targets **r8s**. The kernel source supports all Exynos 990 devices:

| Codename | Device |
|---|---|
| `x1s` / `x1slte` | Galaxy S20 / S20 5G |
| `y2s` / `y2slte` | Galaxy S20+ / S20+ 5G |
| `z3s` | Galaxy S20 Ultra |
| `c1s` / `c1slte` | Galaxy Note 20 |
| `c2s` / `c2slte` | Galaxy Note 20 Ultra |
| `r8s` ✓ | **Galaxy S20 FE (SM-G780F)** |

---

## License

Scripts: MIT.
Config fragments are derived from the LineageOS kernel defconfig (GPLv2 — as all Linux kernel code).
