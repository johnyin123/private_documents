#!/usr/bin/env bash
L_ADDR=172.17.17.2
R_ADDR=172.17.17.1
IPSET_NAME=myset
RULE_TABLE=100
FWMARK=1

iplist=(
    10.170.24.4/32
    10.170.24.3/32
)

echo ipset destroy ${IPSET_NAME}
echo ipset create ${IPSET_NAME} hash:net
echo ipset list
for ip in "${iplist[@]}"; do
    echo ipset -A ${IPSET_NAME} ${ip}
done
echo ipset save
# # Blocking a list of IP addresses
# iptables -I INPUT -m set --match-set myset-ip src -j DROP
echo ip rule delete table ${RULE_TABLE} 2>/dev/null || true
echo ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
echo iptables -t mangle -A OUTPUT -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
echo iptables -t nat -A POSTROUTING -m set --match-set ${IPSET_NAME} dst -j SNAT --to-source ${L_ADDR}
echo ip route del default table ${RULE_TABLE} 2>/dev/null || true
echo ip route add default via ${R_ADDR} table ${RULE_TABLE}
echo ip route list table ${RULE_TABLE}
