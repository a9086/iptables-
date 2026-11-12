
#!/bin/bash

# ==========================================
# PVE LXC 批量 NAT 端口转发
# 内网范围：172.16.1.2 - 172.16.1.254
# 公网网卡：vmbr0
# 内网网卡：vmbr1
# ==========================================

set -euo pipefail

IPT="iptables"
INTERNAL_PREFIX="172.16.1"
PUBLIC_IF="vmbr0"

# 必须使用 root
if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 执行"
    exit 1
fi

# 检查 iptables
command -v "$IPT" >/dev/null || {
    echo "iptables 未安装"
    exit 1
}

echo "=========================================="
echo "开始配置 LXC 批量 NAT 转发"
echo "=========================================="

# 开启 IPv4 转发
sysctl -w net.ipv4.ip_forward=1

# 遍历内网 IP
for D in {2..254}; do

    INTERNAL_IP="${INTERNAL_PREFIX}.${D}"

    # SSH 公网端口：61 + 三位 IP 尾数
    SSH_PORT=$(printf "61%03d" "$D")

    # 业务端口：1 + 三位 IP 尾数 + 1~9
    START_PORT=$(printf "1%03d1" "$D")
    END_PORT=$(printf "1%03d9" "$D")

    # SSH DNAT
    if ! $IPT -t nat -C PREROUTING \
        -i "$PUBLIC_IF" \
        -p tcp --dport "$SSH_PORT" \
        -j DNAT --to-destination "${INTERNAL_IP}:22" 2>/dev/null; then

        $IPT -t nat -A PREROUTING \
            -i "$PUBLIC_IF" \
            -p tcp --dport "$SSH_PORT" \
            -j DNAT --to-destination "${INTERNAL_IP}:22"

        echo "SSH: ${SSH_PORT} -> ${INTERNAL_IP}:22"
    fi

    # 业务端口 DNAT
    if ! $IPT -t nat -C PREROUTING \
        -i "$PUBLIC_IF" \
        -p tcp --dport "${START_PORT}:${END_PORT}" \
        -j DNAT --to-destination "$INTERNAL_IP" 2>/dev/null; then

        $IPT -t nat -A PREROUTING \
            -i "$PUBLIC_IF" \
            -p tcp --dport "${START_PORT}:${END_PORT}" \
            -j DNAT --to-destination "$INTERNAL_IP"

        echo "PORT: ${START_PORT}-${END_PORT} -> ${INTERNAL_IP}"
    fi

done

# 所有 LXC 共用一条出站 MASQUERADE 规则
if ! $IPT -t nat -C POSTROUTING \
    -m iprange --src-range 172.16.1.2-172.16.1.254 \
    -o "$PUBLIC_IF" \
    -j MASQUERADE 2>/dev/null; then

    $IPT -t nat -A POSTROUTING \
        -m iprange --src-range 172.16.1.2-172.16.1.254 \
        -o "$PUBLIC_IF" \
        -j MASQUERADE
fi

echo
echo "=========================================="
echo "NAT 配置完成"
echo "=========================================="

echo "SSH 转发规则数量："
$IPT -t nat -L PREROUTING -n | grep -c 'dpt:' || true

echo
echo "POSTROUTING 规则："
$IPT -t nat -L POSTROUTING -n -v

echo
echo "IPv4 转发状态："
sysctl net.ipv4.ip_forward
