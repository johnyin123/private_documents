#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

export ROOTFS=${1:-${DIRNAME}/kernel-$(date '+%Y%m%d%H%M%S')}

export PATH=${DIRNAME}/gcc-linaro-aarch64/bin/:$PATH
export LOCALVERSION="-johnyin-s905d"
export ARCH=arm64
export CFLAGS='-march=native -O3 -flto -pipe'
export CXXFLAGS='-march=native -O3 -flto -pipe'
export CROSS_COMPILE=aarch64-linux-gnu-
export INSTALL_PATH=${ROOTFS}/boot
export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1
KERVERSION="$(make kernelversion)"

# scripts/diffconfig .config.old .config | less
make -j$(nproc) Image dtbs modules

mkdir -p ${ROOTFS}/boot/dtb ${ROOTFS}/usr
rsync -av ${DIRNAME}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dtb ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${LOCALVERSION}.dtb
make install
make modules_install

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} /bin/bash <<EOSHELL
    depmod ${KERVERSION}${LOCALVERSION}
    update-initramfs -c -k ${KERVERSION}${LOCALVERSION}
EOSHELL
