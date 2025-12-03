#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("a559a380[2025-12-02T14:22:37+08:00]:ssh_tunnel2.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
readonly MAX_TAPDEV_NUM=10
SSH_OPTS="-F none -o StrictHostKeyChecking=no -o UpdateHostKeys=no -o UserKnownHostsFile=/dev/null -o ControlMaster=no ${SSH_OPTS:-}"
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
    env: SSH_OPTS
        -L|--local   <str>     LOCAL_BRIDGE
        -R|--remote  <str>     REMOTE_BRIDGE
        -s|--ssh      *        SSH_CONNECTION user@host | host
        -p|--port  ${G}<int>${N}       SSH_PORT, default 60022
        -J|--proxyjump         ProxyJump user@proxy:port, use ssh proxy jump
                               u1@host1:port1,u2@host2:port2
        --remote_tap <str>     remote tap name,default eth9
        --l_ip      <ip cidr>  local tap dev ipaddr (no use bridge)
        --r_ip      <ip cidr>  remote tap dev ipaddr (no use bridge)
        -q|--quiet
        -l|--log ${G}<int>${N} log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
)"; echo -e "${usage_doc}"
    exit 1
}
ssh_tunnel() {
    local ssh_connection=${1}
    local ssh_port=${2}
    local l_br=${3}
    local r_br=${4}
    local l_ip=${5:-}
    local r_ip=${6:-}
    local r_tap=${7:-eth99}
    local trans_port=$(random 65100 65200)
    local l_tap=""
    for l_tap in $(seq 0 $MAX_TAPDEV_NUM); do
        [ -e /sys/class/net/sslvpn${l_tap}/tun_flags ] || break;
    done;
    l_tap=sslvpn${l_tap}
    local l_cmd="socat TUN${l_ip:+:${l_ip}},tun-type=tap,tun-name=${l_tap},iff-up TCP-LISTEN:${trans_port},bind=127.0.0.1,reuseaddr& logger ok;${l_br:+sleep 1;ip link set dev ${l_tap} master ${l_br}}"
    local r_cmd="socat TUN${r_ip:+:${r_ip}},tun-type=tap,tun-name=${r_tap},iff-up TCP:127.0.0.1:${trans_port}& logger ok;${r_br:+sleep 1;ip link set ${r_tap} up;ip link set dev ${r_tap} master ${r_br} || brctl addif ${r_br} ${r_tap}}"
    systemctl reset-failed sslvpn 2>/dev/null || true
    systemd-run --unit sslvpn \
        ssh ${SSH_OPTS} \
        -o PermitLocalCommand=yes \
        -o LocalCommand="${l_cmd}" \
        -R 127.0.0.1:${trans_port}:127.0.0.1:${trans_port} \
        -p ${ssh_port} \
        ${ssh_connection} \
        "${r_cmd}"
}
main() {
    local l_br="" r_br="" ssh_conn="" l_ip="" r_ip=""
    local ssh_port="60022"
    local remote_tap="eth9"
    local opt_short="L:R:s:p:J:"
    local opt_long="local:,remote:,ssh:,port:,proxyjump:,remote_tap:,l_ip:,r_ip:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -L | --local)   shift; l_br=${1}; shift;;
            -R | --remote)  shift; r_br=${1}; shift;;
            -s | --ssh)     shift; ssh_conn=${1}; shift;;
            -p | --port)    shift; ssh_port=${1}; shift;;
            -J | --proxyjump) shift; SSH_OPT="-J ${1} ${SSH_OPT}"; shift;;
            --remote_tap)   shift; remote_tap=${1}; shift;;
            --l_ip)         shift; l_ip=${1}; shift;;
            --r_ip)         shift; r_ip=${1}; shift;;
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
    # is_user_root || exit_msg "root user need!!\n"
    require ssh socat systemd-run systemctl ip
    [ -z "${ssh_conn}" ] && usage "SSH_CONNECTION Must input"
    [ -z "${l_ip}" ] || l_br=""
    [ -z "${r_ip}" ] || r_br=""
    [ -z "${l_br}" ] || bridge_exists "${l_br}" || exit_msg "local bridge ${l_br} nofound!!\n"
    ssh_tunnel "${ssh_conn}" "${ssh_port}" "${l_br}" "${r_br}" "${l_ip}" "${r_ip}" "${remote_tap}"
    info_msg "systemctl stop sslvpn.service\n"
    return 0
}
auto_su "$@"
main "$@"
