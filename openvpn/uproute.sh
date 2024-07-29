#!/usr/bin/env bash
# # /etc/openvpn/upaws.sh tun0 1500 0 10.8.0.6 10.8.0.5 init
ZONE=${ZONE:-/etc/openvpn/cn.zone}
echo 'cn zone file: wget -P /etc/openvpn/ http://www.ipdeny.com/ipblocks/data/countries/cn.zone'

IPSET_NAME=aliyun
RULE_TABLE=100
FWMARK=1
ipset create ${IPSET_NAME} hash:net
for ip in $(cat "${ZONE}"); do
    ipset add ${IPSET_NAME} ${ip}
    echo "add ${ip} ......."
done
iptables -t mangle -A OUTPUT -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
ip route flush table ${RULE_TABLE}
iptables -t nat -A POSTROUTING -m set --match-set ${IPSET_NAME} dst -j SNAT --to-source $4
ip route replace default via $5 dev $1 table ${RULE_TABLE}
iptables -t mangle -nvL
exit 0
