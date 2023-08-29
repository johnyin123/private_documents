#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-08-29T14:26:05+08:00]:tun.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
tun_up() {
    local dev=${1}
    local mtu=${2}
    local local_cidr=${3}
    ip link show "${dev}" &>/dev/null && { error_msg "Tunnel is set up already.\n"; return 1; }
    try modprobe ipip || true
    # # info_msg "ont-to-one mode\n"
    # ip tunnel add "${dev}" mode ipip local $LOCAL_IP remote $REMOTE_IP ttl 64 dev $IFDEV
    info_msg "one-to-many mode\n"
    try ip tunnel add ${dev} mode ipip
    try ip link set "${dev}" mtu "${mtu}" up
    try ip addr add ${local_cidr} dev ${dev}
}
tun_down() {
    local dev=${1}
    try ip link delete "${dev}"
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
        -t|--tun           <str>     ipiptun dev name, default tunl0
        --ipaddr        *  <cidr>    ipiptun dev ipaddress, exam: 192.168.166.0/32
        -m|--mtu           <int>     mtu size, default 1476
        --peer_cidr     *  <cidr>    ipip peer cidr address, exam: 192.168.166.1/32
        --remote_ipaddr *  <ipaddr>  remote host address
        --route            <cidr>    route range, multi input, exam: 172.0.0.0/8
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
    local dev=tunl0 mtu=1476
    local local_cidr="" peer_cidr="" remote_ipaddr=""
    local target=()
    local opt_short="t:m:"
    local opt_long="tun:,mtu:,ipaddr:,peer_cidr:,remote_ipaddr:,route:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -t | --tun)     shift; dev=${1}; shift;;
            --ipaddr)       shift; local_cidr=${1}; shift;;
            -m | --mtu)     shift; mtu=${1}; shift;;
            --peer_cidr)    shift; peer_cidr=${1}; shift;;
            --remote_ipaddr)shift; remote_ipaddr=${1}; shift;;
            --route)        shift; target+=(${1}); shift;;
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
    [ -z "${local_cidr}" ] || [ -z "${peer_cidr}" ] || [ -z "${remote_ipaddr}" ] && usage "input ipaddr/peer_cidr/remote_ipaddr"
    tun_up "${dev}" "${mtu}" "${local_cidr}"
    try ip route add ${peer_cidr} via ${remote_ipaddr} dev ${dev} onlink
    for _ip in ${target[@]}; do
        try ip route add ${_ip} via ${remote_ipaddr} dev ${dev} onlink
    done
    return 0
}
main "$@"
