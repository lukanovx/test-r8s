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
# The setup.sh approach: creates a symlink at drivers/kernelsu → KernelSU/kernel/
# and patches drivers/Makefile + drivers/Kconfig to include it.
# This is a non-intrusive integration — does NOT modify any existing kernel file.
if [ "$ENABLE_KSU" = "true" ]; then
    echo
    echo "=== Applying SukiSU-Ultra kernel driver ==="

    KSU_REPO="$BASE/KernelSU"
    if [ -d "$KSU_REPO/.git" ]; then
        echo ">> SukiSU-Ultra already cloned; updating"
        git -C "$KSU_REPO" fetch --depth=1 origin main
        git -C "$KSU_REPO" checkout -B main origin/main
    else
        git clone --depth=1 https://github.com/SukiSU-Ultra/SukiSU-Ultra "$KSU_REPO"
    fi

    # If a specific tag/commit was requested, check it out
    if [ -n "$KSU_TAG" ]; then
        echo ">> Pinning SukiSU-Ultra to $KSU_TAG"
        git -C "$KSU_REPO" fetch --depth=1 origin "$KSU_TAG" 2>/dev/null || true
        git -C "$KSU_REPO" checkout "$KSU_TAG"
    else
        # Checkout latest tagged release
        LATEST_TAG=$(git -C "$KSU_REPO" describe --abbrev=0 --tags 2>/dev/null || echo "")
        if [ -n "$LATEST_TAG" ]; then
            git -C "$KSU_REPO" checkout "$LATEST_TAG"
            echo ">> Checked out latest tag: $LATEST_TAG"
        fi
    fi

    # Run the official setup.sh from inside the kernel source root
    # It detects drivers/ automatically and creates the symlink
    (
        cd "$SRC"
        sh "$KSU_REPO/kernel/setup.sh"
    )
    echo ">> SukiSU-Ultra driver linked at $SRC/drivers/kernelsu"
else
    echo ">> ENABLE_KSU=false — skipping SukiSU-Ultra integration"
fi

# ── 4. SUSFS4KSU kernel patches ───────────────────────────────────────────────
# SUSFS provides kernel-space hooks for hiding root/mounts from apps.
# It requires kernel-side patches applied via git apply.
# Official patch repo: https://gitlab.com/simonpunk/susfs4ksu (branch: kernel-4.19)
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

    # Apply the two required patch files to the kernel source
    # 1. The KSU-side patch (adds SUSFS support to the KernelSU driver)
    # 2. The kernel-side patch (adds susfs syscall hooks to fs/ and include/)
    KSU_PATCH="$SUSFS_REPO/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    KERNEL_PATCH="$SUSFS_REPO/kernel_patches/50_add_susfs_in_kernel-4.19.patch"

    [ -f "$KSU_PATCH" ] || { echo "!! KSU susfs patch not found: $KSU_PATCH"; exit 1; }
    [ -f "$KERNEL_PATCH" ] || { echo "!! Kernel susfs patch not found: $KERNEL_PATCH"; exit 1; }

    # Apply KSU-side patch inside the KernelSU driver directory
    KSU_DRIVER="$SRC/KernelSU"
    echo ">> Applying KSU susfs patch..."
    git -C "$KSU_DRIVER" apply --check "$KSU_PATCH" 2>/dev/null \
        && git -C "$KSU_DRIVER" apply "$KSU_PATCH" \
        || echo "   (patch already applied or not applicable — continuing)"

    # Apply kernel-side patch to the kernel source root
    echo ">> Applying kernel susfs patch..."
    git -C "$SRC" apply --check "$KERNEL_PATCH" 2>/dev/null \
        && git -C "$SRC" apply "$KERNEL_PATCH" \
        || echo "   (patch already applied or not applicable — continuing)"

    echo ">> SUSFS patches applied"
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
