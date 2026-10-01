#!/bin/bash
# 02-fontes.sh — clone kernel source + Clang toolchain + apply SukiSU-Ultra + SUSFS
#
# What this does:
#   1. Clone (or update) LineageOS/android_kernel_samsung_universal9830 @ $BRANCH
#   2. Clone clang-${CLANG_VER} prebuilt
#   3. If ENABLE_KSU=true: apply SukiSU-Ultra kernel driver (setup.sh symlink method)
#   4. If ENABLE_SUSFS=true: apply SUSFS4KSU kernel patches (kernel-4.19 branch)
#
# Environment variables:
#   KERNEL_BASE   — parent dir for src/ clang/ gcc/   (default: ~/kernel)
#   BRANCH        — kernel branch                      (default: lineage-23.2)
#   CLANG_VER     — clang prebuilt tag                 (default: r416183b)
#   ENABLE_KSU    — apply SukiSU-Ultra driver          (default: false)
#   ENABLE_SUSFS  — apply SUSFS kernel patches         (default: false)
#   KSU_TAG       — SukiSU-Ultra tag/commit to pin     (default: latest tag)
#
# NOTE: The kernel repo on LineageOS already contains r8s.config with ALL
# device-specific options. This script only sets up the source tree.
# Config merging is done in 04-build.sh.

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
set -e

BASE="${KERNEL_BASE:-$HOME/kernel}"
SRC="$BASE/src"
CLANG="$BASE/clang"
BRANCH="${BRANCH:-lineage-23.2}"
CLANG_VER="${CLANG_VER:-r416183b}"
ENABLE_KSU="${ENABLE_KSU:-false}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
KSU_TAG="${KSU_TAG:-}"

mkdir -p "$BASE"

# ── 1. Kernel source ──────────────────────────────────────────────────────────
if [ -d "$SRC/.git" ]; then
    echo ">> Kernel already cloned; syncing branch $BRANCH"
    git -C "$SRC" fetch --depth=1 origin "$BRANCH"
    git -C "$SRC" checkout -B "$BRANCH" "origin/$BRANCH"
else
    echo "=== Cloning kernel (LineageOS android_kernel_samsung_universal9830 @ $BRANCH) ==="
    git clone --depth=1 -b "$BRANCH" \
        https://github.com/LineageOS/android_kernel_samsung_universal9830 "$SRC"
fi

# ── 2. Clang toolchain ────────────────────────────────────────────────────────
if [ -x "$CLANG/bin/clang" ]; then
    echo ">> Clang already present at $CLANG"
else
    echo "=== Cloning clang-${CLANG_VER} ==="
    git clone --depth=1 \
        "https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-${CLANG_VER}" \
        "$CLANG"
fi

# ── 3. SukiSU-Ultra kernel driver ─────────────────────────────────────────────
# We checkout the official 'builtin' branch of SukiSU-Ultra for non-GKI / Linux 4.19.
# It provides native in-tree compilation and built-in SUSFS inline hooks detection.
if [ "$ENABLE_KSU" = "true" ]; then
    echo
    echo "=== Applying SukiSU-Ultra kernel driver (builtin branch) ==="

    KSU_REPO="$BASE/KernelSU"
    if [ -d "$KSU_REPO/.git" ]; then
        echo ">> SukiSU-Ultra already cloned; updating builtin branch"
        git -C "$KSU_REPO" fetch --depth=1 origin builtin
        git -C "$KSU_REPO" checkout -B builtin origin/builtin
    else
        git clone --depth=1 -b builtin https://github.com/SukiSU-Ultra/SukiSU-Ultra "$KSU_REPO"
    fi

    # If a specific commit or branch was requested, checkout that
    if [ -n "$KSU_TAG" ]; then
        echo ">> Checking out requested KSU ref: $KSU_TAG"
        git -C "$KSU_REPO" checkout "$KSU_TAG"
    fi

    # Link driver into kernel drivers/
    DRIVER_DIR="$SRC/drivers"
    ln -sfn "$(realpath --relative-to="$DRIVER_DIR" "$KSU_REPO/kernel")" "$DRIVER_DIR/kernelsu"
    grep -q "kernelsu" "$DRIVER_DIR/Makefile" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_DIR/Makefile"
    grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_DIR/Kconfig" || sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_DIR/Kconfig"

    # Also link $SRC/KernelSU for compatibility
    [ -e "$SRC/KernelSU" ] || ln -sfn "$KSU_REPO" "$SRC/KernelSU"

    echo ">> SukiSU-Ultra driver linked at $SRC/drivers/kernelsu"
else
    echo ">> ENABLE_KSU=false — skipping SukiSU-Ultra integration"
fi

# ── 4. SUSFS4KSU kernel patches ───────────────────────────────────────────────
# SUSFS provides kernel-space hooks for hiding root/mounts from apps.
# Repository: https://gitlab.com/simonpunk/susfs4ksu (branch: kernel-4.19)
if [ "$ENABLE_SUSFS" = "true" ]; then
    echo
    echo "=== Applying SUSFS4KSU kernel patches (kernel-4.19) ==="

    if [ "$ENABLE_KSU" != "true" ]; then
        echo "!! SUSFS requires SukiSU-Ultra (ENABLE_KSU=true) to be applied first"
        exit 1
    fi

    SUSFS_REPO="$BASE/susfs4ksu"
    if [ -d "$SUSFS_REPO/.git" ]; then
        echo ">> susfs4ksu already cloned; updating"
        git -C "$SUSFS_REPO" fetch --depth=1 origin kernel-4.19
        git -C "$SUSFS_REPO" checkout -B kernel-4.19 origin/kernel-4.19
    else
        git clone --depth=1 -b kernel-4.19 \
            https://gitlab.com/simonpunk/susfs4ksu.git "$SUSFS_REPO"
    fi

    # Copy SUSFS fs and include files provided by SUSFS
    if [ -d "$SUSFS_REPO/kernel_patches/fs" ]; then
        echo ">> Copying SUSFS fs files..."
        cp -rv "$SUSFS_REPO/kernel_patches/fs/"* "$SRC/fs/"
    fi
    if [ -d "$SUSFS_REPO/kernel_patches/include/linux" ]; then
        echo ">> Copying SUSFS include files..."
        cp -rv "$SUSFS_REPO/kernel_patches/include/linux/"* "$SRC/include/linux/"
    fi

    # SukiSU-Ultra's 'builtin' branch already contains native SUSFS inline hook support.
    # Therefore, 10_enable_susfs_for_ksu.patch is NOT needed (and incompatible).

    # Apply tailored Samsung Exynos 990 / universal9830 SUSFS patch
    SAMSUNG_SUSFS_PATCH="$PROJECT_DIR/patches/50_add_susfs_in_kernel-4.19-exynos990.patch"
    if [ -f "$SAMSUNG_SUSFS_PATCH" ]; then
        echo ">> Applying tailored Samsung Exynos 990 SUSFS patch: $SAMSUNG_SUSFS_PATCH"
        patch -d "$SRC" -p1 -N --forward < "$SAMSUNG_SUSFS_PATCH" || {
            echo "!! Failed to apply $SAMSUNG_SUSFS_PATCH"
            exit 1
        }
    else
        echo "!! Tailored SUSFS patch not found at $SAMSUNG_SUSFS_PATCH"
        exit 1
    fi

    echo ">> SUSFS patches applied successfully"
else
    echo ">> ENABLE_SUSFS=false — skipping SUSFS patches"
fi

# ── Sanity check ──────────────────────────────────────────────────────────────
echo
echo "=== Source check ==="
echo "Kernel version   : $(grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' "$SRC/Makefile" | tr -d ' ' | tr '\n' ' ')"
echo "Branch           : $(git -C "$SRC" rev-parse --abbrev-ref HEAD)"
echo "Commit           : $(git -C "$SRC" rev-parse --short=12 HEAD)"
echo "Clang            : $("$CLANG/bin/clang" --version 2>/dev/null | head -1)"
echo
echo "exynos9830_defconfig : $([ -f "$SRC/arch/arm64/configs/exynos9830_defconfig" ] && echo present || echo MISSING)"
echo "r8s.config           : $([ -f "$SRC/arch/arm64/configs/r8s.config" ] && echo present || echo MISSING)"
echo "KSU driver           : $([ -L "$SRC/drivers/kernelsu" ] && echo "linked ($(readlink "$SRC/drivers/kernelsu"))" || echo not applied)"
echo "SUSFS in fs/susfs    : $([ -d "$SRC/fs/susfs" ] && echo present || echo not applied)"
echo
du -sh "$SRC" "$CLANG" 2>/dev/null
echo
echo ">> ok"
