#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("virt-qemu-agent.sh - 2f47b81 - 2021-04-28T09:07:41+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
VIRSH_OPT="-k 300 -K 5 -q"
#ControlMaster auto
#ControlPath  ~/.ssh/sockets/%r@%h-%p

fake_virsh() {
    local usr_srv_port=$1;shift 1
    try virsh -c qemu+ssh://${usr_srv_port}/system ${VIRSH_OPT} ${*}
}

agent_passwd() {
    local usr_srv_port=$1;shift 1
    local domain=$1;shift 1
    local username=$1;shift 1
    local password=$(echo -en "${1}" | base64);shift 1
    for it in ${*}; do
        args="${args},\"$it\""
    done
    debug_msg "'{\"execute\":\"guest-set-user-password\",\"arguments\":{\"username\":\"${username}\",\"password\":\"${password}\",\"crypted\":false}}'"
    fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "'{\"execute\":\"guest-set-user-password\",\"arguments\":{\"username\":\"${username}\",\"password\":\"${password}\",\"crypted\":false}}'"
}
#agent_command root@10.32.147.3:60022 p3sywin161 cmd.exe /c dir
agent_command() {
    local usr_srv_port=$1;shift 1
    local domain=$1;shift 1
    local cmd=$1;shift 1
    local args="\"${1:-}\"";shift 1 || true
    for it in ${*}; do
        args="${args},\"$it\""
    done
    debug_msg "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"${cmd}\",\"arg\":[${args}],\"capture-output\":true}}"
    local out=$(fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "'{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"${cmd}\",\"arg\":[${args}],\"capture-output\":true}}'" | jq ".return.pid")
    out=$(fake_virsh "${usr_srv_port}" qemu-agent-command ${domain} "'{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":${out}}}'")
    local exitcode=$(printf "%s" $out | jq -c ".return.exitcode")
    local exited=$(printf "%s" $out | jq -c ".return.exited")
    printf "%s" $out | jq -cr '.return."out-data"' | base64 -d
    return $exitcode
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} -q -l <int> -d -h passwd/exec <args>
        exec <usr_srv_port> <domain> <cmd> <arg>
        passwd <usr_srv_port> <domain> <username> <password>
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    case "${1:-}" in
        passwd)
            shift
            agent_passwd ${*}
            ;;
        exec)
            shift
            agent_command ${*}
            ;;
        *)
            usage "passwd/exec"
            ;;
    esac
}
main "$@"
