#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("94758ec[2022-07-04T15:10:21+08:00]:s905_debootstrap.sh")
################################################################################
source ${DIRNAME}/os_debian_init.sh
menu_select() {
    local prompt=${1}
    shift 1
    local org_PS3=${PS3:-}
    PS3="${prompt}"
    select sel in ${@}; do
        [ -z  ${sel} ] || {
            echo -n "${sel}"
            break
        }
    done
    PS3=${org_PS3}
}

# USB boot disk must del /etc/udev/rules.d/98-usbmount.rules
: <<'EOF_DOC'
#fw_setenv bootcmd "run update"; reboot
#之后PC端的刷机程序就会检测到设备进入刷机模式，按软件的刷机提示刷机即可。

短接->插USB线->上电->取消短接
./aml-flash --img=T1-6.23-fix.img --parts=all
        ./update identify 7
        ./update bulkcmd "     echo 12345"
        ./update identify 7
        ./update rreg 4 0xc8100228
        ./update cwr ./t1/DDR_ENC.USB 0xd9000000
        ./update write usbbl2runpara_ddrinit.bin 0xd900c000
        ./update run 0xd9000000
        sleep 8
        ./update identify 7
        ./update write ./t1/DDR_ENC.USB 0xd9000000
        ./update write usbbl2runpara_runfipimg.bin 0xd900c000
        ./update write ./t1/UBOOT_ENC.USB 0x200c000
        ./update run 0xd9000000
        sleep 8
        ./update mwrite ./t1/_aml_dtb.PARTITION mem dtb normal
        ./update bulkcmd "     disk_initial 0"
        ./update mwrite ./t1/meson1.dtb mem dtb normal
        ./update partition bootloader ./t1/bootloader.PARTITION
# ########################################################
./update identify 7
./update mwrite ./n1/_aml_dtb.PARTITION mem dtb normal
./update bulkcmd "     disk_initial 0"
./update partition bootloader ./n1/bootloader.PARTITION
./update partition boot ./n1/boot.PARTITION normal
./update partition logo ./n1/logo.PARTITION normal
./update partition recovery ./n1/recovery.PARTITION normal
./update partition system ./n1/system.PARTITION sparse
./update bulkcmd "     setenv upgrade_step 1"
./update bulkcmd "     save"
./update bulkcmd "     setenv firstboot 1"
./update bulkcmd "     save"
./update bulkcmd "     rpmb_reset"
./update bulkcmd "     amlmmc erase data"
./update bulkcmd "     nand erase.part data"
./update bulkcmd "     amlmmc erase cache"
./update bulkcmd "     nand erase.part cache"
./update bulkcmd "     burn_complete 1"
设置->媒体盒状态->版本号->连续点击进入开发模式
adb connect ${IPADDR}:5555
adb shell reboot update (!!! aml_autoscript in vfat boot partition)
adb shell
   su
     31183118
ssh -p${PORT} ${IPADDR}
################################################################################
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
EOF_DOC

BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
FS_TYPE=${FS_TYPE:-ext4}

old_ifs="$IFS" IFS=','
custom_pkgs="$*"
IFS=$old_ifs

PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools,u-boot-tools,fake-hwclock,openssh-server,busybox"
PKG+=",udev,isc-dhcp-client,netbase,console-setup,pkg-config,net-tools,wpasupplicant,hostapd,iputils-ping,telnet,vim,ethtool,dosfstools,iw,ipset,nmap,ipvsadm,bridge-utils,batctl,babeld,ifenslave,vlan"
PKG+=",parprouted,dhcp-helper,nbd-client,iftop,pigz,nfs-common,nfs-kernel-server,netcat-openbsd"
PKG+=",systemd-container,nftables,systemd-timesyncd"
PKG+=",fonts-noto-cjk"
#PKG+=",fonts-droid-fallback"
PKG+=",cron,logrotate,bsdmainutils,rsyslog,openssh-client,wget,ntpdate,less,wireless-tools,file,lsof,strace,rsync"
PKG+=",xz-utils,zip,udisks2"
# # xfce
PKG+=",alsa-utils,pulseaudio,pulseaudio-utils,smplayer,smplayer-l10n,mpg123,lightdm,xserver-xorg-core,xinit,xserver-xorg-video-fbdev,xfce4,xfce4-terminal,xserver-xorg-input-all,pavucontrol"
PKG+=",x11-utils"
# # tools
PKG+=",sudo,aria2,axel,curl,eject,rename,bc,socat,tmux,xmlstarlet,jq,traceroute,ipcalc,ncal,qrencode,tcpdump"
# # for xfce auto mount
PKG+=",thunar-volman,policykit-1,gvfs"
# # finally add custom packages
PKG+="${custom_pkgs:+,${custom_pkgs}}"

[ "$(id -u)" -eq 0 ] || {
    echo "Must be root to run this script."
    exit 1
}

mkdir -p ${DIRNAME}/buildroot
mkdir -p ${DIRNAME}/cache

#HOSTNAME="s905d3"
#HOSTNAME="usbpc"
DEBIAN_VERSION=${DEBIAN_VERSION:-bullseye} \
    INST_ARCH=arm64 \
    REPO=${REPO:-http://mirrors.aliyun.com/debian} \
    HOSTNAME="s905d2" \
    NAME_SERVER=114.114.114.114 \
    PASSWORD=password \
    debian_build "${DIRNAME}/buildroot" "${DIRNAME}/cache" "${PKG}"

LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL
    /bin/mkdir -p /dev/pts && /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts || true
    /bin/mknod -m 666 /dev/null c 1 3 || true

    debian_zswap_init 512
    debian_sshd_init
    debian_sysctl_init
    debian_vim_init
    debain_overlay_init
# # disable saradc module
cat << EOF > /etc/modprobe.d/meson_saradc.conf
blacklist meson_saradc
EOF

# cat << EOF > /etc/modprobe.d/brcmfmac.conf
# options brcmfmac p2pon=1
# EOF
# if start p2p device so can not start ap & sta same time
#漫游
# cat << EOF > /etc/modprobe.d/brcmfmac.conf
# options brcmfmac roamoff=1
# EOF

#echo "修改systemd journald日志存放目录为内存，也就是/run/log目录，限制最大使用内存空间64MB"

#sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
#sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=64M/' /etc/systemd/journald.conf

systemctl mask systemd-machine-id-commit.service

apt update
apt -y remove ca-certificates wireless-regdb crda --purge
apt -y autoremove --purge
# # fix lightdm
# touch /var/lib/lightdm/.Xauthority || true
# chown lightdm:lightdm /var/lib/lightdm/.Xauthority || true

# add lima xorg.conf
mkdir -p /etc/X11/xorg.conf.d/
# avoid "page flip error" in Xorg.0.log
cat <<EOF > /etc/X11/xorg.conf.d/20-lima.conf
Section "Device"
    Identifier "Default Device"
    Driver "modesetting"
    Option "AccelMethod" "glamor"  ### "glamor" to enable 3D acceleration, "none" to disable.
    Option "PageFlip" "off"
    Option "DRI" "2"
    Option "Dri2Vsync" "true"
    Option "TripleBuffer" "true"
EndSection
Section "ServerFlags"
    Option "AutoAddGPU" "off"
    Option "Debug" "dmabuf_capable"
EndSection
Section "OutputClass"
    Identifier "Lima"
    MatchDriver "meson"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
EOF
# # pulseaudio --start for root
# sed -i "/ConditionUser=.*/d" /usr/lib/systemd/user/pulseaudio.service
# sed -i "/ConditionUser=.*/d" /usr/lib/systemd/user/pulseaudio.socket

# fix hwclock
rm -f /etc/fake-hwclock.data || true

useradd -m -s /bin/bash johnyin
# disable dpms auto off screen
# su - johnyin -c "echo 'DISPLAY=:0 xset -dpms' > /home/johnyin/.xsessionrc"
echo "DISPLAY=:0 xset -dpms" > /home/johnyin/.xsessionrc
# su - johnyin -c "echo 'DISPLAY=:0 xset s off' >> /home/johnyin/.xsessionrc"
echo "DISPLAY=:0 xset s off" >> /home/johnyin/.xsessionrc
chown johnyin.johnyin /home/johnyin/.xsessionrc
ln -s /home/johnyin/.Xauthority /root/.Xauthority
echo "%johnyin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/johnyin
chmod 0440 /etc/sudoers.d/johnyin
sed -i "s/^\(.*requiretty\)$/#\1/" /etc/sudoers
echo "auto login xfce"
sed -i "s/#autologin-user=.*/autologin-user=johnyin/g" /etc/lightdm/lightdm.conf
echo "auto mount RO options"
echo "[defaults]" > /etc/udisks2/mount_options.conf || true
echo "defaults=ro" >> /etc/udisks2/mount_options.conf || true

gpasswd -a johnyin pulse
gpasswd -a johnyin lp
gpasswd -a pulse lp
gpasswd -a johnyin audio
gpasswd -a pulse audio

# # disable gvfs trash
# sed -i "s/AutoMount=.*/AutoMount=false/g" /usr/share/gvfs/mounts/trash.mount
debian_bash_init johnyin
# timedatectl set-local-rtc 0
echo "Force Users To Change Passwords Upon First Login"
chage -d 0 root || true
/bin/umount /dev/pts
exit
EOSHELL

cat > ${DIRNAME}/buildroot/etc/fstab << EOF
LABEL=${ROOT_LABEL}    /    ${FS_TYPE}    defaults,errors=remount-ro,noatime    0    1
LABEL=${BOOT_LABEL}    /boot    vfat    ro    0    2
# LABEL=EMMCSWAP    none     swap    sw,pri=-1    0    0
tmpfs /var/log  tmpfs   defaults,noatime,nosuid,nodev,noexec,size=16M  0  0
tmpfs /run      tmpfs   rw,nosuid,noexec,relatime,mode=755  0  0
tmpfs /tmp      tmpfs   rw,nosuid,relatime,mode=777  0  0
# overlayfs can not nfs exports, so use tmpfs
tmpfs /media    tmpfs   defaults,size=1M  0  0
EOF

# auto reformatoverlay plug usb ttl
cat > ${DIRNAME}/buildroot/etc/udev/rules.d/99-reformatoverlay.rules << EOF
SUBSYSTEM=="tty", ACTION=="add", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="//bin/sh -c 'touch /overlay/reformatoverlay; echo heartbeat > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
SUBSYSTEM=="tty", ACTION=="remove", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="//bin/sh -c 'rm /overlay/reformatoverlay; echo none > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
EOF

# # auto mount usb storage (readonly)
# cat > ${DIRNAME}/buildroot/etc/udev/rules.d/98-usbmount.rules << EOF
# # udevadm control --reload-rules
# SUBSYSTEM=="block", KERNEL=="sd[a-z]*[0-9]", ACTION=="add", RUN+="/bin/systemctl start usb-mount@%k.service"
# SUBSYSTEM=="block", KERNEL=="sd[a-z]*[0-9]", ACTION=="remove", RUN+="/bin/systemctl stop usb-mount@%k.service"
# EOF
#     cat > ${DIRNAME}/buildroot/usr/lib/systemd/system/usb-mount@.service <<EOF
# [Unit]
# Description=auto mount block %i
#
# [Service]
# RemainAfterExit=true
# ExecStart=/bin/sh -c '/bin/udisksctl mount -o ro -b /dev/%i || exit 0'
# ExecStop=/bin/sh -c '/bin/udisksctl unmount -f -b /dev/%i || exit 0'
# EOF
# end auto mount usb storage (readonly)

# enable ttyAML0 login
sed -i "/^ttyAML0/d" ${DIRNAME}/buildroot/etc/securetty 2>/dev/null || true
echo "ttyAML0" >> ${DIRNAME}/buildroot/etc/securetty

# export nfs
# no_root_squash(enable root access nfs)
cat > ${DIRNAME}/buildroot/etc/exports << EOF
/media/       192.168.168.0/24(ro,sync,no_subtree_check,crossmnt,nohide,no_root_squash,no_all_squash,fsid=0)
EOF

cat << EOF > ${DIRNAME}/buildroot/etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat << EOF > ${DIRNAME}/buildroot/etc/network/interfaces.d/br-ext
auto eth0
allow-hotplug eth0
iface eth0 inet manual

auto br-ext

mapping br-ext
    script /etc/johnyin/wifi_mode.sh
    map s905d3
    map s905d2
    map usbpc

iface s905d2 inet static
    bridge_ports eth0
    address 192.168.168.2/24
    # hwaddress 7e:b1:81:90:5d:02
iface s905d3 inet static
    bridge_ports eth0
    address 192.168.168.3/24
    # hwaddress 7e:b1:81:90:5d:03
iface usbpc inet static
    bridge_ports eth0
    address 192.168.168.101/24
    # hwaddress 7e:b1:81:90:5d:99

# post-up ip rule add from 192.168.168.0/24 table out.168
# post-up ip rule add to 192.168.168.0/24 table out.168
# post-up ip route add default via 192.168.168.1 dev br-ext table out.168
# post-up ip route add 192.168.168.0/24 dev br-ext src 192.168.168.2 table out.168
EOF

cat << "EOF" > ${DIRNAME}/buildroot/etc/network/interfaces.d/wifi
auto wlan0
allow-hotplug wlan0

mapping wlan0
    script /etc/johnyin/wifi_mode.sh
    map work
    map home
    map adhoc
    map ap
    map ap0
    map initmode

iface ap0 inet manual
    hostapd /run/hostapd.ap0.conf
    # INTERFACE BRIDGE SSID PASSPHRASE IS_5G HIDDEN_SSID
    pre-up (/etc/johnyin/gen_hostapd.sh ap0 br-int "$(cat /etc/hostname)" "password123" 1 1 || true)
    pre-up (/etc/johnyin/gen_udhcpd.sh br-int || true)
    pre-up (/usr/sbin/iw phy `/usr/bin/ls /sys/class/ieee80211/` interface add ap0 type __ap)
    #pre-up (/usr/sbin/ifup work || true)
    #post-up (/usr/sbin/iptables-restore < /etc/iptables.rules || true)
    post-up (/etc/johnyin/ap.ruleset || true)
    post-up (/usr/bin/touch /var/run/udhcpd.leases || true)
    post-up (/usr/bin/busybox udhcpd -S /run/udhcpd.conf || true)
    pre-down (/usr/bin/kill -9 $(cat /var/run/udhcpd-wlan0.pid) || true)
    pre-down (/usr/bin/kill -9 $(cat /run/hostapd.ap0.pid) || true)
    post-down (/usr/sbin/iw dev ap0 del)

iface ap inet manual
    hostapd /run/hostapd.wlan0.conf
    pre-up (/etc/johnyin/gen_hostapd.sh wlan0 br-int "$(cat /etc/hostname)" "password123" 0 1 || true)
    pre-up (/etc/johnyin/gen_udhcpd.sh br-int || true)
    pre-up (/usr/bin/touch /var/run/udhcpd.leases || true)
    #post-up (/usr/sbin/iptables-restore < /etc/iptables.rules || true)
    post-up (/etc/johnyin/ap.ruleset || true)
    post-up (/usr/bin/busybox udhcpd -S /run/udhcpd.conf || true)
    pre-down (/usr/bin/kill -9 $(cat /run/hostapd.wlan0.pid) || true)
    pre-down (/usr/bin/kill -9 $(cat /var/run/udhcpd-wlan0.pid) || true)

iface work inet manual
    wpa_iface wlan0
    wpa_conf /etc/johnyin/work.conf
    post-up (/usr/sbin/dhclient -v -pf /run/dhclient.wlan0.pid -lf /run/dhclient.wlan0.lease wlan0 || true)
    pre-down (/usr/bin/kill -9 $(cat /run/dhclient.wlan0.pid ) || true)
    post-up (/usr/sbin/ifup ap0 || true)
    pre-down (/usr/sbin/ifdown ap0 || true)

iface home inet manual
    wpa_iface wlan0
    wpa_conf /etc/johnyin/home.conf
    post-up (/usr/sbin/dhclient -v -pf /run/dhclient.wlan0.pid -lf /run/dhclient.wlan0.lease  wlan0 || true)
    pre-down (/usr/bin/kill -9 $(cat /run/dhclient.wlan0.pid ) || true)
    post-up (/usr/sbin/ifup ap0 || true)
    pre-down (/usr/sbin/ifdown ap0 || true)

iface adhoc inet manual
    wpa_driver wext
    wpa_conf /etc/johnyin/adhoc.conf
    post-up (/usr/sbin/ip link add name wifi-mesh0 type batadv || true)
    post-up (/usr/sbin/ip link set dev $IFACE master wifi-mesh0 || true)
    post-up (/usr/sbin/ip link set dev wifi-mesh0 master br-ext || true)
    post-up (/usr/sbin/ip link set dev wifi-mesh0 up || true)
    pre-down (/usr/sbin/ip link set dev $IFACE nomaster || true)
    pre-down (/usr/sbin/ip link del wifi-mesh0 || true)

iface initmode inet static
    wpa_iface wlan0
    wpa_conf /etc/johnyin/initmode.conf
    address 192.168.1.1/24
EOF

cat << EOF > ${DIRNAME}/buildroot/etc/network/interfaces.d/br-int
auto br-int
iface br-int inet static
    bridge_ports none
    address 192.168.167.1/24
EOF

cat << EOF > ${DIRNAME}/buildroot/etc/network/interfaces.d/pppoe
# auto myadsl
# iface myadsl inet ppp
#     pre-up /sbin/ip link set dev eth0 up
#     provider myadsl
#

# sample /etc/ppp/peers/dsl-provider
# cat >/etc/ppp/peers/myadsl <<EOF
# # Use Roaring Penguin's PPPoE implementation.
# plugin rp-pppoe.so eth0
#
# # Login settigns.
# user "username"
# noauth
# hide-password
#
# # Connection settings.
# persist
# maxfail 0
# holdoff 5
#
# # LCP settings.
# lcp-echo-interval 10
# lcp-echo-failure 3
#
# # PPPoE compliant settings.
# noaccomp
# default-asyncmap
# mtu 1492
#
# # IP settings.
# noipdefault
# defaultroute
# EOF
#
# cat >/etc/ppp/chap-secrets <<EOF
# username * my-password *
# EOF
EOF

mkdir -p ${DIRNAME}/buildroot/etc/johnyin
cat << EO_DOC > ${DIRNAME}/buildroot/etc/johnyin/ap.ruleset
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
	chain PREROUTING {
		type nat hook prerouting priority -100; policy accept;
	}

	chain INPUT {
		type nat hook input priority 100; policy accept;
	}

	chain POSTROUTING {
		type nat hook postrouting priority 100; policy accept;
		ip saddr 192.168.167.0/24 ip daddr != 192.168.167.0/24 counter packets 0 bytes 0 masquerade
	}

	chain OUTPUT {
		type nat hook output priority -100; policy accept;
	}
}
table ip filter {
	chain INPUT {
		type filter hook input priority 0; policy accept;
	}

	chain FORWARD {
		type filter hook forward priority 0; policy accept;
		meta l4proto tcp tcp flags & (syn|rst) == syn counter packets 0 bytes 0 tcp option maxseg size set rt mtu
	}

	chain OUTPUT {
		type filter hook output priority 0; policy accept;
	}
}
EO_DOC
chmod 755 ${DIRNAME}/buildroot/etc/johnyin/ap.ruleset

cat << 'EO_DOC' > ${DIRNAME}/buildroot/etc/johnyin/gen_udhcpd.sh
#!/bin/sh
set -e
export LANG=C

if [ `id -u` -ne 0 ]; then exit 1; fi

INTERFACE=${1:-wlan0}
eval `/usr/sbin/ifquery ${INTERFACE} 2>/dev/null | /usr/bin/awk '/address:/{ print "ADDRESS="$2} /netmask:/{ print "MASK="$2}'`
ADDRESS=${ADDRESS:-192.168.0.1}
MASK=${MASK:-255.255.255.0}

cat > /run/udhcpd.conf <<EOF
interface       ${INTERFACE}
start           ${ADDRESS%.*}.100
end             ${ADDRESS%.*}.150
option  subnet  ${MASK}
opt     router  ${ADDRESS}
opt     dns     114.114.114.114
max_leases      45
lease_file      /var/run/udhcpd.leases
pidfile         /var/run/udhcpd-wlan0.pid
option  domain  local
option  lease   86400
# Currently supported options, for more info, see options.c
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
EO_DOC
chmod 755 ${DIRNAME}/buildroot/etc/johnyin/gen_udhcpd.sh

cat << 'EO_DOC' > ${DIRNAME}/buildroot/etc/johnyin/gen_hostapd.sh
#!/bin/sh
set -e
export LANG=C

if [ `id -u` -ne 0 ]; then exit 1; fi

INTERFACE=${1:-wlan0}
BRIDGE=${2:-br-int}
SSID=${3:-$(cat /etc/hostname)}
PASSPHRASE=${4:-password123}
IS_5G=${5:-1}
IGNORE_BROADCAST_SSID=${6:-1}

cat > /run/hostapd.${INTERFACE}.conf <<EOF
interface=${INTERFACE}
bridge=${BRIDGE}
ssid=${SSID}
wpa_passphrase=${PASSPHRASE}
ignore_broadcast_ssid=${IGNORE_BROADCAST_SSID}

utf8_ssid=1
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

macaddr_acl=0
#accept_mac_file=/etc/hostapd.accept
#deny_mac_file=/etc/hostapd.deny

auth_algs=1
# 采用 OSA 认证算法
wpa=2
# 指定 WPA 类型
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP

driver=nl80211
# 设定无线驱动
EOF

if [ "${IS_5G}" = 0 ]; then
    cat >> /run/hostapd.${INTERFACE}.conf <<EOF
# hw_mode=g
# 指定802.11协议，包括 a =IEEE 802.11a, b = IEEE 802.11b, g = IEEE802.11g
channel=4
# 指定无线频道
EOF
    exit 0
fi
cat >> /run/hostapd.${INTERFACE}.conf <<EOF
hw_mode=a
# 指定802.11协议，包括 a =IEEE 802.11a, b = IEEE 802.11b, g = IEEE802.11g
channel=44
# 指定无线频道

wmm_enabled=1         # QoS support
#obss_interval=300
ieee80211n=1
require_ht=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]
ieee80211ac=1         # 802.11ac support
require_vht=1
#vht_oper_chwidth=0
#vht_capab=[SHORT-GI-80][SU-BEAMFORMEE]
#个别N1无法使用[SU-BEAMFORMEE] ，请在下面行中自行去除
vht_capab=[MAX-MPDU-3895][SHORT-GI-80][SU-BEAMFORMEE]
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
#beacon_int=50
#dtim_period=20
basic_rates=60 90 120 180 240 360 480 540
disassoc_low_ack=0
EOF
EO_DOC
chmod 755 ${DIRNAME}/buildroot/etc/johnyin/gen_hostapd.sh

cat << 'EO_DOC' > ${DIRNAME}/buildroot/etc/johnyin/wifi_mode.sh
#!/bin/sh
set -e
export LANG=C
MODE_CONF=/etc/wifi_mode.conf
if [ `id -u` -ne 0 ] || [ "$1" = "" ]; then exit 1; fi
#no config wifi_mode.conf default use "initmode"
[ -r "${MODE_CONF}" ] || {
    cat >"${MODE_CONF}" <<-EOF
# wifi mode select
# station=work
# station=home

# 5G on ap0(virtual device)
# station=ap0

# 2.4G on wlan0
# station=ap

# adhoc create adhoc mesh network and bridge it.
# station=adhoc

# initmode no dhcpd no secret ap 192.168.1.1/24
station=initmode
EOF
}
. ${MODE_CONF}
case "$1" in
    wlan0)
        /usr/sbin/iw ${2} set power_save off >/dev/null 2>&1 || true
        echo ${station:-initmode}
        ;;
    br-ext)
        # hostname must in (s905d2/s905d3/usbpc)
        # # fix not connect on startup, and connect later no link
        /usr/sbin/ip link set eth0 up  >/dev/null 2>&1 || true
        cat /etc/hostname
        ;;
esac
exit 0
EO_DOC
chmod 755 ${DIRNAME}/buildroot/etc/johnyin/wifi_mode.sh

cat << EO_DOC > ${DIRNAME}/buildroot/etc/johnyin/adhoc.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
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
EO_DOC
cat << EO_DOC > ${DIRNAME}/buildroot/etc/johnyin/home.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
#ap_scan=1

network={
    id_str="home"
    priority=100
    scan_ssid=1
    ssid="s905d03"
    # ssid="yangchuang" psk="89484545"
    #key_mgmt=wpa-psk
    psk="Admin@123"
    #disabled=1
}
EO_DOC
cat << EO_DOC > ${DIRNAME}/buildroot/etc/johnyin/initmode.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
#ap_scan=1

network={
    id_str="admin"
    priority=70
    #frequency=60480
    ssid="s905d-admin"
    mode=2
    key_mgmt=NONE
}
EO_DOC
cat << EO_DOC > ${DIRNAME}/buildroot/etc/johnyin/p2p.conf
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
EO_DOC
cat << EO_DOC > ${DIRNAME}/buildroot/etc/johnyin/work.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#ap_scan=1
scan_cur_freq=1
#Whether to scan only the current frequency
# 0:  Scan all available frequencies. (Default)
# 1:  Scan current operating frequency if another VIF on the same radio is already associated.

network={
    id_str="work"
    priority=100
    scan_ssid=1
    ssid="xk-admin"
    #key_mgmt=wpa-psk
    psk="ADMIN@123"
}
EO_DOC

echo "enable fw_printenv command, bullseye u-boot-tools remove fw_printenv, so need copy!"
cat >${DIRNAME}/buildroot/etc/fw_env.config <<EOF
# Device to access      offset          env size
/dev/mmcblk2            0x27400000      0x10000
EOF

mkdir -p ${DIRNAME}/buildroot/etc/initramfs/post-update.d/
cat>${DIRNAME}/buildroot/etc/initramfs/post-update.d/99-uboot<<"EOF"
#!/bin/sh
echo "update-initramfs: Converting to u-boot format" >&2
tempname="/boot/uInitrd-$1"
mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d $2 $tempname > /dev/null
exit 0
EOF
chmod 755 ${DIRNAME}/buildroot/etc/initramfs/post-update.d/99-uboot

cat <<EOF>${DIRNAME}/buildroot/etc/motd
## ${VERSION[@]}
1. edit /etc/wifi_mode.conf for wifi mode modify
2. touch /overlay/reformatoverlay for factory mode after next reboot
3. fw_printenv / fw_setenv for get or set fw env
    fw_setenv bootdelay 0  #disable reboot delay hit key, bootdelay=1 enable it
4. dumpleases dump dhcp clients
5. overlayroot-chroot can chroot overlay lower fs(rw)
6. set eth0 mac address:
    fw_setenv ethaddr 5a:57:57:90:5d:01
7. set wifi0 mac address:
    sed "s/macaddr=.*/macaddr=b8:be:ef:90:5d:02/g" /lib/firmware/brcm/brcmfmac43455-sdio.txt
8. iw dev wlan0 station dump -v
9. start nfs-server: systemctl start nfs-server.service nfs-kernel-server.service
EOF

cat <<'EOF'> ${DIRNAME}/buildroot/usr/bin/overlayroot-chroot
#!/bin/sh
set -e
set -f # disable path expansion
REMOUNTS=""

error() {
	printf "ERROR: $@\n" 1>&2
}
fail() { [ $# -eq 0 ] || error "$@"; exit 1; }

info() {
	printf "INFO: $@\n" 1>&2
}

get_lowerdir() {
	local overlay=""
	overlay=$(awk '$1 == "overlay" && $2 == "/" { print $0 }' /proc/mounts)
	if [ -n "${overlay}" ]; then
		lowerdir=${overlay##*lowerdir=}
		lowerdir=${lowerdir%%,*}
		if mountpoint "${lowerdir}" >/dev/null; then
			_RET="${lowerdir}"
		else
			fail "Unable to find the overlay lowerdir"
		fi
	else
		fail "Unable to find an overlay filesystem"
	fi
}

clean_exit() {
	local mounts="$1" rc=0 d="" lowerdir="" mp=""
	for d in ${mounts}; do
		if mountpoint ${d} >/dev/null; then
			umount ${d} || rc=1
		fi
	done
	for mp in $REMOUNTS; do
		mount -o remount,ro "${mp}" ||
			error "Note that [${mp}] is still mounted read/write"
	done
	[ "$2" = "return" ] && return ${rc} || exit ${rc}
}

# Try to find the overlay filesystem
get_lowerdir
lowerdir=${_RET}

recurse_mps=$(awk '$1 ~ /^\/dev\// && $2 ~ starts { print $2 }' starts="^$lowerdir/" /proc/mounts)

mounts=
for d in proc dev run sys; do
	if ! mountpoint "${lowerdir}/${d}" >/dev/null; then
		mount -o bind "/${d}" "${lowerdir}/${d}" || fail "Unable to bind /${d}"
		mounts="$mounts $lowerdir/$d"
		trap "clean_exit \"${mounts}\" || true" EXIT HUP INT QUIT TERM
	fi
done

# Remount with read/write
for mp in "$lowerdir" $recurse_mps; do
	mount -o remount,rw "${mp}" &&
		REMOUNTS="$mp $REMOUNTS" ||
		fail "Unable to remount [$mp] writable"
done
info "Chrooting into [${lowerdir}]"
chroot ${lowerdir} "$@"
rm -rf ${lowerdir}/var/cache/apt/* ${lowerdir}/var/lib/apt/lists/* ${lowerdir}/var/log/* ${lowerdir}/var/lib/dpkg/status-old
rm -rf ${lowerdir}/root/.bash_history ${lowerdir}/root/.viminfo ${lowerdir}/root/.vim/
# Clean up mounts on exit
clean_exit "${mounts}" "return"
trap "" EXIT HUP INT QUIT TERM

# vi: ts=4 noexpandtab
EOF
chmod 755 ${DIRNAME}/buildroot/usr/bin/overlayroot-chroot

echo "add emmc_install script"
cat > ${DIRNAME}/buildroot/root/sync.sh <<'EOF'
#!/usr/bin/env bash

IP=${1:?from which ip???}
mount -o remount,rw /overlay/lower
rsync -avzP --numeric-ids --exclude-from=/root/exclude.txt --delete \
    -e "ssh -p60022" root@${IP}:/overlay/lower/* /overlay/lower/

echo "change ssid && dhcp router"
apaddr=$(ifquery wlan0=ap | grep "address:" | awk '{ print $2}')
sed -i "s/ssid=.*/ssid=\"$(hostname)\"/g" /overlay/lower/etc/wpa_supplicant/ap.conf
sed -n 's|^ssid=\(.*\)$|\1|p' /overlay/lower/etc/wpa_supplicant/ap.conf
mount -o remount,ro /overlay/lower

mount -o remount,rw /boot
rsync -avzP --numeric-ids -e "ssh -p60022" root@${IP}:/boot/* /boot/

mount -o remount,ro /boot

touch /overlay/reformatoverlay
sync
sync
EOF

cat > ${DIRNAME}/buildroot/root/exclude.txt <<'EOF'
/etc/network/interfaces.d/
firmware/brcm/brcmfmac43455-sdio.txt
/etc/ssh/
/etc/hostname
/etc/hosts
EOF
cat > ${DIRNAME}/buildroot/root/fix_sound_out_hdmi.sh <<'EOF'
amixer -c  GXP230Q200 sset 'AIU HDMI CTRL SRC' 'I2S'
aplay /usr/share/sounds/alsa/Noise.wav
# # su - johnyin (add to ~/.xsessionrc)
# DISPLAY=:0 xset -q
# DISPLAY=:0 xset -dpms
# DISPLAY=:0 xset s off
# DISPLAY=:0 xset dpms 0 0 0
# DISPLAY=:0 xrandr -q
# DISPLAY=:0 xrandr --output HDMI-1 --mode 1280x1024
EOF
cat > ${DIRNAME}/buildroot/root/emmc_linux.sh <<'EOF'
#!/usr/bin/env bash
DEV_EMMC=${DEV_EMMC:=/dev/mmcblk2}
BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
OVERLAY_LABEL="EMMCOVERLAY"
cat <<EOPART
# Mark reserved regions
# /dev/env: This "device" (present in Linux 3.x) uses 0x27400000 ~ +0x800000.
#           It seems that they're overwritten each time system boots if value
#           there is invalid. Therefore we must not touch these blocks.
# /dev/logo: This "device"  uses 0x28400000~ +0x800000. You may mark them as
#            bad blocks if you want to preserve or replace the boot logo.
#
# All other "devices" (i.e., recovery, rsv, tee, crypt, misc, boot, system, data
# should be safe to overwrite.)
[mmcblk0p01]  bootloader  offset 0x000000000000  size 0x000000400000      0MiB     4
[mmcblk0p02]    reserved  offset 0x000002400000  size 0x000004000000      36MiB    64
[mmcblk0p03]       cache  offset 0x000006c00000  size 0x000020000000      108MiB   512
[mmcblk0p04]         env  offset 0x000027400000  size 0x000000800000      628MiB   8
[mmcblk0p05]        logo  offset 0x000028400000  size 0x000002000000      644MiB   32
[mmcblk0p06]    recovery  offset 0x00002ac00000  size 0x000002000000      684MiB   32
[mmcblk0p07]         rsv  offset 0x00002d400000  size 0x000000800000      724MiB   8
[mmcblk0p08]         tee  offset 0x00002e400000  size 0x000000800000      740MiB   8
[mmcblk0p09]       crypt  offset 0x00002f400000  size 0x000002000000      756MiB   32
[mmcblk0p10]        misc  offset 0x000031c00000  size 0x000002000000      796MiB   32
[mmcblk0p11]        boot  offset 0x000034400000  size 0x000002000000      836MiB   32
[mmcblk0p12]      system  offset 0x000036c00000  size 0x000050000000      876MiB   1280
[mmcblk0p13]        data  offset 0x000087400000  size 0x00014ac00000      2164MiB  5292
EOPART
####################################################################################################
echo "Start script create MBR and filesystem"
echo "So as to not overwrite U-boot, we backup the first 1M."
dd if=${DEV_EMMC} of=/tmp/boot-bak bs=1M count=4
dd if=${DEV_EMMC} of=/tmp/env-bak bs=1024 count=8192 skip=643072
dd if=${DEV_EMMC} of=/tmp/logo-bak bs=1024 count=32768 skip=659456

echo "(Re-)initialize the eMMC and create partition."
parted -s "${DEV_EMMC}" mklabel msdos
parted -s "${DEV_EMMC}" mkpart primary fat32 108MiB 172MiB
parted -s "${DEV_EMMC}" mkpart primary linux-swap 172MiB 512MiB
parted -s "${DEV_EMMC}" mkpart primary ext4 684MiB 3GiB
parted -s "${DEV_EMMC}" mkpart primary ext4 3GiB 100%

echo "Start restore u-boot"
# Restore U-boot (except the first 442 bytes, where partition table is stored.)
dd if=/tmp/boot-bak of=${DEV_EMMC} conv=fsync bs=1 count=442
dd if=/tmp/boot-bak of=${DEV_EMMC} conv=fsync bs=512 skip=1 seek=1

DISK=${DEV_EMMC}
PART_BOOT="${DISK}p1"
PART_SWAP="${DISK}p2"
PART_ROOT="${DISK}p3"
PART_OVERLAY="${DISK}p4"

echo "Format the partitions."
mkfs.vfat -n ${BOOT_LABEL} ${PART_BOOT}
mkswap -L EMMCSWAP "${PART_SWAP}"
mkfs -t ext4 -m 0 -q -L ${ROOT_LABEL} ${PART_ROOT}
mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${PART_OVERLAY}

echo "Flush changes (in case they were cached.)."
sync
echo "reflush env&logo, mkfs crash it!!!!"
dd if=/tmp/env-bak of=${DEV_EMMC} bs=1024 count=8192 seek=643072
dd if=/tmp/logo-bak of=${DEV_EMMC} bs=1024 count=32768 seek=659456
EOF
cat <<'EO_DOC'
export PROMPT_COMMAND='export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$([[ -r "/overlay/reformatoverlay" ]] && echo "[reboot factory]")$"'
#Xfce
aplay -l
pactl list cards
# output soundcard
pactl set-card-profile 0 output:analog-stereo
# output hdmi
pactl set-card-profile 0 output:hdmi-stereo
# login xfce, run  alsamixer -> F6 -> ....
amixer -c  GXP230Q200 sset 'AIU HDMI CTRL SRC' 'I2S'
EO_DOC

# autologin-guest=false
# autologin-user=user(not root)
# autologin-user-timeout=0
# groupadd -r autologin
# gpasswd -a root autologin
echo "SUCCESS build rootfs, all!!!"

echo "start install you kernel&patchs"
if [ -d "${DIRNAME}/kernel" ]; then
    rsync -avzP --numeric-ids ${DIRNAME}/kernel/* ${DIRNAME}/buildroot/ || true
    # kerver=$(ls ${DIRNAME}/buildroot/usr/lib/modules/ | sort --version-sort -f | tail -n1)
    kerver=$(menu_select "kernel: " $(ls ${DIRNAME}/buildroot/usr/lib/modules/))
    dtb=$(menu_select "dtb: " $(ls ${DIRNAME}/buildroot/boot/dtb/))
    echo "USE KERNEL ${kerver} ------>"
    cat > ${DIRNAME}/buildroot/boot/aml_autoscript.cmd <<'EOF'
setenv bootcmd "run start_autoscript; run storeboot;"
setenv start_autoscript "if usb start; then run start_usb_autoscript; fi; if mmcinfo; then run start_mmc_autoscript; fi; run start_mmc_autoscript;"
setenv start_mmc_autoscript "if fatload mmc 0 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload mmc 1 1020000 s905_autoscript; then autoscr 1020000; fi;"
setenv start_usb_autoscript "if fatload usb 0 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 1 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 2 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 3 1020000 s905_autoscript; then autoscr 1020000; fi;"
setenv upgrade_step "0"
saveenv
sleep 1
reboot
EOF
    cat > ${DIRNAME}/buildroot/boot/s905_autoscript.nfs.cmd <<'EOF'
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv serverip 172.16.16.2
setenv ipaddr 172.16.16.168
setenv bootargs "root=/dev/nfs nfsroot=${serverip}:/nfsshare/root rw net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 rootwait"
setenv bootcmd_pxe "tftp ${kernel_addr} zImage; tftp ${initrd_addr} uInitrd; tftp ${dtb_mem_addr} dtb.img; booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr}"
run bootcmd_pxe
EOF
   cat > ${DIRNAME}/buildroot/boot/s905_autoscript.cmd <<'EOF'
setenv env_addr     "0x10400000"
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv boot_start booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr}
if fatload usb 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if fatload usb 0 ${kernel_addr} ${image}; then if fatload usb 0 ${initrd_addr} ${initrd}; then if fatload usb 0 ${dtb_mem_addr} ${dtb}; then run boot_start; fi; fi; fi; fi;
if fatload usb 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if fatload usb 1 ${kernel_addr} ${image}; then if fatload usb 1 ${initrd_addr} ${initrd}; then if fatload usb 1 ${dtb_mem_addr} ${dtb}; then run boot_start; fi; fi; fi; fi;
if fatload mmc 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if fatload mmc 0 ${kernel_addr} ${image}; then if fatload mmc 0 ${initrd_addr} ${initrd}; then if fatload mmc 0 ${dtb_mem_addr} ${dtb}; then run boot_start; fi; fi; fi; fi;
if fatload mmc 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if fatload mmc 1 ${kernel_addr} ${image}; then if fatload mmc 1 ${initrd_addr} ${initrd}; then if fatload mmc 1 ${dtb_mem_addr} ${dtb}; then run boot_start; fi; fi; fi; fi;
EOF
    cat > ${DIRNAME}/buildroot/boot/uEnv.ini <<EOF
image=vmlinuz-${kerver}
initrd=uInitrd-${kerver}
dtb=/dtb/${dtb}
bootargs=root=LABEL=${ROOT_LABEL} rootflags=data=writeback fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 video=1280x1024@60me
boot_pxe=false
EOF
    cat  > ${DIRNAME}/buildroot/boot/s905_autoscript.uboot.cmd <<'EOF'
echo "Start u-boot......"
setenv env_addr   "0x10400000"
setenv uboot_addr "0x1000000"
if fatload usb 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload usb 0 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload usb 0 ${uboot_addr} u-boot.usb.bin; then go ${uboot_addr}; fi; fi;
if fatload usb 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload usb 1 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload usb 1 ${uboot_addr} u-boot.usb.bin; then go ${uboot_addr}; fi; fi;
if fatload mmc 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload mmc 0 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload mmc 0 ${uboot_addr} u-boot.mmc.bin; then go ${uboot_addr}; fi; fi;
if fatload mmc 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload mmc 1 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload mmc 1 ${uboot_addr} u-boot.mmc.bin; then go ${uboot_addr}; fi; fi;
EOF
    mkdir -p ${DIRNAME}/buildroot/boot/extlinux
    cat <<EOF > ${DIRNAME}/buildroot/boot/extlinux/extlinux.conf
label PHICOMM_N1
    linux /vmlinuz-${kerver}
    initrd /initrd.img-${kerver}
    fdt /dtb/${dtb}
    append root=LABEL=${ROOT_LABEL} rootflags=data=writeback fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 video=1280x1024@60me
EOF
    echo "https://github.com/PuXiongfei/phicomm-n1-u-boot"
    echo "5d921bf1d57baf081a7b2e969d7f70a5  u-boot.bin"
    echo "ade4aa3942e69115b9cc74d902e17035  u-boot.bin.new"
    cat ${DIRNAME}/u-boot.mmc.bin > ${DIRNAME}/buildroot/boot/u-boot.mmc.bin || true
    cat ${DIRNAME}/u-boot.usb.bin > ${DIRNAME}/buildroot/boot/u-boot.usb.bin || true
    cat ${DIRNAME}/u-boot.pxe.bin > ${DIRNAME}/buildroot/boot/u-boot.pxe.bin || true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot/ /bin/bash <<EOSHELL
    depmod ${kerver}
    update-initramfs -c -k ${kerver}
    rm -f /boot/s905_autoscript /boot/s905_autoscript /boot/s905_autoscript.uboot /boot/s905_autoscript.nfs || true
    # aml_autoscript for android to linux bootup
    mkimage -C none -A arm -T script -d /boot/aml_autoscript.cmd /boot/aml_autoscript
    mkimage -C none -A arm -T script -d /boot/s905_autoscript.cmd /boot/s905_autoscript
    mkimage -C none -A arm -T script -d /boot/s905_autoscript.uboot.cmd /boot/s905_autoscript.uboot
    mkimage -C none -A arm -T script -d /boot/s905_autoscript.nfs.cmd /boot/s905_autoscript.nfs
    rm -f /boot/aml_autoscript.cmd /boot/s905_autoscript.cmd /boot/s905_autoscript.uboot.cmd /boot/s905_autoscript.nfs.cmd || true
EOSHELL
    echo "!!!!!!!!!IF USB BOOT DISK, rm -f ${DIRNAME}/buildroot/etc/udev/rules.d/*"
fi
ls -lhR ${DIRNAME}/buildroot/boot/
echo "end install you kernel&patchs"

echo "start chroot shell, disable service & do other work"
chroot ${DIRNAME}/buildroot/ /usr/bin/env -i PS1='\u@s905d:\w$' /bin/bash --noprofile --norc -o vi || true
chroot ${DIRNAME}/buildroot/ /bin/bash -s <<EOF
    debian_minimum_init
    sed -i "s/TimeoutStartSec=.*/TimeoutStartSec=5sec/g" /lib/systemd/system/networking.service
EOF
exit 0
