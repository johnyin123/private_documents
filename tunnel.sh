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

del_ns() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    #try brctl delif br-ext ${ns_name}-eth1
    try ip link set ${ns_name}-eth1 promisc off || true
    try ip link set ${ns_name}-eth1 down || true
    try ip link set dev ${ns_name}-eth1 nomaster || true
    try ip netns del ${ns_name} || true
    ip link delete ${ns_name}-eth1 || true
    try rm -rf "/etc/netns/${ns_name}" || true
    return 0
}

add_ns() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    local host_br="$2"
    local ns_cidr="$3"
    try ip netns add ${ns_name} || return 4
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo || return 4
    try ip netns exec ${ns_name} ip link set lo up || return 4
    try ip link add ${ns_name}-eth0 type veth peer name ${ns_name}-eth1 || return 4
    #try brctl addif br-ext ${ns_name}-eth1
    try ip link set dev ${ns_name}-eth1 promisc on || return 4
    try ip link set dev ${ns_name}-eth1 up || return 4
    try ip link set dev ${ns_name}-eth1 master ${host_br} || return 4
    try ip link set ${ns_name}-eth0 netns ${ns_name} || return 4
    try ip netns exec ${ns_name} ip link set dev ${ns_name}-eth0 name eth0 up || return 4
    try ip netns exec ${ns_name} ip address add ${ns_cidr} dev eth0 || return 4
    return 0
}

error_clean() {
    local ns_name="$1";shift 1
    del_ns ${ns_name} 1>/dev/null 2>&1 || true
    exit_msg "clean over! $* error\n";
}

setup_nameserver() {
    ns_name=$1
    nameserver=$2

    mkdir -p "/etc/netns/$ns_name"
    echo "nameserver ${nameserver}" > "/etc/netns/$ns_name/resolv.conf"
     cat > /etc/netns/$ns_name/bash.bashrc <<EOF
export PROMPT_COMMAND=""
alias ll='ls -lh'
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\](\033[5;41;92m${ns_name}\033[m):\[\033[33;1m\]\w\[\033[m\]\$"
EOF
}

cleanup_nameserver() {
    ns_name=$1
    rm -rf /etc/netns/$ns_name
}

main() {
    local NS_CIDR=${NS_CIDR:-"10.32.149.223/24"}
    local NS_NAME=${NS_NAME:-"web_ns"}
    local HOST_BR=${1:-br-srvzone}
    info_msg "IPADDR=$NS_CIDR ${SCRIPTNAME} ${HOST_BR}\n"

    add_ns ${NS_NAME} ${HOST_BR} "${NS_CIDR}" || error_clean "${NS_NAME}" "add netns $?"
    #ip netns exec ${NS_NAME} /bin/bash || true
    #su johnyin /opt/google/chrome/google-chrome
    try ip netns exec ${NS_NAME} "ip link set eth0 mtu 1300" || true
    try ip netns exec ${NS_NAME} "ip route add default via 10.32.149.1" || true
    ( nsenter --net=/var/run/netns/${NS_NAME} su johnyin /opt/google/chrome/google-chrome || true ) &>/dev/null &
    setup_nameserver "${NS_NAME}" "202.107.117.11"
    ip netns exec ${NS_NAME} /bin/bash --rcfile <(echo "PS1=\"namespace ${NS_NAME}> \"") || true
    del_ns ${NS_NAME}
    cleanup_nameserver "${NS_NAME}"
    info_msg "Exit success\n"
    return 0
}
main "$@"
