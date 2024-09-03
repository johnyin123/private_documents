#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("057ea8a[2024-08-28T10:05:38+08:00]:create_netns.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
setup_nameserver() {
    ns_name=$1
    nameserver=$2
    try mkdir -p "/etc/netns/$ns_name"
    try echo "nameserver ${nameserver}" \> "/etc/netns/$ns_name/resolv.conf"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -i|--ipaddr         <cidr>     * x  ipaddress for netns eth0
        -n|--nsname         <name>     * x  netns name
        -b|--bridge         <br>       * x  host bridge for connect
        -g|--gw             <gateway>    x  ns gateway, default .1
        -r|--dns            <ipaddr>     x  dns server, default 114.114.114.114
        -D|--delete         <name>       *  remove net namespace
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        ${SCRIPTNAME} --nsname=test -i 192.168.168.234/24 -b br-ext 
        systemd-run --unit nssvc1 -p NetworkNamespacePath=/run/netns/test /usr/bin/v2ray -c /etc/v2ray/config.json
        # # nsenter/ip netns different
        nsenter --net=/var/run/netns/nsname # # !!! /etc/netns/<name>/resolv.conf, not effict
        ip netns exec nsname bash,  # # !!! /etc/netns/<name>/resolv.conf, OK
EOF
    exit 1
}

remove_netns() {
    ns_name=$1
    netns_exists "${ns_name}" || exit_msg "${ns_name} not exist!!\n"
    maybe_netns_bridge_dellink "${ns_name}-eth1" ""
    cleanup_link "${ns_name}-eth1"
    cleanup_ns "${ns_name}"
    info_msg "${ns_name} removed\n"
    exit 0
}

main() {
    local ipaddr= ns_name= host_br= gateway= dns=114.114.114.114
    local opt_short="i:n:b:g:r:"
    local opt_long="ipaddr:,nsname:,bridge:,gw:,dns:,delete:,"
    opt_short+="ql:dVhD:"
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
            -D | --delete)  shift; remove_netns "${1}"; shift;;
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
    info_msg "${ns_name} create success\n"
    info_msg "nsenter --net=/var/run/netns/${ns_name}\n"
    return 0
}
auto_su "$@"
main "$@"
