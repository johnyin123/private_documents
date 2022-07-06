#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-07-06T08:52:01+08:00]:mount_img.sh")
################################################################################
NBD_DEV=""

disconnect_nbd() {
    [ -z "${NBD_DEV}" ] || {
        kpartx -dvs ${NBD_DEV} 
        qemu-nbd -d ${NBD_DEV} 2>/dev/null || true
    }
}

connect_nbd() {
    local image=${1}
    local fmt=${2:-}
    local i=
    [ -b /dev/nbd0 ] || modprobe nbd max_part=16 || return 1
    for i in {0..15} ; do
        [ -b /dev/nbd${i} ] && {
            qemu-nbd ${fmt:+-f ${fmt} }-c /dev/nbd${i} ${image} && {
                NBD_DEV=/dev/nbd${i}
                kpartx -avs ${NBD_DEV}
                # blkid -o udev ${NBD_DEV}
                echo "Connected ${image} to ${NBD_DEV}"
                return 0
            }
            qemu-nbd -d /dev/nbd${i} >/dev/null 2>&1
        }
    done
    return 2
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -f|--image * <str>    nbd image name, default nbdroot.qcow2
        --fmt        <str>    nbd image format, default qcow2
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local image= fmt=
    local opt_short="f:"
    local opt_long="image:,fmt:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -f | --image)   shift; image=${1}; shift;;
            --fmt)          shift; fmt=${1}; shift;;
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
    [ -z "${image}" ] && usage "image ?"
    connect_nbd "${image}" "${fmt}"
    # mount /dev/mapper/nbd0p3 ~/drive_c/
    /usr/bin/env -i \
        SHELL=/bin/bash \
        TERM=${TERM:-} \
        HISTFILE= \
        PS1="${NBD_DEV}#" \
        /bin/bash --noprofile --norc -o vi || true
    disconnect_nbd
    return 0
}
main "$@"
