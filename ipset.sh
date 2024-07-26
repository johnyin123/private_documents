#!/usr/bin/env bash
LOCAL_ADDR=172.17.17.2
REMOTE_ADDR=172.17.17.1
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
    echo ipset add ${IPSET_NAME} ${ip}
done
echo ipset save
# # Blocking a list of IP addresses
# iptables -I INPUT -m set --match-set myset-ip src -j DROP
echo iptables -t mangle -A OUTPUT -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
echo ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
echo iptables -t nat -A POSTROUTING -m set --match-set ${IPSET_NAME} dst -j SNAT --to-source ${LOCAL_ADDR}
echo ip route add default via ${REMOTE_ADDR} table ${RULE_TABLE}
echo ip route list table ${RULE_TABLE}

# iptables -t mangle -A PREROUTING -i wlan0 -p tcp --dport 80 -j MARK --set-mark 1
# ip rule add fwmark 1 table 201
# ip route add 0.0.0.0/1 via 10.8.0.13 dev tun0 table 201
# iptables -t mangle -A PREROUTING -p tcp --dport 80 -s 192.168.99.0/24 -j MARK --set-mark 4
# iptables -t nat -A POSTROUTING -o eth4 -j SNAT --to-source ${LOCAL_ADDR}
# iptables -t mangle -nvL
