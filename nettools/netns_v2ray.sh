#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2024-08-01T14:13:59+08:00]:netns_v2ray.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -i|--ipaddr <cidr> * ipaddress for netns eth0
        -n|--nsname <name> * netns name
        -b|--bridge <br>   * host bridge for connect
        -g|--gw <gateway>    ns gateway, default .1
        -r|--dns <ipaddr>    dns server, default 114.114.114.114
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
setup_nameserver() {
    ns_name=$1
    nameserver=$2
    try mkdir -p "/etc/netns/$ns_name"
    try echo "nameserver ${nameserver}" \> "/etc/netns/$ns_name/resolv.conf"
}
main() {
    local ipaddr="" ns_name="" host_br="" gateway="" dns="114.114.114.114"
    local opt_short="i:n:b:g:r:"
    local opt_long="ipaddr:,nsname:,bridge:,gw:,dns:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -i | --ipaddr)  shift; ipaddr=${1}; shift;;
            -n | --nsname)  shift; ns_name=${1}; shift;;
            -b | --bridge)  shift; host_br=${1}; shift;;
            -g | --gw)      shift; gateway=${1}; shift;;
            -r | --dns)     shift; dns=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${ipaddr}"  ] && usage "ipaddr must input"
    [ -z "${ns_name}" ] && usage "nsname must input"
    [ -z "${host_br}" ] && usage "bridge must input"
    file_exists "${DIRNAME}/v2ray" || exit_msg "${DIRNAME}/v2ray no found\n"
    file_exists "${DIRNAME}/v2ctl" || exit_msg "${DIRNAME}/v2ctl no found\n"
    file_exists "${DIRNAME}/config.json" || exit_msg "${DIRNAME}/config.json no found\n"
    is_ipv4_subnet "${ipaddr}" || usage "ipaddr ip/mask"
    gateway=${gateway:-"${ipaddr%.*}.1"}
    info_msg "IPADDR=${ipaddr}\n"
    netns_exists "${ns_name}" && exit_msg "${ns_name} exist!!\n"
    bridge_exists "${host_br}" || exit_msg "${host_br} no found!!\n"
    setup_ns "${ns_name}" || { cleanup_ns "${ns_name}"; exit_msg "netns ${ns_name} setup error!\n"; }
    maybe_netns_setup_veth ${ns_name}-eth0 ${ns_name}-eth1 "" || { cleanup_ns "${ns_name}"; exit_msg "setup veth error!\n"; }
    maybe_netns_bridge_addlink "${host_br}" "${ns_name}-eth1" "" || { maybe_netns_bridge_dellink "${ns_name}-eth1" ""; cleanup_ns "${ns_name}"; exit_msg "bridge add link error!\n"; }
    maybe_netns_addlink "${ns_name}-eth0" "${ns_name}" "eth0" || { maybe_netns_bridge_dellink "${ns_name}-eth1" ""; cleanup_ns "${ns_name}"; exit_msg "netns add link error!\n"; }
    maybe_netns_run "ip address add ${ipaddr} dev eth0" "${ns_name}" ||  true
    maybe_netns_run "ip route add default via ${gateway}" "${ns_name}" || true
    setup_nameserver "${ns_name}" "${dns}" || true

    IPSET_NAME=local_ip
    V2RAY_TPROXY_PORT=50099
    # # RFC5735
    iplist=(
    0.0.0.0/8
    10.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    224.0.0.0/4
    240.0.0.0/4
)
    maybe_netns_run "ipset create local_ip hash:net" "${ns_name}" ||  true
    for ip in "${iplist[@]}"; do
        maybe_netns_run "ipset add local_ip ${ip}" "${ns_name}" ||  true
    done
    maybe_netns_run "iptables -t mangle -N V2RAY" "${ns_name}" || true
    maybe_netns_run "iptables -t mangle -A V2RAY -p tcp -m set --match-set ${IPSET_NAME} dst -m tcp ! --dport 53 -j RETURN" "${ns_name}" || true
    maybe_netns_run "iptables -t mangle -A V2RAY -p udp -m set --match-set ${IPSET_NAME} dst -m udp ! --dport 53 -j RETURN" "${ns_name}" || true
    maybe_netns_run "iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port ${V2RAY_TPROXY_PORT} --tproxy-mark 1" "${ns_name}" || true
    maybe_netns_run "iptables -t mangle -A V2RAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port ${V2RAY_TPROXY_PORT} --tproxy-mark 1" "${ns_name}" || true
    maybe_netns_run "iptables -t mangle -A PREROUTING -j V2RAY" "${ns_name}" || true
    maybe_netns_run "ip rule add fwmark 1 table 100" "${ns_name}" || true
    maybe_netns_run "ip route add local 0.0.0.0/0 dev lo table 100" "${ns_name}" || true
    export V2RAY_LOCATION_ASSET=${DIRNAME}
    maybe_netns_run "" "${ns_name}" "" <<EOF
start-stop-daemon --start --quiet --background --exec '${DIRNAME}/v2ray' -- -c '${DIRNAME}/config.json'
EOF
    maybe_netns_shell "${host_br}" "${ns_name}" || true

    maybe_netns_bridge_dellink "${ns_name}-eth1" ""
    cleanup_link "${ns_name}-eth1"
    cleanup_ns "${ns_name}"
    info_msg "Exit success\n"
    return 0
}
auto_su "$@"
main "$@"
