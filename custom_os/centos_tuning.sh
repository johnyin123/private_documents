#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("c518be6[2023-01-06T14:50:41+08:00]:centos_tuning.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
[ -e ${DIRNAME}/os_centos_init.sh ] && . ${DIRNAME}/os_centos_init.sh || { echo '**ERROR: os_centos_init.sh nofound!'; exit 1; }

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        --password  <str>  ssh password(default use sshkey)
        -n|--hostname      new hostname
        -z|--zramswap         zramswap size(MB, 128/255)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local ssh="" port=60022 name="" zramswap="" password=""
    local opt_short="s:p:n:z:"
    local opt_long="ssh:,port:,hostname:,zramswap:,password:,"
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
            -z | --zramswap)   shift; zramswap=${1}; shift;;
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
    [ -r "${DIRNAME}/motd.sh" ] && {
        try "cat ${DIRNAME}/motd.sh | ssh -p${port} ${ssh} 'cat >/etc/motd.sh'"
    }
    ssh_func "${ssh}" "${port}" centos_limits_init || true
    ssh_func "${ssh}" "${port}" centos_disable_selinux || true
    ssh_func "${ssh}" "${port}" centos_sshd_init || true
    ssh_func "${ssh}" "${port}" centos_disable_ipv6 || true
    ssh_func "${ssh}" "${port}" centos_service_init || true
    ssh_func "${ssh}" "${port}" centos_sysctl_init || true
    [ -z "${zramswap}" ] || ssh_func "${ssh}" "${port}" centos_zramswap_init ${zramswap}
    ssh_func "${ssh}" "${port}" "sed -i '/motd.sh/d' /etc/profile ; echo 'sh /etc/motd.sh' >> /etc/profile;touch /etc/logo.txt /etc/motd.sh" || true
    [ -z '${name}' ] || ssh_func "${ssh}" "${port}" "echo '${name}' > /etc/hostname"
    return 0
}
main "$@"
