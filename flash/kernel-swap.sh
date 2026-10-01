#!/system/bin/sh
# ============================================================
#  kernel-swap.sh - troca o kernel dentro da boot.img
#
#  Espera encontrar o kernel novo em /data/local/tmp/Image
#  (enviado por adb push).
#
#  NAO grava nada na particao. Só produz a imagem nova para
#  voce patchar no app do Magisk.
#
#  su -c "sh /data/local/tmp/kernel-swap.sh"
# ============================================================
set -e

MB=/data/adb/magisk/magiskboot
WORK=/data/local/tmp/bootwork
NOVO=/data/local/tmp/Image
BKP_DE=/data/local/tmp/boot-original.img
BKP_SD=/sdcard/Download/boot-original.img

[ -x "$MB" ] || { echo "!! magiskboot nao encontrado em $MB"; exit 1; }
[ -f "$NOVO" ] || { echo "!! kernel novo nao encontrado em $NOVO"; exit 1; }

BOOT=$(readlink -f /dev/block/by-name/boot)
[ -b "$BOOT" ] || { echo "!! particao boot nao encontrada"; exit 1; }
echo ">> particao boot: $BOOT"

# ---------- 1. backup, em dois lugares ----------
# /data/local/tmp e device-encrypted: legivel mesmo sem desbloquear a tela
if [ ! -f "$BKP_DE" ]; then
    echo ">> extraindo a boot atual"
    dd if="$BOOT" of="$BKP_DE" 2>/dev/null
    cp "$BKP_DE" "$BKP_SD" 2>/dev/null || echo "   (copia no /sdcard falhou - siga assim mesmo)"
else
    echo ">> backup ja existe, preservando o original: $BKP_DE"
fi
echo "   $(ls -l "$BKP_DE" | awk '{print $5" bytes"}')"
echo "   md5: $(md5sum "$BKP_DE" | cut -d' ' -f1)"

# ---------- 2. desmontar ----------
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
cp "$BKP_DE" ./boot.img
echo
echo ">> desmontando a boot.img"
"$MB" unpack boot.img
echo "   arquivos extraidos:"
ls -l | awk 'NR>1 {print "     "$9"  ("$5" bytes)"}'

[ -f kernel ] || { echo "!! a boot.img nao tinha um arquivo 'kernel'"; exit 1; }
echo
echo "   kernel atual : $(md5sum kernel | cut -d' ' -f1)  $(ls -l kernel | awk '{print $5}') bytes"
echo "   kernel novo  : $(md5sum "$NOVO" | cut -d' ' -f1)  $(ls -l "$NOVO" | awk '{print $5}') bytes"

# ---------- 3. trocar e reempacotar ----------
cp "$NOVO" ./kernel
echo
echo ">> reempacotando"
"$MB" repack boot.img new-boot.img
[ -f new-boot.img ] || { echo "!! repack falhou"; exit 1; }

cp new-boot.img /sdcard/Download/boot-novo.img
cp new-boot.img /data/local/tmp/boot-novo.img

echo
echo "============================================================"
echo " boot-novo.img gerada:"
echo "   /sdcard/Download/boot-novo.img   ($(ls -l new-boot.img | awk '{print $5}') bytes)"
echo
echo " BACKUP do original (guarde!):"
echo "   $BKP_DE"
echo "   $BKP_SD"
echo
echo " PROXIMO PASSO - no CELULAR, no app do Magisk:"
echo "   Instalar > Selecionar e corrigir um arquivo"
echo "   escolha:  Download/boot-novo.img"
echo
echo " Ele gera Download/magisk_patched-XXXXX.img."
echo " NAO grave a boot-novo.img crua: sem o patch do Magisk voce"
echo " perde o root, e sem root o servidor Linux nao sobe no boot."
echo "============================================================"
