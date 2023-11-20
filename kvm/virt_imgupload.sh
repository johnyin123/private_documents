#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("262fa90[2023-11-20T10:31:23+08:00]:virt_imgupload.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
    -K|--kvmhost          <ipaddr>           kvm host address
    -U|--kvmuser          <str>              kvm host ssh user
    -P|--kvmport          <int>              kvm host ssh port
    --kvmpass             <password>         kvm host ssh password
    -v|--vol               *                 vol
    -t|--template                            telplate disk for upload(or stdin)
    --rbd             <ceph cluster name>    upload ceph rbd vol via ssh, otherwise use vol-upload
    --size                <vol size>         1M/1G/1T
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit
    Example:
       ${SCRIPTNAME} -t tpl/linux.raw -v /storage/disk.raw
       ${SCRIPTNAME} --rbd ceph -t tpl/linux.raw -v libvirt-pool/disk.raw
EOF
exit 1
}

main() {
    local kvmhost="" kvmuser="" kvmport=""
    local disk_tpl="" vol_name="" rbd=""
    local opt_short="K:U:P:v:t:"
    local opt_long="kvmhost:,kvmuser:,kvmport:,kvmpass:,vol:,template:,rbd:,size:,"
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
            -t | --template) shift; disk_tpl=${1}; shift ;;
            -v | --vol)      shift; vol_name=${1}; shift ;;
            --rbd)           shift; rbd=${1}; shift;;
            --size)          shift; size=${1}; shift;;
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
    [[ -t 0 ]] || disk_tpl=/dev/stdin    #stdin is redirect
    [ -z "${disk_tpl}" ] && usage "disk_tpl must input"
    [ -z "${vol_name}" ] && usage "vol_name must input"
    info_msg "upload ${disk_tpl} => ${vol_name} start\n"
    local upload_cmd="dd of=${vol_name}${size:+;truncate -s ${size} ${vol_name}}"
    [ -z ${rbd} ] || upload_cmd="rbd --cluster ${rbd} import --image-feature layering - ${vol_name}${size:+;rbd --cluster ${rbd} resize --size ${size} ${vol_name} --no-progress}"
    try "cat ${disk_tpl} | ${kvmhost:+ssh ${kvmport:+-p ${kvmport}} ${kvmuser:+${kvmuser}@}${kvmhost}} ${upload_cmd}"
    info_msg "upload template file ${disk_tpl} ok\n"
    return 0
}
main "$@"
