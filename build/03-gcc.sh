#!/bin/bash
# 03-gcc.sh — clone AOSP cross-binutils (aarch64-linux-android-4.9)
#
# Clang does not ship its own binutils (as/ld/objcopy).
# The kernel build uses CROSS_COMPILE=aarch64-linux-android- which comes
# from this AOSP prebuilt (~91 MB, depth=1).
set -e

BASE="${KERNEL_BASE:-$HOME/kernel}"
GCC="$BASE/gcc"

if [ -x "$GCC/bin/aarch64-linux-android-ld" ]; then
    echo ">> GCC prebuilt already present at $GCC"
else
    echo "=== Cloning aarch64-linux-android-4.9 (AOSP binutils) ==="
    git clone --depth=1 \
        https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 \
        "$GCC"
fi

echo
echo "=== Verification ==="
"$GCC/bin/aarch64-linux-android-ld" --version | head -1
"$GCC/bin/aarch64-linux-android-as" --version | head -1
du -sh "$GCC"
echo
echo ">> ok"
