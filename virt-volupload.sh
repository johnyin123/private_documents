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
    local opt_short="ql:dVhp:v:t:"
    local opt_long="quite,log:,dryrun,version,help,pool:,vol:,template:"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage 1
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -p | --pool) pool=${2}; shift 2 ;;
            -v | --vol) vol_name=${2}; shift 2 ;;
            -t | --template) disk_tpl=${2}; shift 2 ;;
            -q | --quiet) QUIET=1; shift 1 ;;
            -l | --log) set_loglevel ${2}; shift 2 ;;
            -d | --dryrun) DRYRUN=1; shift 1 ;;
            -V | --version) exit_msg "${SCRIPTNAME} version\n" ;;
            -h | --help) shift 1; usage ;;
            --) shift 1; break ;;
            *)  error_msg "Unexpected option: $1.\n"; usage ;;
        esac
    done
    local upload_cmd=${VIRSH}
    #stdin is redirect 
    #[ -p /dev/stdin ] || { disk_tpl=/dev/stdin; upload_cmd="cat | ${VIRSH}"; }
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
