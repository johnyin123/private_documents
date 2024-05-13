#!/bin/bash
set -o nounset -o pipefail
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

KERVERSION="$(make kernelversion)"
MYVERSION="-johnyin-s905d"

ROOTFS=${1:-${DIRNAME}/kernel-${KERVERSION}-$(date '+%Y%m%d%H%M%S')}

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
# fp asimd evtstrm aes pmull sha1 sha2 crc32 cpuid
# aarch64-linux-gnu-gcc -c -Q -mcpu=cortex-a53+fp+aes+crc+sha2 --help=target
# gcc -c -Q -mcpu=native --help=target
export KCFLAGS='-mcpu=cortex-a53+crypto+fp+crc+simd'
export KCPPFLAGS='-mcpu=cortex-a53+crypto+fp+crc+simd'
export INSTALL_PATH=${ROOTFS}/boot
export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1

#scripts/config --disable DEBUG_INFO
# export LOCALVERSION="${MYVERSION}"
scripts/config --set-str CONFIG_LOCALVERSION "${MYVERSION}"

# # OPTIMIZE
scripts/config --enable DEBUG_INFO
scripts/config --enable EARLY_PRINTK
scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
scripts/config --enable CONFIG_NLS --set-str CONFIG_NLS_DEFAULT "utf-8"
scripts/config --set-val CONFIG_NR_CPUS 8
scripts/config --enable CONFIG_NUMA
scripts/config --enable CONFIG_ZSWAP --enable CONFIG_SWAP --enable CONFIG_SLUB --enable CONFIG_SMP
scripts/config --enable CONFIG_AUDIT

scripts/config --enable CONFIG_EXPERT

enable_module_networks() {
    # enable ktls
    scripts/config --module CONFIG_TLS
    scripts/config --enable CONFIG_NET_CORE \
        --enable CONFIG_NET \
        --enable CONFIG_ETHERNET \
        --enable CONFIG_INET \
        --enable CONFIG_PACKET \
        --enable CONFIG_UNIX \
        --enable CONFIG_XDP_SOCKETS \
        --enable CONFIG_NETFILTER \
        --enable CONFIG_EPOLL \
        --module CONFIG_ATA_OVER_ETH \
        --module CONFIG_BATMAN_ADV \
        --module CONFIG_BRIDGE \
        --module CONFIG_IP_SET \
        --module CONFIG_IP_VS \
        --module CONFIG_L2TP \
        --module CONFIG_NET_IPGRE \
        --module CONFIG_OPENVSWITCH \
        --module CONFIG_VLAN_8021Q \
        --module CONFIG_NET_IPIP \
        --module CONFIG_NET_UDP_TUNNEL \
        --module CONFIG_NET_FOU \
        --module CONFIG_PPP \
        --module CONFIG_PPPOE \
        --module CONFIG_PPTP \
        --module CONFIG_TUN \
        --module CONFIG_TAP \
        --module CONFIG_VETH \
        --module CONFIG_MII \
        --module CONFIG_BONDING \
        --module CONFIG_DUMMY \
        --module CONFIG_WIREGUARD \
        --module CONFIG_NET_TEAM \
        --module CONFIG_NETCONSOLE \
        --module CONFIG_MACVLAN \
        --module CONFIG_MACVTAP \
        --module CONFIG_IPVLAN \
        --module CONFIG_IPVTAP \
        --module CONFIG_VXLAN \
        --module CONFIG_GENEVE \
        --module CONFIG_IPV6

    scripts/config --enable  CONFIG_NET_SCHED \
        --enable CONFIG_TCP_CONG_ADVANCED \
        --module CONFIG_TCP_CONG_BBR
}
enable_module_xz_sign() {
    local sign=${1:-}
    echo "use xz compress module"
    scripts/config --disable CONFIG_MODULE_COMPRESS_NONE
    scripts/config --disable CONFIG_MODULE_DECOMPRESS
    scripts/config --enable CONFIG_MODULE_COMPRESS_XZ

    scripts/config --disable CONFIG_MODULE_SIG_ALL
    scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    [ -z ${sign} ] && {
        echo "without sign........."
        return
    }
    echo "enable module sign sha256"
    [ -f "certs/signing_key.pem" ]  || {
        cat << EOCONF > key.conf
[ req ]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts

[ req_distinguished_name ]
#O = Unspecified company
CN = johnyin kernel key $(date '+%Y%m%d%H%M%S')
emailAddress = johnyin.news@163.com

[ myexts ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOCONF
        openssl req -new -nodes -utf8 -sha256 -days 36500 -batch -x509 -config key.conf -outform PEM -out certs/signing_key.pem -keyout certs/signing_key.pem
}
    openssl x509 -text -noout -in certs/signing_key.pem
    scripts/config --enable CONFIG_MODULE_SIG
    scripts/config --enable CONFIG_MODULE_SIG_ALL
    scripts/config --enable CONFIG_MODULE_SIG_FORCE
    scripts/config --enable CONFIG_MODULE_SIG_SHA256
    scripts/config --set-str CONFIG_MODULE_SIG_HASH "sha256"

    scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS "certs/signing_key.pem"
    scripts/config --set-str CONFIG_MODULE_SIG_KEY "certs/signing_key.pem"

    scripts/config --enable CONFIG_MODULE_SIG_KEY_TYPE_RSA
    scripts/config --disable CONFIG_MODULE_SIG_KEY_TYPE_ECDSA

    scripts/config --disable CONFIG_MODULE_SIG_SHA1
    scripts/config --disable CONFIG_MODULE_SIG_SHA224
    scripts/config --disable CONFIG_MODULE_SIG_SHA384
    scripts/config --disable CONFIG_MODULE_SIG_SHA512
}
enable_virtual_wifi() {
    cat <<EOF
# radios=2 defines how many virtual interfaces will be created
modprobe mac80211_hwsim radios=2
# create netns, add device to ns us iw
# iw phy phy0 set netns <hostapd_netns>
# hostapd ...
# iw phy phy1 set netns <station_ns>
# wpa_supplicant ......
EOF
    echo "enable Virtual WLAN Interfaces module"
    scripts/config --module CONFIG_MAC80211_HWSIM
    cat <<EOF
modprobe virt_wifi
ifconfig eth0 down
ip link set eth0 name wifi_eth
ifconfig wifi_eth up
ip link add link wifi_eth name wlan0 type virt_wifi

ifconfig wlan0 down
ifconfig wifi_eth down
ip link delete wlan0
ip link set wifi_eth name eth0
ifconfig eth0 up
rmmod virt_wifi
EOF
    scripts/config --module CONFIG_VIRT_WIFI
    echo "enable emulate input devices from userspace"
    scripts/config --enable CONFIG_INPUT_UINPUT
}
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
    # Full dynticks system
    scripts/config --enable CONFIG_NO_HZ_FULL
    # uselib()系统接口支持,仅使用基于libc5应用使用
    scripts/config --disable CONFIG_USELIB

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
    local byes=${1:-}
    [ -z ${byes} ] && {
        echo "without nfs root"
        scripts/config --module CONFIG_NFS_FS
        scripts/config --disable CONFIG_ROOT_NFS
        return
    }
    echo "enable nfs rootfs"
    scripts/config --enable CONFIG_NFS_FS
    scripts/config --enable CONFIG_ROOT_NFS
}
s905d_opt() {
    echo "no use acpi, uefi"
    scripts/config --disable CONFIG_ACPI --disable CONFIG_EFI

    scripts/config --enable CONFIG_ARCH_MESON
    scripts/config --enable CONFIG_MAILBOX
    scripts/config --enable CONFIG_MMU
    scripts/config --enable CONFIG_CPU_LITTLE_ENDIAN
    scripts/config --module CONFIG_ARM_SCPI_CPUFREQ
    scripts/config --enable CONFIG_ARM_PMU --enable CONFIG_ARM_PMUV3
    scripts/config --enable CONFIG_USB
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
    echo "enable meson vdec(staging)"
    scripts/config --enable CONFIG_STAGING \
        --enable CONFIG_STAGING_MEDIA \
        --module CONFIG_VIDEO_MESON_VDEC

    echo "opensource GPU driver, HDMI"
    scripts/config --enable CONFIG_DRM  --enable CONFIG_HDMI \
        --module CONFIG_DRM_LIMA \
        --module CONFIG_DRM_MESON \
        --module CONFIG_DRM_MESON_DW_HDMI \
        --module CONFIG_DRM_MESON_DW_MIPI_DSI

    echo "NETWORK"
    scripts/config --enable CONFIG_WLAN --enable CONFIG_WIRELESS \
        --module CONFIG_BRCMFMAC \
        --enable CONFIG_BRCMFMAC_SDIO

    echo "MMC"
    scripts/config --enable CONFIG_MMC \
        --module CONFIG_MMC_MESON_GX \
        --module CONFIG_MMC_MESON_MX_SDIO

    echo "BLUETOOTH"
    scripts/config --module CONFIG_BT \
        --module CONFIG_BT_HCIUART \
        --enable CONFIG_BT_HCIUART_3WIRE \
        --enable CONFIG_BT_HCIUART_BCM

    echo "SOUND"
    scripts/config --module CONFIG_SOUND \
        --module CONFIG_SND_MESON_AIU \
        --module CONFIG_SND_MESON_AXG_FIFO \
        --module CONFIG_SND_MESON_AXG_FRDDR \
        --module CONFIG_SND_MESON_AXG_TODDR \
        --module CONFIG_SND_MESON_AXG_TDM_FORMATTER \
        --module CONFIG_SND_MESON_AXG_TDM_INTERFACE \
        --module CONFIG_SND_MESON_AXG_TDMIN \
        --module CONFIG_SND_MESON_AXG_TDMOUT \
        --module CONFIG_SND_MESON_AXG_SOUND_CARD \
        --module CONFIG_SND_MESON_AXG_SPDIFOUT \
        --module CONFIG_SND_MESON_AXG_SPDIFIN \
        --module CONFIG_SND_MESON_AXG_PDM \
        --module CONFIG_SND_MESON_CARD_UTILS \
        --module CONFIG_SND_MESON_CODEC_GLUE \
        --module CONFIG_SND_MESON_GX_SOUND_CARD \
        --module CONFIG_SND_MESON_G12A_TOACODEC \
        --module CONFIG_SND_MESON_G12A_TOHDMITX \
        --module CONFIG_SND_SOC_MESON_T9015

    echo "MESON OTHER MODULES"
    scripts/config --module CONFIG_MESON_SM \
        --module CONFIG_DWMAC_MESON \
        --module CONFIG_MDIO_BUS_MUX_MESON_G12A \
        --module CONFIG_SERIAL_MESON \
        --enable CONFIG_SERIAL_MESON_CONSOLE \
        --module CONFIG_I2C_MESON \
        --module CONFIG_SPI_AMLOGIC_SPIFC_A1 \
        --module CONFIG_SPI_MESON_SPICC \
        --module CONFIG_SPI_MESON_SPIFC \
        --module CONFIG_PINCTRL_MESON \
        --module CONFIG_PINCTRL_MESON_GXBB \
        --module CONFIG_PINCTRL_MESON_GXL \
        --module CONFIG_PINCTRL_MESON8_PMX \
        --module CONFIG_PINCTRL_MESON_AXG \
        --module CONFIG_PINCTRL_MESON_AXG_PMX \
        --module CONFIG_PINCTRL_MESON_G12A \
        --module CONFIG_PINCTRL_MESON_A1 \
        --module CONFIG_PINCTRL_MESON_S4 \
        --module CONFIG_PINCTRL_AMLOGIC_C3 \
        --module CONFIG_AMLOGIC_THERMAL \
        --module CONFIG_MESON_GXBB_WATCHDOG \
        --module CONFIG_MESON_WATCHDOG \
        --module CONFIG_IR_MESON \
        --module CONFIG_IR_MESON_TX \
        --module CONFIG_CEC_MESON_AO \
        --module CONFIG_CEC_MESON_G12A_AO \
        --module CONFIG_VIDEO_MESON_GE2D \
        --module CONFIG_RTC_DRV_MESON_VRTC \
        --module CONFIG_COMMON_CLK_MESON_REGMAP \
        --module CONFIG_COMMON_CLK_MESON_DUALDIV \
        --module CONFIG_COMMON_CLK_MESON_MPLL \
        --module CONFIG_COMMON_CLK_MESON_PHASE \
        --module CONFIG_COMMON_CLK_MESON_PLL \
        --module CONFIG_COMMON_CLK_MESON_SCLK_DIV \
        --module CONFIG_COMMON_CLK_MESON_VID_PLL_DIV \
        --module CONFIG_COMMON_CLK_MESON_CLKC_UTILS \
        --module CONFIG_COMMON_CLK_MESON_AO_CLKC \
        --module CONFIG_COMMON_CLK_MESON_EE_CLKC \
        --module CONFIG_COMMON_CLK_MESON_CPU_DYNDIV \
        --module CONFIG_MESON_CANVAS \
        --module CONFIG_MESON_CLK_MEASURE \
        --enable CONFIG_MESON_GX_SOCINFO \
        --module CONFIG_MESON_GX_PM_DOMAINS \
        --module CONFIG_MESON_EE_PM_DOMAINS \
        --module CONFIG_MESON_SECURE_PM_DOMAINS \
        --module CONFIG_MESON_SARADC \
        --module CONFIG_PWM_MESON \
        --module CONFIG_MESON_IRQ_GPIO \
        --module CONFIG_RESET_MESON \
        --module CONFIG_RESET_MESON_AUDIO_ARB \
        --module CONFIG_PHY_MESON_G12A_MIPI_DPHY_ANALOG \
        --module CONFIG_PHY_MESON_AXG_PCIE \
        --module CONFIG_PHY_MESON_AXG_MIPI_PCIE_ANALOG \
        --module CONFIG_PHY_MESON_AXG_MIPI_DPHY \
        --module CONFIG_MESON_DDR_PMU \
        --disable CONFIG_NVMEM_MESON_EFUSE \
        --disable CONFIG_NVMEM_MESON_MX_EFUSE \
        --module CONFIG_CRYPTO_DEV_AMLOGIC_GXL \
        --enable CONFIG_CRYPTO_DEV_AMLOGIC_GXL_DEBUG
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
enable_module_networks
enable_virtual_wifi
enable_ebpf
s905d_opt
enable_nfs_rootfs
# enable_nfs_rootfs yes
enable_kvm
enable_usbip
enable_usb_gadget
enable_arch_inline
enable_module_xz_sign yes
# yes "" | make oldconfig
# yes "y" | make oldconfig

make listnewconfig
# make helpnewconfig
# ARCH=<arch> scripts/kconfig/merge_config.sh <...>/<platform>_defconfig <...>/android-base.config <...>/android-base-<arch>.config <...>/android-recommended.config
scripts/diffconfig .config.old .config 2>/dev/null

pahole --version 2>/dev/null || echo "pahole no found DEBUG_INFO_BTF not effict"

echo -n "PAGE SIZE =================> "
grep -oE "^CONFIG_ARM64_.*_PAGES" .config

read -n 1 -p "Press any key continue build..." value

make V=1 -j$(nproc) Image dtbs modules

# make -j$(nproc) bindeb-pkg #gen debian deb package!!

mkdir -p ${ROOTFS}/boot/dtb ${ROOTFS}/usr
rsync -a ${DIRNAME}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dtb ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${MYVERSION}.dtb

echo "INSTALL UNCOMPRESSED KERNEL"
make install > /dev/null

[[ ${COMPRESS-true} =~ ^1|yes|true$ ]] && {
    echo "USE GZIP KERNEL OVERWRITE UNCOMPRESSED KERNEL"
    make V=1 -j$(nproc) Image.gz
    # cat arch/arm64/boot/Image | gzip -n -f -9 > ${ROOTFS}/boot/vmlinuz-${KERVERSION}${MYVERSION}
    cat arch/arm64/boot/Image.gz > ${ROOTFS}/boot/vmlinuz-${KERVERSION}${MYVERSION}
}
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
