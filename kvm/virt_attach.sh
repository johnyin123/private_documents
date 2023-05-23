#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("dd2dbea[2023-05-23T13:43:52+08:00]:virt_attach.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
VIRSH_OPT="-q ${KVM_HOST:+-c qemu+ssh://${KVM_USER:-root}@${KVM_HOST}:${KVM_PORT:-60022}/system}"
VIRSH="virsh ${VIRSH_OPT}"
LOGFILE=""
gen_tpl() {
    cat <<'EOF'
# disk tpl demo
<disk type='block' device='disk'>
  <driver name='qemu' type='raw' cache='none' io='native'/>
  <source dev='{{ store_path }}'/>
  <backingStore/>
  <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
  <blockio logical_block_size='4096' physical_block_size='4096'/>
</disk>
# net tpl demo
<interface type='network'>
  <source network='br_mgmt.2430'/>
  <model type='virtio'/>
  <driver name='vhost' queues='8'/>
</interface>
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -u|--uuid   *   <uuid>    vm uuid
        -t|--tpl    *   <file>    device tpl file
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    gen_tpl
    exit 1
}
set_last_disk() {
    local disks=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o")
    local uuid="$1"
    local last_disk=
    local xml=$(${VIRSH} dumpxml ${uuid} 2>/dev/null)
    [[ -z "${xml}" ]] && return 9
    for ((i=1;i<10;i++))
    do
        #last_disk=$(printf "$xml" | xmllint --xpath "string(/domain/devices/disk[$i]/target/@dev)" -)
        last_disk=$(printf "$xml" | xmlstarlet sel -t -v "/domain/devices/disk[$i]/target/@dev")
        [[ -z "${last_disk}" ]] && { echo "${disks[((i-1))]}" ; return 0; }
    done
    return 7
}
domain_live_arg() {
    local uuid=$1
    ${VIRSH} list --state-running --uuid | grep -q ${uuid} && echo "--live" || echo ""
}
main() {
    local tpl="" uuid=""
    local opt_short="t:u:"
    local opt_long="tpl:,uuid:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -u | --uuid)    shift; uuid="${1}"; shift;;
            -t | --tpl)     shift; tpl=${1}; shift;;
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
    require j2 xmlstarlet virsh
    defined QUIET || LOGFILE="-a /dev/stderr"
    [ -z "${uuid}" ] && usage "uuid must input"
    [ -z "${tpl}" ] && usage "tpl must input"
    local live=$(domain_live_arg "${uuid}")
    info_msg "${uuid}(${live:-shut off}) attach device\n"
    local last_disk=$(set_last_disk "${uuid}") || exit_msg "${uuid} get last disk ERROR\n"
    cat <<EOF | tee ${LOGFILE} | j2 --format=yaml ${tpl} | tee ${LOGFILE} | \
    ${VIRSH} attach-device --domain ${uuid} --file /dev/stdin --persistent ${live} || exit_msg "${uuid} attach ERROR\n"
vm_uuid: "${uuid}"
vm_last_disk: "${last_disk}"
EOF
    info_msg "${uuid} attach OK\n"
    return 0
}
main "$@"
