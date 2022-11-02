#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-11-02T09:07:08+08:00]:inst_kernel.sh")
################################################################################
SRC=${1:?inst_kernel.sh <src> <rootfs>, src need input}
ROOTFS=${2:?inst_kernel.sh <src> <rootfs>, rootfs need input}

export kerver=$(ls ${SRC}/usr/lib/modules 2>/dev/null | sort --version-sort -f | tail -n1)
# export kerver=$(ls ${SRC}/boot/vmlinuz* | grep -E -o '[0-9\.]*' | sort --version-sort -f | tail -n1)

[ -z "${kerver}" ] && { echo "src dir <${SRC}> struct error, see build.sh"; exit 1; }

rsync -avP ${SRC}/usr/lib/modules/${kerver} ${ROOTFS}/usr/lib/modules/

rsync -avP ${SRC}/boot/config-${kerver}  \
           ${SRC}/boot/System.map-${kerver} \
           ${SRC}/boot/vmlinuz-${kerver} \
           ${ROOTFS}/boot/

rsync -avP ${SRC}/boot/dtb/phicomm-n1-${kerver}.dtb ${ROOTFS}/boot/dtb/

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} /bin/bash <<EOSHELL
    depmod ${kerver}
    update-initramfs -c -k ${kerver}
    [ -e "/boot/extlinux/extlinux.conf" ] && {
        sed -i "s/\s*linux\s.*/    linux \/vmlinuz-${kerver}/g" /boot/extlinux/extlinux.conf
        sed -i "s/\s*initrd\s.*/    initrd \/initrd.img-${kerver}/g" /boot/extlinux/extlinux.conf
        sed -i "s/\s*fdt\s.*/    fdt \/dtb\/phicomm-n1-${kerver}.dtb/g" /boot/extlinux/extlinux.conf
    }
    [ -e "/boot/uEnv.ini" ] && {
        sed -i "s/\s*image\s*=.*/image=vmlinuz-${kerver}/g" /boot/uEnv.ini
        sed -i "s/\s*initrd\s*=.*/initrd=uInitrd-${kerver}/g" /boot/uEnv.ini
        sed -i "s/\s*dtb\s*=.*/dtb=\/dtb\/phicomm-n1-${kerver}.dtb/g" /boot/uEnv.ini
    }
    rm -f /boot/*.old
EOSHELL
