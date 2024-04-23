#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2024-04-23T08:53:53+08:00]:dir_overlay.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -t|--tpl     *   <str>   root dir 
        -r|--rootfs  **  <str>   new rootfs directory
        -u            *          umount overlay rootfs
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local tpl="" rootfs="" umount=""
    local opt_short="t:r:u"
    local opt_long="tpl:,rootfs:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -t | --tpl)     shift; tpl=${1}; shift;;
            -r | --rootfs)  shift; rootfs=${1}; shift;;
            -u)             shift; umount=1;;
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
    [ -z "${umount}" ] || [ -z "${rootfs}" ] || {
        cleanup_overlayfs "${rootfs}"
        return 0
    }
    [ -z "${rootfs}" ] || [ -z "${tpl}" ] || {
        setup_overlayfs "${tpl}" "${rootfs}"
        info_msg "mount ${tpl} on ${rootfs}\n"
    }
    return 0
}
auto_su "$@"
main "$@"
