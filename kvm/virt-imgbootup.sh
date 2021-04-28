#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("virt-imgbootup.sh - initversion - 2021-04-28T09:07:50+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--cpu    <int>     number of cpus (default 1)
        -m|--mem    <int>     mem size MB (default 2048)
        -D|--disk   <file> *  disk image
        -b|--bridge <br>   *  host net bridge
        -f|--fmt    <fmt>     disk image format(default raw)
        --cdrom     <iso>     iso file
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local cpu=1 mem=2048 disk= bridge= fmt=raw cdrom=
    local opt_short="c:m:D:b:f:"
    local opt_long="cpu:,mem:,disk:,bridge:,fmt:,cdrom:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --cpu)     shift; cpu=${1}; shift;;
            -m | --mem)     shift; mem=${1}; shift;;
            -D | --disk)    shift; disk=${1}; shift;;
            -b | --bridge)  shift; bridge=${1}; shift;;
            -f | --fmt)     shift; fmt=${1}; shift;;
            --cdrom)        shift; cdrom=${1}; shift;;
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
    is_user_root || exit_msg "root need\n"
    [ -z ${disk} ] && usage "disk image ?"
    [ -z ${bridge} ] &&  usage "bridge network ?"
    file_exists "${disk}" || usage "disk nofound"
    bridge_exists "${bridge}" || usage "bridge nofound"

    directory_exists /etc/qemu/ || try mkdir -p /etc/qemu/
    grep "\s*allow\s*all" /etc/qemu/bridge.conf || {
        try "echo 'allow all' >> /etc/qemu/bridge.conf"
        try chmod 640 /etc/qemu/bridge.conf
    }

    try qemu-system-x86_64 -enable-kvm -cpu kvm64 -smp ${cpu} -m ${mem} \
        ${cdrom:+-cdrom ${cdrom} -boot menu=on} \
        -drive file=${disk},index=0,cache=none,aio=threads,if=virtio,format=${fmt} \
        -netdev bridge,br=${bridge},id=net0 -device virtio-net-pci,netdev=net0
    return 0
}
main "$@"
