#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

PKG=${1:?deb/rpm need input}

# apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
export LOCALVERSION="-johnyin"
export CFLAGS='-march=native -O3 -flto -pipe'
export CXXFLAGS='-march=native -O3 -flto -pipe'
# export INSTALL_PATH=${ROOTFS}/boot
# export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1

# scripts/diffconfig .config.old .config | less

sed -ri '/CONFIG_SYSTEM_TRUSTED_KEYS/s/=.+/=""/g' .config
scripts/config --disable DEBUG_INFO
scripts/config --disable DEBUG_INFO_BTF
scripts/config --disable MODULE_SIG_ALL
scripts/config --disable MODULE_COMPRESS_NONE
scripts/config --disable MODULE_DECOMPRESS
scripts/config --enable MODULE_COMPRESS_XZ 

case "$1" in
    rpm) make -j$(nproc) binrpm-pkg; shift;;
    deb) make -j$(nproc) bindeb-pkg; shift;;
    *)   echo "not build"
esac
# cat<<EOF
# rm .config
# make tinyconfig
# make kvm_guest.config
# make kvmconfig
# ./scripts/config \
#         -e EARLY_PRINTK \
#         -e 64BIT \
#         -e BPF -d EMBEDDED -d EXPERT \
#         -e INOTIFY_USER
# 
# ./scripts/config \
#         -e VIRTIO -e VIRTIO_PCI -e VIRTIO_MMIO \
#         -e SMP
# ....
# EOF
