#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

[ -e "${DIRNAME}/gcc" ] &&
{
    export PATH=${DIRNAME}/gcc/bin/:$PATH
    export CROSS_COMPILE=x86_64-linux-
    export ARCH=x86_64
}
PKG=${1:?deb/rpm need input}

# apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
export LOCALVERSION="-johnyin"
# export CFLAGS='-march=native -O3 -flto -pipe'
# export CXXFLAGS='-march=native -O3 -flto -pipe'
# export INSTALL_PATH=${ROOTFS}/boot
# export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1

echo "build bpftool: apt -y install llvm && cd tools/bpf/bpftool && make"
echo "build perf, cd tools/perf && make"
# scripts/diffconfig .config.old .config | less

sed -Ei '/CONFIG_SYSTEM_TRUSTED_KEYS/s/=.+/=""/g' .config || true
echo "use xz compress module"
scripts/config --disable MODULE_SIG_ALL
scripts/config --disable MODULE_COMPRESS_NONE
scripts/config --disable MODULE_DECOMPRESS
scripts/config --enable MODULE_COMPRESS_XZ
echo "fix eBPF bpftool gen vmlinux.h, see: lib/Kconfig.debug, pahole tools in package dwarves"
echo "dwarves: https://github.com/acmel/dwarves"
scripts/config --enable CONFIG_BPF_SYSCALL
scripts/config --enable CONFIG_DEBUG_INFO_BTF
scripts/config --enable CONFIG_FTRACE
# enable CONFIG_DEBUG_INFO_BTF need: apt install dwarves
scripts/config --enable DEBUG_INFO

# enable KVM
scripts/config --enable CONFIG_KVM_GUEST
scripts/config --enable CONFIG_KVM
scripts/config --enable CONFIG_VIRTUALIZATION
scripts/config --enable CONFIG_PARAVIRT
scripts/config --module CONFIG_VIRTIO

# yes "" | make oldconfig
scripts/diffconfig .config.old .config 2>/dev/null

pahole --version 2>/dev/null || echo "pahole no found DEBUG_INFO_BTF not effict"
case "$1" in
    rpm)
        shift
        echo "RPM output: /usr/lib/rpm/macros; %_topdir        %{getenv:HOME}/rpmbuild"
        echo "HOME=<your place> ./buile_kernel.sh"
        make -j$(nproc) binrpm-pkg
        ;;
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
