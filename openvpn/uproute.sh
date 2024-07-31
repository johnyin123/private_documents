#!/usr/bin/env bash
# # /etc/openvpn/uproute.sh tun0 1500 0 10.8.0.6 10.8.0.5 init
env | logger
logger "$*"

ZONE=${ZONE:-/etc/openvpn/cn.zone}
SKIP_ZONE=${SKIP_ZONE:-/etc/openvpn/skip.zone}
IPSET_NAME=${IPSET_NAME:-aliyun}
RULE_TABLE=${RULE_TABLE:-100}
FWMARK=${FWMARK:-1}

LOGFILE=""
# LOGFILE="-a log.txt"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

echo 'cn zone file: wget -P /etc/openvpn/ http://www.ipdeny.com/ipblocks/data/countries/cn.zone'

ipset create ${IPSET_NAME} hash:net 2>/dev/null || {
    log "${IPSET_NAME} exists flush clear"
    ipset flush ${IPSET_NAME}
}

log "add ipset"
cat <<EOF | tee ${LOGFILE} | ipset -exist restore
create ${IPSET_NAME} hash:net
$(cat "${ZONE}" | sed  -e "s/^/add ${IPSET_NAME} /")
EOF

log "add fwmark ${FWMARK},for as a router"
iptables -t mangle -D PREROUTING -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK} &>/dev/null || true
iptables -t mangle -A PREROUTING -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
log "add fwmark ${FWMARK},for local machine usage"
iptables -t mangle -D OUTPUT -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK} &>/dev/null || true
iptables -t mangle -A OUTPUT -m set --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
log "add ip rule for fwmark ${FWMARK}"
ip rule delete fwmark ${FWMARK} table ${RULE_TABLE} &>/dev/null || true
ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
# iptables -t nat -D POSTROUTING -d 39.104.207.142 -j RETURN &>/dev/null || true
# iptables -t nat -A POSTROUTING -d 39.104.207.142 -j RETURN
for ip in $(cat "${SKIP_ZONE}"); do
    log "exclude vpnserver ipaddr ${ip}"
    ipset add ${IPSET_NAME} ${ip} nomatch || true
done
log "other cn.zone ips snat"
# iptables -t nat -D POSTROUTING -m set --match-set ${IPSET_NAME} dst -j SNAT --to-source $4 &>/dev/null || true
# iptables -t nat -A POSTROUTING -m set --match-set ${IPSET_NAME} dst -j SNAT --to-source $4
iptables -t nat -D POSTROUTING -m set --match-set ${IPSET_NAME} dst -j MASQUERADE -o $1 &>/dev/null || true
iptables -t nat -A POSTROUTING -m set --match-set ${IPSET_NAME} dst -j MASQUERADE -o $1
log "set route"
ip route flush table ${RULE_TABLE} &>/dev/null || true
# # if vpnserver topology subnet: uproute.sh tun0 1500 0 10.8.0.2 255.255.255.0 init
# # env route_vpn_gateway set by openvpn main process!!
log "vpn env: ${route_net_gateway}, ${route_vpn_gateway}, ${ifconfig_local}, ${ifconfig_remote}"
# ip route replace default via ${route_vpn_gateway} dev $1 table ${RULE_TABLE}
# # if vpnserver topology net30/p2p
ip route replace default via $5 dev $1 table ${RULE_TABLE}
log "show route"
ip route show table ${RULE_TABLE}
iptables -t mangle -nvL
exit 0

cat <<EOF
到本机某进程的报文：PREROUTING–>INPUT
由本机转发的报文：PREROUTING–>FORWARD–>POSTROUTING
由本机某进程发出的报文：OUTPUT–>POSTROUTING
###############################################################
# #  DOCS
###############################################################
# iptables -t mangle -A PREROUTING -i eth0 -p tcp --dport 80 --source 192.168.99.0/24 --jump MARK --set-mark 4
# iptables -t mangle -A PREROUTING -i eth0 -m set --set ${IPSET_NAME} dst --jump MARK --set-mark 4
# iptables -t mangle -A POSTROUTING -p tcp -m multiport --dports 21,40000:41000 --jump MARK --set-mark 4
# iptables -t nat -A POSTROUTING -o eth4 -j SNAT --to-source ${LOCAL_ADDR}
# # Blocking ip set
# iptables -I INPUT -m set --match-set ${IPSET_NAME} src -j DROP
# # not in ip set
# iptables -t mangle -A OUTPUT -m set ! --match-set ${IPSET_NAME} dst -j MARK --set-mark ${FWMARK}
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
