#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("tgz_rootfs_inst.sh - 060cbc4 - 2021-08-24T12:47:56+08:00")
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -t|--tgz         *    root tar.gz(tgz) for install
        -d|--disk        *    disk, /dev/sdX
        -p|--part             install tgz in this <DISK> part as rootfs
                              default 1
        -V|--version          version info
        -h|--help             help
EOF
    exit 1
}
main() {
    local root_tgz= disk= partition=1
    local opt_short+="t:d:p:vh"
    local opt_long+="tgz:,disk:,part:,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -t | --tgz)       shift; root_tgz=${1}; shift;;
            -d | --disk)      shift; disk=${1}; shift;;
            -p | --part)      shift; part=${1}; shift;;
            -V | --version)   shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)      shift; usage;;
            --)               shift; break;;
            *)                usage "Unexpected option: $1";;
        esac
    done
    [ -z "${root_tgz}" ] && usage "tgz rootfs package?"
    [ -z "${disk}" ] && usage "need disk and  partition?"
    echo "install ${root_tgz} => ${disk}${part}"
    local root_dir=$(mktemp -d /tmp/rootfs.XXXXXX)
    mkfs.xfs -f -L rootfs "${disk}${part}"
    mount "${disk}${part}" ${root_dir}
    tar -C ${root_dir} -xvf ${root_tgz}
    [ -d "${root_dir}/sys" ] && mount -o bind /sys ${root_dir}/sys
    [ -d "${root_dir}/proc" ] && mount -o bind /proc ${root_dir}/proc
    [ -d "${root_dir}/dev" ] && mount -o bind /dev ${root_dir}/dev
    LC_ALL=C LANGUAGE=C LANG=C chroot ${root_dir} /bin/bash <<EOSHELL
source /etc/os-release
case "${ID}" in
    debian)
        grub-install --target=i386-pc --boot-directory=/boot --modules="xfs part_msdos" ${disk}
        grub-mkconfig -o /boot/grub/grub.cfg
        ;;
    centos)
        grub2-install --target=i386-pc --boot-directory=/boot --modules="xfs part_msdos" ${disk}
        grub2-mkconfig -o /boot/grub2/grub.cfg
        ;;
esac
EOSHELL
    local new_uuid=$(blkid -s UUID -o value ${disk$}${part})
    echo "UUID=${new_uuid} / xfs noatime 0 0" > ${root_dir}/etc/fstab
    umount ${root_dir}/sys ${root_dir}/proc ${root_dir}/dev || true
    umount ${root_dir} || true
}
main "$@"

