#!/usr/bin/env bash
set -o nounset -o pipefail

setup_ns() {
    ns_name="$1"
    ip="$2"
    ns_name0="${ns_name}0"
    ns_name1="${ns_name}1"

    ip netns del $ns_name 2> /dev/null

    ip netns add $ns_name
    ip netns exec $ns_name ip addr add 127.0.0.1/8 dev lo
    ip netns exec $ns_name ip link set lo up

    ip link add $ns_name0 type veth peer name $ns_name1
    ip link set $ns_name0 up
    ip link set $ns_name1 netns $ns_name name eth0 up
    ip addr add $ip.1/24 dev $ns_name0
    ip netns exec $ns_name ip addr add $ip.2/24 dev eth0
    ip netns exec $ns_name ip route add default via $ip.1 dev eth0
}

cleanup_ns() {
    ns_name="$1"
    ip="$2"
    ip netns del $ns_name
    ip link delete $ns_name0
}

setup_traffic() {
    ns_name=$1
    ip=$2
    interface=$3

    iptables -A INPUT \! -i $ns_name0 -s $ip.0/24 -j DROP
    iptables -A POSTROUTING -t nat -s $ip.0/24 -o $interface -j MASQUERADE
    sysctl -q net.ipv4.ip_forward=1
}

cleanup_traffic() {
    ns_name0="${1}0"
    ip=$2
    interface=$3
    iptables -D INPUT \! -i $ns_name0 -s $ip.0/24 -j DROP
    iptables -D POSTROUTING -t nat -s $ip.0/24 -o $interface -j MASQUERADE
}

setup_strategy_route() {
    ip=$1
    route_ip=$2
    tid=$3
    # route flow to vpn peer!! gvpe other peer ip as default route
    ip rule add from $ip.0/24 table ${tid}
    ip route add default via ${route_ip} table ${tid} 
}

cleanup_strategy_route() {
    # remove netns route to vpn peer!
    tid=$1
    ip route delete default table ${tid}
    ip rule delete table ${tid}
}

setup_nameserver() {
    ns_name=$1
    nameserver=$2

    mkdir -p "/etc/netns/$ns_name"
    echo "nameserver ${nameserver}" > "/etc/netns/$ns_name/resolv.conf"
     cat > /etc/netns/$ns_name/bash.bashrc <<EOF
export PROMPT_COMMAND=""
alias ll='ls -lh'
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\](${ns_name}):\[\033[33;1m\]\w\[\033[m\]\$"
EOF
}

cleanup_nameserver() {
    ns_name=$1
    rm -rf /etc/netns/$ns_name
}

ns_run() {
    ns_name=$1
    shift
    ip netns exec $ns_name "$@"
}

# trap cleanup TERM
# trap cleanup INT

main() {
    NS_NAME="vpnet"
    IP_PREFIX="192.168.100"
    OUT_INTERFACE="vpn0"
    ROUTE_TBL_ID=10
    ROUTE_IP="10.0.1.4"
    DNS="8.8.8.8"
    [[ $UID = 0 ]] || {
        echo "recommended to run as root.";
        exit 1;
    }
    setup_ns "${NS_NAME}" "${IP_PREFIX}"
    setup_traffic "${NS_NAME}" "${IP_PREFIX}" "${OUT_INTERFACE}"
    setup_nameserver "${NS_NAME}" "${DNS}"
    setup_strategy_route "${IP_PREFIX}" "${ROUTE_IP}" "${ROUTE_TBL_ID}"

    ns_run "${NS_NAME}" curl cip.cc
    ns_run "${NS_NAME}" /bin/bash

    cleanup_strategy_route "${ROUTE_TBL_ID}"
    cleanup_nameserver "${NS_NAME}"
    cleanup_traffic "${NS_NAME}" "${IP_PREFIX}" "${OUT_INTERFACE}"
    cleanup_ns "${NS_NAME}" "${IP_PREFIX}"
    exit 0
}

[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"

