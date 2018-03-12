#!/bin/bash
set -o errexit -o nounset -o pipefail

function mychroot() {
    CHROOT=$1
    echo $CHROOT
    shift
    if [ "$CHROOT" == "" ]; then
        echo "invalid usage"
        exit 1
    fi
    mount -o bind /proc $CHROOT/proc
    mount -o bind /dev $CHROOT/dev
    mount -o bind /sys $CHROOT/sys
    chroot $CHROOT "$@"
    RESULT=$?
    umount $CHROOT/sys
    umount $CHROOT/dev
    umount $CHROOT/proc
    return $RESULT
}

ROOTFS=${ROOTFS:-/root/rootfs}
mkdir -p ${ROOTFS}
CENTOS=$(yumdownloader centos-release --urls | tail -1)
yum -y --installroot=${ROOTFS} install ${CENTOS}
# can edit  /root/rootfs/etc/yum.repos.d/....
yum -y --installroot=${ROOTFS} groupinstall "Minimal Install"
yum -y --installroot=${ROOTFS} grub2
mychroot ${ROOTFS} yum upgrade
mychroot ${ROOTFS} /bin/bash

# #extract a single partition from image
# dd if=image of=partitionN skip=offset_of_partition_N count=size_of_partition_N bs=512 conv=sparse
# #put the partition back into image
# dd if=partitionN of=image seek=offset_of_partition_N count=size_of_partition_N bs=512 conv=sparse,notrunc

# #起始扇区  扇区个数  线性映射  目标设备 目标设备上的起始扇区
# 0     2048     linear /dev/loop0  0
# 2048  2095104  linear /dev/loop1  0
# 
# #dd if=dl-08eca7b8-11bf-4dc9-9b9c-b1d4640246c7.raw of=hdr bs=1M count=1
# #dd if=/dev/zero of=data bs=1M count=1023
# #mkfs.xfs data
# #mount data /mnt ...... copy rootfs ....
# #blkid get UUID --> modify /mnt/etc/fstab, /mnt/boot/grub2/grub.cfg
# #
# #kpartx -au hdr
# #kpartx -au data
# #dmsetup create linear_test linear.table
# # parted -s /dev/mapper/linear_test -- mkpart primary xfs 1M -1s \
# #  set 1 boot on
# #
#dmsetup remove_all
#

