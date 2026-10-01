#!/bin/bash
# 02-fontes.sh — clone kernel source + Clang toolchain + apply KernelSU + SUSFS
#
# What this does:
#   1. Clone (or update) LineageOS/android_kernel_samsung_universal9830 @ $BRANCH
#   2. Clone clang-${CLANG_VER} prebuilt
#   3. If ENABLE_KSU=true: apply official KernelSU kernel driver (symlink method)
#   4. If ENABLE_SUSFS=true: apply SUSFS4KSU kernel patches (kernel-4.19 branch)
#
# Environment variables:
#   KERNEL_BASE   — parent dir for src/ clang/ gcc/   (default: ~/kernel)
#   BRANCH        — kernel branch                      (default: lineage-23.2)
#   KERNEL_REF    — kernel commit/tag to pin, or 'latest' (default: pinned SHA)
#   CLANG_VER     — clang prebuilt tag                 (default: r416183b)
#   ENABLE_KSU    — apply official KernelSU driver     (default: false)
#   ENABLE_SUSFS  — apply SUSFS kernel patches         (default: false)
#   KSU_TAG       — tiann/KernelSU tag/commit to pin   (default: v0.9.5)
#   SUSFS_REF     — susfs4ksu commit/tag to pin, or 'latest' (default: pinned SHA)
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
KSU_TAG="${KSU_TAG:-v0.9.5}"
# Pinned refs for reproducible builds. Use 'latest' to follow the branch tip.
KERNEL_REF="${KERNEL_REF:-0d6cd86ea14b8ff28f9099a4c122cd7d96d71434}"
SUSFS_REF="${SUSFS_REF:-001e69919c6271f690fd00b17e4c721c9e599152}"

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

# Pin to an exact commit/tag unless 'latest' was requested.
if [ -n "$KERNEL_REF" ] && [ "$KERNEL_REF" != "latest" ]; then
    echo ">> Pinning kernel to $KERNEL_REF"
    git -C "$SRC" fetch --depth=1 origin "$KERNEL_REF"
    git -C "$SRC" checkout -f FETCH_HEAD
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

# ── 3. KernelSU kernel driver (official, classic SUSFS lineage) ───────────────
# We pin official tiann/KernelSU to v0.9.5 — the last release before upstream
# dropped non-GKI support, and the exact base simonpunk's classic SUSFS patch
# targets. SukiSU-Ultra is NOT used here: its 'builtin' branch only implements
# the modern/enchanted SUSFS ABI (SUSFS_MAGIC), incompatible with susfs4ksu
# kernel-4.19.
if [ "$ENABLE_KSU" = "true" ]; then
    echo
    echo "=== Applying KernelSU kernel driver (tiann/KernelSU @ ${KSU_TAG}) ==="

    KSU_REPO="$BASE/KernelSU"
    if [ -d "$KSU_REPO/.git" ]; then
        echo ">> KernelSU already cloned; updating ${KSU_TAG}"
        git -C "$KSU_REPO" fetch --depth=1 origin "refs/tags/${KSU_TAG}:refs/tags/${KSU_TAG}"
        git -C "$KSU_REPO" checkout -B "ksu-${KSU_TAG}" "refs/tags/${KSU_TAG}"
    else
        git clone --depth=1 --branch "${KSU_TAG}" https://github.com/tiann/KernelSU "$KSU_REPO"
    fi

    # Link driver into kernel drivers/
    DRIVER_DIR="$SRC/drivers"
    ln -sfn "$(realpath --relative-to="$DRIVER_DIR" "$KSU_REPO/kernel")" "$DRIVER_DIR/kernelsu"
    grep -q "kernelsu" "$DRIVER_DIR/Makefile" || printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> "$DRIVER_DIR/Makefile"
    grep -q "source \"drivers/kernelsu/Kconfig\"" "$DRIVER_DIR/Kconfig" || sed -i "/endmenu/i\source \"drivers/kernelsu/Kconfig\"" "$DRIVER_DIR/Kconfig"

    # Also link $SRC/KernelSU for compatibility
    [ -e "$SRC/KernelSU" ] || ln -sfn "$KSU_REPO" "$SRC/KernelSU"

    echo ">> KernelSU driver linked at $SRC/drivers/kernelsu"
else
    echo ">> ENABLE_KSU=false — skipping KernelSU integration"
fi

# ── 4. SUSFS4KSU kernel patches ───────────────────────────────────────────────
# SUSFS provides kernel-space hooks for hiding root/mounts from apps.
# Repository: https://gitlab.com/simonpunk/susfs4ksu (branch: kernel-4.19)
if [ "$ENABLE_SUSFS" = "true" ]; then
    echo
    echo "=== Applying SUSFS4KSU kernel patches (kernel-4.19) ==="

    if [ "$ENABLE_KSU" != "true" ]; then
        echo "!! SUSFS requires KernelSU (ENABLE_KSU=true) to be applied first"
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

    # Pin to an exact commit/tag unless 'latest' was requested.
    if [ -n "$SUSFS_REF" ] && [ "$SUSFS_REF" != "latest" ]; then
        echo ">> Pinning susfs4ksu to $SUSFS_REF"
        git -C "$SUSFS_REPO" fetch --depth=1 origin "$SUSFS_REF"
        git -C "$SUSFS_REPO" checkout -f FETCH_HEAD
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

    # Apply the classic SUSFS patch to the KernelSU driver.
    # This is simonpunk's 10_enable_susfs_for_ksu.patch, pre-resolved against
    # tiann/KernelSU v0.9.5 (the upstream patch has one selinux.c hunk that does
    # not apply cleanly). See patches/ for provenance.
    KSU_SUSFS_PATCH="$PROJECT_DIR/patches/10_enable_susfs_for_ksu_v0.9.5.patch"
    if [ -f "$KSU_SUSFS_PATCH" ]; then
        echo ">> Applying resolved KernelSU SUSFS patch: $KSU_SUSFS_PATCH"
        git -C "$KSU_REPO" apply "$KSU_SUSFS_PATCH" || {
            echo "!! Failed to apply $KSU_SUSFS_PATCH"
            exit 1
        }
    else
        echo "!! Resolved KernelSU SUSFS patch not found at $KSU_SUSFS_PATCH"
        exit 1
    fi

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
echo "SUSFS in fs/susfs.c  : $([ -f "$SRC/fs/susfs.c" ] && echo present || echo not applied)"
echo
du -sh "$SRC" "$CLANG" 2>/dev/null
echo
echo ">> ok"
