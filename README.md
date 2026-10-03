# Kernel for r8s with built-in KernelSU and SUSFS

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
| `kernel_ref` | *(empty)* | Kernel commit/tag to pin. Empty = pinned default, `latest` = branch tip |
| `clang` | `r416183b` | Clang prebuilt version (from `BoardConfigCommon.mk`) |
| `extra_config` | *(empty)* | Optional fragment: e.g. `config/docker-kernel.config`. **Docker is OFF by default** |
| `enable_ksu` | `true` | Build with KernelSU (official `tiann/KernelSU` driver) |
| `enable_susfs` | `true` | Apply classic SUSFS patches (hide root). Requires `enable_ksu=true` |
| `ksu_tag` | `v0.9.5` | `tiann/KernelSU` tag to pin — `v0.9.5` matches the classic SUSFS patch |
| `susfs_ref` | *(empty)* | susfs4ksu commit/tag to pin. Empty = pinned default, `latest` = branch tip |
| `boot_img_url` | `https://mirrorbits.lineageos.org/full/r8s/20260928/boot.img` | Stock boot.img URL (pinned 20260928 build). Set to `none`/empty to disable repacking |
| `release` | `true` | Also publish as a GitHub Release |

4. Wait ~15–20 min. Download the **Image** artifact from the run.

> **Reproducibility:** the kernel and SUSFS sources are **pinned to exact commits**
> by default (defined in `build/02-fontes.sh`). Set `kernel_ref` / `susfs_ref` to
> `latest` to follow the branch tips instead. If you provide a `boot_img_url`, the
> workflow also repacks a flashable `boot-new.img` (using the vendored
> `toolchain/magiskboot`) and attaches it to the artifact.

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
config/ksu.config           ← merged automatically when enable_ksu=true (KernelSU + SUSFS)
[extra_config]              ← optional fragment (docker-kernel.config)
```

The build script validates **each merge step** and aborts if any required option was silently dropped by `olddefconfig`.

---

## Build validation gates

The build script runs three gates and **aborts** if any fails:

| Gate | What it checks |
|---|---|
| **Gate 1** | `CONFIG_LTO_CLANG=y` survived `olddefconfig` |
| **Gate 2** | Key r8s options present: `MODEL_R8S`, `QCA_CLD_WLAN`, `MHI_BUS`, `TOUCHSCREEN_STM_FTS5CU56A`, `CAMERA_RST_V08` |
| **Gate 2b** | (when `enable_ksu=true`) `CONFIG_KSU`, `CONFIG_KALLSYMS(_ALL)`, and `CONFIG_KSU_SUSFS` (when `enable_susfs=true`) |
| **Gate 3** | Image size ≤ 44 MB (larger = LTO missing = will not boot) |

After the build, the workflow also reads the config **from inside the Image binary** (via `extract-ikconfig`) and verifies all options one more time.

---

## KernelSU + SUSFS (optional)

Enable via the workflow inputs `enable_ksu` and `enable_susfs`.

- **KernelSU:** official `tiann/KernelSU` pinned to **`v0.9.5`** — the last release before
  upstream dropped non-GKI support. Uses **manual (non-kprobe) hooks** — `CONFIG_KPROBES` is
  left OFF because Samsung's TZASC hardware blocks kprobes' runtime text-patching and panics.
- **SUSFS:** classic `simonpunk/susfs4ksu` `kernel-4.19` ABI (`SUSFS_VERSION "v1.5.5"`).

> **Why not SukiSU-Ultra?** Its `builtin` branch implements the *modern/enchanted* SUSFS ABI
> (`SUSFS_MAGIC`, `void __user **`, `AS_FLAGS_*` on `i_mapping->flags`), which is incompatible
> with the classic susfs4ksu `kernel-4.19` headers. Mixing the two produced the
> `SUSFS_MAGIC` / `CMD_SUSFS_ADD_SUS_MAP` compile errors. This repo uses the classic lineage
> for stability; the modern lineage can be revisited as a later phase.

Patch flow (`build/02-fontes.sh`):

1. Symlink the `tiann/KernelSU@v0.9.5` driver into `drivers/kernelsu`.
2. Apply `patches/60_ksu_manual_hooks_exynos990.patch` — official KernelSU non-GKI manual hooks
   (`exec`/`open`/`read_write`/`stat`/`devpts`/`input`), for the non-kprobe path.
3. Apply `patches/10_enable_susfs_for_ksu_v0.9.5.patch` — simonpunk's classic SUSFS patch,
   pre-resolved against v0.9.5.
4. Apply `patches/11_ksu_try_umount_path_leak.patch` — fixes a `struct path` reference leak in
   KernelSU v0.9.5's `ksu_try_umount()` (upstream bug: 5 leaked references per app launch).
5. Copy `susfs4ksu` `fs/*` + `include/linux/*` into the kernel tree.
6. Apply `patches/50_add_susfs_in_kernel-4.19-exynos990.patch` — tailored Samsung Exynos 990 hooks.

---

## Repacking & flashing (all on Linux)

The build emits a raw ARM64 `Image`. To make a flashable `boot.img`, swap that
kernel into your stock boot image **on the host** — no Magisk on the phone, no
on-device repacking:

> CI does this automatically by default — the `boot_img_url` input is pre-filled
> with the pinned 20260928 LineageOS `boot.img`, so every run also attaches a
> ready `boot-new.img`. Set it to `none` (or empty) to skip repacking.

```bash
# 1. Pull the stock boot.img from the ROM you are currently running
#    (get it from the LineageOS zip, or extract it off the device with root)
adb shell su -c 'dd if=/dev/block/by-name/boot of=/sdcard/boot-original.img bs=4096'
adb pull /sdcard/boot-original.img .

# 2. Rebuild boot.img on the PC (uses /usr/bin/magiskboot)
./flash/repack-boot.sh boot-original.img out/Image out/boot-new.img
```

`repack-boot.sh` preserves the original header (base/offsets/cmdline), ramdisk
and DTB, and only replaces the kernel payload — which is exactly what this
device's bootloader expects (it jumps directly into the raw `Image`).

Then flash `out/boot-new.img` one of two ways:

```bash
# A. Rooted recovery (dd)
adb push out/boot-new.img /sdcard/boot-new.img
adb shell su -c 'dd if=/sdcard/boot-new.img of=/dev/block/by-name/boot bs=4096 && sync'
adb reboot

# B. Download mode + Heimdall (Linux, no root needed)
heimdall flash --BOOT out/boot-new.img
```

> **Notes:** use the `boot.img` from the *same* ROM build you're running, and
> keep `boot-original.img` safe — you need it to recover. Repacking invalidates
> the AVB signature, but an unlocked Samsung Exynos bootloader does not enforce
> it (validated on real Exynos 990 hardware by the upstream project).
>
> **`dtbo.img` is not needed** — only the `kernel` inside `boot.img` is swapped,
> so just flash `boot.img`.

### Recovery

If the device doesn't boot, restore the original boot image:

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
  ksu.config                KernelSU + classic SUSFS options (merged when enable_ksu=true)

patches/
  10_enable_susfs_for_ksu_v0.9.5.patch  Classic SUSFS patch, resolved against KernelSU v0.9.5
  11_ksu_try_umount_path_leak.patch  ksu_try_umount() struct path refcount leak fix (upstream v0.9.5)
  50_add_susfs_in_kernel-4.19-exynos990.patch  Tailored Samsung Exynos 990 SUSFS hooks
  60_ksu_manual_hooks_exynos990.patch  KernelSU non-kprobe manual hooks (exec/open/read_write/stat/devpts/input)

toolchain/
  magiskboot                Vendored static magiskboot (used for CI repack)

flash/
  docker-check.sh           Audit running kernel against Docker requirements
  repack-boot.sh            Rebuild boot.img on the HOST (magiskboot) — the recommended flow
  kernel-swap.sh            (legacy) On-device boot.img repack via Magisk's magiskboot
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
