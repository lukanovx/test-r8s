#!/bin/bash
# =============================================================================
#  04-build.sh — compile the kernel for Samsung Galaxy S20 FE
#                (Exynos 990 / r8s / SM-G780F)
#
#  WHY LLVM=1 LLVM_IAS=1 MATTERS:
#    - LLVM=1      → use the full LLVM suite (clang, lld, llvm-ar,
#                    llvm-objcopy, etc.)
#    - LLVM_IAS=1  → use clang's INTEGRATED assembler instead of GNU as
#
#  Kernels built with GNU `as` (as the LineageOS docs suggest, with only
#  CC=clang LD=ld.lld) load but DO NOT EXECUTE on this bootloader.
#  The log shows "Starting kernel..." and nothing after — no panic, no
#  pstore record. This was isolated after four discarded builds in the
#  upstream exynos990-docker-kernel project. See research/ for history.
#
#  CONFIG MERGE ORDER:
#    1. exynos9830_defconfig    base for all Exynos 990 devices
#    2. r8s.config              r8s hardware: QCA WiFi/BT, MHI modem,
#                               cameras (IMX616, HI847, 3L6), display (EA8076/EA8079/S6E3FC3),
#                               touchscreen (FTS5CU56A, ZT7650), sensors, etc.
#    3. $EXTRA_CONFIG           optional fragment (docker-kernel.config, KSU, etc.)
#
#  USAGE:
#      bash build/04-build.sh
#      KERNEL_BASE=/mnt/d/kernel bash build/04-build.sh
#      EXTRA_CONFIG=config/docker-kernel.config bash build/04-build.sh
# =============================================================================
set -e

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

KERNEL_BASE="${KERNEL_BASE:-$HOME/kernel}"
SRC="$KERNEL_BASE/src"
OUT="out-r8s"
DEFCONFIG="exynos9830_defconfig"
EXTRA_CONFIG="${EXTRA_CONFIG:-}"

ENABLE_KSU="${ENABLE_KSU:-false}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"

[ -d "$SRC" ] || { echo "!! $SRC does not exist — run 02-fontes.sh first"; exit 1; }


export ARCH=arm64
export PATH="$KERNEL_BASE/clang/bin:$KERNEL_BASE/gcc/bin:$PATH"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-builder}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github}"

ARGS="LLVM=1 LLVM_IAS=1 ARCH=arm64 READELF=$KERNEL_BASE/clang/bin/llvm-readelf"

# ── Resolve optional extra config ─────────────────────────────────────────────
EXTRA_ABS=""
if [ -n "$EXTRA_CONFIG" ]; then
    if   [ -f "$EXTRA_CONFIG" ];             then EXTRA_ABS="$(realpath "$EXTRA_CONFIG")"
    elif [ -f "$PROJECT_DIR/$EXTRA_CONFIG" ]; then EXTRA_ABS="$PROJECT_DIR/$EXTRA_CONFIG"
    else
        echo "!! EXTRA_CONFIG '$EXTRA_CONFIG' not found (tried absolute and relative to $PROJECT_DIR)"
        exit 1
    fi
fi

cd "$SRC"

echo "=== Configuring for r8s ==="
echo "  defconfig  : $DEFCONFIG"
echo "  device cfg : r8s.config"
[ -n "$EXTRA_ABS" ] && echo "  extra cfg  : $EXTRA_ABS" || echo "  extra cfg  : (none)"
echo

# Step 1 — base defconfig
make O="$OUT" $ARGS "$DEFCONFIG" > /dev/null

# Step 2 — merge device + optional KSU + optional extra fragment
MERGE_SRCS="$OUT/.config arch/arm64/configs/r8s.config"

if [ "$ENABLE_KSU" = "true" ] && [ -f "$PROJECT_DIR/config/ksu.config" ]; then
    echo "  ksu cfg    : $PROJECT_DIR/config/ksu.config"
    MERGE_SRCS="$MERGE_SRCS $PROJECT_DIR/config/ksu.config"
fi

[ -n "$EXTRA_ABS" ] && MERGE_SRCS="$MERGE_SRCS $EXTRA_ABS"

./scripts/kconfig/merge_config.sh -m -O "$OUT" $MERGE_SRCS > /dev/null

# Step 3 — resolve any unsatisfied dependencies
make O="$OUT" $ARGS olddefconfig > /dev/null

# ── GATE 1: LTO must survive ──────────────────────────────────────────────────
# Kconfig silently reverts CONFIG_LTO_CLANG if LD_IS_LLD is not satisfied.
# LLVM=1 is what ensures ld.lld is used. Without LTO the image is ~3.4 MB
# larger AND does not boot on this bootloader.
if grep -q "^CONFIG_LTO_CLANG=y" "$OUT/.config"; then
    echo "  [ok] CONFIG_LTO_CLANG active"
else
    echo "!! CONFIG_LTO_CLANG was silently disabled."
    echo "   The image will be ~3.4 MB too large and will NOT boot."
    echo "   Ensure LLVM=1 is in effect so ld.lld is the linker."
    exit 1
fi

# ── GATE 2: r8s-specific options must survive ─────────────────────────────────
echo
echo "=== r8s-specific options in final .config ==="
MISSING=0
for c in CONFIG_MODEL_R8S \
         CONFIG_QCA_CLD_WLAN \
         CONFIG_MHI_BUS \
         CONFIG_TOUCHSCREEN_STM_FTS5CU56A \
         CONFIG_CAMERA_RST_V08; do
    v=$(grep -E "^${c}=" "$OUT/.config" | cut -d= -f2)
    if [ -n "$v" ]; then printf '  [%s] %s\n' "$v" "$c"
    else printf '  [MISSING] %s\n' "$c"; MISSING=$((MISSING+1)); fi
done
[ "$MISSING" = "0" ] || { echo "!! $MISSING r8s option(s) missing — aborting"; exit 1; }

# ── GATE 2b: KSU/SUSFS options (when enabled) ────────────────────────────────
if [ "$ENABLE_KSU" = "true" ]; then
    echo
    echo "=== KSU/SUSFS options in final .config ==="
    KMISSING=0
    KSU_CHECKS="CONFIG_KSU CONFIG_KPROBES CONFIG_KALLSYMS CONFIG_KALLSYMS_ALL"
    [ "$ENABLE_SUSFS" = "true" ] && KSU_CHECKS="$KSU_CHECKS CONFIG_KSU_SUSFS"
    for c in $KSU_CHECKS; do
        v=$(grep -E "^${c}=" "$OUT/.config" | cut -d= -f2)
        if [ -n "$v" ]; then printf '  [%s] %s\n' "$v" "$c"
        else printf '  [MISSING] %s\n' "$c"; KMISSING=$((KMISSING+1)); fi
    done
    [ "$KMISSING" = "0" ] || { echo "!! $KMISSING KSU option(s) missing — aborting"; exit 1; }
fi



# ── If an extra config was merged, verify its key options too ─────────────────
if [ -n "$EXTRA_ABS" ]; then
    echo
    echo "=== Options from extra config ==="
    XMISSING=0
    # Extract =y lines from the fragment and check each in the final config
    while IFS= read -r line; do
        case "$line" in
            CONFIG_*=y)
                c="${line%=*}"
                v=$(grep -E "^${c}=" "$OUT/.config" | cut -d= -f2)
                if [ -n "$v" ]; then printf '  [%s] %s\n' "$v" "$c"
                else printf '  [MISSING] %s\n' "$c"; XMISSING=$((XMISSING+1)); fi
                ;;
        esac
    done < "$EXTRA_ABS"
    [ "$XMISSING" = "0" ] || {
        echo "!! $XMISSING option(s) from extra config did not survive olddefconfig."
        echo "   Check that dependencies are met in the base config."
        exit 1
    }
fi

# ── Compile ───────────────────────────────────────────────────────────────────
echo
echo "=== Building with -j$(nproc) ==="
date
make O="$OUT" $ARGS -j"$(nproc)" > "$KERNEL_BASE/build.log" 2>&1 || {
    echo "!! Build failed. Last errors:"
    grep -E "error:" "$KERNEL_BASE/build.log" | tail -20
    exit 1
}
date

IMG="$SRC/$OUT/arch/arm64/boot/Image"
[ -f "$IMG" ] || { echo "!! Image was not generated"; exit 1; }

# ── GATE 3: image size sanity check ──────────────────────────────────────────
# Without LTO the image grows by ~3.4 MB.
# With LTO it stays close to the stock kernel (~42.5 MB for the y2s baseline).
# STRICT_SIZE_CHECK=true makes this a hard failure; default is warning-only
# until we've calibrated the real r8s Image size with LTO on first run.
STRICT_SIZE_CHECK="${STRICT_SIZE_CHECK:-false}"
SIZE=$(stat -c %s "$IMG")
echo
echo "============================================================"
printf "  Image size : %'d bytes (%.1f MB)\n" "$SIZE" "$(echo "scale=1; $SIZE/1048576" | bc)"
echo
if [ "$SIZE" -gt 44000000 ]; then
    echo "  !! LARGER THAN EXPECTED. A kernel with LTO should be ~42.5 MB."
    echo "     Above ~44 MB may indicate LTO is absent (+3.4 MB) or will not boot."
    if [ "$STRICT_SIZE_CHECK" = "true" ]; then
        echo "     STRICT_SIZE_CHECK=true — aborting. DO NOT FLASH."
        exit 1
    else
        echo "     Warning only (set STRICT_SIZE_CHECK=true to make this a hard failure)."
        echo "     Note the actual size above and calibrate after first successful flash."
    fi
else
    echo "  [ok] Size is consistent with LTO enabled"
fi

mkdir -p "$PROJECT_DIR/out"
cp "$IMG" "$PROJECT_DIR/out/Image"
echo
echo "  Copied to : $PROJECT_DIR/out/Image"
echo "  md5       : $(md5sum "$IMG" | cut -d' ' -f1)"
echo
echo "  Next step: see flash/ in the README"
echo "============================================================"
