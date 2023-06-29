#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("da5c6d3[2023-06-01T12:51:03+08:00]:virt-volupload.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
# KVM_USER=${KVM_USER:-root}
# KVM_HOST=${KVM_HOST:-127.0.0.1}
# KVM_PORT=${KVM_PORT:-60022}
VIRSH_OPT="-q ${KVM_HOST:+-c qemu+ssh://${KVM_USER:-root}@${KVM_HOST}:${KVM_PORT:-60022}/system}"
VIRSH="virsh ${VIRSH_OPT}"

usage() {
    [ "$#" != 0 ] && echo "$*"
cat <<EOF
${SCRIPTNAME}
     env:
        KVM_HOST: default <not define, local>
        KVM_USER: default root
        KVM_PORT: default 60022
    -p|--pool              *                 pool
    -v|--vol               *                 vol
    -t|--template                            telplate disk for upload(or stdin)
    --rbd             <ceph cluster name>    upload ceph rbd vol via ssh, otherwise use vol-upload
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit
    Example:
       KVM_HOST=127.0.0.1 ${SCRIPTNAME} -p default -v disk.raw -t tpl/linux.raw
EOF
exit 1
}

main() {
    local disk_tpl=
    local vol_name=
    local pool=
    local rbd=""
    local opt_short="p:v:t:"
    local opt_long="pool:,vol:,template:,rbd:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -p | --pool)     shift; pool=${1}; shift ;;
            -v | --vol)      shift; vol_name=${1}; shift ;;
            -t | --template) shift; disk_tpl=${1}; shift ;;
            --rbd)           shift; rbd=${1}; shift;;
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
    local upload_cmd=${VIRSH}
    #stdin is redirect
    #[ -p /dev/stdin ] || { disk_tpl=/dev/stdin; upload_cmd="cat | ${VIRSH}"; }
    [[ -t 0 ]] || { disk_tpl=/dev/stdin; upload_cmd="cat | ${VIRSH}"; }
    [ ! -z "${disk_tpl}" ] && [ ! -z "${vol_name}" ] && [ ! -z "${pool}" ] || usage "vol_name/tpl/pool must input"
    [ -r ${disk_tpl} ] || exit_msg "template file ${disk_tpl} no found\n"
    [[ -t 0 ]] || disk_tpl=/dev/stdin    #stdin is redirect
    info_msg "upload ${disk_tpl} start\n"
    [ -z ${rbd} ] && {
        try ${upload_cmd} vol-upload --pool ${pool} --vol ${vol_name} --file ${disk_tpl} || exit_msg "upload template file ${disk_tpl} error\n"
    } || {
        local ceph_rbd_pool=$(${VIRSH} pool-dumpxml ${pool} | xmlstarlet sel -t -v "/pool/source/name")
        try "${KVM_HOST:+ssh -p ${KVM_PORT:-60022} ${KVM_USER:-root}@${KVM_HOST}} rbd --cluster ${rbd} rm --no-progress --pool ${ceph_rbd_pool} ${vol_name} 2>/dev/null" || true
        try "cat ${disk_tpl} | ${KVM_HOST:+ssh -p ${KVM_PORT:-60022} ${KVM_USER:-root}@${KVM_HOST}} rbd --cluster ${rbd} import --image-feature layering - ${ceph_rbd_pool}/${vol_name}" || exit_msg "upload template file ${disk_tpl} via rbd error\n"
    }
    info_msg "upload template file ${disk_tpl} ok\n"
    return 0
}
main "$@"
