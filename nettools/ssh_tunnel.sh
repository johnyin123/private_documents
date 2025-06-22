#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("81954536[2025-06-20T09:43:04+08:00]:ssh_tunnel.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
readonly MAX_TAPDEV_NUM=10
SSH_OPT="-o ControlMaster=no"
mk_support() {
    local ssh_connection=${1}
    local ssh_port=${2}
    try ssh -tt ${SSH_OPT} -p${ssh_port} ${ssh_connection} "(grep -v PermitTunnel /etc/ssh/sshd_config ;echo PermitTunnel yes) | tee /etc/ssh/sshd_config" || true
    return 0
}

ssh_tunnel() {
    local remote_br=${1}
    local ssh_connection=${2}
    local ssh_port=${3}
    local tapname=${4}
    local local_br=${5}
    local l_tap= r_tap=
    for l_tap in $(seq 0 $MAX_TAPDEV_NUM); do
        [ -e /sys/class/net/tap${l_tap}/tun_flags ] || break;
    done;
    [ "${l_tap}" == "${MAX_TAPDEV_NUM}" ] && return -1;
    r_tap=$(try "ssh ${SSH_OPT} -p${ssh_port} ${ssh_connection} 'for i in \$(seq 0 $MAX_TAPDEV_NUM); do [ -e /sys/class/net/tap\${i}/tun_flags ] || break; done; echo \$i'")
    [ "${r_tap}" == "${MAX_TAPDEV_NUM}" ] && return -2
    local localcmd="ip link set dev tap${l_tap} up${local_br:+;ip link set dev tap${l_tap} master ${local_br}}"
    local remotecmd="ip link set dev tap${r_tap} up;ip link set dev tap${r_tap} master ${remote_br}"
    #exec 5> >(ssh -tt -o StrictHostKeyChecking=no -p${port} ${user}@${host} > /dev/null 2>&1)
    #Tunnel=ethernet must before -w 5:5 :)~~
    maybe_netns_run "bash -s"<<EOF
        start-stop-daemon --start --make-pidfile --pidfile "/run/tap${l_tap}.pid" --quiet --background --exec \
        /bin/ssh -- \
            -M \
            ${SSH_OPT} \
            -o PermitLocalCommand=yes \
            -o LocalCommand='${localcmd}' \
            -o Tunnel=ethernet -w ${l_tap}:${r_tap} \
            -p${ssh_port} ${ssh_connection} '${remotecmd}'
EOF
    upvar "${tapname}" "tap${l_tap}"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} 
        -L|--local        LOCAL_BRIDGE
        -R|--remote   *   REMOTE_BRIDGE
        -s|--ssh      *   SSH_CONNECTION user@host | host
        -p|--port         SSH_PORT, default 60022
        -J|--proxyjump    ProxyJump user@proxy:port, use ssh proxy jump
                          u1@host1:port1,u2@host2:port2
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
demo:
    ./ssh_tunnel.sh -L br0 -R br1 -s root@target_address
    ./br-hostapd.sh -s wlan0 -b br0
    ./netns_shell.sh -i 172.16.16.22/24 -n my_netns -b br0
    ./wireguard_netns.sh -w test -c wg0.conf -n my_wg_netns
    DISPLAY=:0.0 su johnyin -c google-chrome &>/dev/null &
EOF
    exit 1
}
main() {
    local local_br=
    local remote_br=
    local ssh_conn=
    local ssh_port="60022"
    local opt_short="L:R:s:p:J:"
    local opt_long="local:,remote:,ssh:,port:,proxyjump:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -L | --local)   shift; local_br=${1}; shift;;
            -R | --remote)  shift; remote_br=${1}; shift;;
            -s | --ssh)     shift; ssh_conn=${1}; shift;;
            -p | --port)    shift; ssh_port=${1}; shift;;
            -J | --proxyjump) shift; SSH_OPT="-J ${1} ${SSH_OPT}"; shift;;
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
    [[ -z "${local_br}" ]] || bridge_exists "${local_br}" || exit_msg "local bridge ${local_br} nofound!!\n"
    local tapname=
    ssh_tunnel "${remote_br}" "${ssh_conn}" "${ssh_port}" "tapname" "${local_br}" || exit_msg "error ssh_tunnel $?\n"
    try ps --pid=$(try cat /run/${tapname}.pid) > /dev/null || exit_msg "backend ssh ${ssh_conn}:${ssh_port} failed\n"
    info_msg "backend ssh($(try cat /run/${tapname}.pid)) localdev ${tapname} ${ssh_conn}:${ssh_port} ok\n"
    # maybe_netns_shell "ssh_tunnel:${ssh_conn}[${local_br:-${tapname}}<=>${remote_br}]"
    # try "kill -9 $(try cat /run/${tapname}.pid)" &> /dev/null
    # info_msg "Exit!!\n"
    return 0
}
main "$@"
