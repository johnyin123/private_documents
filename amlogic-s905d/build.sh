#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

export ROOTFS=${1:-${DIRNAME}/kernel-$(date '+%Y%m%d%H%M%S')}

[ -e "${DIRNAME}/gcc-aarch64" ] && 
{
    export PATH=${DIRNAME}/gcc-aarch64/bin/:$PATH
    export CROSS_COMPILE=aarch64-linux-
} || {
    # apt -y install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu bison flex libelf-dev libssl-dev
    # apt -y install pahole -t bullseye-backports
    export CROSS_COMPILE=aarch64-linux-gnu-
}
export LOCALVERSION="-johnyin-s905d"
export ARCH=arm64
# export CFLAGS='-O3 -flto -pipe'
# export CXXFLAGS='-O3 -flto -pipe'
export INSTALL_PATH=${ROOTFS}/boot
export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1
KERVERSION="$(make kernelversion)"

#scripts/config --disable DEBUG_INFO
sed -Ei '/CONFIG_SYSTEM_TRUSTED_KEYS/s/=.+/=""/g' .config || true
echo "use xz compress module"
scripts/config --disable MODULE_SIG_ALL
scripts/config --disable MODULE_COMPRESS_NONE
scripts/config --disable MODULE_DECOMPRESS
scripts/config --enable MODULE_COMPRESS_XZ
echo "fix eBPF bpftool gen vmlinux.h, see: lib/Kconfig.debug, pahole tools in package dwarves"
echo "dwarves: https://github.com/acmel/dwarves"
scripts/config --enable CONFIG_BPF_SYSCALL
scripts/config --enable CONFIG_BPF_JIT
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
scripts/diffconfig .config.old .config

pahole --version || echo "pahole no found DEBUG_INFO_BTF not effict"

make -j$(nproc) Image dtbs modules

# make -j$(nproc) bindeb-pkg #gen debian deb package!!

mkdir -p ${ROOTFS}/boot/dtb ${ROOTFS}/usr
rsync -a ${DIRNAME}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dtb ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${LOCALVERSION}.dtb
make install > /dev/null
make modules_install > /dev/null

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} /bin/bash <<EOSHELL
    depmod ${KERVERSION}${LOCALVERSION}
    update-initramfs -c -k ${KERVERSION}${LOCALVERSION}
    [ -e "/boot/extlinux/extlinux.conf" ] && {
        sed -i "s/\s*linux\s.*/    linux \/vmlinuz-${KERVERSION}${LOCALVERSION}/g" /boot/extlinux/extlinux.conf
        sed -i "s/\s*initrd\s.*/    initrd \/initrd.img-${KERVERSION}${LOCALVERSION}/g" /boot/extlinux/extlinux.conf
        sed -i "s/\s*fdt\s.*/    fdt \/dtb\/phicomm-n1-${KERVERSION}${LOCALVERSION}.dtb/g" /boot/extlinux/extlinux.conf
    }
    [ -e "/boot/uEnv.ini" ] && {
        sed -i "s/\s*image\s*=.*/image=vmlinuz-${KERVERSION}${LOCALVERSION}/g" /boot/uEnv.ini
        sed -i "s/\s*initrd\s*=.*/initrd=uInitrd-${KERVERSION}${LOCALVERSION}/g" /boot/uEnv.ini
        sed -i "s/\s*dtb\s*=.*/dtb=\/dtb\/phicomm-n1-${KERVERSION}${LOCALVERSION}.dtb/g" /boot/uEnv.ini
    }
    rm -f /boot/*.old
EOSHELL
cat<<EOF
rm .config
make tinyconfig
make kvm_guest.config
make kvmconfig
./scripts/config \
        -e EARLY_PRINTK \
        -e 64BIT \
        -e BPF -d EMBEDDED -d EXPERT \
        -e INOTIFY_USER

./scripts/config \
        -e VIRTIO -e VIRTIO_PCI -e VIRTIO_MMIO \
        -e SMP
....
EOF
