#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

KERVERSION="$(make kernelversion)"
MYVERSION="-johnyin-s905d"

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
export ARCH=arm64
# export KCFLAGS='-O3 -flto -pipe'
# export KCPPFLAGS='-O3 -flto -pipe'
export INSTALL_PATH=${ROOTFS}/boot
export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1

#scripts/config --disable DEBUG_INFO
scripts/config --set-str CONFIG_LOCALVERSION "${MYVERSION}"
scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
echo "use xz compress module"
scripts/config --disable MODULE_SIG_ALL
scripts/config --disable MODULE_COMPRESS_NONE
scripts/config --disable MODULE_DECOMPRESS
scripts/config --enable MODULE_COMPRESS_XZ
# # OPTIMIZE
scripts/config --enable DEBUG_INFO
scripts/config --enable EARLY_PRINTK
scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
# Full dynticks system
scripts/config --enable CONFIG_NO_HZ_FULL
# enable ktls
scripts/config --module CONFIG_TLS
# uselib()系统接口支持,仅使用基于libc5应用使用
scripts/config --disable CONFIG_USELIB

enable_ebpf() {
    echo "fix eBPF bpftool gen vmlinux.h, see: lib/Kconfig.debug, pahole tools in package dwarves"
    echo "dwarves: https://github.com/acmel/dwarves"
    scripts/config --enable CONFIG_KPROBES
    scripts/config --enable CONFIG_HAVE_DYNAMIC_FTRACE
    scripts/config --enable CONFIG_HAVE_DYNAMIC_FTRACE_WITH_REGS
    scripts/config --enable CONFIG_HAVE_FTRACE_MCOUNT_RECORD
    scripts/config --enable CONFIG_FTRACE
    scripts/config --enable CONFIG_DYNAMIC_FTRACE
    scripts/config --enable CONFIG_BPF
    scripts/config --enable CONFIG_BPF_SYSCALL
    scripts/config --enable CONFIG_BPF_JIT
    scripts/config --enable CONFIG_DEBUG_INFO_BTF
    # enable CONFIG_DEBUG_INFO_BTF need: apt install dwarves
}
enable_arch_inline() {
    cat <<EOF
    CONFIG_PREEMPT_NONE：无抢占
    CONFIG_PREEMPT：允许内核被抢占
    CONFIG_PREEMPT_VOLUNTARY suits desktop environments.
EOF
    scripts/config --disable CONFIG_PREEMPT_NONE
    scripts/config --disable CONFIG_PREEMPT
    scripts/config --disable CONFIG_PREEMPT_DYNAMIC
    scripts/config --disable CONFIG_SCHED_CORE
    scripts/config --enable CONFIG_HAVE_PREEMPT_DYNAMIC
    scripts/config --enable CONFIG_HAVE_PREEMPT_DYNAMIC_KEY
    scripts/config --enable CONFIG_PREEMPT_NOTIFIERS
    scripts/config --enable CONFIG_PREEMPT_VOLUNTARY_BUILD
    scripts/config --enable CONFIG_PREEMPT_VOLUNTARY
    # scripts/config --enable CONFIG_PREEMPT_RCU
    # scripts/config --enable CONFIG_TASKS_RCU
    scripts/config --enable ARCH_INLINE_SPIN_TRYLOCK
    scripts/config --enable ARCH_INLINE_SPIN_TRYLOCK_BH
    scripts/config --enable ARCH_INLINE_SPIN_LOCK
    scripts/config --enable ARCH_INLINE_SPIN_LOCK_BH
    scripts/config --enable ARCH_INLINE_SPIN_LOCK_IRQ
    scripts/config --enable ARCH_INLINE_SPIN_LOCK_IRQSAVE
    scripts/config --enable ARCH_INLINE_SPIN_UNLOCK
    scripts/config --enable ARCH_INLINE_SPIN_UNLOCK_BH
    scripts/config --enable ARCH_INLINE_SPIN_UNLOCK_IRQ
    scripts/config --enable ARCH_INLINE_SPIN_UNLOCK_IRQRESTORE
    scripts/config --enable ARCH_INLINE_READ_LOCK
    scripts/config --enable ARCH_INLINE_READ_LOCK_BH
    scripts/config --enable ARCH_INLINE_READ_LOCK_IRQ
    scripts/config --enable ARCH_INLINE_READ_LOCK_IRQSAVE
    scripts/config --enable ARCH_INLINE_READ_UNLOCK
    scripts/config --enable ARCH_INLINE_READ_UNLOCK_BH
    scripts/config --enable ARCH_INLINE_READ_UNLOCK_IRQ
    scripts/config --enable ARCH_INLINE_READ_UNLOCK_IRQRESTORE
    scripts/config --enable ARCH_INLINE_WRITE_LOCK
    scripts/config --enable ARCH_INLINE_WRITE_LOCK_BH
    scripts/config --enable ARCH_INLINE_WRITE_LOCK_IRQ
    scripts/config --enable ARCH_INLINE_WRITE_LOCK_IRQSAVE
    scripts/config --enable ARCH_INLINE_WRITE_UNLOCK
    scripts/config --enable ARCH_INLINE_WRITE_UNLOCK_BH
    scripts/config --enable ARCH_INLINE_WRITE_UNLOCK_IRQ
    scripts/config --enable ARCH_INLINE_WRITE_UNLOCK_IRQRESTORE
    scripts/config --enable INLINE_SPIN_TRYLOCK
    scripts/config --enable INLINE_SPIN_TRYLOCK_BH
    scripts/config --enable INLINE_SPIN_LOCK
    scripts/config --enable INLINE_SPIN_LOCK_BH
    scripts/config --enable INLINE_SPIN_LOCK_IRQ
    scripts/config --enable INLINE_SPIN_LOCK_IRQSAVE
    scripts/config --enable INLINE_SPIN_UNLOCK_BH
    scripts/config --enable INLINE_SPIN_UNLOCK_IRQ
    scripts/config --enable INLINE_SPIN_UNLOCK_IRQRESTORE
    scripts/config --enable INLINE_READ_LOCK
    scripts/config --enable INLINE_READ_LOCK_BH
    scripts/config --enable INLINE_READ_LOCK_IRQ
    scripts/config --enable INLINE_READ_LOCK_IRQSAVE
    scripts/config --enable INLINE_READ_UNLOCK
    scripts/config --enable INLINE_READ_UNLOCK_BH
    scripts/config --enable INLINE_READ_UNLOCK_IRQ
    scripts/config --enable INLINE_READ_UNLOCK_IRQRESTORE
    scripts/config --enable INLINE_WRITE_LOCK
    scripts/config --enable INLINE_WRITE_LOCK_BH
    scripts/config --enable INLINE_WRITE_LOCK_IRQ
    scripts/config --enable INLINE_WRITE_LOCK_IRQSAVE
    scripts/config --enable INLINE_WRITE_UNLOCK
    scripts/config --enable INLINE_WRITE_UNLOCK_BH
    scripts/config --enable INLINE_WRITE_UNLOCK_IRQ
    scripts/config --enable INLINE_WRITE_UNLOCK_IRQRESTORE
}
enable_nfs_rootfs() {
    # enable nfs rootfs
    scripts/config --enable CONFIG_NFS_FS
    scripts/config --enable CONFIG_ROOT_NFS
}
s905d_opt() {
    scripts/config --enable CONFIG_ARCH_MESON
    scripts/config --module CONFIG_USB_DWC3 --enable CONFIG_USB_DWC3_ULPI --enable CONFIG_USB_DWC3_DUAL_ROLE
    scripts/config --module CONFIG_USB_DWC3_MESON_G12A --module CONFIG_USB_DWC3_OF_SIMPLE
    scripts/config --module CONFIG_FIXED_PHY \
        --module CONFIG_FWNODE_MDIO \
        --module CONFIG_HW_RANDOM \
        --module CONFIG_HW_RANDOM_ARM_SMCCC_TRNG \
        --module CONFIG_HW_RANDOM_MESON \
        --module CONFIG_MDIO_BUS \
        --module CONFIG_MDIO_BUS_MUX \
        --module CONFIG_MDIO_BUS_MUX_MESON_GXL \
        --module CONFIG_MDIO_DEVRES \
        --module CONFIG_MESON_GXL_PHY \
        --module CONFIG_NET_SELFTESTS \
        --module CONFIG_OF_MDIO \
        --module CONFIG_PHYLIB \
        --module CONFIG_PHY_MESON8B_USB2 \
        --module CONFIG_PHY_MESON_GXL_USB2 \
        --module CONFIG_REALTEK_PHY \
        --module CONFIG_SMSC_PHY

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
    scripts/config --module CONFIG_VHOST_NET
    scripts/config --module CONFIG_VHOST_IOTLB
    scripts/config --module CONFIG_VHOST
    scripts/config --module CONFIG_VHOST_NET
    scripts/config --module CONFIG_VHOST_SCSI
    scripts/config --module CONFIG_VHOST_VSOCK
    scripts/config --module CONFIG_VIRTIO
    scripts/config --enable CONFIG_VIRTIO_MENU
    scripts/config --enable CONFIG_BLK_MQ_VIRTIO
    scripts/config --enable CONFIG_VIRTIO_ANCHOR
    scripts/config --module CONFIG_VIRTIO_VSOCKETS
    scripts/config --module CONFIG_VIRTIO_VSOCKETS_COMMON
    scripts/config --module CONFIG_VIRTIO_BLK
    scripts/config --enable CONFIG_BLK_MQ_VIRTIO
    scripts/config --module CONFIG_VIRTIO_NET
    scripts/config --module CONFIG_VIRTIO_BALLOON
    scripts/config --enable CONFIG_BALLOON_COMPACTION
    scripts/config --module CONFIG_VIRTIO_INPUT
    scripts/config --module CONFIG_VIRTIO_MMIO
    scripts/config --enable CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES
    scripts/config --module CONFIG_VIRTIO_IOMMU
    scripts/config --module CONFIG_SCSI_VIRTIO
    scripts/config --module CONFIG_SND_VIRTIO
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
enable_ebpf
s905d_opt
enable_nfs_rootfs
enable_kvm
enable_usbip
enable_usb_gadget
enable_arch_inline
# yes "" | make oldconfig
# yes "y" | make oldconfig

make listnewconfig

read -n 1 -p "Press any key continue build..." value

# ARCH=<arch> scripts/kconfig/merge_config.sh <...>/<platform>_defconfig <...>/android-base.config <...>/android-base-<arch>.config <...>/android-recommended.config
scripts/diffconfig .config.old .config 2>/dev/null

pahole --version 2>/dev/null || echo "pahole no found DEBUG_INFO_BTF not effict"

echo -n "PAGE SIZE =================> "
grep -oE "^CONFIG_ARM64_.*_PAGES" .config

make V=1 -j$(nproc) Image dtbs modules

# make -j$(nproc) bindeb-pkg #gen debian deb package!!

mkdir -p ${ROOTFS}/boot/dtb ${ROOTFS}/usr
rsync -a ${DIRNAME}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dtb ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${MYVERSION}.dtb
make install > /dev/null
make modules_install > /dev/null

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} /bin/bash <<EOSHELL
    depmod ${KERVERSION}${MYVERSION}
    update-initramfs -c -k ${KERVERSION}${MYVERSION}
    [ -e "/boot/extlinux/extlinux.conf" ] && {
        sed -i "s/\s*linux\s.*/    linux \/vmlinuz-${KERVERSION}${MYVERSION}/g" /boot/extlinux/extlinux.conf
        sed -i "s/\s*initrd\s.*/    initrd \/initrd.img-${KERVERSION}${MYVERSION}/g" /boot/extlinux/extlinux.conf
        sed -i "s/\s*fdt\s.*/    fdt \/dtb\/phicomm-n1-${KERVERSION}${MYVERSION}.dtb/g" /boot/extlinux/extlinux.conf
    }
    [ -e "/boot/uEnv.ini" ] && {
        sed -i "s/\s*image\s*=.*/image=vmlinuz-${KERVERSION}${MYVERSION}/g" /boot/uEnv.ini
        sed -i "s/\s*initrd\s*=.*/initrd=uInitrd-${KERVERSION}${MYVERSION}/g" /boot/uEnv.ini
        sed -i "s/\s*dtb\s*=.*/dtb=\/dtb\/phicomm-n1-${KERVERSION}${MYVERSION}.dtb/g" /boot/uEnv.ini
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
