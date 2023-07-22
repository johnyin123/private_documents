#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("75f9bf7[2023-04-27T08:47:38+08:00]:nbd_attach.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################

disconnect_nbd() {
    local dev=${1}
    kpartx -dvs ${dev} 
    qemu-nbd -d ${dev} 2>/dev/null || true
}

connect_nbd() {
    local image=${1}
    local fmt=${2:-}
    local dev=
    [ -b /dev/nbd0 ] || modprobe nbd max_part=16 || return 1
    for i in {0..15} ; do
        [ -b /dev/nbd${i} ] && {
            [ $(cat /sys/block/nbd${i}/size) -gt 0 ] && continue
            qemu-nbd ${fmt:+-f ${fmt} }-c /dev/nbd${i} ${image} && {
                dev=/dev/nbd${i}
                kpartx -avs ${dev} 2>&1
                # blkid -o udev ${dev}
                echo "Connected ${image} to ${dev}"
                return 0
            }
            blkid -o udev /dev/nbd${i} >/dev/null 2>&1 || true
            qemu-nbd -d /dev/nbd${i} >/dev/null 2>&1
        }
    done
    return 2
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -a         * <str>    attach nbd image.
        -f|--fmt     <str>    nbd image format, default auto guess. 
        -d        *  <str>    dettach nbd device.
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
      ./${SCRIPTNAME} -a disk.img -f raw
      ./${SCRIPTNAME} -a disk.qcow2 
      ./${SCRIPTNAME} -d /dev/nbd0
      -----
        truncate -s 2GiB disk.img
        parted -s disk.img -- \\
              mklabel gpt \\
              mkpart primary fat32 1M 128M \\
              mkpart primary xfs 128M 100% \\
              set 1 boot on
        DEV=\$(kpartx -avs disk.img | grep -o "/dev/loop[1234567890]*" | tail -1)
        # DEV=\$(losetup -f --show disk.img --offset=\$((2048 * 512)))
        mkfs.xfs "\${DEV}"
        mount -o offset=\$((2048*512)) disk.img mnt_point
        umount -R mnt_point
        kpartx -dsv disk.img
        # loset -D ..
EOF
    exit 1
}
main() {
    local img= fmt= dev=
    local opt_short="a:f:d:"
    local opt_long="fmt:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -a)             shift; img=${1}; shift;;
            -d)             shift; dev=${1}; shift;;
            -f | --fmt)     shift; fmt=${1}; shift;;
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
    [ -z "${img}" ] && [ -z "${dev}" ] && usage "img/dev ?"
    [ -z "${img}" ] || {
        connect_nbd "${img}" "${fmt}" || echo "$?, ERROR Connect nbd device"
        return 0
    }
    # # mount /dev/mapper/nbd0p3 ~/drive_c/
    # /usr/bin/env -i \
    #     SHELL=/bin/bash \
    #     TERM=${TERM:-} \
    #     HISTFILE= \
    #     PS1="${dev}#" \
    #     /bin/bash --noprofile --norc -o vi || true
    [ -z "${dev}" ] || {
        [ -b ${dev} ] && ps -ef | grep qemu-nbd | grep "${dev}" &>/dev/null && {
            disconnect_nbd "${dev}"
            return 0
        }
        echo "${dev} no found or qemu-nbd process no found, force disconnect it!"
        disconnect_nbd "${dev}"
        return 1
    }
    return 0
}
auto_su "$@"
main "$@"
