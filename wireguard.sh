#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
cat <<EOF
Enable WireGuard kernel debug logging:
echo 'module wireguard +p' | sudo tee /sys/kernel/debug/dynamic_debug/control

Disable WireGuard kernel debug logging:
echo 'module wireguard -p' | sudo tee /sys/kernel/debug/dynamic_debug/control

EOF
gen_wireguard() {
    #wg genkey | tee server_privatekey | wg pubkey > server_publickey
    PRI_KEY0=$(wg genkey)
    PUB_KEY0=$(echo -n "${PRI_KEY0}" | wg pubkey)

    PRI_KEY1=$(wg genkey)
    PUB_KEY1=$(echo -n "${PRI_KEY1}" | wg pubkey)

    PRI_KEY2=$(wg genkey)
    PUB_KEY2=$(echo -n "${PRI_KEY2}" | wg pubkey)

    nodes=" \
        172.16.16.1    24   202.111.11.111 50055 \
        172.16.16.2    24   '' '' \
        172.16.16.3    24   '' '' \
        "
    set $nodes
    i=0
    while [ "$#" != 0 ]; do
        is_ipv4 $1 || { echo "$i => $1: not ipv4"; exit 1; }
        eval "IP${i}=$1"
        eval "MASK${i}=$2"
        is_ipv4 $3 && eval "PUB_IP${i}=$3"
        eval "PUB_PORT${i}=$4"
        shift 4
        let i=i+1
    done

    cat <<EOF
# command below
ip link add dev wg0 type wireguard
ip address add dev wg0 <ip>/<mask>
wg setconf wg0 /etc/wireguard/wg0.conf
ip link set up dev wg0

#wg0.conf example
#[Interface]
#PrivateKey = <prikey>
#[Peer]
#PublicKey = <peer_pubkey>
#Endpoint = <peerip>:<peerport>
#AllowedIPs = <ip>/<mask>;....
#PersistentKeepalive = 5

#add route table for wireguard
echo "200 tbl" >> /etc/iproute2/rt_tables
#create ipset table
#ipset create tbl hash:net
#保存规则ipset save tbl -f tbl.txt
#从文件创建
#ipset restore -f tbl.txt

#enable iptables rule，mark ip packages equal ipset table
iptables -t mangle -A PREROUTING -m set --match-set tbl dst -j MARK --set-mark 8
iptables -t mangle -A OUTPUT -m set --match-set tbl dst -j MARK --set-mark 8
iptables -t nat -A POSTROUTING -m mark --mark 8 -j MASQUERADE
iptables -I FORWARD -o wg0 -j ACCEPT

#config route table tbl:default route,lan
ip route add default dev wg0 table tbl
ip route add 192.168.3.0/24 dev br-lan table tbl

#enable ip rule
ip rule add fwmark 8 table tbl
EOF

    echo "-------------------------------"
    cat << EOF
[Interface]
PrivateKey = ${PRI_KEY0}
${PUB_PORT0:+ListenPort = ${PUB_PORT0}}

[Peer]
PublicKey = ${PUB_KEY1}
# ${PUB_IP1:+Endpoint = ${PUB_IP1}:${PUB_PORT1}}
AllowedIPs = ${IP1}/32
PersistentKeepalive = 5

[Peer]
PublicKey = ${PUB_KEY2}
# ${PUB_IP2:+Endpoint = ${PUB_IP2}:${PUB_PORT2}}
AllowedIPs = ${IP2}/32
PersistentKeepalive = 5
EOF

    echo "-------------------------------"
    cat <<EOF
[Interface]
PrivateKey = ${PRI_KEY1}
${PUB_PORT1:+ListenPort = ${PUB_PORT1}}

[Peer]
PublicKey = ${PUB_KEY0}
AllowedIPs = ${IP0}/${MASK0}
# ${PUB_IP0:+Endpoint = ${PUB_IP0}:${PUB_PORT0}}
PersistentKeepalive = 5
EOF

    echo "-------------------------------"
    cat <<EOF
[Interface]
PrivateKey = ${PRI_KEY2}
${PUB_PORT2:+ListenPort = ${PUB_PORT2}}

[Peer]
PublicKey = ${PUB_KEY0}
AllowedIPs = ${IP0}/${MASK0}
# ${PUB_IP0:+Endpoint = ${PUB_IP0}:${PUB_PORT0}}
PersistentKeepalive = 5
EOF
}
main() {
    gen_wireguard
    return 0
}
main "$@"

