#!/bin/bash
set -o nounset -o pipefail
DIRNAME="$(dirname "$(readlink -e "$0")")"
SCRIPTNAME=${0##*/}

cat <<'EOF'
git clone https://github.com/cattyhouse/new-uboot-for-N1
N1自带u-boot, 但是只能启动打了TEXT_OFFSET补丁的内核,为了启动一个原生的内核, 需要挂载新版本的u-boot, 复制u-boot.ext到boot分区,N1可以用自身的u-boot,挂载这个新的u-boot.ext
启动原理:
1.N1内置u-boot->优先寻找U盘->寻找boot分区的s905_autoscript->根据这个s905_autoscript的内容加载新的u-boot.ext
2.根据u-boot.ext内置的脚本依次执行:bootcmd->distro_bootcmd->boot_targets->bootcmd_usb0->usb_boot->scan_dev_for_boot_part->scan_dev_for_boot->scan_dev_for_extlinux->boot_extlinux, 然后找到了extlinux.conf
3.根据extlinux.conf的设置,定位root分区->寻找zImage和uInitrd.
EOF
#  64-bit SoCs (GXBB / S905 or newer)
#  Download recent cross-toolchain Linaro Latest aarch64-linux-gnu binaries
#
#  To compile the 64-bit mainline kernel:
#
#  # make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
#  # make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image dtbs
# * build a standard "vmlinux" kernel image (in ELF binary format):
# * convert the kernel into a raw binary image:
#     ${CROSS_COMPILE}-objcopy -O binary -R .note -R .comment -S vmlinux linux.bin
#     gzip -9 linux.bin
#     mkimage -A arm64 -O linux -T kernel -C gzip -a 0x1080000 -e 0x1080000 -n "Linux Kernel Image" -d linux.bin.gz uImage
# #  # mkimage -A arm64 -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -n linux-next -d arch/arm64/boot/Image ../uImage
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
# https://git.kernel.org/pub/scm/linux/kernel/git/amlogic/linux.git

export PATH=${DIRNAME}/gcc-linaro-7.4.1-aarch64/bin/:$PATH

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j4 LOCALVERSION="-johnyin-s905d" Image dtbs modules

dest=/home/johnyin/n1/buildroot
rsync -av ./arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dtb  ${dest}/boot/dtb
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- install INSTALL_PATH=${dest}/boot
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_STRIP=1 modules_install INSTALL_MOD_PATH=${dest}/usr/
# mount /dev/sdb2 root/
# mount /dev/sdb1 root/boot/
# kerver=5.17.0-johnyin-s905d
# bash
# LC_ALL=C LANGUAGE=C LANG=C chroot root /bin/bash <<EOSHELL
#     depmod ${kerver}
#     update-initramfs -c -k ${kerver}
# EOSHELL
# rm -f root/boot/initrd.img-${kerver} root/boot/uInitrd root/boot/zImage
# mv root/boot/uInitrd-${kerver} root/boot/uInitrd
# mv root/boot/vmlinuz-${kerver} root/boot/zImage
# rm -f root/etc/udev/rules.d/*
# umount root/boot/
# umount root/

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


