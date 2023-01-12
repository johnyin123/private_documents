#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}

ROOTFS=${1:?rootfs need input}

for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do
    mount -o bind $i "${root_dir}${i}" 2>/dev/null && echo "mount root $i ...." || true
done

# mount -t tmpfs -o size=32M tmpfs ${ROOTFS}/dev
# chroot ${ROOTFS} busybox mdev -s

echo "Running chroot with mounted sysfs, proc and mdev..."
chroot ${ROOTFS}

echo "Unmounting..."
for i in /dev /proc /sys /run; do
    umount -R -v "${root_dir}${i}" || true
done
