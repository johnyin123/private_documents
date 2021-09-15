#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("centos_tuning.sh - 2274cee - 2021-09-15T13:24:21+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
source ${DIRNAME}/os_centos_init.sh

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        -n|--hostname      new hostname
        -z|--zswap         zswap size, default 512
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local ssh= port=60022 name= zswap=512
    local opt_short="s:p:n:z:"
    local opt_long="ssh:,port:,hostname:,zswap:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --ssh)     shift; ssh=${1}; shift;;
            -p | --port)    shift; port=${1}; shift;;
            -n | --hostname)shift; name=${1}; shift;;
            -z | --zswap)   shift; zswap=${1}; shift;;
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
    [ -r "${DIRNAME}/motd.sh" ] && {
        try "cat ${DIRNAME}/motd.sh | ssh -p${port} ${ssh} 'cat >/etc/motd.sh'"
    }
    try ssh -p${port} ${ssh} /bin/bash -s << EOF
        $(typeset -f centos_limits_init)
        $(typeset -f centos_disable_selinux)
        $(typeset -f centos_sshd_init)
        $(typeset -f centos_disable_ipv6)
        $(typeset -f centos_service_init)
        centos_limits_init
        centos_disable_selinux
        centos_sshd_init
        centos_disable_ipv6
        centos_service_init
        $(typeset -f centos_sysctl_init)
        centos_sysctl_init
        $(typeset -f centos_zswap_init)
        centos_zswap_init ${zswap}
        sed -i "/motd.sh/d" /etc/profile
        echo "sh /etc/motd.sh" >> /etc/profile
        touch /etc/logo.txt /etc/motd.sh
        [ -z "${name}" ] || echo "${name}" > /etc/hostname
EOF
    return 0
}
main "$@"
