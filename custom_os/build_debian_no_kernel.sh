#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("91a06b1[2023-08-14T10:08:21+08:00]:build_debian_no_kernel.sh")
[ -e ${DIRNAME}/os_debian_init.sh ] && . ${DIRNAME}/os_debian_init.sh || { echo '**ERROR: os_debian_init.sh nofound!'; exit 1; }
################################################################################
log() { echo "######$*" >&2; }
export -f log
cat <<HELP
HELP:
DEBIAN_VERSION=bookworm ./build_debian_no_kernel.sh linux-image-amd64 dbus-user-session qemu-guest-agent cloud-init cloud-initramfs-growroot
HELP
old_ifs="$IFS" IFS=','
custom_pkgs="$*"
IFS=$old_ifs

PKG="efibootmgr"

case "${INST_ARCH:-}" in
    arm64)
        PKG+=",grub2-common,grub-efi,grub-efi-arm64-bin,grub-efi-arm64-signed,shim-signed"
        ;;
    *)
        PKG+=",grub2-common,grub-pc-bin,grub-efi-amd64-bin,grub-efi-amd64-signed,shim-signed"
        # biosdevname"
        ;;
esac
PKG+=",dosfstools,fdisk,xfsprogs"
PKG+=",libc-bin,tzdata,locales,apt-utils,systemd-sysv,ifupdown,initramfs-tools"
PKG+=",udev,isc-dhcp-client,netbase,console-setup,cron,rsyslog,logrotate"
PKG+=",parted"
PKG+=",systemd-timesyncd"
# PKG+=",dialog"
# PKG+=",dbus-user-session"
# PKG+=",bridge-utils"
PKG+=",dnsutils"
PKG+=",lsof"
PKG+=",telnet"
PKG+=",rsync"
PKG+=",sshfs"
PKG+=",sysstat"
PKG+=",zstd"
PKG+=",net-tools"
PKG+=",iputils-ping"
PKG+=",openssh-client"
PKG+=",openssh-server"
PKG+=",xz-utils"
PKG+=",vim"
PKG+="${custom_pkgs:+,${custom_pkgs}}"
[ "$(id -u)" -eq 0 ] || { log "Must be root to run this script."; exit 1; }

CACHE_DIR=${DIRNAME}/cache-${DEBIAN_VERSION:-bullseye}
ROOT_DIR=${DIRNAME}/rootfs-${DEBIAN_VERSION:-bullseye}
mkdir -p ${ROOT_DIR}
mkdir -p ${CACHE_DIR}

DEBIAN_VERSION=${DEBIAN_VERSION:-bullseye} \
    INST_ARCH=${INST_ARCH:-amd64} \
    REPO=${REPO:-http://mirrors.aliyun.com/debian} \
    HOSTNAME="srv1" \
    NAME_SERVER=114.114.114.114 \
    PASSWORD=password \
    debian_build "${ROOT_DIR}" "${CACHE_DIR}" "${PKG}"

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOT_DIR} /bin/bash <<EOSHELL
    /bin/mkdir -p /dev/pts && /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts || true
    /bin/mknod -m 666 /dev/null c 1 3 2>/dev/null || true

    debian_grub_init
    debian_zswap_init 512
    debian_sshd_init
    debian_vim_init

    systemctl mask systemd-machine-id-commit.service

    # timedatectl set-local-rtc 0
    log "Force Users To Change Passwords Upon First Login"
    chage -d 0 root || true
    debian_service_init
    /bin/umount /dev/pts
    exit
EOSHELL

log "modify networking waitonline tiemout to 5s"
sed -i "s|TimeoutStartSec=.*|TimeoutStartSec=5sec|g" ${ROOT_DIR}/lib/systemd/system/networking.service

cat << EOF > ${ROOT_DIR}/etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat << EOF > ${ROOT_DIR}/etc/network/interfaces.d/br-ext
# auto eth0
allow-hotplug eth0
iface eth0 inet manual

auto br-ext
iface br-ext inet static
    bridge_ports eth0
    bridge_maxwait 0
    address 192.168.168.101/24
    gateway 192.168.168.1
EOF

cat <<EOF > ${ROOT_DIR}/etc/nftables.conf
#!/usr/sbin/nft -f
flush ruleset
EOF
chmod 755 ${ROOT_DIR}/etc/nftables.conf

log "SUCCESS build rootfs, all!!!"

log "start chroot shell, disable service & do other work"
chroot ${ROOT_DIR} /usr/bin/env -i PS1='\u@pcsrv:\w$' /bin/bash --noprofile --norc -o vi || true
chroot ${ROOT_DIR} /bin/bash -s <<EOF
    debian_minimum_init
EOF
log "ALL OK ###########################"
exit 0
