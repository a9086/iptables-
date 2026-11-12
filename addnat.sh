# 内网 IP 范围，从 172.16.1.2 开始
for D in {2..254}; do
    # 计算 SSH 端口（61D），如果 D 不足三位补0
    SSH_PORT=$(printf "61%03d" "$D")
    # 可用端口范围（1D1 - 1D9），如果 D 不足三位补0
    START_PORT=$(printf "1%03d1" "$D") END_PORT=$(printf "1%03d9" "$D")

    # 内网 IP
    INTERNAL_IP="172.16.1.$D"
    # 设置 DNAT 规则，将外部 SSH 端口转发到对应的内网 IP
    iptables -t nat -A PREROUTING -p tcp --dport $SSH_PORT -j DNAT --to-destination $INTERNAL_IP:22
    # 设置 DNAT 规则，将外部可用端口范围转发到对应的内网 IP
    iptables -t nat -A PREROUTING -p tcp --dport $START_PORT:$END_PORT -j DNAT --to-destination $INTERNAL_IP
    # 设置 SNAT 规则，将内网返回的流量伪装为外部接口的 IP
    iptables -t nat -A POSTROUTING -s $INTERNAL_IP -j MASQUERADE
done
