#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("3682f90[2023-06-01T12:49:54+08:00]:virt_start_domain.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
LOGFILE=""
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -K|--kvmhost    <ipaddr>  kvm host address
        -U|--kvmuser    <str>     kvm host ssh user
        -P|--kvmport    <int>     kvm host ssh port
        --kvmpass       <password>kvm host ssh password
        -u|--uuid    *  <uuid>    domain uuid
        --console                 console
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local kvmhost="" kvmuser="" kvmport="" kvmpass=""
    local uuid="" opts=()
    local opt_short="K:U:P:u:"
    local opt_long="kvmhost:,kvmuser:,kvmport:,kvmpass:,uuid:,console,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -K | --kvmhost) shift; kvmhost=${1}; shift;;
            -U | --kvmuser) shift; kvmuser=${1}; shift;;
            -P | --kvmport) shift; kvmport=${1}; shift;;
            --kvmpass)      shift; kvmpass=${1}; shift;;
            -u | --uuid)    shift; uuid="${1}"; shift;;
            --console)      shift; opts+=("--console");;
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
    [ -z "${uuid}" ] && usage "uuid must input"
    [ -z ${kvmpass} ]  || set_sshpass "${kvmpass}"
    set -- "${opts[@]}"
    exec virsh -q ${kvmhost:+-c qemu+ssh://${kvmuser:+${kvmuser}@}${kvmhost}${kvmport:+:${kvmport}}/system} start ${uuid} $@
    return 0
}
main "$@"
