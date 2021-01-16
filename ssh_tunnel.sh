#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("ssh_tunnel.sh - 74c6148 - 2021-01-16T18:07:57+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
readonly MAX_TAPDEV_NUM=10

mk_support() {
    local ssh_connection=${1}
    local ssh_port=${2}
    try ssh -tt -p${ssh_port} ${ssh_connection} "(grep -v PermitTunnel /etc/ssh/sshd_config ;echo PermitTunnel yes) | tee /etc/ssh/sshd_config" || true
    return 0
}

ssh_tunnel() {
    local remote_br=${1}
    local ssh_connection=${2}
    local ssh_port=${3}
    local tapname=${4}
    local sshpid=${5}
    local local_br=${6}
    local l_tap= r_tap=
    for ((l_tap=0;l_tap<MAX_TAPDEV_NUM;l_tap++)); do
        file_exists /sys/class/net/tap${l_tap}/tun_flags || break
    done
    [[ ${l_tap} = ${MAX_TAPDEV_NUM} ]] && return -1
    r_tap=$(ssh -p${ssh_port} ${ssh_connection} "bash -s" <<< "for ((i=0;i<$MAX_TAPDEV_NUM;i++)); do [[ -e /sys/class/net/tap\${i}/tun_flags ]] || break; done; echo \$i")
    [[ ${r_tap} = ${MAX_TAPDEV_NUM} ]] && return -2
    local localcmd="ip link set dev tap${l_tap} up${local_br:+;ip link set dev tap${l_tap} master ${local_br}}"
    local remotecmd="ip link set dev tap${r_tap} up;ip link set dev tap${r_tap} master ${remote_br}"
    #exec 5> >(ssh -tt -o StrictHostKeyChecking=no -p${port} ${user}@${host} > /dev/null 2>&1)
    #Tunnel=ethernet must before -w 5:5 :)~~
    nohup ssh \
        -o PermitLocalCommand=yes \
        -o LocalCommand="${localcmd}" \
        -o Tunnel=ethernet -w ${l_tap}:${r_tap} \
        -p${ssh_port} ${ssh_connection} "${remotecmd}" &>/dev/null &
    upvar "${sshpid}" "$!"
    upvar "${tapname}" "tap${l_tap}"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} 
        -L|--local    LOCAL_BRIDGE
        -R|--remote * REMOTE_BRIDGE
        -s|--ssh    * SSH_CONNECTION
        -p|--port     SSH_PORT, default 60022
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local local_br=
    local remote_br=
    local ssh_conn=
    local ssh_port="60022"
    local opt_short="L:R:s:p:"
    local opt_long="local:,remote:,ssh:,port:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -L | --local)   shift; local_br=${1}; shift;;
            -R | --remote)  shift; remote_br=${1}; shift;;
            -s | --ssh)     shift; ssh_conn=${1}; shift;;
            -p | --port)    shift; ssh_port=${1}; shift;;
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
    is_user_root || exit_msg "root need!!\n"
    [[ -z "${ssh_conn}" ]] && usage "SSH_CONNECTION Must input"
    [[ -z "${remote_br}" ]] && usage "REMOTE_BRIDGE Must input"
    [[ -z "${local_br}" ]] || file_exists /sys/class/net/${local_br}/bridge/bridge_id || exit_msg "local bridge ${local_br} nofound!!\n"
    local tapname=
    local sshpid=
    ssh_tunnel "${remote_br}" "${ssh_conn}" "${ssh_port}" "tapname" "sshpid" "${local_br}" || exit_msg "error ssh_tunnel $?\n"
    ps --pid=$sshpid &> /dev/null || exit_msg "backend ssh($sshpid) ${ssh_conn}:${ssh_port} failed\n"
    info_msg "backend ssh($sshpid) localdev ${tapname} ${ssh_conn}:${ssh_port} ok\n"
    /bin/bash --rcfile <(echo "PS1=\"(ssh_tunnel:${ssh_conn}[${local_br:-${tapname}}<=>${remote_br}])\$PS1\"") || true
    try "kill -9 ${sshpid:-} &> /dev/null"
    info_msg "Exit!!\n"
    return 0
}
main "$@"
