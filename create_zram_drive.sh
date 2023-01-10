#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d246a1e[2022-07-18T15:32:57+08:00]:create_zram_drive.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
remove_zram() {
    local dev=${1}
    try zramctl -r "${dev}"
    info_msg "remove_zram: ${dev}\n"
}

create_zram() {
    local size=${1} #like zramctl size options
    local algo=${2:-lz4}
    [ ! -d "/sys/class/zram-control" ] && try modprobe zram
    local zram_dev=$(zramctl -f)
    try zramctl -a "${algo}" -s "${size}" ${zram_dev}
    # zram_dev=$(cat /sys/class/zram-control/hot_add)
    # echo -n "${algo}" > /sys/block/zram${zram_dev}/comp_algorithm || return 2
    # echo -n "${size}" > /sys/block/zram${zram_dev}/disksize || return 1
    # echo -n "${size}" > "/sys/block/zram${zram_dev}/mem_limit"
    info_msg "create_zram: ${zram_dev} size=${size}MiB, algo=${algo}\n"
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--create *   <int>  zram size MiB
        -a|--algo       <str>  zram compress algo
        -r|--remove  *  <dev>  zram dev
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local size="" algo="" dev=""
    local opt_short="c:a:r:"
    local opt_long="create:,algo:,remove:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --create)  shift; size=${1}; shift;;
            -a | --algo)    shift; algo=${1}; shift;;
            -r | --remove)  shift; dev=${1}; shift;;
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
    require zramctl
    [ -z "${size}" ] || create_zram "${size}" "${algo}" || true
    [ -z "${dev}" ] || remove_zram "${dev}" || true
    info_msg "ALL DONE\n"
    return 0
}
auto_su "$@"
main "$@"
