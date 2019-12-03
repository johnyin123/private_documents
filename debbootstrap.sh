#!/bin/bash
#fw_setenv bootcmd "run update"; reboot
#之后PC端的刷机程序就会检测到设备进入刷机模式，按软件的刷机提示刷机即可。
set -o errexit -o nounset -o pipefail

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

REPO=http://mirrors.163.com/debian
PASSWORD=password
export DIRNAME="$(pwd)"
#DIRNAME="$(dirname "$(realpath "$0")")"
#DIRNAME="$(dirname "$(readlink -e "$0")")"
export SCRIPTNAME=${0##*/}
export DEBIAN_VERSION=${DEBIAN_VERSION:-buster}
export FS_TYPE=${FS_TYPE:-ext4}
BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
OVERLAY_LABEL="EMMCOVERLAY"

ZRAMSWAP="udisks2"
#ZRAMSWAP="zram-tools"
PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools,jfsutils,u-boot-tools,fake-hwclock,openssh-server,busybox"
PKG="${PKG},udev,isc-dhcp-client,netbase,console-setup,pkg-config,net-tools,wpasupplicant,iputils-ping,telnet,vim,ethtool,${ZRAMSWAP},bridge-utils,dosfstools,iw,ipset,nmap,ipvsadm"

if [ "$UID" -ne "0" ]
then 
    echo "Must be root to run this script." 
    exit 1
fi

cleanup() {
    trap '' INT TERM EXIT
    echo "EXIT!!!"
}

final_disk() {
    umount ${DIRNAME}/buildroot/
    losetup -d ${DIRNAME}/DISK.IMG
}

prepair_disk() {
    # DISK="/dev/sdb"
    # PART_BOOT="/dev/sdb1"
    # PART_ROOT="/dev/sdb2"

    truncate -s 8G ${DIRNAME}/DISK.IMG
    DISK=$(losetup -fP --show ${DIRNAME}/DISK.IMG)
    PART_BOOT="${DISK}p1"
    PART_ROOT="${DISK}p2"
    PART_OVERLAY="${DISK}p3"

    parted -s "${DISK}" "mklabel msdos"
    parted -s "${DISK}" "mkpart primary fat32 1M 128M"
    parted -s "${DISK}" "mkpart primary ${FS_TYPE} 128M 1G"
    parted -s "${DISK}" "mkpart primary ext4 1G 100%"

    echo -n "Formatting BOOT partition..."
    mkfs.vfat -n "${BOOT_LABEL}" ${PART_BOOT}
    echo "done."

    echo "Formatting ROOT partition..."
    mkfs -t ${FS_TYPE} -q -L "${ROOT_LABEL}" ${PART_ROOT}
    echo "done."
    mount ${PART_ROOT} ${DIRNAME}/buildroot/

    mke2fs -FL "${OVERLAY_LABEL}" -t ext4 -E lazy_itable_init,lazy_journal_init ${PART_OVERLAY}
}
mkdir -p ${DIRNAME}/buildroot

if [ -d "${DIRNAME}/deb-cache" ]; then
    mkdir -p ${DIRNAME}/buildroot/var/cache/apt/archives/
    cp ${DIRNAME}/deb-cache/* ${DIRNAME}/buildroot/var/cache/apt/archives/ || true
    sync;sync
fi

trap cleanup EXIT
trap cleanup TERM
trap cleanup INT

debootstrap --verbose --no-check-gpg --arch arm64 --variant=minbase --include=${PKG} --foreign ${DEBIAN_VERSION} ${DIRNAME}/buildroot ${REPO} 

cp /usr/bin/qemu-aarch64-static ${DIRNAME}/buildroot/usr/bin/

unset PROMPT_COMMAND
LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /debootstrap/debootstrap --second-stage

LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL

echo usb905d > /etc/hostname

echo "Enable udisk2 zram swap"
mkdir -p /usr/local/lib/zram.conf.d/
echo "zram" >> /etc/modules
cat << EOF > /usr/local/lib/zram.conf.d/zram0-env
ZRAM_NUM_STR=lzo
#512
ZRAM_DEV_SIZE=536870912
SWAP=y
EOF

cat << EOF > /etc/hosts
127.0.0.1       localhost usb905d
EOF

cat > /etc/fstab << EOF
LABEL=${ROOT_LABEL}    /    ${FS_TYPE}    defaults,errors=remount-ro,noatime    0    1
LABEL=${BOOT_LABEL}    /boot    vfat    ro    0    2
tmpfs /var/log  tmpfs   defaults,noatime,nosuid,nodev,noexec,size=16M  0  0
EOF

echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
#echo 'APT::Install-Recommends "0";'> /etc/apt/apt.conf.d/71-no-recommends
#echo 'APT::Install-Suggests "0";'> /etc/apt/apt.conf.d/72-no-suggests


cat > /etc/apt/sources.list << EOF
deb http://mirrors.163.com/debian ${DEBIAN_VERSION} main non-free contrib
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-proposed-updates main non-free contrib
deb http://mirrors.163.com/debian-security ${DEBIAN_VERSION}/updates main contrib non-free
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

#Installing packages without docs
cat >  /etc/dpkg/dpkg.cfg.d/01_nodoc <<EOF
path-exclude /usr/share/doc/*
# we need to keep copyright files for legal reasons
path-include /usr/share/doc/*/copyright
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
# lintian stuff is small, but really unnecessary
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
EOF
#apt update
#apt -y upgrade

#dpkg-reconfigure locales
sed -i "s/^# *zh_CN.UTF-8/zh_CN.UTF-8/g" /etc/locale.gen
locale-gen
echo -e 'LANG="zh_CN.UTF-8"\nLANGUAGE="zh_CN:zh"\nLC_ALL="zh_CN.UTF-8"\n' > /etc/default/locale

#echo "Asia/Shanghai" > /etc/timezone
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
dpkg-reconfigure -f noninteractive openssh-server
cat << EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat << EOF > /etc/network/interfaces.d/br-ext
auto eth0
allow-hotplug eth0
iface eth0 inet manual

auto br-ext
iface br-ext inet static
    bridge_ports eth0
    address 192.168.168.168/24
    #mtu 1500
    #hwaddress 11:22:33:44:55:66
    #netmask 255.255.255.0
    #gateway 192.168.168.1
    #up (ip route add 10.0.0.0/8 via 10.32.166.1 || true)
EOF

cat << EOF > /etc/network/interfaces.d/wifi
auto wlan0
allow-hotplug wlan0
iface wlan0 inet manual
    wpa-roam /etc/wpa.conf
    pre-up (iw dev wlan0 set power_save off || true)
    pre-up (iw phy phy0 interface add adminap type __ap)
iface xkadmin inet dhcp
#    post-up (ip r a default via 10.32.166.129||true)

iface adminap inet static
    address 192.168.167.1/24

EOF

cat << EOF > /etc/wpa.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
ap_scan=1
network={
    ssid="xk-admin"
    scan_ssid=1
    #key_mgmt=wpa-psk
    psk="ADMIN@123"
    id_str="xkadmin"
    priority=1
}
#host ap mod
network={
    #frequency=60480
    ssid="s905d2"
    mode=2
    key_mgmt=NONE
    id_str="adminap"
    priority=2
}

EOF

#漫游
cat << EOF > /etc/modprobe.d/brcmfmac.conf 
options brcmfmac roamoff=1
EOF

cat << EOF > /etc/rc.local
#!/bin/sh -e
exit 0
EOF
chmod 755 /etc/rc.local

echo "enable fw_printenv command"
cat >/etc/fw_env.config <<EOF
# Device to access      offset          env size
/dev/mmcblk1            0x27400000      0x10000
EOF

cat >>/etc/initramfs-tools/modules <<EOF
jfs
brcmfmac
dwmac_meson8b
overlay
EOF

mkdir -p /etc/initramfs/post-update.d/

cat>/etc/initramfs/post-update.d/99-uboot<<"EOF"
#!/bin/sh
echo "update-initramfs: Converting to u-boot format" >&2
tempname="/boot/uInitrd-\$1"
mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d \$2 \$tempname > /dev/null
exit 0
EOF
chmod 755 /etc/initramfs/post-update.d/99-uboot

echo "修改systemd journald日志存放目录为内存，也就是/run/log目录，限制最大使用内存空间64MB"

sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=64M/' /etc/systemd/journald.conf

cat >/etc/profile.d/johnyin.sh<<"EOF"
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF

sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/g' /etc/ssh/sshd_config
echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
echo "MACs    hmac-sha1" >> /etc/ssh/sshd_config
echo "PermitRootLogin yes">> /etc/ssh/sshd_config

#set the file limit
cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
cat > /root/aptrom.sh <<EOF
#!/usr/bin/env bash

mount -o remount,rw /overlay/lower
cp /overlay/lower/etc/apt/sources.list ~/sources.list.bak

mount -o remount,rw /overlay/lower

cat >/overlay/lower/etc/apt/sources.list<<EOF
deb http://mirrors.163.com/debian buster main non-free contrib
deb http://mirrors.163.com/debian buster-proposed-updates main non-free contrib
deb http://mirrors.163.com/debian-security buster/updates main contrib non-free
deb http://mirrors.163.com/debian buster-backports main contrib non-free
EOF

chroot /overlay/lower apt update
chroot /overlay/lower apt install \$*

rm -rf /overlay/lower/var/cache/apt/* /overlay/lower/var/lib/apt/lists/* /overlay/lower/var/log/*
rm -rf /overlay/lower/root/.bash_history /overlay/lower/root/.viminfo /overlay/lower/root/.vim/
cat ~/sources.list.bak > /overlay/lower/etc/apt/sources.list
rm -f ~/sources.list.bak
sync
mount -o remount,ro /overlay/lower

EOF
cat >> /root/inst.sh <<EOF
if [ -d "/etc/ssh/" ] ; then
  # Remove ssh host keys
  rm -f /etc/ssh/ssh_host_*
  systemctl stop sshd

  # Regenerate ssh host keys
  ssh-keygen -q -t rsa -N "" -f /etc/ssh/ssh_host_rsa_key
  ssh-keygen -q -t dsa -N "" -f /etc/ssh/ssh_host_dsa_key
  ssh-keygen -q -t ecdsa -N "" -f /etc/ssh/ssh_host_ecdsa_key
  ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
  systemctl start sshd
fi

if [ -d "/etc/dropbear/" ] ; then
  # Remove ssh host keys
  rm -f /etc/dropbear/dropbear_*
  systemctl stop dropbear

  # Regenerate ssh host keys
  dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
  dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key
  dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
  systemctl start dropbear
fi

#create AP intreface
iw phy phy0 interface add ap0 type __ap
ifconfig ap0 down
ifconfig ap0 hw ether 18:3F:47:95:DF:0B
ifconfig ap0 up
# Configure IP address for WLAN
ifconfig ap0 192.168.150.1
# Start DHCP/DNS server
# Enable routing
# sysctl net.ipv4.ip_forward=1
# Enable NAT
# iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
# Run access point daemon
# hostapd /etc/hostapd.conf

#led
echo 0 > /sys/devices/platform/leds/leds/n1\:white\:status/brightness
echo 255 > /sys/devices/platform/leds/leds/n1\:white\:status/brightness
#get temp
awk '{print \$1/1000}' /sys/class/hwmon/hwmon0/temp1_input
journalctl -alb
apt install --no-install-recommends  rsyslog
systemctl enable getty@tty1
systemctl enable getty@tty2
#systemctl set-default multi-user.target
#ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

#multimedia
echo "deb http://www.deb-multimedia.org ${DEBIAN_VERSION} main non-free" > /etc/apt/sources.list.d/multimedia.conf
apt-get update -oAcquire::AllowInsecureRepositories=true
apt-get install deb-multimedia-keyring
#bluetooth
apt install --no-install-recommends blueman pulseaudio pulseaudio-module-bluetooth pavucontrol mpg123

apt install --no-install-recommends bluez pulseaudio-module-bluetooth alsa-utils mpg123
#pulseaudio --start for root
sed -i "/ConditionUser=.*/d" /usr/lib/systemd/user/pulseaudio.service
sed -i "/ConditionUser=.*/d" /usr/lib/systemd/user/pulseaudio.socket

systemctl enable pulseaudio.service --user
systemctl start pulseaudio.service --user

bluetoothctl
    power on
    agent on
    default-agent
    scan on
    pair xx:xx:xx:xx:xx:xx
    trust xx:xx:xx:xx:xx:xx
    connect xx:xx:xx:xx:xx:xx
    scan off
    exit

If you're pairing a keyboard, you will need to enter a six-digit string of numbers. 
You will see that the device has been paired, but it may not have connected. To connect the device, 
type connect XX:XX:XX:XX:XX:XX.


apt-get install --no-install-recommends pulseaudio-module-bluetooth bluez-tools
    Add users to groups. This is very important. If using any other distro, replace ‘johnyin’ with your username.
gpasswd -a johnyin pulse
gpasswd -a johnyin lp
gpasswd -a pulse lp
gpasswd -a johnyin audio
gpasswd -a pulse audio
    Set up PulseAudio, Bluetooth Device Class
echo 'extra-arguments = --exit-idle-time=-1 --log-target=syslog' >> /etc/pulse/client.conf
hciconfig hci0 up
hciconfig hci0 class 0x200420
reboot
The Bluetooth service/device class 0x200420 mean the device is set up for Car Audio. 
See http://bluetooth-pentest.narod.ru/software/bluetooth_class_of_device-service_generator.html to explore more Bluetooth Class options.

#Xfce
apt install --no-install-recommends lightdm xserver-xorg-core xinit xserver-xorg-video-fbdev xfce4 xfce4-terminal xserver-xorg-input-all
apt install --no-install-recommends mpv smplayer qt4-qtconfig libqt4-opengl
ldconfig
EOF

cat >> /etc/sysctl.conf << EOF
net.core.rmem_max = 134217728 
net.core.wmem_max = 134217728 
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.core.wmem_default = 16777216
net.ipv4.ip_local_port_range = 1024 65530
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_timestamps = 0
#net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 0
EOF

cat >> /etc/vim/vimrc.local <<EOF
syntax on
" color evening
set number
set nowrap
set fileencodings=utf-8,gb2312,gbk,gb18030
" set termencoding=utf-8
let &termencoding=&encoding
set fileformats=unix
set hlsearch                 " highlight the last used search pattern
set noswapfile
set tabstop=4                " 设置tab键的宽度
set shiftwidth=4             " 换行时行间交错使用4个空格
set expandtab                " 用space替代tab的输入
set autoindent               " 自动对齐
set backspace=2              " 设置退格键可用
set cindent shiftwidth=4     " 自动缩进4空格
set smartindent              " 智能自动缩进
"Paste toggle - when pasting something in, don't indent.
set pastetoggle=<F7>
set mouse=r
EOF
sed -i "/mouse=a/d" /usr/share/vim/vim81/defaults.vim

usermod -p '$(echo ${PASSWORD} | openssl passwd -1 -stdin)' root
# echo "root:${PASSWORD}" |chpasswd 
echo "Force Users To Change Their Passwords Upon First Login"
chage -d 0 root

apt -y install --no-install-recommends cron logrotate bsdmainutils rsyslog openssh-client wget ntpdate less wireless-tools file fonts-droid-fallback lsof strace rsync
apt -y install --no-install-recommends xz-utils zip


exit

EOSHELL

echo "add emmc_install script"
cat >> ${DIRNAME}/buildroot/root/emmc_linux.sh <<'EOF'
#!/usr/bin/env bash

BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
OVERLAY_LABEL="EMMCOVERLAY"

####################################################################################################
echo "Start script create MBR and filesystem"
ENV_LOGO_PART_START=288768  #sectors
DEV_EMMC=${DEV_EMMC:=/dev/mmcblk1}
echo "So as to not overwrite U-boot, we backup the first 1M."
dd if=${DEV_EMMC} of=/tmp/boot-bak bs=1M count=4
echo "(Re-)initialize the eMMC and create partition."
echo "bootloader & reserved occupies [0, 100M]. Since sector size is 512B, byte offset would be 204800."
echo "Start create MBR and partittion"
echo "mmcblk0p04  env   offset 0x000027400000  size 0x000000800000"
echo "mmcblk0p05  logo  offset 0x000028400000  size 0x000002000000"
parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 204800s $((ENV_LOGO_PART_START-1))s
parted -s "${DEV_EMMC}" mkpart primary ext4 ${ENV_LOGO_PART_START}s 1G
parted -s "${DEV_EMMC}" mkpart primary ext4 1G 100%
echo "Start restore u-boot"
# Restore U-boot (except the first 442 bytes, where partition table is stored.)
dd if=/tmp/boot-bak of=${DEV_EMMC} conv=fsync bs=1 count=442
dd if=/tmp/boot-bak of=${DEV_EMMC} conv=fsync bs=512 skip=1 seek=1
# This method is used to convert byte offset in `/dev/mmcblk1` to block offset in `/dev/mmcblk1p2`.
as_block_number() {
    # Block numbers are offseted by ${ENV_LOGO_PART_START} sectors
    # Because we're using 4K blocks, the byte offsets are divided by 4K.
    expr $((($1 - $ENV_LOGO_PART_START*512) / 4096))
}
# This method generates a sequence of block number in range [$1, $1 + $2).
# It's used for marking several reserved regions as bad blocks below.
gen_blocks() {
    seq $(as_block_number $1) $(($(as_block_number $(($1 + $2))) - 1))
}

# Mark reserved regions as bad block to prevent Linux from using them.
# /dev/env: This "device" (present in Linux 3.x) uses 0x27400000 ~ +0x800000.
#           It seems that they're overwritten each time system boots if value
#           there is invalid. Therefore we must not touch these blocks.
#
# /dev/logo: This "device"  uses 0x28400000~ +0x800000. You may mark them as
#            bad blocks if you want to preserve or replace the boot logo.
#
# All other "devices" (i.e., `recovery`, `rsv`, `tee`, `crypt`, `misc`, `boot`,
# `system`, `data` should be safe to overwrite.)
gen_blocks 0x27400000 0x800000 > /tmp/reservedblks
echo "Marked blocks used by env partition start=0x28400000 size=0x800000 as bad."
echo "dd if=/boot/n1-logo.img of=/dev/mmcblk1 bs=1M seek=644 can install new logo"
gen_blocks 0x28400000 0x2000000 >> /tmp/reservedblks
echo "Marked blocks used by /dev/logo start=0x28400000 size=0x2000000 as bad."

DISK=${DEV_EMMC}
PART_BOOT="${DISK}p1"
PART_ROOT="${DISK}p2"
PART_OVERLAY="${DISK}p3"

echo "Format the partitions."
mkfs.vfat -n ${BOOT_LABEL} ${PART_BOOT}
mkfs -t ext4 -m 0 -b4096 -l /tmp/reservedblks -q -L ${ROOT_LABEL} ${PART_ROOT}
mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${PART_OVERLAY}

echo "Flush changes (in case they were cached.)."
sync
echo "show reserved!!"
false && dumpe2fs -b ${PART_ROOT}
echo "Partition table (re-)initialized."

EOF

echo "start install you kernel&patchs"
if [ -d "${DIRNAME}/kernel" ]; then
    rsync -avzP ${DIRNAME}/kernel/* ${DIRNAME}/buildroot/ || true
fi
echo "end install you kernel&patchs"

echo "start install overlay_rootfs"
cat <<EOF
kernel parm "skipoverlay"
overlayfs lable "${OVERLAY_LABEL}"
/overlay/reformatoverlay exist will format it!
EOF

if ! grep -q "^overlay" ${DIRNAME}/buildroot/etc/initramfs-tools/modules; then
    echo overlay >> ${DIRNAME}/buildroot/etc/initramfs-tools/modules
fi

cat > ${DIRNAME}/buildroot/usr/share/initramfs-tools/hooks/overlay <<EOF
#!/bin/sh

. /usr/share/initramfs-tools/scripts/functions
. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/blkid
copy_exec /sbin/fsck
copy_exec /sbin/mke2fs
copy_exec /sbin/fsck.f2fs
copy_exec /sbin/fsck.ext2
copy_exec /sbin/fsck.ext3
copy_exec /sbin/fsck.ext4
copy_exec /sbin/logsave
cp -p /lib/firmware/regulatory.db \$DESTDIR/lib/firmware/
cp -p /lib/firmware/regulatory.db.p7s \$DESTDIR/lib/firmware/
EOF

cat > ${DIRNAME}/buildroot/etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay <<'EOF'
#!/bin/sh

PREREQ=""
prereqs()
{
   echo "$PREREQ"
}

case $1 in
prereqs)
   prereqs
   exit 0
   ;;
esac

. /scripts/functions

if grep -q -E '(^|\s)skipoverlay(\s|$)' /proc/cmdline; then
    log_begin_msg "Skipping overlay, found 'skipoverlay' in cmdline"
    log_end_msg
    exit 0
fi

log_begin_msg "Starting overlay"
log_end_msg

mkdir -p /overlay

EOF
cat >> ${DIRNAME}/buildroot/etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay <<EOF
# if we have a filesystem label of OVERLAY
# use that as the overlay, otherwise use tmpfs.
OLDEV=\`blkid -L ${OVERLAY_LABEL}\`
if [ -z "\${OLDEV}" ]; then
    mount -t tmpfs tmpfs /overlay
else
    _checkfs_once \${OLDEV} /overlay ext4 >> /log.txt 2>&1 ||  \
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init \${OLDEV}
    if ! mount \${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

# if you sudo touch /overlay/reformatoverlay
# next reboot will give you a fresh /overlay
if [ -f /overlay/reformatoverlay ]; then
    umount /overlay
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init \${OLDEV}
    if ! mount \${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi
EOF
cat > ${DIRNAME}/buildroot/etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay <<'EOF'

mkdir -p /overlay/upper
mkdir -p /overlay/work
mkdir -p /overlay/lower

# make the readonly root available
mount -n -o move ${rootmnt} /overlay/lower
mount -t overlay overlay -olowerdir=/overlay/lower,upperdir=/overlay/upper,workdir=/overlay/work ${rootmnt}

mkdir -p ${rootmnt}/overlay
mount -n -o rbind /overlay ${rootmnt}/overlay

# fix up fstab
cp ${rootmnt}/etc/fstab ${rootmnt}/etc/fstab.orig
awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab.orig > ${rootmnt}/etc/fstab
awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab >> ${rootmnt}/etc/fstab

exit 0
EOF
chmod 755 ${DIRNAME}/buildroot/usr/share/initramfs-tools/hooks/overlay
chmod 755 ${DIRNAME}/buildroot/etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay

echo "end install overlay_rootfs"
echo "you need run 'apt -y install busybox && update-initramfs -c -k KERNEL_VERSION'"
# autologin-guest=false
# autologin-user=user(not root)
# autologin-user-timeout=0
# groupadd -r autologin
# gpasswd -a root autologin

chroot ${DIRNAME}/buildroot/ /bin/bash
chroot ${DIRNAME}/buildroot/ apt clean
rm ${DIRNAME}/buildroot/dev/* ${DIRNAME}/buildroot/var/log/* -fr
# Remove all doc files
find "${DIRNAME}/buildroot/usr/share/doc" -depth -type f ! -name copyright -print0 | xargs -0 rm || true
find "${DIRNAME}/buildroot/usr/share/doc" -empty -print0 | xargs -0 rm -rf || true
# Remove all man pages and info files
rm -rf "${DIRNAME}/buildroot/usr/share/man" "${DIRNAME}/buildroot/usr/share/groff" "${DIRNAME}/buildroot/usr/share/info" "${DIRNAME}/buildroot/usr/share/lintian" "${DIRNAME}/buildroot/usr/share/linda" "${DIRNAME}/buildroot/var/cache/man"
exit 0

gen_uEnv_ini() {
    cat > /boot/uEnv.ini <<EOF
dtb_name=/dtb/meson-gxl-s905d-phicomm-n1.dtb
bootargs=root=LABEL=${ROOT_LABEL} rootflags=rw fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 
EOF
}
gen_s905_emmc_autoscript() {
    cat > /boot/emmc_autoscript <<'EOF'
setenv env_addr "0x10400000"
setenv kernel_addr "0x11000000"
setenv initrd_addr "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv boot_start booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr}
if fatload mmc 1 ${kernel_addr} zImage; then if fatload mmc 1 ${initrd_addr} uInitrd; then if fatload mmc 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; fi; if fatload mmc 1 ${dtb_mem_addr} ${dtb_name}; then run boot_start;fi;fi;fi;
EOF
}

gen_s905_net_boot_autoscript() {
    cat > /boot/s905_autoscript.nfs.cmd <<'EOF'
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv serverip 192.168.168.2
setenv ipaddr 192.168.168.168
setenv bootargs "root=/dev/nfs nfsroot=${serverip}:/nfsshare/root rw net.ifnames=0 console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 rootwait"
setenv bootcmd_pxe "tftp ${kernel_addr} zImage; tftp ${initrd_addr} uInitrd; tftp ${dtb_mem_addr} dtb.img; booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr} "
run bootcmd_pxe
EOF
}

gen_s905_autoscript() {
    cat > /boot/s905_autoscript.cmd <<'EOF'
setenv env_addr     "0x10400000"
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv boot_start booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr}
if fatload usb 0 ${kernel_addr} zImage; then if fatload usb 0 ${initrd_addr} uInitrd; then if fatload usb 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize};fi; if fatload usb 0 ${dtb_mem_addr} ${dtb_name}; then run boot_start; else store dtb read ${dtb_mem_addr}; run boot_start;fi;fi;fi;
if fatload usb 1 ${kernel_addr} zImage; then if fatload usb 1 ${initrd_addr} uInitrd; then if fatload usb 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize};fi; if fatload usb 1 ${dtb_mem_addr} ${dtb_name}; then run boot_start; else store dtb read ${dtb_mem_addr}; run boot_start;fi;fi;fi;
if fatload mmc 0 ${kernel_addr} zImage; then if fatload mmc 0 ${initrd_addr} uInitrd; then if fatload mmc 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize};fi; if fatload mmc 0 ${dtb_mem_addr} ${dtb_name}; then run boot_start; else store dtb read ${dtb_mem_addr}; run boot_start;fi;fi;fi;
EOF
}

install_bootloader() {
    gen_uEnv_ini
    gen_s905_autoscript
    mkimage -C none -A arm -T script -d s905_autoscript.cmd s905_autoscript
    mkimage -C none -A arm -T script -d s905_autoscript.nfs.cmd s905_autoscript.nfs
    mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d initramfs-linux.img uInitrd
}

build_mesa_19_10() {
apt -y install build-essential cmake python3-mako meson pkg-config bison flex gettext zlib1g-dev
apt -y install libexpat1-dev libxrandr-dev
apt -y install wayland-protocols libwayland-egl-backend-dev

tar xvf ...
cd mesa
mkdir build
meson build/ -Dprefix=/usr/ 
meson configure build/ -Dprefix=/usr/ 
ninja -C build/
ninja -C build/ install

meson build -Dvulkan-drivers=[] -Dplatforms=drm,x11 -Ddri-drivers=[] -Dgallium-drivers=lima,kmsro
}

net_demo() {
cat > interfaces.hostapd << EOF
auto lo br0
iface lo inet loopback

auto eth0
iface eth0 inet manual

auto wlan0
iface wlan0 inet manual

iface br0 inet dhcp
bridge_ports eth0 wlan0
#hwaddress ether # will be added at first boot
EOF
cat > interfaces.bonding << EOF
auto eth0
iface eth0 inet manual
    bond-master bond0
    bond-primary eth0
    bond-mode active-backup
   
auto wlan0
iface wlan0 inet manual
    wpa-ssid your_SSID
    wpa-psk xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    # to generate proper encrypted key: wpa_passphrase your_SSID your_password
    bond-master bond0
    bond-primary eth0
    bond-mode active-backup
   
# Define master
auto bond0
iface bond0 inet dhcp
    bond-slaves none
    bond-primary eth0
    bond-mode active-backup
    bond-miimon 100
EOF

cat > interfaces.router << EOF

auto lo
iface lo inet loopback

auto eth0.101
iface eth0.101 inet manual
    pre-up swconfig dev eth0 set reset 1
    pre-up swconfig dev eth0 set enable_vlan 1
    pre-up swconfig dev eth0 vlan 101 set ports '3 8t'
    pre-up swconfig dev eth0 set apply 1

auto eth0.102
iface eth0.102 inet manual
    pre-up swconfig dev eth0 vlan 102 set ports '0 1 2 4 8t'
    pre-up swconfig dev eth0 set apply 1

allow-hotplug wlan0
iface wlan0 inet manual

# WAN
auto eth0.101
iface eth0.101 inet dhcp

# LAN
auto br0
iface br0 inet static
bridge_ports eth0.102 wlan0
    address 192.168.2.254
    netmask 255.255.255.0
EOF
cat > interfaces.switch << EOF
auto lo
iface lo inet loopback

auto eth0.101
iface eth0.101 inet manual
    pre-up swconfig dev eth0 set reset 1
    pre-up swconfig dev eth0 set enable_vlan 1
    pre-up swconfig dev eth0 vlan 101 set ports '0 1 2 3 4 8t'
    pre-up swconfig dev eth0 set apply 1

auto wlan0
iface wlan0 inet manual

auto br0
iface br0 inet dhcp
bridge_ports eth0.101 wlan0
EOF

}
cat <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="SCHOOLS NETWORK NAME"
    psk="SCHOOLS PASSWORD"
    id_str="school"
}

network={
    ssid="HOME NETWORK NAME"
    psk="HOME PASSWORD"
    id_str="home"
}

#interface.d/wifi.conf
allow-hotplug wlan0
iface wlan0 inet manual
wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf

iface school inet static
address <school address>
gateway <school gateway>
netmask <school netmask>

iface home inet static
address <home address>
gateway <home gateway>
netmask <home netmask>
EOF
cat <<'EOF'
#ext4 boot disk
fw_setenv start_emmc_autoscript 'if ext4load mmc 1 ${env_addr} /boot/boot.ini; then env import -t ${env_addr} ${filesize}; if ext4load mmc 1 ${kernel_addr} ${image}; then if ext4load mmc 1 ${initrd_addr} ${initrd}; then if ext4load mmc 1 ${dtb_mem_addr} ${dtb}; then run boot_start;fi;fi;fi;fi;'

#boot.ini
image=/boot/vmlinuz-5.1.7
initrd=/boot/uInitrd
dtb=/boot/meson-gxl-s905d-phicomm-n1.dtb
bootargs=root=/dev/mmcblk1p1 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0
EOF
