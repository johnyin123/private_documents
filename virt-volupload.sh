#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
KVM_USER=${KVM_USER:-root}
KVM_HOST=${KVM_HOST:-10.32.166.33}
KVM_PORT=${KVM_PORT:-60022}
VIRSH_OPT=${VIRSH_OPT:-"-c qemu+ssh://${KVM_USER}@${KVM_HOST}:${KVM_PORT}/system"}

VIRSH="virsh -q ${VIRSH_OPT}"

usage() {
cat <<EOF
${SCRIPTNAME} 
    -p|--pool              *                 pool
    -v|--vol               *                 vol
    -t|--template                            telplate disk for upload(or stdin)
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit
EOF
exit 1
}

main() {
    local disk_tpl=
    local vol_name=
    local pool=

    while test $# -gt 0
    do
        local opt="$1"
        shift
        case "${opt}" in
            -p|--pool)
                pool=${1:?disk pool need input};shift 1
                ;;
            -v|--vol)
                vol_name=${1:?vol name need input};shift 1
                ;;
            -t|--template)
                disk_tpl=${1:?disk template need input};shift 1
                ;;
            -q | --quiet)
                QUIET=1
                ;;
            -l | --log)
                set_loglevel ${1}; shift
                ;;
            -d | --dryrun)
                DRYRUN=1
                ;;
            -h | --help | *)
                usage
                ;;
        esac
    done
    local upload_cmd=${VIRSH}
    #stdin is redirect
    [[ -t 0 ]] || { disk_tpl=/dev/stdin; upload_cmd="cat | ${VIRSH}"; } 
    [[ -z "${disk_tpl}" ]] && usage
    [[ -z "${vol_name}" ]] && usage
    [[ -z "${pool}"     ]] && usage
    [ -r ${disk_tpl} ] || exit_msg "template file ${disk_tpl} no found\n"
    [[ -t 0 ]] || disk_tpl=/dev/stdin    #stdin is redirect
    info_msg "upload ${disk_tpl} start\n" 
    try ${upload_cmd} vol-upload --pool ${pool} --vol ${vol_name} --file ${disk_tpl} || exit_msg "upload template file ${disk_tpl} error\n" 
    info_msg "upload template file ${disk_tpl} ok\n" 
    return 0
}
main "$@"
