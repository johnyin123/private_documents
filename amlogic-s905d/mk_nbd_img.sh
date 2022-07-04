#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-07-04T11:10:55+08:00]:mk_nbd_img.sh")
# [ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
NBD_DEV=
LABEL=${LABEL:-rootfs}
trap cleanup EXIT TERM INT
cleanup() {
    [ -z "${NBD_DEV}" ] || qemu-nbd -d ${NBD_DEV}
    echo "Exit!"
}
prepare_disk_img() {
    local image=${1}
    local size=${2}
    local fmt=${3}
    local i=""
    qemu-img create -f ${fmt} ${image} ${size}
    modprobe nbd max_part=16 || return 1
    for i in /dev/nbd*; do
        qemu-nbd -f ${fmt} -c $i ${image} && { NBD_DEV=$i; break; }
    done
    [ "${NBD_DEV}" == "" ] && return 2
    echo "Connected ${image} to ${NBD_DEV}"
    parted -s "${NBD_DEV}" "mklabel msdos"
    # parted -s "${NBD_DEV}" "mkpart primary fat32 1MiB 65MiB"
    parted -s "${NBD_DEV}" "mkpart primary ext4 1MiB 100%"
    echo "Format the partitions."
    # mkfs.vfat -n ${BOOT_LABEL} ${PART_BOOT}
    # mkswap -L EMMCSWAP "${PART_SWAP}"
    mkfs -t ext4 -m 0 -L "${LABEL}" ${NBD_DEV}p1
}

main() {
    local image=${1:-nbdroot.qcow2} size=${2:-4G} fmt=qcow2
    prepare_disk_img ${image} ${size} ${fmt} || echo "ERROR: prepare_disk_img return = $?"
    /usr/bin/env -i \
        SHELL=/bin/bash \
        HISTFILE= \
        PS1="${NBD_DEV} #" \
        /bin/bash --noprofile --norc -o vi || true
    return 0
}
main "$@"
