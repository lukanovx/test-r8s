#!/usr/bin/env bash
# repack-boot.sh — build a flashable boot.img on the HOST (Linux), not the phone.
#
# Replaces the kernel inside a stock boot.img with a freshly compiled Image,
# preserving the original header (version, base/offsets, cmdline), ramdisk and
# DTB. This is the correct transformation for Samsung Exynos 990 (r8s): the
# bootloader expects the RAW, uncompressed ARM64 `Image`, which is exactly what
# the CI build emits at out/Image.
#
# Usage:
#   ./flash/repack-boot.sh <boot.img> [Image] [out.img]
#
#   <boot.img>  Stock LineageOS boot.img (pull it from the ROM you are running)
#   [Image]     Compiled kernel (default: ./out/Image)
#   [out.img]   Output image    (default: ./out/boot-new.img)
#
set -euo pipefail

MB="${MAGISKBOOT:-/usr/bin/magiskboot}"
BOOT="${1:?usage: repack-boot.sh <boot.img> [Image] [out.img]}"
IMAGE="${2:-out/Image}"
OUT="${3:-out/boot-new.img}"

[ -x "$MB" ]     || { echo "!! magiskboot not found/executable at $MB (set MAGISKBOOT=)"; exit 1; }
[ -f "$BOOT" ]   || { echo "!! boot.img not found: $BOOT"; exit 1; }
[ -f "$IMAGE" ]  || { echo "!! kernel Image not found: $IMAGE"; exit 1; }

# Resolve to absolute paths (we cd into a temp dir below).
BOOT="$(realpath "$BOOT")"
IMAGE="$(realpath "$IMAGE")"
OUT="$(realpath -m "$OUT")"
mkdir -p "$(dirname "$OUT")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> magiskboot: $MB"
echo ">> boot.img   : $BOOT"
echo ">> kernel     : $IMAGE"
echo ">> output     : $OUT"
echo

cd "$WORK"
cp "$BOOT" boot.img

echo ">> Unpacking boot.img"
"$MB" unpack boot.img

[ -f kernel ] || { echo "!! unpack did not produce a 'kernel' payload (unexpected format)"; exit 1; }

echo "   original kernel : $(stat -c%s kernel) bytes  md5=$(md5sum kernel | cut -d' ' -f1)"
echo "   new kernel      : $(stat -c%s "$IMAGE") bytes  md5=$(md5sum "$IMAGE" | cut -d' ' -f1)"

cp "$IMAGE" kernel

echo
echo ">> Repacking"
"$MB" repack boot.img new-boot.img
[ -f new-boot.img ] || { echo "!! repack failed"; exit 1; }

cp new-boot.img "$OUT"
echo
echo ">> Created: $OUT ($(stat -c%s "$OUT") bytes)"
echo
echo "   Flash via download mode:"
echo "     heimdall flash boot \"$OUT\""
echo
echo "   Keep the original $BOOT. Do NOT flash without a way back."
