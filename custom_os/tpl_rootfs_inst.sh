#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("1963ca3[2023-02-03T12:47:56+08:00]:tpl_rootfs_inst.sh")
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -t|--tpl  *   <str>   root squashfs(tpl) for install
        --uefi        <str>   uefi partition(fat32), /dev/vda1
                              uefi partition type fat32, boot flag on.
                        parted -s /dev/vda "mklabel gpt"
                        parted -s /dev/vda "mkpart primary fat32 1M 128M"
                        parted -s /dev/vda "mkpart primary xfs 128M 100%"
                        parted -s /dev/vda "set 1 boot on"
        -d|--disk *   <str>   disk, /dev/sdX
        -p|--part *   <str>   install tpl in partition as rootfs, /dev/vda1, /dev/mapper/..
        --fs          <fstype> ext4/xfs, default xfs
                        initramfs include the right module!!
                        debian: echo "ext4" >> /etc/initramfs-tools/modules
                                update-initramfs -c -k \$(uname -r)
                        centos: dracut -f --kver \$(uname -r) --filesystems xfs --filesystems ext4
        -V|--version          version info
        -h|--help             help
        Exam:
           ${SCRIPTNAME} -t /mnt/bullseye.1122.tpl --uefi /dev/vda1 -d /dev/vda -p 2
           ${SCRIPTNAME} -t /mnt/bullseye.1122.tpl -d /dev/vda -p 1
        Exam:
           truncate -s 4G disk.img
           parted -s disk.img "mklabel msdos"
           parted -s disk.img "mkpart primary xfs 1M 100%"
           ./nbd_attach.sh -a disk.img --fmt raw
           .${SCRIPTNAME} -t tpl.tpl -d /dev/nbd0 -p 1
           ./nbd_attach.sh -d /dev/nbd0
EOF
    exit 1
}
main() {
    local root_tpl="" disk="" part="" uefi="" fs="xfs"
    local opt_short+="t:d:p:xvh"
    local opt_long+="tpl:,disk:,part:,uefi:,fs:,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -t | --tpl)       shift; root_tpl=${1}; shift;;
            -d | --disk)      shift; disk=${1}; shift;;
            -p | --part)      shift; part=${1}; shift;;
            --uefi)           shift; uefi=${1}; shift;;
            --fs)             shift; fs=${1}; shift;;
            -V | --version)   shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)      shift; usage;;
            --)               shift; break;;
            *)                usage "Unexpected option: $1";;
        esac
    done
    [ -z "${root_tpl}" ] && usage "tpl rootfs package?"
    [ -z "${disk}" ] && usage "need disk and  partition?"
    echo "install ${root_tpl} => ${disk}:${part}"
    local work_dir=$(mktemp -d /tmp/squashfs.XXXXXX)
    mount ${root_tpl} ${work_dir} || true
    for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do
        mount -o bind $i "${work_dir}${i}" 2>/dev/null && echo "mount work $i ...." || true
    done
    local target="i386-pc"
    # [ -d "/sys/firmware/efi" ]
    [ -z "${uefi}" ] || {
        [ -d "/sys/firmware/efi" ] || echo "HOST EFI FIREWARE NO FOUND!!, CONTINUE."
        echo "install UEFI ${uefi}"
        target="x86_64-efi"
        mkfs.vfat -F 32 ${uefi} # need chroot ?
    }
    case "${fs}" in
        ext4) chroot ${work_dir} /sbin/mkfs.ext4 -F -L rootfs "${part}";;
        xfs)  chroot ${work_dir} /sbin/mkfs.xfs -f -L rootfs "${part}";;
        *)    umount -R -v ${work_dir} || true; echo "fstype not support"; exit 1;;
    esac
    umount -R -v ${work_dir} || true
    # xfs_admin -O bigtime=1 device # no work some version xfsprogs
    # xfs_repair -c bigtime=1 device
    local root_dir=$(mktemp -d /tmp/rootfs.XXXXXX)
    mount "${part}" ${root_dir}
    [ -z "${uefi}" ] || {
        mkdir -p ${root_dir}/boot/efi
        mount ${uefi} ${root_dir}/boot/efi
    }
    unsquashfs -f -d ${root_dir} ${root_tpl}
    for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do
        mount -o bind $i "${root_dir}${i}" 2>/dev/null && echo "mount root $i ...." || true
    done
    source ${root_dir}/etc/os-release
    # if no initrd can use kernel-install (in systemd package)
    # kernel-install add  3.10.0-693.21.1.el7.x86_64 /boot/vmlinuz-3.10.0-693.21.1.el7.x86_64
    LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash -x -o errexit -s <<EOSHELL
case "${ID}" in
    debian)
        grub-install --target=${target} --boot-directory=/boot --modules="xfs part_msdos" ${disk} || true
        grub-mkconfig -o /boot/grub/grub.cfg || true
        ;;
    centos|rocky|openEuler|*)
        echo "rocky9 & openeuler22, when uefi grub2-install bug https://bugzilla.redhat.com/show_bug.cgi?id=1917213"
        [ -z "${uefi}" ] && {
            grub2-install --target=${target} --boot-directory=/boot --modules="xfs part_msdos" ${disk} || true
            grub2-mkconfig -o /boot/grub2/grub.cfg || true
        } || {
            efibootmgr --create --remove-dups --disk ${disk} --part ${uefi: -1} --label "${ID} Linux" || true
            grub2-mkconfig -o /boot/efi/EFI/${ID}/grub.cfg || true
        }
        ;;
esac
exit 0
EOSHELL
    local new_uuid=$(blkid -s UUID -o value ${part})
    cat ${root_dir}/etc/fstab > ${root_dir}/etc/fstab.orig || true
    {
        echo "# $(date '+%Y-%m-%d %H:%M:%S')"
        echo "UUID=${new_uuid} / ${fs} noatime,relatime 0 0"
        [ -z "${uefi}" ] || {
            echo "UUID=$(blkid -s UUID -o value ${uefi}) /boot/efi vfat umask=0077 0 1"
        }
        grep -Ev "\s/\s|\/boot\/efi" ${root_dir}/etc/fstab.orig || true
    }  | tee ${root_dir}/etc/fstab
    umount -R -v ${root_dir} || true
    echo "ALL DONE OK"
}
main "$@"
