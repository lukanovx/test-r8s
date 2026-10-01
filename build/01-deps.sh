#!/bin/bash
# 01-deps.sh — install build dependencies on Ubuntu (GitHub Actions runner)
set -e

if [ "$(id -u)" = "0" ]; then SUDO="env"; else SUDO="sudo -E"; fi

echo "=== Installing build dependencies ==="
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
    git build-essential bc bison flex libssl-dev libncurses-dev \
    zip unzip python3 ccache device-tree-compiler lz4 cpio rsync patch

echo
echo "=== Tool versions ==="
echo "git   : $(git --version)"
echo "gcc   : $(gcc -dumpversion)"
echo "make  : $(make --version | head -1)"
echo "bison : $(bison --version | head -1)"
echo "flex  : $(flex --version)"
echo "dtc   : $(dtc --version 2>&1 | head -1)"
echo "nproc : $(nproc)"
echo
echo "=== Disk space ==="
df -h "$HOME" | tail -1
echo
echo ">> ok"
