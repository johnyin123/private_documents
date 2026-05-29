#!/bin/bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("f4d0e7b1[2026-05-27T16:22:00+08:00]:build.sh")
################################################################################
RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m'
log() { printf "[${GREEN}$(date +'%Y-%m-%dT%H:%M:%S.%2N%z')${NC}]${RED}%b${NC}\n" "$@"; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <config> <kernel dir> [install dir]
EOF
    cat <<'EOF'
for p in $(ls --sort=version ../src/patch-6.18.*); do xzcat $p | patch -p1; done
EOF
}
CONFIG="${1:?$(usage)}"
SRC="${2:?$(usage)}"
OUTPUT=${OUTPUT:-${DIRNAME}/build-output}
DOT_CONFIG="--file ${OUTPUT}/.config"
CMD_MAKE="make -C ${SRC} -j$(nproc) O=${OUTPUT}"
KERVERSION="$(${CMD_MAKE} --silent kernelversion)"
ROOTFS=${3:-${DIRNAME}/kernel-${KERVERSION}-$(date '+%Y%m%d%H%M%S')}
[ -e "${CONFIG}" ] || { log "${CONFIG} no found"; exit 1; }
${SRC}/scripts/diffconfig ${OUTPUT}/.config ${CONFIG} 2>/dev/null
mkdir -p "${OUTPUT}" && cat ${CONFIG} > "${OUTPUT}"/.config
[ -d "${ROOTFS}" ] && ROOTFS="$(readlink -f "${ROOTFS}")"
##################################################
##OPTION_START##
# # apt -f install libelf-dev libssl-dev
CONFIG_HZ=${CONFIG_HZ:-100}
NFSROOTFS=${NFSROOTFS:-""}      # not null is true/yes
ACPI_EFI=${ACPI_EFI:-""}        # not null is true/yes
MODULE_SIGN=${MODULE_SIGN=yes}  # not null is true/yes
MYVERSION=${MYVERSION="-johnyin-s905d"}
##OPTION_END##
show_option() {
    local file="${1}"
    sed -n '/^##OPTION_START/,/^##OPTION_END/p' ${file} | while IFS= read -r line; do
        [[ ${line} =~ ^\ *#.*$ ]] && continue #skip comment line
        [[ ${line} =~ ^\ *$ ]] && continue #skip blank
        eval "printf '%-16.16s = %s\n' \"${line%%=*}\" \"\${${line%%=*}:-UNSET}\""
    done
}
show_option "${SCRIPTNAME}"
read -n 1 -p "Press any key continue..." value
#
builder_version=$(echo "${VERSION[@]}" | cut -d'[' -f 1)
# ${CMD_MAKE} ARCH= O=. -C <linux-sources> headers_install INSTALL_HDR_PATH=<output-directory>
##################################################
is_set() {
    local cfg=${1}
    grep "CONFIG_$1=[y|m]" "$cfg" > /dev/null
}
# if is_set_in_kernel "$1"; then
# fi
is_set_in_kernel() {
    local cfg=${1}
    grep "CONFIG_$1=y" "$cfg" > /dev/null
}
is_set_as_module() {
    local cfg=${1}
    grep "CONFIG_$1=m" "$cfg" > /dev/null
}
log "build bpftool: apt -y install llvm && cd tools/bpf/bpftool && make"
log "build perf, cd tools/perf && make"

[ -e "${DIRNAME}/gcc-aarch64" ] && {
    log "https://mirrors.edge.kernel.org/pub/tools/crosstool/"
    export PATH=${DIRNAME}/gcc-aarch64/bin/:$PATH
    export CROSS_COMPILE=aarch64-linux-
} || {
    # apt -y install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu bison flex libelf-dev libssl-dev
    # apt -y install pahole -t bullseye-backports
    export CROSS_COMPILE=aarch64-linux-gnu-
}
export ARCH=arm64
export KBUILD_BUILD_USER=johnyin
# export KBUILD_BUILD_HOST=
log "ARCH=${ARCH}"
log "CROSS_COMPILE=${CROSS_COMPILE}"
${CROSS_COMPILE}gcc --version
# fp asimd evtstrm aes pmull sha1 sha2 crc32 cpuid
# aarch64-linux-gnu-gcc -c -Q -mcpu=cortex-a53+fp+aes+crc+sha2 --help=target
# gcc -c -Q -mcpu=native --help=target
export KCFLAGS='-mcpu=cortex-a53+crypto+fp+crc+simd'
export KCPPFLAGS='-mcpu=cortex-a53+crypto+fp+crc+simd'
export INSTALL_PATH=${ROOTFS}/boot
export INSTALL_MOD_PATH=${ROOTFS}/usr/
export INSTALL_MOD_STRIP=1

#${SRC}/scripts/config ${DOT_CONFIG} --disable DEBUG_INFO
# export LOCALVERSION="${MYVERSION}"
${SRC}/scripts/config ${DOT_CONFIG} --set-str CONFIG_LOCALVERSION "${MYVERSION}"

# # OPTIMIZE
${SRC}/scripts/config ${DOT_CONFIG} --enable DEBUG_INFO
${SRC}/scripts/config ${DOT_CONFIG} --enable EARLY_PRINTK
${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
${SRC}/scripts/config ${DOT_CONFIG} --set-val CONFIG_NR_CPUS 8
${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_NUMA
${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_SLUB --enable CONFIG_SMP
${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_AUDIT

${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_EXPERT
${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_TTY_PRINTK \
    --set-val CONFIG_TTY_PRINTK_LEVEL 6

# since version 6.11
${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_COMPRESSED_INSTALL

enable_zram() {
    log "ENABLE ZSWAP && ZRAM MODULES"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_SWAP
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_ZSWAP
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_ZRAM \
        --enable CONFIG_ZRAM_WRITEBACK \
        --enable CONFIG_ZRAM_MULTI_COMP \
        --enable CONFIG_ZRAM_DEF_COMP_ZSTD \
        --set-str CONFIG_ZRAM_DEF_COMP "zstd"
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ZRAM_DEF_COMP_LZORLE
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ZRAM_DEF_COMP_LZ4
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ZRAM_DEF_COMP_LZO
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ZRAM_DEF_COMP_LZ4H
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ZRAM_DEF_COMP_842
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ZRAM_MEMORY_TRACKING
}

enable_module_networks() {
    log "NETWORK MODULES 6LOWPAN"
cat <<EOF
# #
# apt -y install wpan-tools
# modprobe fakelb numlbs=1
# mount -t debugfs none /sys/kernel/debug
# #
# hciconfig hci0 reset
modprobe bluetooth_6lowpan
echo 1 > /sys/kernel/debug/bluetooth/6lowpan_enable
# Advertise over LE
hciconfig hci0 leadv
# hciconfig hci0 noleadv  #停止广播
# hcitool lescan
cat /sys/kernel/debug/bluetooth/l2cap
echo "connect 43:45:C0:00:1F:AC 1" >/sys/kernel/debug/bluetooth/6lowpan_control
# connect <addr> <addr_type>
# disconnect <addr> <addr_type>
IPV6ADDR=fe80::MAC123+ff:fe+MAC456
ping6 -I bt0 <ipv6addr>
echo 1 > /sys/kernel/debug/bluetooth/6lowpan_enable
ping6 <ipv6addr>%bt0
ssh root@<ipv6addr>%bt0

apt -y install radvd
cat << CFG >/etc/radvd.conf
interface bt0
{
    AdvSendAdvert on;
    prefix 2001:db8::/64
    {
        AdvOnLink off;
        AdvAutonomous on;
        AdvRouterAddr on;
    };
};
CFG
# Set IPv6 forwarding (must be present).
sudo echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
# Run radvd daemon.
radvd
# If successfull then all devices connected to the host will receive a routable 2001:db8 prefix.
# This can be verified by sending echo request to the full address:
ping6 -I bt0 2001:db8::2aa:bbff:fexx:yyzz
# where aa:bbff:fexx:yyzz is device Bluetooth address.
EOF
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_BT_6LOWPAN \
        --module CONFIG_6LOWPAN \
        --module CONFIG_IEEE802154_FAKELB \
        --module CONFIG_IEEE802154_HWSIM

    log "KTLS MODULES"
    # enable ktls CONFIG_MPTCP_IPV6 depends IPV6=y
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_TLS
    log "NETWORK MODULES"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_NET_CORE \
        --enable CONFIG_NET \
        --enable CONFIG_ETHERNET \
        --enable CONFIG_MPTCP \
        --enable CONFIG_MPTCP_IPV6 \
        --enable CONFIG_INET \
        --enable CONFIG_IP_MULTICAST \
        --enable CONFIG_XDP_SOCKETS \
        --enable CONFIG_NETFILTER \
        --enable CONFIG_EPOLL \
        --enable CONFIG_UNIX \
        --enable CONFIG_NET_SWITCHDEV \
        --module CONFIG_PACKET \
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
        --module CONFIG_NET_VRF \
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

    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_NET_SCHED \
        --enable CONFIG_TCP_CONG_ADVANCED \
        --module CONFIG_TCP_CONG_BBR
}
enable_module_filesystem() {
    log "FILESYSTEM MODULES"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_NLS --set-str CONFIG_NLS_DEFAULT "utf-8" \
        --module CONFIG_NLS_ASCII \
        --module CONFIG_UNICODE \
        --module CONFIG_NLS_UTF8

    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_PROC_FS \
        --enable CONFIG_KERNFS \
        --enable CONFIG_SYSFS \
        --enable CONFIG_TMPFS \
        --enable CONFIG_TMPFS_QUOTA \
        --enable CONFIG_FSNOTIFY \
        --enable CONFIG_DNOTIFY \
        --enable CONFIG_INOTIFY_USER \
        --enable CONFIG_FANOTIFY \
        --enable CONFIG_QUOTA \
        --module CONFIG_FUSE_FS \
        --module CONFIG_EXT4_FS \
        --module CONFIG_JFS_FS \
        --module CONFIG_XFS_FS \
        --module CONFIG_F2FS_FS \
        --module CONFIG_OVERLAY_FS \
        --module CONFIG_ISO9660_FS \
        --module CONFIG_UDF_FS \
        --module CONFIG_FAT_FS \
        --module CONFIG_MSDOS_FS \
        --module CONFIG_VFAT_FS \
        --module CONFIG_EXFAT_FS \
        --module CONFIG_SQUASHFS \
        --module CONFIG_SYSV_FS \
        --module CONFIG_CEPH_FS \
        --module CONFIG_CIFS \
        --module CONFIG_SMB_SERVER \
        --module CONFIG_SMBFS \
        --module CONFIG_NTFS3_FS

}

enable_network_storage() {
    log "MODULES NETWORK BLOCK DEV"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_ATA_OVER_ETH \
        --module CONFIG_BLK_DEV_NBD \
        --module CONFIG_BLK_DEV_RBD \
        --module CONFIG_BLK_DEV_DRBD \
        --module CONFIG_BLK_DEV_LOOP \
        --module CONFIG_BLK_DEV_RAM \
        --module CONFIG_BLK_DEV_NULL_BLK
}

enable_module_xz_sign() {
    local sign=${1:-}
    log "MODULES XZ COMPRESS"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULES \
        --enable CONFIG_MODVERSIONS \
        --enable CONFIG_ASM_MODVERSIONS

    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_COMPRESS_NONE
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_DECOMPRESS
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_COMPRESS
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_COMPRESS_ALL
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_COMPRESS_XZ

    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_SIG_ALL
    ${SRC}/scripts/config ${DOT_CONFIG} --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""

    [ -z ${sign} ] && {
        log "MODULES NOT SIGNED"
        return
    }
    log "MODULES SIGNED SHA256"
cat <<EOF
MODULES_SIG_KEY look like this:
Code:
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
Code:
cat key.key crt.crt > combined.pem
Code:
openssl req -new -nodes -utf8 -sha256 -days 36500 -batch -x509 \
   -config x509.genkey -outform PEM -out kernel_key.pem \
   -keyout kernel_key.pem
EOF
    [ -f "${OUTPUT}/johnyin_key.pem" ] || {
        cat << EOCONF > ${OUTPUT}/key.conf
[ req ]
default_bits = 4096
distinguished_name = req_distinguished_name
prompt = no
string_mask = utf8only
x509_extensions = myexts

[ req_distinguished_name ]
#O = Unspecified company
CN = johnyin kernel key ${builder_version}
emailAddress = johnyin.news@163.com

[ myexts ]
basicConstraints=critical,CA:FALSE
keyUsage=digitalSignature
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid
EOCONF
    openssl req -new -nodes -utf8 -sha256 -days 36500 -batch -x509 -config ${OUTPUT}/key.conf -outform PEM -out ${OUTPUT}/johnyin_key.pem -keyout ${OUTPUT}/johnyin_key.pem
}
    openssl x509 -text -noout -in ${OUTPUT}/johnyin_key.pem
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_SIG
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_SIG_ALL
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_SIG_FORCE
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_SIG_SHA256
    ${SRC}/scripts/config ${DOT_CONFIG} --set-str CONFIG_MODULE_SIG_HASH "sha256"

    ${SRC}/scripts/config ${DOT_CONFIG} --set-str CONFIG_SYSTEM_TRUSTED_KEYS "johnyin_key.pem"
    ${SRC}/scripts/config ${DOT_CONFIG} --set-str CONFIG_MODULE_SIG_KEY "johnyin_key.pem"

    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MODULE_SIG_KEY_TYPE_RSA
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_SIG_KEY_TYPE_ECDSA

    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_SIG_SHA1
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_SIG_SHA224
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_SIG_SHA384
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_MODULE_SIG_SHA512
    cat <<EOF
# manually sign a module
scripts/sign-file sha512 kernel-signkey.priv kernel-signkey.x509 module.ko
EOF
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
    log "enable Virtual WLAN Interfaces module"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_MAC80211_HWSIM
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
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRT_WIFI
    log "enable emulate input devices from userspace"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_INPUT_UINPUT
}
enable_ebpf() {
    echo "fix eBPF bpftool gen vmlinux.h, see: lib/Kconfig.debug, pahole tools in package dwarves"
    echo "dwarves: https://github.com/acmel/dwarves"
    log "ebpf"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_KPROBES
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_HAVE_DYNAMIC_FTRACE
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_HAVE_DYNAMIC_FTRACE_WITH_REGS
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_HAVE_FTRACE_MCOUNT_RECORD
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_FTRACE
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_DYNAMIC_FTRACE
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_BPF
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_BPF_SYSCALL
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_BPF_JIT
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_DEBUG_INFO_BTF
    # enable CONFIG_DEBUG_INFO_BTF need: apt install dwarves
}
enable_preempt_voluntary() {
    cat <<EOF
    CONFIG_PREEMPT_NONE：无抢占
    CONFIG_PREEMPT：允许内核被抢占
    CONFIG_PREEMPT_VOLUNTARY: 自愿抢占，适用于有桌面的环境
EOF
    log "PREEMPT_VOLUNTARY select"
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_PREEMPT_NONE \
        --disable CONFIG_PREEMPT \
        --disable CONFIG_PREEMPT_VOLUNTARY

    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_PREEMPT_BUILD \
        --enable CONFIG_PREEMPT_VOLUNTARY \
        --enable CONFIG_PREEMPT_DYNAMIC \
        --enable CONFIG_PREEMPT_COUNT \
        --enable CONFIG_PREEMPTION \
        --enable CONFIG_TASKS_RCU \
        --enable CONFIG_PREEMPT_RCU

    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_SCHED_CORE
}
enable_arch_inline() {
    local hz=${1:-100}
    log "AARCH64 ARCH inline"
    # Full dynticks system
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_NO_HZ_FULL \
        --enable CONFIG_HIGH_RES_TIMERS

    case "${hz}" in
        100|250|300|1000)
            log "CONFIG_HZ=${hz}"
            ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_HZ_1000 \
                --disable CONFIG_HZ_300 \
                --disable CONFIG_HZ_250 \
                --disable CONFIG_HZ_100
            ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_HZ_${hz} \
                --set-val CONFIG_HZ ${hz}
            ;;
        *)
            log "CONFIG_HZ error: ${hz}???"
            exit 1
            ;;
    esac

    # uselib()系统接口支持,仅使用基于libc5应用使用
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_USELIB


    ${SRC}/scripts/config ${DOT_CONFIG} --enable ARCH_INLINE_SPIN_TRYLOCK \
        --enable ARCH_INLINE_SPIN_TRYLOCK_BH \
        --enable ARCH_INLINE_SPIN_LOCK \
        --enable ARCH_INLINE_SPIN_LOCK_BH \
        --enable ARCH_INLINE_SPIN_LOCK_IRQ \
        --enable ARCH_INLINE_SPIN_LOCK_IRQSAVE \
        --enable ARCH_INLINE_SPIN_UNLOCK \
        --enable ARCH_INLINE_SPIN_UNLOCK_BH \
        --enable ARCH_INLINE_SPIN_UNLOCK_IRQ \
        --enable ARCH_INLINE_SPIN_UNLOCK_IRQRESTORE \
        --enable ARCH_INLINE_READ_LOCK \
        --enable ARCH_INLINE_READ_LOCK_BH \
        --enable ARCH_INLINE_READ_LOCK_IRQ \
        --enable ARCH_INLINE_READ_LOCK_IRQSAVE \
        --enable ARCH_INLINE_READ_UNLOCK \
        --enable ARCH_INLINE_READ_UNLOCK_BH \
        --enable ARCH_INLINE_READ_UNLOCK_IRQ \
        --enable ARCH_INLINE_READ_UNLOCK_IRQRESTORE \
        --enable ARCH_INLINE_WRITE_LOCK \
        --enable ARCH_INLINE_WRITE_LOCK_BH \
        --enable ARCH_INLINE_WRITE_LOCK_IRQ \
        --enable ARCH_INLINE_WRITE_LOCK_IRQSAVE \
        --enable ARCH_INLINE_WRITE_UNLOCK \
        --enable ARCH_INLINE_WRITE_UNLOCK_BH \
        --enable ARCH_INLINE_WRITE_UNLOCK_IRQ \
        --enable ARCH_INLINE_WRITE_UNLOCK_IRQRESTORE \
        --enable INLINE_SPIN_TRYLOCK \
        --enable INLINE_SPIN_TRYLOCK_BH \
        --enable INLINE_SPIN_LOCK \
        --enable INLINE_SPIN_LOCK_BH \
        --enable INLINE_SPIN_LOCK_IRQ \
        --enable INLINE_SPIN_LOCK_IRQSAVE \
        --enable INLINE_SPIN_UNLOCK_BH \
        --enable INLINE_SPIN_UNLOCK_IRQ \
        --enable INLINE_SPIN_UNLOCK_IRQRESTORE \
        --enable INLINE_READ_LOCK \
        --enable INLINE_READ_LOCK_BH \
        --enable INLINE_READ_LOCK_IRQ \
        --enable INLINE_READ_LOCK_IRQSAVE \
        --enable INLINE_READ_UNLOCK \
        --enable INLINE_READ_UNLOCK_BH \
        --enable INLINE_READ_UNLOCK_IRQ \
        --enable INLINE_READ_UNLOCK_IRQRESTORE \
        --enable INLINE_WRITE_LOCK \
        --enable INLINE_WRITE_LOCK_BH \
        --enable INLINE_WRITE_LOCK_IRQ \
        --enable INLINE_WRITE_LOCK_IRQSAVE \
        --enable INLINE_WRITE_UNLOCK \
        --enable INLINE_WRITE_UNLOCK_BH \
        --enable INLINE_WRITE_UNLOCK_IRQ \
        --enable INLINE_WRITE_UNLOCK_IRQRESTORE
}
enable_nfs_rootfs() {
    local byes=${1:-}
    [ -z ${byes} ] && {
        log "DISABLE NFS ROOTFS"
        ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_NFS_FS
        ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ROOT_NFS
        return
    }
    log "ENABLE NFS ROOTFS"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_NFS_FS
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_ROOT_NFS
}
s905d_opt() {
    log "AMLOGIC S905D MODULES, s905d no need EFI/ACPI"
    log "enable arm64 NUMA_EMULATION"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_NUMA_EMU

    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_ARCH_MESON
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MAILBOX
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_MMU
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_CPU_LITTLE_ENDIAN
    ################# CONFIG_SENSORS_ARM_SCPI, cpu temp !
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_SENSORS_ARM_SCPI
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_ARM_SCPI_CPUFREQ
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_ARM_PMU --enable CONFIG_ARM_PMUV3
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USB \
        --module CONFIG_TYPEC \
        --module CONFIG_USB_COMMON \
        --module CONFIG_USB_ULPI_BUS \
        --module CONFIG_USB_ROLE_SWITCH
    log "USB DWC2 is define as peripheral"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USB_DWC2 --enable CONFIG_USB_DWC2_DUAL_ROLE
    log "USB DWC3 is define as host"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USB_DWC3 --enable CONFIG_USB_DWC3_ULPI --enable CONFIG_USB_DWC3_DUAL_ROLE
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USB_DWC3_MESON_G12A --module CONFIG_USB_DWC3_OF_SIMPLE
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_FIXED_PHY \
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
    log "enable meson vdec(staging)"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_STAGING \
        --enable CONFIG_STAGING_MEDIA \
        --module CONFIG_VIDEO_MESON_VDEC

    log "opensource LIMA, mali450 GPU driver, HDMI"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_DRM --enable CONFIG_HDMI \
        --module CONFIG_DRM_LIMA \
        --module CONFIG_DRM_MESON \
        --module CONFIG_DRM_MESON_DW_HDMI \
        --module CONFIG_DRM_MESON_DW_MIPI_DSI

    log "FRAMEBUFFER MODULES"
    log "enable framebuffer console"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_DRM
    # CONFIG_VT=y
    # CONFIG_FRAMEBUFFER_CONSOLE=y
    # CONFIG_FB=y
    # CONFIG_FB_SIMPLE=y

    # ${SRC}/scripts/config --module CONFIG_FB \
    #     --module CONFIG_FB_CORE \
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_VT \
        --enable CONFIG_FRAMEBUFFER_CONSOLE \
        --enable CONFIG_FB \
        --enable CONFIG_FB_CORE \
        --enable CONFIG_FB_SIMPLE \
        --module CONFIG_FB_CFB_FILLRECT \
        --module CONFIG_FB_CFB_COPYAREA \
        --module CONFIG_FB_CFB_IMAGEBLIT \
        --module CONFIG_FB_SYS_FILLRECT \
        --module CONFIG_FB_SYS_COPYAREA \
        --module CONFIG_FB_SYS_IMAGEBLIT \
        --module CONFIG_FB_SYS_FOPS

    log "BRCMFMAC Wireless"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_WLAN --enable CONFIG_WIRELESS \
        --module CONFIG_BRCMFMAC \
        --enable CONFIG_BRCMFMAC_SDIO

    log "meson gx mmc"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_MMC \
        --module CONFIG_MMC_BLOCK \
        --module CONFIG_MMC_MESON_GX \
        --module CONFIG_MMC_MESON_MX_SDIO

    log "bcm bluetooth"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_BT \
        --module CONFIG_BT_HCIUART \
        --enable CONFIG_BT_HCIUART_3WIRE \
        --enable CONFIG_BT_HCIUART_BCM

    log "meson sound"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_SOUND \
        --module CONFIG_SND \
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

    log "MESON WATCHDOG MODULES"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_WATCHDOG_SYSFS \
        --module CONFIG_MESON_GXBB_WATCHDOG \
        --module CONFIG_MESON_WATCHDOG

    log "MESON NETWORK MODULES, MESON8B-DWMAC[RTL8211F Gigabit Ethernet]"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_DWMAC_MESON

    log "kernel 6.1 SERIAL_MESON need buildin, 6,6 can module"
    case "${KERVERSION}" in
        6.1.*)
            log "6.1+"
            ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_SERIAL_MESON \
                --enable CONFIG_SERIAL_MESON_CONSOLE
            ;;
        6.6.*)
            log "6.6.+"
            ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_SERIAL_MESON \
                --enable CONFIG_SERIAL_MESON_CONSOLE
            ;;
        *)
            log "6.9+"
            ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_SERIAL_MESON \
                --enable CONFIG_SERIAL_MESON_CONSOLE
            ;;
    esac

    log "MESON OTHER MODULES"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_MESON_SM \
        --module CONFIG_MDIO_BUS_MUX_MESON_G12A \
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
        --module CONFIG_CRYPTO_DEV_AMLOGIC_GXL \
        --enable CONFIG_CRYPTO_DEV_AMLOGIC_GXL_DEBUG

    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_NVMEM_MESON_EFUSE
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_NVMEM_MESON_MX_EFUSE
}
enable_container() {
    log "enable container"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_CGROUPS \
        --enable CONFIG_NAMESPACES \
        --enable CONFIG_NET_NS \
        --enable CONFIG_PID_NS \
        --enable CONFIG_USER_NS \
        --enable CONFIG_UTS_NS \
        --enable CONFIG_IPC_NS \
        --enable CONFIG_TIME_NS \
        --enable CONFIG_CGROUP_BPF \
        --enable CONFIG_CGROUP_CPUACCT \
        --enable CONFIG_CGROUP_DEVICE \
        --enable CONFIG_CGROUP_FREEZER \
        --enable CONFIG_CGROUP_HUGETLB \
        --enable CONFIG_CGROUP_PERF \
        --enable CONFIG_CGROUP_PIDS \
        --enable CONFIG_CGROUP_SCHED \
        --enable CONFIG_CGROUP_MISC \
        --enable CONFIG_CPUSETS \
        --enable CONFIG_BLK_CGROUP \
        --enable CONFIG_BLK_CGROUP_IOCOST \
        --enable CONFIG_BLK_CGROUP_IOLATENCY \
        --enable CONFIG_BLK_CGROUP_IOPRIO \
        --enable CONFIG_BLK_DEV_THROTTLING \
        --enable CONFIG_BRIDGE_VLAN_FILTERING \
        --enable CONFIG_CFS_BANDWIDTH \
        --enable CONFIG_FAIR_GROUP_SCHED \
        --enable CONFIG_IP_VS_NFCT \
        --enable CONFIG_IP_VS_PROTO_TCP \
        --enable CONFIG_IP_VS_PROTO_UDP \
        --enable CONFIG_KEYS \
        --enable CONFIG_MEMCG \
        --enable CONFIG_POSIX_MQUEUE \
        --enable CONFIG_SECCOMP \
        --enable CONFIG_SECCOMP_FILTER \
        --enable CONFIG_XFRM
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_BRIDGE \
        --module CONFIG_BRIDGE_NETFILTER \
        --module CONFIG_CRYPTO \
        --module CONFIG_CRYPTO_AEAD \
        --module CONFIG_CRYPTO_GCM \
        --module CONFIG_CRYPTO_GHASH \
        --module CONFIG_CRYPTO_SEQIV \
        --module CONFIG_DUMMY \
        --module CONFIG_INET_ESP \
        --module CONFIG_IPVLAN \
        --module CONFIG_IP_NF_FILTER \
        --module CONFIG_IP_NF_MANGLE \
        --module CONFIG_IP_NF_NAT \
        --module CONFIG_IP_NF_TARGET_MASQUERADE \
        --module CONFIG_IP_NF_TARGET_REDIRECT \
        --module CONFIG_IP_VS \
        --module CONFIG_IP_VS_RR \
        --module CONFIG_MACVLAN \
        --module CONFIG_NETFILTER_XT_MARK \
        --module CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
        --module CONFIG_NETFILTER_XT_MATCH_BPF \
        --module CONFIG_NETFILTER_XT_MATCH_CONNTRACK \
        --module CONFIG_NETFILTER_XT_MATCH_IPVS \
        --module CONFIG_NET_CLS_CGROUP \
        --module CONFIG_NF_CONNTRACK_FTP \
        --module CONFIG_NF_CONNTRACK_TFTP \
        --module CONFIG_NF_NAT \
        --module CONFIG_NF_NAT_FTP \
        --module CONFIG_NF_NAT_TFTP \
        --module CONFIG_OVERLAY_FS \
        --module CONFIG_VETH \
        --module CONFIG_VXLAN \
        --module CONFIG_XFRM_ALGO \
        --module CONFIG_XFRM_USER
}
enable_kvm() {
    log "enable KVM"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_KVM
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_KVM_GUEST
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_VIRTUALIZATION
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_PARAVIRT
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_VHOST_MENU
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VHOST_NET
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VHOST_IOTLB
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VHOST
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VHOST_NET
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VHOST_SCSI
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VHOST_VSOCK
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO \
        --enable CONFIG_VIRTIO_MENU \
        --enable CONFIG_VIRTIO_ANCHOR
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_VSOCKETS
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_VSOCKETS_COMMON
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_BLK \
        --enable CONFIG_BLK_MQ_VIRTIO
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_NET
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_BALLOON \
        --enable CONFIG_BALLOON_COMPACTION
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_INPUT
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_MMIO \
        --enable CONFIG_VIRTIO_MMIO_CMDLINE_DEVICES
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_VIRTIO_IOMMU
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_SCSI_VIRTIO
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_SND_VIRTIO
}
enable_usbip() {
    log "enable usbip modules"
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USBIP_CORE
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USBIP_VHCI_HCD
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USBIP_HOST
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USBIP_VUDC
    log "enable usbmon"
    cat <<EOF
mount -t debugfs none_debugs /sys/kernel/debug
modprobe usbmon
ls /sys/kernel/debug/usb/usbmon
cat /sys/kernel/debug/usb/devices | grep -oE "(Bus|Vendor|ProdID)=[^ ]*|Product=.*"
lsusb
# # Bus _+ u
cat /sys/kernel/debug/usb/usbmon/3u > /tmp/1.mon.out
EOF
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USB_MON
}
enable_usb_gadget() {
    log "enable g_mass_storage"
    cat <<EOF
lsusb && modprobe dummy_hcd && lsusb
modprobe g_mass_storage file=/root/disk
# idVendor=0x1d6b idProduct=0x0104 iManufacturer=Myself iProduct=VirtualBlockDevice iSerialNumber=123
mount .....
EOF
    ${SRC}/scripts/config ${DOT_CONFIG} --module CONFIG_USB_ZERO \
        --enable CONFIG_USB_G_MULTI_CDC \
        --module CONFIG_USB_G_DBGP \
        --module CONFIG_USB_AUDIO \
        --module CONFIG_USB_ETH \
        --module CONFIG_USB_G_NCM \
        --module CONFIG_USB_MASS_STORAGE \
        --module CONFIG_USB_G_SERIAL \
        --module CONFIG_USB_MIDI_GADGET \
        --module CONFIG_USB_G_PRINTER \
        --module CONFIG_USB_CDC_COMPOSITE \
        --module CONFIG_USB_G_ACM_MS \
        --module CONFIG_USB_G_MULTI \
        --module CONFIG_USB_G_HID \
        --module CONFIG_USB_G_WEBCAM \
        --module CONFIG_USB_RAW_GADGET \
        --module CONFIG_USB_GADGET \
        --module CONFIG_USB_GADGETFS \
        --module CONFIG_USB_DUMMY_HCD \
        --module CONFIG_USB_CONFIGFS
}

v4l_config() {
    log "V4L"
#        --module CONFIG_V4L2_H264 \
#        --module CONFIG_V4L2_VP9 \
#        --module CONFIG_V4L2_JPEG_HELPER \
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_VIDEO_V4L2_I2C \
        --module CONFIG_V4L2_MEM2MEM_DEV \
        --module CONFIG_V4L2_FWNODE \
        --module CONFIG_V4L2_ASYNC
}

cpu_freq() {
    log "CPU FREQUENCY SCALING"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_CPU_FREQ \
        --enable CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
        --enable CONFIG_CPU_FREQ_GOV_PERFORMANCE \
        --module CONFIG_CPU_FREQ_GOV_POWERSAVE \
        --module CONFIG_CPU_FREQ_GOV_USERSPACE \
        --module CONFIG_CPU_FREQ_GOV_ONDEMAND \
        --module CONFIG_CPU_FREQ_GOV_CONSERVATIVE \
        --enable CONFIG_CPU_FREQ_GOV_SCHEDUTIL
}

enable_acpi_efi() {
    local byes=${1:-}
    [ -z ${byes} ] && {
        log "DISABLE ACPI&EFI"
        ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_ACPI --disable CONFIG_EFI
        return
    }
    log "ENABLE ACPI&EFI"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_ACPI --enable CONFIG_EFI
}

common_config() {
    log "COMMON KERNEL CONFIG"
    ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_SYSVIPC \
        --enable CONFIG_SHMEM \
        --enable CONFIG_AIO \
        --enable CONFIG_BLOCK \
        --enable CONFIG_IO_URING
    ${SRC}/scripts/config ${DOT_CONFIG} --disable CONFIG_COMPAT \
        --disable CONFIG_ARM64_PSEUDO_NMI
    # ${SRC}/scripts/config ${DOT_CONFIG} --enable CONFIG_RCU_EXPERT
}
gen_usb_otg_devicetree() {
    log "edit arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dts:"
    log 'Valid arguments are "host", "peripheral" and "otg"'
    log 'cat /sys/firmware/devicetree/base/soc/usb@d0078080/dr_mode'
    log "peripheral mode then 1-otg, 2-host"
    log "test ok, use gadget.sh"
    log 'echo device | tee /sys/bus/platform/drivers/dwc3-meson-g12a/d0078080.usb/usb_role/d0078080.usb-role-switch/role'
    log 'echo c9100000.usb | tee /sys/bus/platform/drivers/dwc2/unbind'
    log 'echo c9100000.usb | tee /sys/bus/platform/drivers/dwc2/bind'
    log "BUGGY: not work: echo host > /sys/devices/platform/soc/d0078080.usb/usb_role/d0078080.usb-role-switch/role"
    log "rmmod dwc3_meson_g12a && modprobe dwc3_meson_g12a, usb reinit, drivers/usb/dwc3/dwc3-meson-g12a.c "
    cat <<EOF
# http://lists.infradead.org/pipermail/linux-amlogic/2017-July/004321.html
please note that device mode and OTG support on Amlogic Meson GXL is
more complicated, as it uses dwc2 and dwc3 controllers in combination:
- dwc3 is reponsible for host-only mode
- dwc2 is responsible for device-only mode
- OTG detection is done by the USB3 PHY
EOF
}

enable_module_xz_sign ${MODULE_SIGN}
enable_zram
enable_module_networks
enable_module_filesystem
enable_network_storage
enable_virtual_wifi
enable_ebpf
s905d_opt
enable_nfs_rootfs ${NFSROOTFS}
enable_acpi_efi ${ACPI_EFI}
enable_kvm
enable_container
enable_usbip
enable_usb_gadget
enable_arch_inline ${CONFIG_HZ}
enable_preempt_voluntary
common_config
cpu_freq
v4l_config
gen_usb_otg_devicetree
# yes "y" | ${CMD_MAKE} oldconfig
log "${ARCH} support defined config:" && ls ${SRC}/arch/${ARCH}/configs/ 2>/dev/null
log "${ARCH} list new config" && ${CMD_MAKE} listnewconfig 2>/dev/null
# ${CMD_MAKE} helpnewconfig
# ARCH=<arch> scripts/kconfig/merge_config.sh <...>/<platform>_defconfig <...>/android-base.config <...>/android-base-<arch>.config <...>/android-recommended.config
log "${ARCH} diff config" && [ -e "${OUTPUT}/.config.old" ] && ${SRC}/scripts/diffconfig ${OUTPUT}/.config.old ${OUTPUT}/.config 2>/dev/null
log "panhole version" && pahole --version 2>/dev/null || log "pahole no found DEBUG_INFO_BTF not effict"
log "PAGE SIZE =================> $(grep -oE "^CONFIG_ARM64_.*_PAGES" ${OUTPUT}/.config)"
read -n 1 -p "Press any key continue build device tree..." value

make_device_tree() {
    # # peripheral/host
    local mode=$1
    log "Make USB ${mode}device-tree"
    sed -i "s/dr_mode\s*=.*/dr_mode = \"${mode}\";/g" ${SRC}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dts
    grep -o "dr_mode\s*=.*" ${SRC}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dts
    ${CMD_MAKE} dtbs
    mkdir -p ${ROOTFS}/boot/dtb ${ROOTFS}/usr
    rsync -a ${OUTPUT}/arch/arm64/boot/dts/amlogic/meson-gxl-s905d-phicomm-n1.dtb ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${MYVERSION}.dtb.${mode}
}

make_device_tree peripheral
make_device_tree host
log "default: USB host mode"
cat ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${MYVERSION}.dtb.host > ${ROOTFS}/boot/dtb/phicomm-n1-${KERVERSION}${MYVERSION}.dtb

read -n 1 -p "Press any key continue build kernel & modules..." value
${CMD_MAKE} V=1 Image modules Image.gz
# ${CMD_MAKE} bindeb-pkg #gen debian deb package!!

log "INSTALL COMPRESSED KERNEL"
${CMD_MAKE} zinstall > /dev/null
${CMD_MAKE} modules_install > /dev/null
log "install ${ARCH} linux-libc-dev headers"
${CMD_MAKE} headers > /dev/null
${CMD_MAKE} INSTALL_HDR_PATH=${ROOTFS}/usr/ ARCH=${ARCH} headers_install > /dev/null
log "move asm headers to /usr/include/<libc-machine>/asm to match the structure, used by Debian-based distros (to support multi-arch)"
host_arch=$(dpkg-architecture -a${ARCH} -qDEB_HOST_MULTIARCH)
log "mkdir include/${host_arch}"
mkdir -p ${ROOTFS}/usr/include/${host_arch}
log "mv include/asm -> include/$host_arch/"
rm -rf ${ROOTFS}/usr/include/$host_arch/asm
mv ${ROOTFS}/usr/include/asm ${ROOTFS}/usr/include/$host_arch/

log "START LIST BUILD_MODULES CONFIG KEYS."
log "find . -name Kconfig | xargs -I@ grep -H <config key> @ | grep depends"
find ${SRC} -name Makefile | xargs -I@ cat @ > tmp.makefile
count=1
for it in $(cat ${OUTPUT}/modules.builtin); do
    ko=$(basename ${it})
    ko_dot_o=${ko%.*}.o
    set +o errexit
    grep "obj-.* ${ko_dot_o}" tmp.makefile | grep -o "CONFIG_[^)]*" | sort | uniq | while IFS='\n' read line || [ -n "$line" ]; do
        log "$count : $ko            ->        $line"
    done
    set -o errexit
    let count++
done
rm -f tmp.makefile
log "END LIST BUILD_MODULES CONFIG KEYS."

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} /bin/bash -x<<EOSHELL
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
${CMD_MAKE} tinyconfig
${CMD_MAKE} kvm_guest.config
${CMD_MAKE} kvmconfig
EOF
