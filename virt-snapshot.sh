#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
# KVM_USER=${KVM_USER:-root}
# KVM_HOST=${KVM_HOST:-127.0.0.1}
# KVM_PORT=${KVM_PORT:-60022}
VIRSH_OPT="-q ${KVM_HOST:+-c qemu+ssh://${KVM_USER:-root}@${KVM_HOST}:${KVM_PORT:-60022}/system}"
VIRSH="virsh ${VIRSH_OPT}"

declare -A APP_ERRORS=(
    [0]="success"
    [1]="domain not exist or not running"
)

snapshot_commit() {
    # blockcommit live merging snapshot into base image
    local uuid=${1}
    local target="$(try ${VIRSH} domblklist ${uuid} --details | awk '$2 ~ /disk/ {print $3}')"
    for t in $targets; do
        try ${VIRSH} blockcommit ${uuid} ${target} --active --verbose --pivot
        if [ $? -ne 0 ]; then
            error_msg "Could not merge changes for disk $t of ${uuid}. VM may be in invalid state."
            return 1
        fi
    done
    return 0
}

snapshot() {
    local uuid=${1}
    local val=$(try ${VIRSH} list --uuid --all --state-running)
    [[ -z $val ]] && return 1
    val="$(try ${VIRSH} domblklist ${uuid} --details)"
    local diskspec=
    while IFS=' ' read -r Type Device Target Source; do
        [[ "$Device"  == "cdrom" ]] && continue
        info_msg "Type=$Type Device=$Device Target=$Target Source=$Source\n"
        diskspec+=" --diskspec $Target,snapshot=external"
    done <<< $val
    #local target=$(awk '$2 ~ /disk/ && $1 !~ /file/ {print $3}' <<< $val)
    #local diskimg=$(awk '$2 ~ /disk/ && $1 !~ /file/ {print $4}' <<< $val)
    # add --no-metadata  virsh snapshot-list can not list the snapshot
    [[ -z ${diskspec+x} ]] || try ${VIRSH} snapshot-create-as --domain ${uuid} \
        --name snap-$(date +"%Y%m%d%H%M%S") --atomic --disk-only --no-metadata ${diskspec}
    #
    # virsh snapshot-create-as --domain xp-571028ab-1444-41ac-b95a-e45cebc468dd --name state1
    # virsh snapshot-list xp-571028ab-1444-41ac-b95a-e45cebc468dd
    # virsh snapshot-revert xp-571028ab-1444-41ac-b95a-e45cebc468dd state1

}
usage() {
cat <<EOF
${SCRIPTNAME} <arg>
    -u|--uuid <uuid>           *             domain uuid
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -V|--version                             display version and exit
    -h|--help                                display this help and exit
EOF
exit 1
}
main() {
    local uuid
    local opt_short="u:"
    local opt_long="uuid:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -u | --uuid)    shift; uuid=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; exit_msg "${SCRIPTNAME} version\n";;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              error_msg "Unexpected option: $1.\n"; usage;;
        esac
    done
    [[ -z ${uuid+x} ]] && usage
    snapshot "${uuid}"
    return 0
}
main "$@"
