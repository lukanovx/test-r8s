#!/system/bin/sh
# ============================================================
#  docker-check.sh - audita o kernel do aparelho contra os
#  requisitos do Docker/containerd/runc.
#  su -c "sh /data/local/tmp/linuxsrv/docker-check.sh"
# ============================================================

CFG=/proc/config.gz
if [ ! -r "$CFG" ]; then
    echo "!! /proc/config.gz ausente - nao da para auditar"
    exit 1
fi

DUMP=$(zcat "$CFG" 2>/dev/null)

tem() {
    echo "$DUMP" | grep -q "^$1=[ym]"
}

# $1 = config, $2 = categoria, $3 = para que serve
check() {
    if tem "$1"; then
        printf '  [ok]     %-38s %s\n' "$1" "$3"
    else
        printf '  [FALTA]  %-38s %s\n' "$1" "$3"
        eval "${2}=\$((${2}+1))"
    fi
}

OBRIG=0; REDE=0; OPC=0

echo "============================================================"
echo " Docker vs kernel $(uname -r)"
echo "============================================================"

echo
echo "--- OBRIGATORIOS (sem estes o daemon nao sobe) ---"
check CONFIG_NAMESPACES        OBRIG "namespaces"
check CONFIG_NET_NS            OBRIG "isolamento de rede"
check CONFIG_PID_NS            OBRIG "isolamento de processos"
check CONFIG_UTS_NS            OBRIG "hostname por container"
check CONFIG_IPC_NS            OBRIG "memoria compartilhada isolada"
check CONFIG_CGROUPS           OBRIG "limites de recurso"
check CONFIG_CGROUP_SCHED      OBRIG "limite de CPU"
check CONFIG_CGROUP_DEVICE     OBRIG "controle de acesso a devices"
check CONFIG_CGROUP_FREEZER    OBRIG "pausar containers"
check CONFIG_CPUSETS           OBRIG "fixar CPUs"
check CONFIG_MEMCG             OBRIG "limite de memoria"
check CONFIG_KEYS              OBRIG "chaveiro do kernel"
check CONFIG_SECCOMP           OBRIG "filtro de syscalls"
check CONFIG_POSIX_MQUEUE      OBRIG "filas POSIX"

echo
echo "--- REDE (sem estes: so --network=host) ---"
check CONFIG_VETH              REDE "par de interfaces virtuais"
check CONFIG_BRIDGE            REDE "a ponte docker0"
check CONFIG_BRIDGE_NETFILTER  REDE "firewall na ponte"
check CONFIG_NF_NAT            REDE "NAT"
check CONFIG_IP_NF_NAT         REDE "NAT ipv4"
check CONFIG_IP_NF_FILTER      REDE "filtro ipv4"
check CONFIG_IP_NF_TARGET_MASQUERADE REDE "saida dos containers"
check CONFIG_NETFILTER_XT_MATCH_ADDRTYPE REDE "regras de porta do Docker"
check CONFIG_NETFILTER_XT_MATCH_CONNTRACK REDE "rastreio de conexao"
check CONFIG_NF_CONNTRACK      REDE "rastreio de conexao"

echo
echo "--- ARMAZENAMENTO ---"
check CONFIG_OVERLAY_FS        OPC "driver overlay2 (o padrao)"
check CONFIG_EXT4_FS_POSIX_ACL OPC "ACLs"
check CONFIG_EXT4_FS_SECURITY  OPC "xattrs de seguranca"

echo
echo "--- OPCIONAIS ---"
check CONFIG_USER_NS           OPC "rootless / userns-remap"
check CONFIG_CGROUP_PIDS       OPC "limite de numero de processos"
check CONFIG_BLK_CGROUP        OPC "limite de I/O"
check CONFIG_CFS_BANDWIDTH     OPC "cota de CPU"

echo
echo "--- estado atual do sistema ---"
echo "  cgroup v2 unificado : $(grep -c cgroup2 /proc/mounts) montagem(ns)"
echo "  overlayfs em /proc/filesystems : $(grep -cw overlay /proc/filesystems)"
echo "  /dev/net/tun : $( [ -e /dev/net/tun ] && echo presente || echo ausente )"

echo
echo "============================================================"
echo " obrigatorios faltando : $OBRIG"
echo " de rede faltando      : $REDE"
echo " opcionais faltando    : $OPC"
echo
if [ "$OBRIG" = "0" ] && [ "$REDE" = "0" ]; then
    echo " VEREDITO: Docker roda normalmente."
elif [ "$OBRIG" = "0" ]; then
    echo " VEREDITO: Docker roda em modo degradado:"
    echo "   dockerd --iptables=false --bridge=none  +  docker run --network=host"
    echo "   (containers usam portas do host direto; sem -p e sem rede isolada)"
else
    echo " VEREDITO: Docker NAO roda neste kernel."
    echo "   Seria preciso recompilar o kernel do LineageOS e flashar pelo Odin."
fi
echo "============================================================"
