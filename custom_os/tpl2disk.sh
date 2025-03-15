#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("ba30695b[2023-09-19T14:12:10+08:00]:tpl2disk.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
    TODO: xfs chroot env, cannot set blocksize 512 on block device ..: Function not implemented
          debian tpl arm64 uefi no support
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
           # parted -s disk.img "mklabel gpt"
           # parted -s disk.img "mkpart primary fat32 1M 128M"
           parted -s disk.img "mkpart primary ext4 1M 100%"
           parted -s disk.img "set 1 boot on"
           ./nbd_attach.sh -a disk.img --fmt raw
           ./${SCRIPTNAME} -t tpl.tpl -d /dev/nbd0 --uefi /dev/mapper/nbd0p1 -p /dev/mapper/nbd0p2 --fs ext4
           ./nbd_attach.sh -d /dev/nbd0
EOF
    exit 1
}

mkdiskfs() {
    local root_tpl=${1}
    local part=${2}
    local fs=${3}
    local work_dir=$(mktemp -d /tmp/squashfs.XXXXXX)
    mount ${root_tpl} ${work_dir} || true
    for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do
        mount -o bind $i "${work_dir}${i}" 2>/dev/null && echo "mount work $i ...." || true
    done
    case "${fs}" in
        ext4) LC_ALL=C LANGUAGE=C LANG=C chroot ${work_dir} /sbin/mkfs.ext4 -F -L rootfs "${part}";;
        xfs)  LC_ALL=C LANGUAGE=C LANG=C chroot ${work_dir} /sbin/mkfs.xfs -f -L rootfs "${part}";;
        *)    umount -R -v ${work_dir} || true; echo "ERROR: ** fstype not support"; return 1;;
    esac
    umount -R -v ${work_dir} || true
    return 0
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
    mkdiskfs "${root_tpl}" "${part}" "${fs}" || return 2
    local root_dir=$(mktemp -d /tmp/rootfs.XXXXXX)
    mount "${part}" ${root_dir}
    [ -z "${uefi}" ] || {
        mkfs.vfat -F 32 ${uefi} || return 1
        mkdir -p ${root_dir}/boot/efi
        mount ${uefi} ${root_dir}/boot/efi
    }
    unsquashfs -f -d ${root_dir} ${root_tpl} || {
        umount -R -v ${root_dir} || true
        echo "********************rootfs ERROR*********************"
        return 1
    }
    source ${root_dir}/etc/os-release || true
    mount -v -t devtmpfs -o mode=0755,nosuid devtmpfs ${root_dir}/dev || true
    mount -v -t devpts -o gid=5,mode=620 devpts ${root_dir}/dev/pts || true
    mount -v -t proc none ${root_dir}/proc || true
    # not mount sysfs, otherwise grub menu will include host system os entry!!
    # mount -v -t sysfs none ${root_dir}/sys || true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash -x -o errexit -s <<EOSHELL
target="i386-pc"
[ -z "${uefi}" ] || {
    echo "fake efivars"
    mkdir -p /sys/firmware/efi/efivars || true
    mkdir -p /sys/firmware/efi/vars || true
    case "\$(uname -m)" in
        aarch64)  target="arm64-efi";;
        x86_64)   target="x86_64-efi";;
        *)        target=""; echo "UEFI ARCH NOT AUTO FOUND!!!!!, CONTINUE.";;
    esac
}
case "${ID:-}" in
    debian)
        grub-install --force \${target:+--target=\${target}} --boot-directory=/boot --modules="xfs part_msdos" ${disk} 2>/dev/null || true
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        [ -z "${uefi}" ] || {
            echo "Copying fallback bootloader"
            mkdir /boot/efi/EFI/BOOT || true
            cp /boot/efi/EFI/${ID:-}/fbx64.efi /boot/efi/EFI/BOOT/bootx64.efi 2>/dev/null || true
            cp /boot/efi/EFI/${ID:-}/fbaa64.efi /boot/efi/EFI/BOOT/bootaa64.efi 2>/dev/null || true
        }
        ;;
    centos|rocky|openEuler|anolis|kylin|*)
        echo "rocky9 & openeuler22, when uefi grub2-install bug https://bugzilla.redhat.com/show_bug.cgi?id=1917213"
        [ -z "${uefi}" ] && {
            grub2-install \${target:+--target=\${target}} --boot-directory=/boot --modules="xfs part_msdos" ${disk} 2>/dev/null || true
            grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
        } || {
            # uefi no need efibootmgr --create ......
            grub2-mkconfig -o /boot/efi/EFI/${ID:-}/grub.cfg 2>/dev/null || true
        }
        ;;
esac
[ -z "${uefi}" ] || {
    echo "remove fake efivars"
    rm -rf /sys/firmware || true
}
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
auto_su "$@"
main "$@"
