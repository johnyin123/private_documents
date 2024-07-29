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
echo iptables -t mangle -nvL

cat <<EOF
###############################################################
# #  DOCS
###############################################################
# iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 80 --source 192.168.99.0/24 --jump MARK --set-mark 4
# iptables -t mangle -A PREROUTING -i eth0 -m set --set ${IPSET_NAME} dst --jump MARK --set-mark 4
# iptables -t mangle -A POSTROUTING -p tcp -m multiport --dports 21,40000:41000 --jump MARK --set-mark 4
# iptables -t nat -A POSTROUTING -o eth4 -j SNAT --to-source ${LOCAL_ADDR}
# Normal packets to go direct out WAN
/sbin/ip rule add fwmark 1 table ISP prio 100

# Put packets destined into VPN when VPN is up
/sbin/ip rule add fwmark 2 table VPN prio 200

# Prevent packets from being routed out when VPN is down.
# This prevents packets from falling back to the main table
# that has a priority of 32766
/sbin/ip rule add prohibit fwmark 2 prio 300
http://linux-ip.net/html/routing-rpdb.html
EOF
