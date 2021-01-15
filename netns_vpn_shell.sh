#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
NS_NAME=${NS_NAME:-"vpnet"}
IP_PREFIX=${IP_PREFIX:-"192.168.100"}
OUT_INTERFACE=${OUT_INTERFACE:-"vpn0"}
ROUTE_TBL_ID=${ROUTE_TBL_ID:-10}
ROUTE_IP=${ROUTE_IP:-"10.0.1.4"}
DNS=${DNS:-"114.114.114.114"}

init_ns_env() {
    ns_name="$1"
    ip="$2"
    ns_name0="${ns_name}0"
    ns_name1="${ns_name}1"
    setup_ns $ns_name
    setup_veth ${ns_name}0 ${ns_name}1 $ns_name
    netns_add_link "${ns_name}1" "${ns_name}" "eth0"
    try ip link set ${ns_name}0 up
    try ip addr add $ip.1/24 dev ${ns_name}0
    maybe_netns_run "ip addr add $ip.2/24 dev eth0" "${ns_name}"
    maybe_netns_run "ip route add default via $ip.1 dev eth0" "${ns_name}"
}

deinit_ns_env() {
    ns_name="$1"
    ip="$2"
    cleanup_ns $ns_name
    cleanup_link "ip link delete ${ns_name}0"
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
}

cleanup_nameserver() {
    ns_name=$1
    rm -rf /etc/netns/$ns_name
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    is_user_root || exit_msg "root user need!!\n"
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; exit_msg "${SCRIPTNAME} version\n";;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    netns_exists "${NS_NAME}" && {
        netns_shell "${NS_NAME}"
        exit 0
    }
    init_ns_env "${NS_NAME}" "${IP_PREFIX}"
    setup_traffic "${NS_NAME}" "${IP_PREFIX}" "${OUT_INTERFACE}"
    setup_nameserver "${NS_NAME}" "${DNS}"
    setup_strategy_route "${IP_PREFIX}" "${ROUTE_IP}" "${ROUTE_TBL_ID}"

    netns_shell "${NS_NAME}"

    cleanup_strategy_route "${ROUTE_TBL_ID}"
    cleanup_nameserver "${NS_NAME}"
    cleanup_traffic "${NS_NAME}" "${IP_PREFIX}" "${OUT_INTERFACE}"
    deinit_ns_env "${NS_NAME}" "${IP_PREFIX}"
    return 0
}
main "$@"
