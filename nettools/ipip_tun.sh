#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-09-05T14:09:43+08:00]:ipip_tun.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
tun_up() {
    local dev=${1}
    local mtu=${2}
    local local_cidr=${3}
    try "modprobe ipip &>/dev/null || true"
    # # info_msg "ont-to-one mode\n"
    # ip tunnel add "${dev}" mode ipip local $LOCAL_IP remote $REMOTE_IP ttl 64 dev $IFDEV
    info_msg "one-to-many mode\n"
    try "ip link show ${dev} &>/dev/null || ip tunnel add ${dev} mode ipip"
    try ip link set "${dev}" mtu "${mtu}" up
    try "ip addr add ${local_cidr} dev ${dev} || true"
}
tun_down() {
    local dev=${1}
    try ip link delete "${dev}"
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
        --ipaddr        *  <cidr>    ipiptun dev ipaddress, exam: 192.168.166.0/32
        -m|--mtu           <int>     mtu size, default 1476
        --remote_ipaddr    <ipaddr>  remote host address
        --route            <cidr>    route range, multi input, exam: 172.0.0.0/8
[root@k2 ~]# ip fou add port 5555 ipproto 4
[root@k1 ~]# ip link add ftok2 type ipip remote 192.168.127.152 local 192.168.127.151 ttl 255 dev eth0 encap fou encap-sport auto encap-dport 5555
通信是双向的，因此还需要按照上述的步骤反过来
[root@k1 ~]# ip fou add port 5555 ipproto 4
[root@k2 ~]# ip link add ftok1 type ipip remote 192.168.127.151 local 192.168.127.152 ttl 255 dev eth0 encap fou encap-sport auto encap-dport 5555
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
    local local_cidr="" remote_ipaddr=""
    local target=()
    local opt_short="m:"
    local opt_long="mtu:,ipaddr:,remote_ipaddr:,route:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --ipaddr)       shift; local_cidr=${1}; shift;;
            -m | --mtu)     shift; mtu=${1}; shift;;
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
    [ -z "${local_cidr}" ] && usage "input ipaddr"
    [ -z "${remote_ipaddr}" ] && [ "$(array_size target)" -gt "0" ] && { usage "remote_ipaddr need"; }
    [ -z "${remote_ipaddr}" ] || [ "$(array_size target)" -gt "0" ] || { usage "use ${remote_ipaddr} to ...??"; }
    tun_up "${dev}" "${mtu}" "${local_cidr}" || true
    for _ip in ${target[@]}; do
        try ip route add ${_ip} via ${remote_ipaddr} dev ${dev} onlink
    done
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
