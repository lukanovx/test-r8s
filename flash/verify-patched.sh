#!/system/bin/sh
# ============================================================
#  verify-patched.sh - confere a imagem patchada pelo Magisk
#  ANTES de gravar. Nao grava nada.
# ============================================================

MB=/data/adb/magisk/magiskboot
WORK=/data/local/tmp/verifywork
NOVO=/data/local/tmp/Image                 # kernel que compilamos
BOOT=$(readlink -f /dev/block/by-name/boot)

# ---------- 1. achar a imagem patchada (a mais recente) ----------
PATCHED=$(ls -t /sdcard/Download/magisk_patched*.img 2>/dev/null | head -n1)
if [ -z "$PATCHED" ]; then
    echo "!! nenhuma magisk_patched*.img encontrada em /sdcard/Download"
    echo "   arquivos .img disponiveis:"
    ls -l /sdcard/Download/*.img 2>/dev/null || echo "     nenhum"
    exit 1
fi
echo ">> imagem patchada: $PATCHED"
echo "   $(stat -c %s "$PATCHED") bytes   (modificada: $(stat -c %y "$PATCHED" | cut -d. -f1))"

# ---------- 2. cabe na particao? ----------
PART_SZ=$(blockdev --getsize64 "$BOOT")
IMG_SZ=$(stat -c %s "$PATCHED")
echo
echo ">> particao $BOOT: $PART_SZ bytes"
if [ "$IMG_SZ" -gt "$PART_SZ" ]; then
    echo "!! A IMAGEM NAO CABE ($IMG_SZ > $PART_SZ). NAO GRAVE."
    exit 1
fi
echo "   cabe (sobram $((PART_SZ - IMG_SZ)) bytes)"

# ---------- 3. desmontar e conferir o conteudo ----------
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
cp "$PATCHED" ./patched.img
echo
echo ">> desmontando a imagem patchada"
"$MB" unpack patched.img >/dev/null 2>&1 || { echo "!! unpack falhou"; exit 1; }

echo
echo "=== o kernel dentro dela e o QUE COMPILAMOS? ==="
MD5_DENTRO=$(md5sum kernel | cut -d' ' -f1)
MD5_NOSSO=$(md5sum "$NOVO" | cut -d' ' -f1)
echo "   dentro da patchada : $MD5_DENTRO"
echo "   o que compilamos   : $MD5_NOSSO"
if [ "$MD5_DENTRO" = "$MD5_NOSSO" ]; then
    echo "   OK - identicos"
    KOK=1
else
    echo "   !! DIFERENTES - voce patchou a imagem errada?"
    KOK=0
fi

echo
echo "=== o Magisk foi mesmo aplicado? ==="
"$MB" cpio ramdisk.cpio test >/dev/null 2>&1
RC=$?
case "$RC" in
    0) echo "   !! ramdisk ESTOCADO - o Magisk NAO foi aplicado"; MOK=0 ;;
    1) echo "   OK - ramdisk com patch do Magisk"; MOK=1 ;;
    2) echo "   OK - ramdisk com patch do Magisk (versao antiga)"; MOK=1 ;;
    *) echo "   ? codigo inesperado: $RC"; MOK=0 ;;
esac
echo "   arquivos do Magisk no ramdisk:"
"$MB" cpio ramdisk.cpio "ls" 2>/dev/null | grep -iE "magisk|overlay.d|init$" | head -8

echo
echo "=== versao do kernel embutida ==="
strings kernel 2>/dev/null | grep -m1 "Linux version"

echo
echo "============================================================"
if [ "$KOK" = "1" ] && [ "$MOK" = "1" ]; then
    echo " TUDO CERTO. seguro para gravar."
    echo "   imagem : $PATCHED"
else
    echo " NAO GRAVE - alguma conferencia falhou acima."
    exit 1
fi
echo "============================================================"
