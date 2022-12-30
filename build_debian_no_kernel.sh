#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("c5d525f[2022-12-30T16:58:34+08:00]:build_debian_no_kernel.sh")
[ -e ${DIRNAME}/os_debian_init.sh ] && . ${DIRNAME}/os_debian_init.sh || { echo '**ERROR: os_debian_init.sh nofound!'; exit 1; }
################################################################################
log() { echo "######$*" >&2; }
export -f log

old_ifs="$IFS" IFS=','
custom_pkgs="$*"
IFS=$old_ifs

PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools"
PKG+=",udev,isc-dhcp-client,netbase,console-setup,systemd-timesyncd,cron,rsyslog,logrotate"
PKG+=",grub2-common,grub-pc-bin,grub-efi-ia32-bin,grub-efi-amd64-bin,grub-efi-amd64-signed,dosfstools,fdisk,parted,xfsprogs"
PKG+=",bridge-utils"
PKG+=",dhcp-helper"
PKG+=",dnsutils"
PKG+=",iputils-ping"
PKG+=",nmon"
PKG+=",nscd"
PKG+=",openssh-client"
PKG+=",openssh-server"
PKG+=",rsync"
PKG+=",pbzip2"
PKG+=",pixz"
PKG+=",sshfs"
PKG+=",sysstat"
PKG+=",wireguard-tools"
PKG+=",xz-utils"
PKG+=",zstd,lsof,net-tools,telnet,vim"
PKG+="${custom_pkgs:+,${custom_pkgs}}"

[ "$(id -u)" -eq 0 ] || { log "Must be root to run this script."; exit 1; }

CACHE_DIR=${DIRNAME}/cache-${DEBIAN_VERSION:-bullseye}
ROOT_DIR=${DIRNAME}/rootfs-${DEBIAN_VERSION:-bullseye}
mkdir -p ${ROOT_DIR}
mkdir -p ${CACHE_DIR}

DEBIAN_VERSION=${DEBIAN_VERSION:-bullseye} \
    INST_ARCH=amd64 \
    REPO=${REPO:-http://mirrors.aliyun.com/debian} \
    HOSTNAME="srv1" \
    NAME_SERVER=114.114.114.114 \
    PASSWORD=password \
    debian_build "${ROOT_DIR}" "${CACHE_DIR}" "${PKG}"

log "generate grub config"
cat << 'EOF' > ${ROOT_DIR}/etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0"
GRUB_CMDLINE_LINUX=""
EOF

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOT_DIR} /bin/bash <<EOSHELL
    /bin/mkdir -p /dev/pts && /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts || true
    /bin/mknod -m 666 /dev/null c 1 3 2>/dev/null || true

    debian_zswap_init 512
    debian_sshd_init
    debian_vim_init

    systemctl mask systemd-machine-id-commit.service

    # timedatectl set-local-rtc 0
    log "Force Users To Change Passwords Upon First Login"
    chage -d 0 root || true
    systemctl disable fstrim.timer e2scrub_all.timer apt-daily.timer apt-daily-upgrade.timer systemd-pstore.service e2scrub_reap.service rsync.service || true
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
auto eth0
allow-hotplug eth0
iface eth0 inet manual

auto br-ext
iface br-ext inet static
    bridge_ports eth0
    bridge_maxwait 0
    address 192.168.168.2/24
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
