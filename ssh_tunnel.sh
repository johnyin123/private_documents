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
TAPDEV_NUM=9

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
    #exec 5> >(ssh -tt -o StrictHostKeyChecking=no -p${port} ${user}@${host} > /dev/null 2>&1)
    #Tunnel=ethernet must before -w 5:5 :)~~
    ssh \
        -o PermitLocalCommand=yes \
        -o LocalCommand="ip link set dev tap${TAPDEV_NUM} up;ip link set dev tap${TAPDEV_NUM} master ${local_br}" \
        -o Tunnel=ethernet -w ${TAPDEV_NUM}:${TAPDEV_NUM} \
        -p${ssh_port} ${ssh_connection} "ip link set dev tap${TAPDEV_NUM} up;ip link set dev tap${TAPDEV_NUM} master ${remote_br}" &
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
        -L|--local  LOCAL_BRIDGE
        -R|--remote REMOTE_BRIDGE
        -s|--ssh    SSH_CONNECTION
        -p|--port   SSH_PORT
EOF
    exit 1
}
main() {
    declare -A PARMS=(
        [LOCAL_BR]="br-ext"
        [REMOTE_BR]="br-data.149"
        [SSH_CONN]="root@10.32.147.16"
        [SSH_PORT]="60022"
    )
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ql:dVhL:R:s:p: -l quite,log:,dryrun,version,help,local:,remote:,ssh:,port: -- "$@") || usage 1
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -L | --local) array_set PARMS "LOCAL_BR" ${2}; shift 2;;
            -R | --remote) array_set PARMS "REMOTE_BR" ${2}; shift 2;;
            -s | --ssh) array_set PARMS "SSH_CONN" ${2}; shift 2;;
            -p | --port) array_set PARMS "SSH_PORT" ${2}; shift 2;;
            -q | --quiet) QUIET=1; shift 1 ;;
            -l | --log) set_loglevel ${2}; shift 2 ;;
            -d | --dryrun) DRYRUN=1; shift 1 ;;
            -V | --version) exit_msg "${SCRIPTNAME} version\n" ;;
            -h | --help) shift 1; usage ;;
            --) shift 1; break ;;
            *)  error_msg "Unexpected option: $1.\n"; usage ;;
        esac
    done
    is_user_root || exit_msg "root need!!\n"
    pid="$(ssh_tunnel $(array_get PARMS "LOCAL_BR") $(array_get PARMS "REMOTE_BR") $(array_get PARMS "SSH_CONN") $(array_get PARMS "SSH_PORT"))"
    /bin/bash --rcfile <(echo "PS1=\"(ssh_tunnel:$(array_get PARMS 'SSH_CONN'))$PS1\"") || true
    try "kill -9 ${pid:-} &> /dev/null"
    info_msg "Exit!!\n"
    return 0
}
main "$@"
