#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}

ROOTFS=${1:?rootfs need input}

cleanup() {
    echo "Unmounting..."
    for i in /dev /proc /sys /run; do
        umount -R -v "${ROOTFS}${i}" || true
    done
    echo "EXIT!!!"
}

for i in /dev /dev/pts /proc /sys /sys/firmware/efi/efivars /run; do
    mount -o bind $i "${ROOTFS}${i}" 2>/dev/null && echo "mount root $i ...." || true
done

trap cleanup EXIT
trap "exit 1" INT TERM  # makes the EXIT trap effective even when killed

# mount -t tmpfs -o size=32M tmpfs ${ROOTFS}/dev
# chroot ${ROOTFS} busybox mdev -s

echo "Running chroot with mounted sysfs, proc and mdev..."
chroot ${ROOTFS} || true
