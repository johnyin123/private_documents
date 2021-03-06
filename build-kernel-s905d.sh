#!/bin/bash
set -o nounset -o pipefail
DIRNAME="$(dirname "$(readlink -e "$0")")"
SCRIPTNAME=${0##*/}

#  64-bit SoCs (GXBB / S905 or newer)
#  Download recent cross-toolchain Linaro Latest aarch64-linux-gnu binaries
#
#  To compile the 64-bit mainline kernel:
#
#  # make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
#  # make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image dtbs
#  # mkimage -A arm64 -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -n linux-next -d arch/arm64/boot/Image ../uImage
#  To boot the 64-bit kernel using the shipped U-Boot:
#
#  # fatload mmc 0:1 0x01080000 uImage
#  # fatload mmc 0:1 $dtb_mem_addr meson-gxbb-vega-s95-telos.dtb
#  # setenv bootargs "console=ttyAML0,115200"
#  # bootm 0x1080000 - $dtb_mem_addr

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

# apt-get install gcc make pkg-config git bison flex libelf-dev libssl-dev libncurses5-dev
# https://releases.linaro.org/components/toolchain/binaries/latest-7/aarch64-linux-gnu/


export PATH=${DIRNAME}/gcc-linaro-7.4.1-aarch64/bin/:$PATH

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 LOCALVERSION="-johnyin-s905d" Image dtbs modules

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- install INSTALL_PATH=/media/johnyin/ROOTFS/boot
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_STRIP=1 modules_install INSTALL_MOD_PATH=/media/johnyin/ROOTFS/
echo "if you user compress module(xz,gz), you should execute depmod command!!(depmod  5.1.0-johnyin-s905d)"
echo "need copy dtb/firmware"


# chroot ..
# update-initramfs -c -k 5.1.0-johnyin-s905d

# dd if=${DIRNAME}/uInitrd bs=64 skip=1 | gunzip -c | cpio -id
# find . | cpio -o -H newc | gzip > ../image.cpio.gz
# mkimage -A arm64 -O linux -T ramdisk -C none  -n "ramdisk" -d ../image.cpio.gz ${DIRNAME}/kernel-out/boot/uInitrd.new
# rm -f ../image.cpio.gz


编译指定模块

make prepare
make scripts
make LOCALVERSION="-johnyin-s905d" M=net/ipv4/ CONFIG_TCP_CONG_BBR=m modules
make LOCALVERSION="-johnyin-s905d" M=drivers/usb/class CONFIG_USB_PRINTER=m modules


#debian package.
# ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- fakeroot make-kpkg --initrd --append-to-version="-johnyin-s905d" binary-arch

export ARCH=arm64
export $(dpkg-architecture -aarm64)
export CROSS_COMPILE=aarch64-linux-gnu-
fakeroot debian/rules clean
debian/rules build
fakeroot debian/rules binary

fakeroot make-kpkg -j4 --arch arm64 --cross-compile aarch64-linux-gnu- --initrd --append-to-version="-johnyin-s905d" binary-arch


