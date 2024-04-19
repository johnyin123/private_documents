#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

KERVERSION="$(make kernelversion)"
export ROOTFS=${1:-${DIRNAME}/kernel-${KERVERSION}-$(date '+%Y%m%d%H%M%S')}

echo "build bpftool: apt -y install llvm && cd tools/bpf/bpftool && make"
echo "build perf, cd tools/perf && make"

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
# export KCFLAGS='-O3 -flto -pipe'
# export KCPPFLAGS='-O3 -flto -pipe'
export INSTALL_PATH=${ROOTFS}/boot
export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1

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
scripts/config --enable EARLY_PRINTK
scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
# Full dynticks system
scripts/config --enable CONFIG_NO_HZ_FULL
# enable ktls
scripts/config --module CONFIG_TLS
enable_nfs_rootfs() {
    # enable nfs rootfs
    scripts/config --enable CONFIG_NFS_FS
    scripts/config --enable CONFIG_ROOT_NFS
}
s905d_opt() {
    scripts/config --module CONFIG_USB_DWC3 --enable CONFIG_USB_DWC3_ULPI --enable CONFIG_USB_DWC3_DUAL_ROLE
    scripts/config --module CONFIG_USB_DWC3_MESON_G12A --module CONFIG_USB_DWC3_OF_SIMPLE
    # CONFIG_ARCH_MESON=y
    # CONFIG_MESON_GXL_PHY=y
    # # hdmi
    # CONFIG_DRM_MESON=m
    # CONFIG_DRM_MESON_DW_HDMI=m
    # # sound
    # CONFIG_SND_MESON_GX_SOUND_CARD=m
    # # network
    # CONFIG_BRCMFMAC=m
    # CONFIG_BRCMFMAC_SDIO=y
    # # mmc
    # CONFIG_MMC_MESON_GX=y
    # CONFIG_MMC_MESON_MX_SDIO=y
    # # bluetooth
    # CONFIG_BT_HCIUART=m
    # CONFIG_BT_HCIUART_3WIRE=y
    # CONFIG_BT_HCIUART_BCM=y
}
enable_kvm() {
    # enable KVM
    scripts/config --enable CONFIG_KVM
    scripts/config --enable CONFIG_KVM_GUEST
    scripts/config --enable CONFIG_VIRTUALIZATION
    scripts/config --enable CONFIG_PARAVIRT
    scripts/config --enable CONFIG_VHOST_MENU
    scripts/config --module CONFIG_VIRTIO
    scripts/config --module CONFIG_VHOST_NET
    scripts/config --module CONFIG_VHOST_IOTLB
    scripts/config --module CONFIG_VHOST
    scripts/config --module CONFIG_VHOST_NET
    scripts/config --module CONFIG_VHOST_SCSI
    scripts/config --module CONFIG_VHOST_VSOCK
}
enable_usbip() {
    # enable usbip modules
    scripts/config --module CONFIG_USBIP_CORE
    scripts/config --module CONFIG_USBIP_VHCI_HCD
    scripts/config --module CONFIG_USBIP_HOST
    scripts/config --module CONFIG_USBIP_VUDC
}
enable_usb_gadget() {
    # # enable g_mass_storage....
    cat <<EOF
lsusb && modprobe dummy_hcd && lsusb
modprobe g_mass_storage file=/root/disk
# idVendor=0x1d6b idProduct=0x0104 iManufacturer=Myself iProduct=VirtualBlockDevice iSerialNumber=123
mount .....
EOF
    scripts/config --module CONFIG_USB_MASS_STORAGE
    scripts/config --module CONFIG_USB_G_HID
    scripts/config --module CONFIG_USB_G_WEBCAM
    scripts/config --module CONFIG_USB_RAW_GADGET
    scripts/config --module CONFIG_USB_GADGET
    scripts/config --module CONFIG_USB_GADGETFS
    scripts/config --module CONFIG_USB_DUMMY_HCD
    scripts/config --module CONFIG_USB_CONFIGFS
}
enable_nfs_rootfs
enable_kvm
enable_usbip
enable_usb_gadget
# yes "" | make oldconfig
# yes "y" | make oldconfig
scripts/diffconfig .config.old .config 2>/dev/null

pahole --version 2>/dev/null || echo "pahole no found DEBUG_INFO_BTF not effict"

echo -n "PAGE SIZE =================> "
grep -oE "^CONFIG_ARM64_.*_PAGES" .config

make V=1 -j$(nproc) Image dtbs modules

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
