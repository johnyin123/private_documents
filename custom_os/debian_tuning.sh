#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("eefea65[2023-01-11T16:08:20+08:00]:debian_tuning.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
[ -e ${DIRNAME}/os_debian_init.sh ] && . ${DIRNAME}/os_debian_init.sh || { echo '**ERROR: os_debian_init.sh nofound!'; exit 1; }

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        --password  <str>  ssh password(default use sshkey)
        -n|--hostname      new hostname
        -z|--zswap         zswap size(MB, 128/255)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local ssh="" port=60022 name="" zswap="" password=""
    local opt_short="s:p:n:z:"
    local opt_long="ssh:,port:,hostname:,zswap:,password:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --ssh)     shift; ssh=${1}; shift;;
            -p | --port)    shift; port=${1}; shift;;
            --password)     shift; password="${1}"; shift;;
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
    [ -z ${password} ]  || set_sshpass "${password}"
    ssh_func "${ssh}" "${port}" debian_apt_init
    ssh_func "${ssh}" "${port}" debian_limits_init
    ssh_func "${ssh}" "${port}" debian_sysctl_init
    ssh_func "${ssh}" "${port}" debian_sshd_regenkey
    ssh_func "${ssh}" "${port}" debian_sshd_init
    [ -z "${zswap}" ] || ssh_func "${ssh}" "${port}" debian_zswap_init2 ${zswap}
    ssh_func "${ssh}" "${port}" debian_locale_init
    ssh_func "${ssh}" "${port}" debian_bash_init root
    [ -r "${DIRNAME}/motd.sh" ] && {
        try "cat ${DIRNAME}/motd.sh | ssh -p${port} ${ssh} 'cat >/etc/update-motd.d/11-motd'"
        ssh_func "${ssh}" "${port}" "touch /etc/logo.txt;chmod 755 /etc/update-motd.d/11-motd"
    }
    ssh_func "${ssh}" "${port}" "[ -z '${name}' ] || echo '${name}' > /etc/hostname"
    ssh_func "${ssh}" "${port}" debian_service_init
    ssh_func "${ssh}" "${port}" debian_minimum_init
    return 0
}
main "$@"
