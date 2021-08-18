#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("s905_debootstrap.sh - 4328ad8 - 2021-08-17T15:36:00+08:00")
################################################################################
source ${DIRNAME}/os_debian_init.sh

#fw_setenv bootcmd "run update"; reboot
#之后PC端的刷机程序就会检测到设备进入刷机模式，按软件的刷机提示刷机即可。
# USB boot disk must del /etc/udev/rules.d/98-usbmount.rules

INST_ARCH=${INST_ARCH:-arm64}
REPO=http://mirrors.163.com/debian
PASSWORD=password
DEBIAN_VERSION=${DEBIAN_VERSION:-bullseye}
export FS_TYPE=${FS_TYPE:-ext4}
BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
OVERLAY_LABEL="EMMCOVERLAY"
HOSTNAME="s905d2"
#HOSTNAME="s905d3"
#HOSTNAME="usbpc"

ZRAMSWAP="udisks2"
#ZRAMSWAP="zram-tools"
PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools,u-boot-tools,fake-hwclock,openssh-server,busybox"
PKG="${PKG},udev,isc-dhcp-client,netbase,console-setup,pkg-config,net-tools,wpasupplicant,hostapd,iputils-ping,telnet,vim,ethtool,${ZRAMSWAP},dosfstools,iw,ipset,nmap,ipvsadm,bridge-utils,batctl,babeld,ifenslave,vlan"
PKG="${PKG},parprouted,dhcp-helper,nbd-client,iftop,pigz,nfs-common,nfs-kernel-server,netcat-openbsd"
PKG+=",systemd-container"
[[ ${INST_ARCH} = "amd64" ]] && PKG="${PKG},linux-image-amd64"

if [ "$UID" -ne "0" ]
then 
    echo "Must be root to run this script." 
    exit 1
fi

mkdir -p ${DIRNAME}/buildroot
mkdir -p ${DIRNAME}/cache

debian_build "${DIRNAME}/buildroot" "${DIRNAME}/cache" "${PKG}"

LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL
    debian_zswap_init 512
    debian_sshd_init
    debian_sysctl_init
    debian_vim_init
    debian_chpasswd root ${PASSWORD}
    debain_overlay_init

    cat > /etc/fstab << EOF
LABEL=${ROOT_LABEL}    /    ${FS_TYPE}    defaults,errors=remount-ro,noatime    0    1
LABEL=${BOOT_LABEL}    /boot    vfat    ro    0    2
tmpfs /var/log  tmpfs   defaults,noatime,nosuid,nodev,noexec,size=16M  0  0
tmpfs /run      tmpfs   rw,nosuid,noexec,relatime,size=8192k,mode=755  0  0
tmpfs /tmp      tmpfs   rw,nosuid,noexec,relatime,mode=777  0  0
# overlayfs can not nfs exports, so use tmpfs
tmpfs /media    tmpfs   defaults,size=1M  0  0
EOF

    # auto reformatoverlay plug usb ttl
    cat > /etc/udev/rules.d/99-reformatoverlay.rules << EOF
SUBSYSTEM=="tty", ACTION=="add", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="//bin/sh -c 'touch /overlay/reformatoverlay; echo heartbeat > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
SUBSYSTEM=="tty", ACTION=="remove", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="//bin/sh -c 'rm /overlay/reformatoverlay; echo none > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
EOF

    # auto mount usb storage (readonly)
    cat > /etc/udev/rules.d/98-usbmount.rules << EOF
# udevadm control --reload-rules
SUBSYSTEM=="block", KERNEL=="sd[a-z]*[0-9]", ACTION=="add", RUN+="/bin/systemctl start usb-mount@%k.service"
SUBSYSTEM=="block", KERNEL=="sd[a-z]*[0-9]", ACTION=="remove", RUN+="/bin/systemctl stop usb-mount@%k.service"
EOF
    cat > /usr/lib/systemd/system/usb-mount@.service <<EOF
[Unit]
Description=auto mount block %i

[Service]
RemainAfterExit=true
ExecStart=/bin/sh -c '/bin/udisksctl mount -o ro -b /dev/%i || exit 0'
ExecStop=/bin/sh -c '/bin/udisksctl unmount -f -b /dev/%i || exit 0'
EOF
# end auto mount usb storage (readonly)

# enable ttyAML0 login
echo "ttyAML0" >> /etc/securetty

# export nfs
# no_root_squash(enable root access nfs)
cat > /etc/exports << EOF
/media/       192.168.168.0/24(ro,sync,no_subtree_check,crossmnt,nohide,no_root_squash,no_all_squash,fsid=0)
EOF

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
    #gateway 192.168.168.1
EOF

cat << "EOF" > /etc/network/interfaces.d/wifi
auto wlan0
allow-hotplug wlan0

iface wlan0 inet static
    wpa_conf /etc/wpa_supplicant/ap.conf
    address 192.168.1.1/24

iface work inet dhcp
    wpa_conf /etc/wpa_supplicant/work.conf

iface home inet dhcp
    wpa_conf /etc/wpa_supplicant/home.conf

iface ap inet manual
    hostapd /etc/hostapd/ap.conf
    pre-up (touch /var/lib/misc/udhcpd.leases || true)
    post-up (iptables-restore < /etc/iptables.rules || true)
    post-up (/usr/bin/busybox udhcpd -S || true)
    pre-down (/usr/bin/kill -9 \$(cat /var/run/udhcpd-wlan0.pid) || true)

iface adhoc inet manual
    wpa_driver wext
    wpa_conf /etc/wpa_supplicant/adhoc.conf
    # /usr/sbin/batctl -m wifi-mesh0 if add \$IFACE
    post-up (/usr/sbin/ip link add name wifi-mesh0 type batadv || true)
    post-up (/usr/sbin/ip link set dev \$IFACE master wifi-mesh0 || true) 
    post-up (/usr/sbin/ip link set dev wifi-mesh0 master br-ext || true)
    post-up (/usr/sbin/ip link set dev wifi-mesh0 up || true)
    pre-down (/usr/sbin/ip link set dev \$IFACE nomaster || true)
    pre-down (/usr/sbin/ip link del wifi-mesh0 || true)
    #batctl -m wifi-mesh0 if del \$IFACE
EOF

cat << EOF > /etc/hostapd/ap.conf
interface=wlan0
bridge=br-ext
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
# hw_mode=a             # a simply means 5GHz
# channel=0             # the channel to use, 0 means the AP will search for the channel with the least interferences 
# ieee80211d=1          # limit the frequencies used to those allowed in the country
# country_code=FR       # the country code
# ieee80211n=1          # 802.11n support
# ieee80211ac=1         # 802.11ac support
# wmm_enabled=1         # QoS support

ssid=s905d2
macaddr_acl=0
#accept_mac_file=/etc/hostapd.accept
#deny_mac_file=/etc/hostapd.deny
auth_algs=1
# 采用 OSA 认证算法 
ignore_broadcast_ssid=0 
wpa=3
# 指定 WPA 类型 
wpa_key_mgmt=WPA-PSK             
wpa_pairwise=TKIP 
rsn_pairwise=CCMP 
wpa_passphrase=password123
# 连接 ap 的密码 

driver=nl80211
# 设定无线驱动 
hw_mode=g
# 指定802.11协议，包括 a =IEEE 802.11a, b = IEEE 802.11b, g = IEEE802.11g 
channel=9
# 指定无线频道 
EOF

cat << EOF > /etc/wpa_supplicant/work.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
#ap_scan=1

network={
    id_str="work"
    priority=100
    scan_ssid=1
    ssid="xk-admin"
    #key_mgmt=wpa-psk
    psk="ADMIN@123"
}
EOF
cat << EOF > /etc/wpa_supplicant/home.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
#ap_scan=1

network={
    id_str="home"
    priority=90
    scan_ssid=1
    ssid="johnap"
    #key_mgmt=wpa-psk
    psk="Admin@123"
    #disabled=1
}
EOF

cat << EOF > /etc/wpa_supplicant/ap.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
#ap_scan=1

network={
    id_str="ap"
    priority=70
    #frequency=60480
    ssid="s905d2"
    mode=2
    key_mgmt=NONE
    #key_mgmt=WPA-PSK
    #proto=WPA
    #pairwise=TKIP
    #group=TKIP
    #psk="password"
}
EOF

cat << EOF > /etc/wpa_supplicant/adhoc.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
ap_scan=2

#adhoc/IBSS
# wpa_supplicant -cwpa-adhoc.conf -iwlan0 -Dwext
# iw wlan0 set type ibss
# ifconfig wlan0 up
# iw wlan0 ibss join johnyin 2427
network={
    id_str="adhoc"
    priority=90
    ssid="johnyin"
    frequency=2412
    mode=1
    key_mgmt=NONE
}
EOF

cat << EOF > /etc/udhcpd.conf
start           192.168.168.100
end             192.168.168.150
interface       br-ext
max_leases      45
lease_file      /var/lib/misc/udhcpd.leases
pidfile         /var/run/udhcpd-wlan0.pid
option  domain  local
option  lease   864000
option  subnet  255.255.255.0
# Currently supported options, for more info, see options.c
opt     dns     114.114.114.114
opt     router  192.168.168.1
#opt subnet
#opt timezone
#opt timesvr
#opt namesvr
#opt logsvr
#opt cookiesvr
#opt lprsvr
#opt bootsize
#opt domain
#opt swapsvr
#opt rootpath
#opt ipttl
#opt mtu
#opt broadcast
#opt wins
#opt lease
#opt ntpsrv
#opt tftp
#opt bootfile
# static_lease 00:60:08:11:CE:4E 192.168.0.54
# siaddr          192.168.1.2
# boot_file       pxelinux.0
EOF

# cat << EOF > /etc/modprobe.d/brcmfmac.conf 
# options brcmfmac p2pon=1
# EOF
# if start p2p device so can not start ap & sta same time

#漫游
# cat << EOF > /etc/modprobe.d/brcmfmac.conf 
# options brcmfmac roamoff=1
# EOF

echo "enable fw_printenv command"
cat >/etc/fw_env.config <<EOF
# Device to access      offset          env size
/dev/mmcblk1            0x27400000      0x10000
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

systemctl mask systemd-machine-id-commit.service

apt update
apt -y install --no-install-recommends cron logrotate bsdmainutils rsyslog openssh-client wget ntpdate less wireless-tools file fonts-droid-fallback lsof strace rsync
apt -y install --no-install-recommends xz-utils zip
apt -y remove ca-certificates wireless-regdb crda --purge
apt -y autoremove --purge

exit
EOSHELL

echo "start install you kernel&patchs"
if [ -d "${DIRNAME}/kernel" ]; then
    rsync -avzP ${DIRNAME}/kernel/* ${DIRNAME}/buildroot/ || true
fi
echo "end install you kernel&patchs"
chroot ${DIRNAME}/buildroot/ /bin/bash
chroot ${DIRNAME}/buildroot/ /bin/bash -s <<EOF
    debian_minimum_init
EOF
echo "SUCCESS build rootfs"

cat << 'EOF'
# baudrate=115200
# ethaddr=5a:57:57:90:5d:03
# bootcmd=run start_autoscript; run storeboot;
# start_autoscript=if usb start ; then run start_usb_autoscript; fi; if mmcinfo; then run start_mmc_autoscript; fi; run start_emmc_autoscript;
# start_usb_autoscript=if fatload usb 0 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 1 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 2 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 3 1020000 s905_autoscript; then autoscr 1020000; fi;
# start_mmc_autoscript=if fatload mmc 0 1020000 s905_autoscript; then autoscr 1020000; fi;
# start_emmc_autoscript=if fatload mmc 1 1020000 emmc_autoscript; then autoscr 1020000; fi;
# bootdelay=0

fw_setenv bootcmd "run start_autoscript; run storeboot;"
fw_setenv start_autoscript "if usb start ; then run start_usb_autoscript; fi; if mmcinfo; then run start_mmc_autoscript; fi; run start_emmc_autoscript;"
fw_setenv start_usb_autoscript "if fatload usb 0 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 1 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 2 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 3 1020000 s905_autoscript; then autoscr 1020000; fi;"
fw_setenv start_mmc_autoscript "if fatload mmc 0 1020000 s905_autoscript; then autoscr 1020000; fi;"
fw_setenv start_emmc_autoscript "if fatload mmc 1 1020000 emmc_autoscript; then autoscr 1020000; fi;"
fw_setenv bootdelay 0
fw_setenv ethaddr 5a:57:57:90:5d:03
EOF

echo "add emmc_install script"
cat >> ${DIRNAME}/buildroot/root/sync.sh <<'EOF'
#!/usr/bin/env bash

IP=${1:?from which ip???}
mount -o remount,rw /overlay/lower
rsync -avzP --exclude-from=/root/exclude.txt --delete \
    -e "ssh -p60022" root@${IP}:/overlay/lower/* /overlay/lower/

echo "change ssid && dhcp router"
apaddr=$(ifquery wlan0=ap | grep "address:" | awk '{ print $2}')
sed -i "s/ssid=.*/ssid=\"$(hostname)\"/g" /overlay/lower/etc/wpa_supplicant/ap.conf
sed -n 's|^ssid=\(.*\)$|\1|p' /overlay/lower/etc/wpa_supplicant/ap.conf
mount -o remount,ro /overlay/lower

mount -o remount,rw /boot
rsync -avzP -e "ssh -p60022" root@${IP}:/boot/* /boot/

mount -o remount,ro /boot

touch /overlay/reformatoverlay
sync
sync
EOF

cat >> ${DIRNAME}/buildroot/root/exclude.txt <<'EOF'
/etc/network/interfaces.d/
firmware/brcm/brcmfmac43455-sdio.txt
/etc/ssh/
/etc/hostname
/etc/hosts
EOF

cat >> ${DIRNAME}/buildroot/root/emmc_linux.sh <<'EOF'
#!/usr/bin/env bash

BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
OVERLAY_LABEL="EMMCOVERLAY"
cat <<EOPART
[mmcblk0p01]  bootloader  offset 0x000000000000  size 0x000000400000
[mmcblk0p02]    reserved  offset 0x000002400000  size 0x000004000000
[mmcblk0p03]       cache  offset 0x000006c00000  size 0x000020000000
[mmcblk0p04]         env  offset 0x000027400000  size 0x000000800000
[mmcblk0p05]        logo  offset 0x000028400000  size 0x000002000000
[mmcblk0p06]    recovery  offset 0x00002ac00000  size 0x000002000000
[mmcblk0p07]         rsv  offset 0x00002d400000  size 0x000000800000
[mmcblk0p08]         tee  offset 0x00002e400000  size 0x000000800000
[mmcblk0p09]       crypt  offset 0x00002f400000  size 0x000002000000
[mmcblk0p10]        misc  offset 0x000031c00000  size 0x000002000000
[mmcblk0p11]        boot  offset 0x000034400000  size 0x000002000000
[mmcblk0p12]      system  offset 0x000036c00000  size 0x000050000000
[mmcblk0p13]        data  offset 0x000087400000  size 0x00014ac00000
EOPART
####################################################################################################
echo "Start script create MBR and filesystem"
ENV_LOGO_PART_START=288768  #sectors
DEV_EMMC=${DEV_EMMC:=/dev/mmcblk2}
echo "So as to not overwrite U-boot, we backup the first 1M."
dd if=${DEV_EMMC} of=/tmp/boot-bak bs=1M count=4
echo "(Re-)initialize the eMMC and create partition."
echo "bootloader & reserved occupies [0, 100M]. Since sector size is 512B, byte offset would be 204800."
echo "Start create MBR and partittion"
echo "${DEV_EMMC}p04  env   offset 0x000027400000  size 0x000000800000"
echo "${DEV_EMMC}p05  logo  offset 0x000028400000  size 0x000002000000"
parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 204800s $((ENV_LOGO_PART_START-1))s
parted -s "${DEV_EMMC}" mkpart primary ext4 ${ENV_LOGO_PART_START}s 3G
parted -s "${DEV_EMMC}" mkpart primary ext4 3G 100%
echo "Start restore u-boot"
# Restore U-boot (except the first 442 bytes, where partition table is stored.)
dd if=/tmp/boot-bak of=${DEV_EMMC} conv=fsync bs=1 count=442
dd if=/tmp/boot-bak of=${DEV_EMMC} conv=fsync bs=512 skip=1 seek=1
# This method is used to convert byte offset in `/dev/mmcblkX` to block offset in `/dev/mmcblkXp2`.
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
echo "dd if=/boot/n1-logo.img of=${DEV_EMMC} bs=1M seek=644 can install new logo"
gen_blocks 0x28400000 0x2000000 >> /tmp/reservedblks
echo "Marked blocks used by /dev/logo start=0x28400000 size=0x2000000 as bad."

DISK=${DEV_EMMC}
PART_BOOT="${DISK}p1"
PART_ROOT="${DISK}p2"
PART_OVERLAY="${DISK}p3"

echo "Format the partitions."
mkfs.vfat -n ${BOOT_LABEL} ${PART_BOOT}
mkfs -t ext4 -m 0 -b4096 -l /tmp/reservedblks  -E num_backup_sb=0  -q -L ${ROOT_LABEL} ${PART_ROOT}
mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${PART_OVERLAY}

echo "Flush changes (in case they were cached.)."
sync
echo "show reserved!!"
false && dumpe2fs -b ${PART_ROOT}
echo "Partition table (re-)initialized."
EOF

cat > ${DIRNAME}/buildroot/root/aptrom.sh <<EOF
#!/usr/bin/env bash
mount -o remount,rw /overlay/lower

chroot /overlay/lower apt update
chroot /overlay/lower apt install \$*

rm -rf /overlay/lower/var/cache/apt/* /overlay/lower/var/lib/apt/lists/* /overlay/lower/var/log/*
rm -rf /overlay/lower/root/.bash_history /overlay/lower/root/.viminfo /overlay/lower/root/.vim/
cat ~/sources.list.bak > /overlay/lower/etc/apt/sources.list
rm -f ~/sources.list.bak
sync
mount -o remount,ro /overlay/lower

EOF

cat >> ${DIRNAME}/buildroot/root/brige_wlan_eth.sh <<'SCRIPT_EOF'
# bridge eth0 & wlan0 Same Subnet!!

# parprouted  - Proxy ARP IP bridging daemon
# dhcp-helper - A DHCP/BOOTP relay agent

cat > /etc/default/dhcp-helper <<EOF
DHCPHELPER_OPTS="-b wlan0"
EOF

# Create a helper script to get an adapter's IP address
cat <<'EOF' >/usr/bin/get-adapter-ip
#!/usr/bin/env bash

/sbin/ip -4 -br addr show \${1} | /bin/grep -Po "\\d+\\.\\d+\\.\\d+\\.\\d+"
EOF
chmod +x /usr/bin/get-adapter-ip

# I have to admit, I do not understand ARP and IP forwarding enough to explain
# exactly what is happening here. I am building off the work of others. In short
# this is a service to forward traffic from wlan0 to eth0
cat <<'EOF' >/etc/systemd/system/parprouted.service
[Unit]
Description=proxy arp routing service
Documentation=https://raspberrypi.stackexchange.com/q/88954/79866

[Service]
Type=forking
# Restart until wlan0 gained carrier
Restart=on-failure
RestartSec=5
TimeoutStartSec=30
ExecStartPre=/lib/systemd/systemd-networkd-wait-online --interface=wlan0 --timeout=6 --quiet
ExecStartPre=/bin/echo 'systemd-networkd-wait-online: wlan0 is online'
# clone the dhcp-allocated IP to eth0 so dhcp-helper will relay for the correct subnet
ExecStartPre=/bin/bash -c '/sbin/ip addr add \$(/usr/bin/get-adapter-ip wlan0)/32 dev eth0'
ExecStartPre=/sbin/ip link set dev eth0 up
ExecStartPre=/sbin/ip link set wlan0 promisc on
ExecStart=-/usr/sbin/parprouted eth0 wlan0
ExecStopPost=/sbin/ip link set wlan0 promisc off
ExecStopPost=/sbin/ip link set dev eth0 down
ExecStopPost=/bin/bash -c '/sbin/ip addr del \$(/usr/bin/get-adapter-ip eth0)/32 dev eth0'

[Install]
WantedBy=wpa_supplicant@wlan0.service
EOF

systemctl daemon-reload
systemctl enable parprouted.service
SCRIPT_EOF

cat >> ${DIRNAME}/buildroot/root/inst.sh <<EOF_INSTSH
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
#wpa_cli p2p_group_add persistent=0
#wpa_cli p2p_group_add persistent=1
network={
    id_str="p2p-client"
    ssid="DIRECT-S905D"
    bssid=ca:ff:ee:ba:be:d0
    psk="hqZ532yoxxoo"
    proto=RSN
    key_mgmt=WPA-PSK
    pairwise=CCMP
    auth_alg=OPEN
    disabled=2
}

network={
    id_str="p2p-go"
    ssid="DIRECT-S905D"
    bssid=ca:ff:ee:ba:be:d0
    psk="hqZ532yoxxoo"
    proto=RSN
    key_mgmt=WPA-PSK
    pairwise=CCMP
    auth_alg=OPEN
    disabled=2
    mode=3
#p2p_client_list=76:2f:4e:ee:3f:dc
}

ip link set dev wlan0 address b8:be:ef:90:5d:02
P2P 
iw list | grep -A10 "valid interface combinations:"

 wpa_cli -ip2p-dev-wlan0 p2p_group_add persistent
 wpa_cli -i p2p-wlan0-0 p2p_find        wpa_cli -i p2p-dev-wlan0 p2p_find
 wpa_cli -i p2p-wlan0-0 p2p_peers       wpa_cli -i p2p-dev-wlan0 p2p_peers
     wps_pbc                            p2p_connect EVM#1_MAC_ADDRESS pbc persistent join
 OR  
     wps_pin any (<mac> 11111111)       p2p_connect <mac> 11111111 persistent join
                                        
 ifconfig p2p-wlan0-0 172.16.16.1/24        ifconfig p2p-wlan0-0 172.16.16.2/24
                                        
                                        
 wpa_cli -ip2p-wlan0-0 p2p_group_remove p2p-wlan0-0

To setup your autonomous group owner, started with p2p_group_add, with a custom ssid and password you have to make it persistent and have a network block inserted in /etc/wpa_supplicant/wpa_supplicant.conf. The easiest way to get the network block in wpa_supplicant.conf is to let it do wpa_supplicant itself. Just start the p2p group with p2p_group_add as usual but persistent and remove it just after that again:

rpi ~$ wpa_cli -ip2p-dev-wlan0
> p2p_group_add persistent
> p2p_group_remove p2p-wlan0-0
> quit
rpi ~$
Now you should find the persistent network block in /etc/wpa_supplicant/wpa_supplicant.conf. From my test it looks like this:

ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
device_name=DIRECT-RasPi1
p2p_go_ht40=1
country=DE

network={
        ssid="DIRECT-Ca"
        bssid=56:1d:c5:95:c2:e9
        psk="yfmyjT8o"
        proto=RSN
        key_mgmt=WPA-PSK
        pairwise=CCMP
        auth_alg=OPEN
        mode=3
        disabled=2
}
Now just edit this and set ssid and psk as you like. When ready then restart your wpa_supplicant to make the change available.

The first network block has number 0 and so on. Now start the persistent autonomous group owner by addressing this network block with:

rpi ~$ wpa_cli -ip2p-dev-wlan0
> p2p_group_add persistent=0 IFNAME=wlan2



  BR -------> ap(dhcpd) <------- BR
ap  eth0                     eth0  ap

ifdown wlan0
ifup wlan0=work    #
ifup wlan0=home    #
ifup wlan0=ap      #
ifup wlan0=adhoc   # add wlan0(adhoc johnyin) to batman-adv wifi-mesh0 and add wifi-mesh0 to br-ext!
#batman-adv
$ ip link add name bat0 type batadv
$ ip link set dev eth0 master bat0
to deactivate an interface you have to detach it from the “bat0” interface:
$ ip link set dev eth0 nomaster
# change eth0 mac address!
fw_setenv ethaddr 5a:57:57:00:df:4a
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

iw wlan0 set type managed
ip link set wlan0 up
iw wlan0 scan
iwconfig wlan0 essid s905d3
iw wlan0 info
ifconfig wlan0 192.168.168.100

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

Human Interface Device
/etc/default/bluetooth - Default HID bluez setting - enable for mice and keyboards
HID2HCI_ENABLED=1
/etc/bluetooth/hcid.conf - HCI bluez settings - configure static device information

device 00:1E:52:FB:68:55 {
    name "Apple Wireless Keyboard";
    auth enable;
    encrypt enable;}

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


  1 bluetooth
    hciconfig hci1 name "test"
  2 ServerSide:
  3   #make us discoverable
  4   hciconfig hci1 piscan
  5   hciconfig hci1 -a
  6   #listen
  7   rfcomm -r -i hci1 listen /dev/rfcomm0 4
  8   or: rfcomm watch hci1 1 getty rfcomm0 115200 vt100 -a root
  9 ClientSide:
 10   hcitool info 43:45:C0:00:1F:AC
 11   rfcomm -r connect /dev/rfcomm0 43:45:C0:00:1F:AC 4
 12   echo "Hello" > /dev/rfcomm0 # test it!
      minicom -D /dev/rfcomm0 
      screen /dev/rfcomm0 115200


# Edit /lib/systemd/system/bluetooth.service to enable BT services
sed -i: 's|^Exec.*toothd$| \
ExecStart=/usr/lib/bluetooth/bluetoothd -C \
ExecStartPost=/usr/bin/sdptool add SP \
ExecStartPost=/bin/hciconfig hci0 piscan \
|g' /lib/systemd/system/bluetooth.service

# create /etc/systemd/system/rfcomm.service to enable 
# the Bluetooth serial port from systemctl
cat >/etc/systemd/system/rfcomm.service <<EOF1
[Unit]
Description=RFCOMM service
After=bluetooth.service
Requires=bluetooth.service

[Service]
ExecStart=/usr/bin/rfcomm watch hci0 1 getty rfcomm0 115200 vt100 -a pi

[Install]
WantedBy=multi-user.target
EOF1

# enable the new rfcomm service
sudo systemctl enable rfcomm
# start the rfcomm service
sudo systemctl restart rfcomm
EOF_INSTSH

echo "you need run 'apt -y install busybox && update-initramfs -c -k KERNEL_VERSION'"
# autologin-guest=false
# autologin-user=user(not root)
# autologin-user-timeout=0
# groupadd -r autologin
# gpasswd -a root autologin

echo "SUCCESS build rootfs, all!!!"
exit 0

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

gen_uEnv_ini() {
    cat > /boot/uEnv.ini <<EOF
dtb_name=/dtb/meson-gxl-s905d-phicomm-n1.dtb
bootargs=root=LABEL=${ROOT_LABEL} rootflags=rw fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0
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
setenv bootargs "root=/dev/nfs nfsroot=${serverip}:/nfsshare/root rw net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 rootwait"
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
cat <<'EOF'
#ext4 boot disk
fw_setenv start_emmc_autoscript 'if ext4load mmc 1 ${env_addr} /boot/boot.ini; then env import -t ${env_addr} ${filesize}; if ext4load mmc 1 ${kernel_addr} ${image}; then if ext4load mmc 1 ${initrd_addr} ${initrd}; then if ext4load mmc 1 ${dtb_mem_addr} ${dtb}; then run boot_start;fi;fi;fi;fi;'

#boot.ini
image=/boot/vmlinuz-5.1.7
initrd=/boot/uInitrd
dtb=/boot/meson-gxl-s905d-phicomm-n1.dtb
bootargs=root=/dev/mmcblk1p1 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0
EOF
