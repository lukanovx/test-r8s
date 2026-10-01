#!/system/bin/sh
# ============================================================
#  repack-test.sh - o magiskboot repack e idempotente?
#
#  Desempacota a boot.img e reempacota SEM TROCAR NADA.
#  Se o resultado nao for identico ao original, o repack e
#  o culpado - e nao o nosso kernel.
#
#  Nao grava nada em particao nenhuma.
# ============================================================
set -e
MB=/data/adb/magisk/magiskboot
SRC=/data/local/tmp/boot-original.img
W=/data/local/tmp/repacktest

[ -f "$SRC" ] || { echo "!! $SRC ausente"; exit 1; }

rm -rf "$W"; mkdir -p "$W"; cd "$W"
cp "$SRC" ./boot.img

echo ">> original : $(md5sum boot.img | cut -d' ' -f1)  $(stat -c %s boot.img) bytes"
echo
echo ">> unpack + repack SEM alteracao nenhuma"
"$MB" unpack boot.img >/dev/null 2>&1
"$MB" repack boot.img saida.img >/dev/null 2>&1
echo ">> resultado : $(md5sum saida.img | cut -d' ' -f1)  $(stat -c %s saida.img) bytes"

echo
if cmp -s boot.img saida.img; then
    echo "============================================================"
    echo " REPACK E IDEMPOTENTE - a imagem sai identica."
    echo " Logo o repack NAO e o culpado; o problema e o kernel."
    echo "============================================================"
else
    echo "============================================================"
    echo " !! REPACK ALTERA A IMAGEM."
    echo "    Isso explicaria TODAS as falhas: toda tentativa nossa"
    echo "    passou por aqui, inclusive a do kernel de controle."
    echo "============================================================"
    echo
    echo " primeiras diferencas (offset, byte original, byte novo):"
    cmp -l boot.img saida.img 2>/dev/null | head -12
    echo " total de bytes diferentes: $(cmp -l boot.img saida.img 2>/dev/null | wc -l)"
    echo
    echo " comparando os rodapes (ultimos 128 bytes):"
    echo " --- original ---"
    tail -c 128 boot.img | od -c | tail -9
    echo " --- reempacotada ---"
    tail -c 128 saida.img | od -c | tail -9
fi
