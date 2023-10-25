#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("ec7473b[2023-10-10T11:16:02+08:00]:virt-volupload.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
cat <<EOF
${SCRIPTNAME}
    -K|--kvmhost          <ipaddr>           kvm host address
    -U|--kvmuser          <str>              kvm host ssh user
    -P|--kvmport          <int>              kvm host ssh port
    --kvmpass             <password>         kvm host ssh password
    -p|--pool              *                 pool
    -v|--vol               *                 vol
    -t|--template                            telplate disk for upload(or stdin)
    --rbd             <ceph cluster name>    upload ceph rbd vol via ssh, otherwise use vol-upload
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit
    Example:
       ${SCRIPTNAME} -p default -v disk.raw -t tpl/linux.raw
EOF
exit 1
}

main() {
    local kvmhost="" kvmuser="" kvmport=""
    local disk_tpl= vol_name= pool= rbd=""
    local opt_short="K:U:P:p:v:t:"
    local opt_long="kvmhost:,kvmuser:,kvmport:,kvmpass:,pool:,vol:,template:,rbd:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -K | --kvmhost)  shift; kvmhost=${1}; shift;;
            -U | --kvmuser)  shift; kvmuser=${1}; shift;;
            -P | --kvmport)  shift; kvmport=${1}; shift;;
            --kvmpass)       shift; set_sshpass "${1}"; shift;;
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
    [ ! -z "${disk_tpl}" ] && [ ! -z "${vol_name}" ] && [ ! -z "${pool}" ] || usage "vol_name/tpl/pool must input"
    [ -r ${disk_tpl} ] || exit_msg "template file ${disk_tpl} no found\n"
    local upload_cmd="virsh_wrap '${kvmhost}' '${kvmport}' '${kvmuser}'"
    #stdin is redirect
    #[ -p /dev/stdin ] || { disk_tpl=/dev/stdin; upload_cmd="cat | ${VIRSH}"; }
    [[ -t 0 ]] || { disk_tpl=/dev/stdin; upload_cmd="cat | virsh_wrap '${kvmhost}' '${kvmport}' '${kvmuser}'"; }
    [[ -t 0 ]] || disk_tpl=/dev/stdin    #stdin is redirect
    info_msg "upload ${disk_tpl} start\n"
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" pool-start ${pool} 2>/dev/null || true
    [ -z ${rbd} ] && {
        try ${upload_cmd} vol-upload --pool ${pool} --vol ${vol_name} --file ${disk_tpl} || exit_msg "upload template file ${disk_tpl} error\n"
    } || {
        local ceph_rbd_pool=$(virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" pool-dumpxml ${pool} | xmlstarlet sel -t -v "/pool/source/name")
        local orgsize=$(${KVM_HOST:+ssh -p ${KVM_PORT:-60022} ${KVM_USER:-root}@${KVM_HOST}} rbd --cluster ${rbd} info --format xml ${ceph_rbd_pool}/${vol_name} | xmlstarlet sel -t -v "/image/size")
        try "${KVM_HOST:+ssh -p ${KVM_PORT:-60022} ${KVM_USER:-root}@${KVM_HOST}} rbd --cluster ${rbd} rm --no-progress --pool ${ceph_rbd_pool} ${vol_name} 2>/dev/null" || true
        try "cat ${disk_tpl} | ${KVM_HOST:+ssh -p ${KVM_PORT:-60022} ${KVM_USER:-root}@${KVM_HOST}} rbd --cluster ${rbd} import --image-feature layering - ${ceph_rbd_pool}/${vol_name}" || exit_msg "upload template file ${disk_tpl} via rbd error\n"
        info_msg "restore ${vol_name} size to  ${orgsize}"
        virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" vol-resize --pool ${pool} --vol ${vol_name} --capacity ${orgsize}
    }
    info_msg "upload template file ${disk_tpl} ok\n"
    return 0
}
main "$@"
