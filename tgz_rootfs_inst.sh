#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("bc91265[2023-01-04T16:44:25+08:00]:tgz_rootfs_inst.sh")
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -t|--tgz  *   <str>   root tar.gz(tgz) for install
        --uefi        <str>   uefi partition(fat32), /dev/vda1
                              uefi partition type fat32, boot flag on.
                        parted -s /dev/vda "mklabel gpt"
                        parted -s /dev/vda "mkpart primary fat32 1M 128M"
                        parted -s /dev/vda "mkpart primary xfs 128M 100%"
                        parted -s /dev/vda "set 1 boot on"
        -d|--disk *   <str>   disk, /dev/sdX
        -p|--part *   <str>   install tgz in partition as rootfs, /dev/vda1, /dev/mapper/..
        -x | --xfsfix         disable xfs v5 feature!! for support kernel below 3.16
        -V|--version          version info
        -h|--help             help
        Exam:
           ${SCRIPTNAME} -t /mnt/bullseye.1122.tar.gz --uefi /dev/vda1 -d /dev/vda -p 2
           ${SCRIPTNAME} -t /mnt/bullseye.1122.tar.gz -d /dev/vda -p 1
        Exam:
           truncate -s 4G disk.img
           parted -s disk.img "mklabel gpt"
           parted -s disk.img "mkpart primary xfs 1M 100%"
           ./nbd_attach.sh -a disk.img --fmt raw
           .${SCRIPTNAME} -t tpl.tgz -d /dev/nbd0 -p 1
           ./nbd_attach.sh -d /dev/nbd0
EOF
    exit 1
}
main() {
    local root_tgz="" disk="" part="" xfsfix="" uefi=""
    local opt_short+="t:d:p:xvh"
    local opt_long+="tgz:,disk:,part:,xfsfix,uefi:,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -t | --tgz)       shift; root_tgz=${1}; shift;;
            -d | --disk)      shift; disk=${1}; shift;;
            -p | --part)      shift; part=${1}; shift;;
            --uefi)           shift; uefi=${1}; shift;;
            -x | --xfsfix)    shift; xfsfix=1;;
            -V | --version)   shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)      shift; usage;;
            --)               shift; break;;
            *)                usage "Unexpected option: $1";;
        esac
    done
    [ -z "${root_tgz}" ] && usage "tgz rootfs package?"
    [ -z "${disk}" ] && usage "need disk and  partition?"
    echo "install ${root_tgz} => ${disk}:${part}"
    local target="i386-pc"
    # [ -d "/sys/firmware/efi" ]
    [ -z "${uefi}" ] || {
        [ -d "/sys/firmware/efi" ] || echo "HOST EFI FIREWARE NO FOUND!!, CONTINUE."
        echo "install UEFI ${uefi}"
        target="x86_64-efi"
        mkfs.vfat -F 32 ${uefi}
    }
    local root_dir=$(mktemp -d /tmp/rootfs.XXXXXX)
    mkfs.xfs -f -L rootfs ${xfsfix:+-m reflink=0 -m crc=0} "${part}"
    # xfs_admin -O bigtime=1 device # no work some version xfsprogs
    # xfs_repair -c bigtime=1 device
    mount "${part}" ${root_dir}
    tar -C ${root_dir} -xvf ${root_tgz}
    for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do
        mount -o bind $i "${root_dir}${i}" 2>/dev/null && echo "mount $i ...." || true
    done
    [ -z "${uefi}" ] || {
        mkdir -p ${root_dir}/boot/efi
        mount ${uefi} ${root_dir}/boot/efi
    }
    source ${root_dir}/etc/os-release
    LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash -x -o errexit -s <<EOSHELL
case "${ID}" in
    debian)
        grub-install --target=${target} --boot-directory=/boot --modules="xfs part_msdos" ${disk} || true
        grub-mkconfig -o /boot/grub/grub.cfg || true
        ;;
    centos|rocky|*)
        grub2-install --target=${target} --boot-directory=/boot --modules="xfs part_msdos" ${disk} || true
        grub2-mkconfig -o /boot/grub2/grub.cfg || true
        ;;
esac
exit 0
EOSHELL
    local new_uuid=$(blkid -s UUID -o value ${part})
    cat ${root_dir}/etc/fstab > ${root_dir}/etc/fstab.orig || true
    {
        echo "# $(date '+%Y-%m-%d %H:%M:%S')"
        echo "UUID=${new_uuid} / xfs noatime,relatime 0 0"
        [ -z "${uefi}" ] || {
            echo "UUID=$(blkid -s UUID -o value ${uefi}) /boot/efi vfat umask=0077 0 1"
        }
        grep -Ev "\s/\s|\/boot\/efi" ${root_dir}/etc/fstab.orig || true
    }  | tee ${root_dir}/etc/fstab
    umount -R -v ${root_dir} || true
    echo "ALL DONE OK"
}
main "$@"
