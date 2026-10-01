#!/system/bin/sh
# ============================================================
#  flash-kernel.sh - grava a boot patchada e CONFERE lendo de volta.
#  Nao reinicia: o reboot fica por sua conta.
# ============================================================
set -e

BOOT=$(readlink -f /dev/block/by-name/boot)
PATCHED=$(ls -t /sdcard/Download/magisk_patched*.img 2>/dev/null | head -n1)
BKP=/data/local/tmp/boot-original.img

[ -n "$PATCHED" ] || { echo "!! imagem patchada nao encontrada"; exit 1; }
[ -f "$BKP" ]     || { echo "!! backup ausente - NAO gravar sem ele"; exit 1; }

PART_SZ=$(blockdev --getsize64 "$BOOT")
IMG_SZ=$(stat -c %s "$PATCHED")
[ "$IMG_SZ" -le "$PART_SZ" ] || { echo "!! nao cabe"; exit 1; }

MD5_ORIG=$(md5sum "$PATCHED" | cut -d' ' -f1)

echo ">> backup confirmado : $BKP ($(stat -c %s "$BKP") bytes)"
echo ">> gravando          : $PATCHED"
echo "   destino           : $BOOT"
echo "   md5 de origem     : $MD5_ORIG"
echo

dd if="$PATCHED" of="$BOOT" bs=4096
sync
echo

# ---------- leitura de volta ----------
echo ">> lendo de volta para conferir"
dd if="$BOOT" of=/data/local/tmp/readback.img bs=4096 count=$((IMG_SZ / 4096)) 2>/dev/null
MD5_LIDO=$(md5sum /data/local/tmp/readback.img | cut -d' ' -f1)
echo "   md5 gravado       : $MD5_LIDO"
rm -f /data/local/tmp/readback.img

echo
if [ "$MD5_ORIG" = "$MD5_LIDO" ]; then
    echo "============================================================"
    echo " GRAVACAO CONFERIDA - os md5 batem."
    echo
    echo " reinicie quando quiser:  reboot"
    echo
    echo " SE NAO BOOTAR:"
    echo "   download mode = Volume Baixo + Bixby + cabo USB"
    echo "   e restaure com Odin, ou com o backup:"
    echo "     dd if=$BKP of=$BOOT"
    echo "============================================================"
else
    echo "!! OS MD5 NAO BATEM. A gravacao saiu errada."
    echo "   restaure AGORA, antes de reiniciar:"
    echo "     dd if=$BKP of=$BOOT"
    exit 1
fi
