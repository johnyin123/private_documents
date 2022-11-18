#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}

ROOTFS=${1:?rootfs need input}

mount -t sysfs sysfs ${ROOTFS}/sys
mount -t proc proc ${ROOTFS}/proc

echo "Making dev..."
mount -t tmpfs -o size=32M tmpfs ${ROOTFS}/dev
chroot ${ROOTFS} busybox mdev -s

echo "Running chroot with mounted sysfs, proc and mdev..."
chroot ${ROOTFS}

echo "Unmounting..."
umount ${ROOTFS}/sys
umount ${ROOTFS}/proc
umount ${ROOTFS}/dev

