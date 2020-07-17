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
readonly MAX_TAPDEV_NUM=10

mk_support() {
    local ssh_connection=${1}
    local ssh_port=${2}
    try ssh -tt -p${ssh_port} ${ssh_connection} "(grep -v PermitTunnel /etc/ssh/sshd_config ;echo PermitTunnel yes) | tee /etc/ssh/sshd_config" || true
    return 0
}

ssh_tunnel() {
    local local_br=${1}
    local remote_br=${2}
    local ssh_connection=${3}
    local ssh_port=${4}
    local l_tap= r_tap=
    for ((l_tap=0;l_tap<MAX_TAPDEV_NUM;l_tap++)); do
        file_exists /sys/class/net/tap${l_tap}/tun_flags || break
    done
    [[ ${l_tap} = ${MAX_TAPDEV_NUM} ]] && return -1
    r_tap=$(ssh -p${ssh_port} ${ssh_connection} "bash -s" <<< "for ((i=0;i<$MAX_TAPDEV_NUM;i++)); do [[ -e /sys/class/net/tap\${i}/tun_flags ]] || break; done; echo \$i")
    [[ ${r_tap} = ${MAX_TAPDEV_NUM} ]] && return -2
    #exec 5> >(ssh -tt -o StrictHostKeyChecking=no -p${port} ${user}@${host} > /dev/null 2>&1)
    #Tunnel=ethernet must before -w 5:5 :)~~
    ssh \
        -o PermitLocalCommand=yes \
        -o LocalCommand="ip link set dev tap${l_tap} up;ip link set dev tap${l_tap} master ${local_br}" \
        -o Tunnel=ethernet -w ${l_tap}:${r_tap} \
        -p${ssh_port} ${ssh_connection} "ip link set dev tap${r_tap} up;ip link set dev tap${r_tap} master ${remote_br}" &
    echo "$!"
}

usage() {
    cat <<EOF
${SCRIPTNAME} 
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        -L|--local  * LOCAL_BRIDGE
        -R|--remote * REMOTE_BRIDGE
        -s|--ssh    * SSH_CONNECTION
        -p|--port   SSH_PORT, default 60022
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
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
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
            -V | --version) shift; exit_msg "${SCRIPTNAME} version\n";;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              error_msg "Unexpected option: $1.\n"; usage;;
        esac
    done
    is_user_root || exit_msg "root need!!\n"
    [[ -z "${ssh_conn}" ]] && usage
    [[ -z "${local_br}" ]] && usage
    [[ -z "${remote_br}" ]] && usage
    file_exists /sys/class/net/${local_br}/bridge/bridge_id || exit_msg "bridge ${local_br} nofound!!\n"
    pid="$(ssh_tunnel ${local_br} ${remote_br} ${ssh_conn} ${ssh_port})" || error_msg "error $?\n"
    info_msg "backend ssh($pid) ${ssh_conn}:${ssh_port} ok\n"
    /bin/bash --rcfile <(echo "PS1=\"(ssh_tunnel:${ssh_conn}[${local_br}<=>${remote_br}])\$PS1\"") || true
    try "kill -9 ${pid:-} &> /dev/null"
    info_msg "Exit!!\n"
    return 0
}
main "$@"
