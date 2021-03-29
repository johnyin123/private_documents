#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("centos_tuning.sh - initversion - 2021-03-29T13:52:27+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
source os_centos_init.sh

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local ssh= port=60022
    local opt_short="s:p:"
    local opt_long="ssh:port:"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --ssh)     shift; ssh=${1}; shift;;
            -p | --port)    shift; port=${1}; shift;;
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
    [ -z ${ssh} ] && usage "ssh must input"
   # ssh -p${port} ${ssh} 
    cat << EOF
        $(typeset -f centos_limits_init)
        $(typeset -f centos_disable_selinux)
        $(typeset -f centos_sshd_init)
        $(typeset -f centos_disable_selinux)
        $(typeset -f centos_disable_ipv6)
        $(typeset -f centos_service_init)
        centos_limits_init
        centos_disable_selinux
        centos_sshd_init
        centos_disable_selinux
        centos_disable_ipv6
        centos_service_init
EOF
    return 0
}
main "$@"
