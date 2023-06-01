#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("6c82f0b[2023-05-30T10:56:42+08:00]:virt_start_domain.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
VIRSH_OPT="-q ${KVM_HOST:+-c qemu+ssh://${KVM_USER:-root}@${KVM_HOST}:${KVM_PORT:-60022}/system}"
VIRSH="virsh ${VIRSH_OPT}"
LOGFILE=""
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
        KVM_HOST: default <not define, local>
        KVM_USER: default root
        KVM_PORT: default 60022
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
    local uuid="" opts=()
    local opt_short="u:"
    local opt_long="uuid:,console,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    set -- "${opts[@]}"
    exec ${VIRSH} start ${uuid} "$@"
    return 0
}
main "$@"
