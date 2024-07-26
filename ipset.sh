#!/usr/bin/env bash
LOCAL_ADDR=192.168.168.1
REMOTE_ADDR=192.168.168.2
IPSET_NAME=myset
RULE_TABLE=100
FWMARK=1

iplist=(
    111.124.200.227
    101.71.33.11/32
)

echo ipset destroy ${IPSET_NAME}
echo ipset create ${IPSET_NAME} hash:net
echo ipset list
for ip in "${iplist[@]}"; do
    echo ipset add ${IPSET_NAME} ${ip}
done
echo ipset save
echo "# Blocking ip set # iptables -I INPUT -m set --match-set ${IPSET_NAME} src -j DROP"
echo "# not in ip set # iptables -t mangle -A OUTPUT -m set ! --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}"
echo iptables -t mangle -A OUTPUT -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
echo ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
echo ip route flush table ${RULE_TABLE}
echo iptables -t nat -A POSTROUTING -m set --match-set ${IPSET_NAME} dst -j SNAT --to-source ${LOCAL_ADDR}
echo ip route add default via ${REMOTE_ADDR} table ${RULE_TABLE}
echo ip route list table ${RULE_TABLE}

# iptables -t mangle -A PREROUTING -i wlan0 -p tcp --dport 80 -j MARK --set-mark 4
# iptables -t mangle -A PREROUTING -p tcp --dport 80 -s 192.168.99.0/24 -j MARK --set-mark 4
# iptables -t mangle -A PREROUTING -i br0 -m set --set ${IPSET_NAME} dst -j MARK --set-mark 4
# iptables -t nat -A POSTROUTING -o eth4 -j SNAT --to-source ${LOCAL_ADDR}
echo iptables -t mangle -nvL
