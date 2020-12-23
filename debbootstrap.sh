#!/bin/bash
#fw_setenv bootcmd "run update"; reboot
#之后PC端的刷机程序就会检测到设备进入刷机模式，按软件的刷机提示刷机即可。
set -o errexit -o nounset -o pipefail

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
export DIRNAME="$(pwd)"
#DIRNAME="$(dirname "$(realpath "$0")")"
#DIRNAME="$(dirname "$(readlink -e "$0")")"
export SCRIPTNAME=${0##*/}

INST_ARCH=${INST_ARCH:-arm64}
REPO=http://mirrors.163.com/debian
PASSWORD=password
export DEBIAN_VERSION=${DEBIAN_VERSION:-buster}
export FS_TYPE=${FS_TYPE:-ext4}
BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
OVERLAY_LABEL="EMMCOVERLAY"

ZRAMSWAP="udisks2"
#ZRAMSWAP="zram-tools"
PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools,u-boot-tools,fake-hwclock,openssh-server,busybox"
PKG="${PKG},udev,isc-dhcp-client,netbase,console-setup,pkg-config,net-tools,wpasupplicant,hostapd,iputils-ping,telnet,vim,ethtool,${ZRAMSWAP},dosfstools,iw,ipset,nmap,ipvsadm,bridge-utils,batctl,babeld,ifenslave,vlan"
PKG="${PKG},parprouted,dhcp-helper,nbd-client,iftop,pigz,nfs-common,nfs-kernel-server"

[[ ${INST_ARCH} = "amd64" ]] && PKG="${PKG},linux-image-amd64"

if [ "$UID" -ne "0" ]
then 
    echo "Must be root to run this script." 
    exit 1
fi

cleanup() {
    trap '' INT TERM EXIT
    echo "EXIT!!!"
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

debootstrap --verbose --no-check-gpg --arch ${INST_ARCH} --variant=minbase --include=${PKG} --foreign ${DEBIAN_VERSION} ${DIRNAME}/buildroot ${REPO}

[[ ${INST_ARCH} = "arm64" ]] && cp /usr/bin/qemu-aarch64-static ${DIRNAME}/buildroot/usr/bin/

unset PROMPT_COMMAND
LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /debootstrap/debootstrap --second-stage

LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL

echo usb905d > /etc/hostname

echo "Enable udisk2 zram swap"
mkdir -p /usr/local/lib/zram.conf.d/
echo "zram" >> /etc/modules
echo "batman-adv" >> /etc/modules
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
tmpfs /run      tmpfs   rw,nosuid,noexec,relatime,size=8192k,mode=755  0  0
tmpfs /tmp      tmpfs   rw,nosuid,noexec,relatime,mode=777  0  0
# overlayfs can not nfs exports, so use tmpfs
tmpfs /media    tmpfs   defaults,size=1M  0  0
EOF

echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
echo 'APT::Install-Recommends "0";'> /etc/apt/apt.conf.d/71-no-recommends
echo 'APT::Install-Suggests "0";'> /etc/apt/apt.conf.d/72-no-suggests

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

cat > /etc/apt/sources.list << EOF
deb http://mirrors.163.com/debian ${DEBIAN_VERSION} main non-free contrib
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-proposed-updates main non-free contrib
deb http://mirrors.163.com/debian-security ${DEBIAN_VERSION}/updates main contrib non-free
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

# enable ttyAML0 login
echo "ttyAML0" >> /etc/securetty

# export nfs
# no_root_squash(enable root access nfs)
cat > /etc/exports << EOF
/media/       192.168.168.0/24(ro,sync,no_subtree_check,crossmnt,nohide,no_root_squash,no_all_squash,fsid=0)
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
# remove noused locale
path-include /usr/share/locale/zh_CN/*
path-exclude /usr/share/locale/*
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
#brcmfmac
#dwmac_meson8b
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

cat >/overlay/lower/etc/apt/sources.list<<DEBEOF
deb http://mirrors.163.com/debian buster main non-free contrib
deb http://mirrors.163.com/debian buster-proposed-updates main non-free contrib
deb http://mirrors.163.com/debian-security buster/updates main contrib non-free
deb http://mirrors.163.com/debian buster-backports main contrib non-free
DEBEOF

chroot /overlay/lower apt update
chroot /overlay/lower apt install \$*

rm -rf /overlay/lower/var/cache/apt/* /overlay/lower/var/lib/apt/lists/* /overlay/lower/var/log/*
rm -rf /overlay/lower/root/.bash_history /overlay/lower/root/.viminfo /overlay/lower/root/.vim/
cat ~/sources.list.bak > /overlay/lower/etc/apt/sources.list
rm -f ~/sources.list.bak
sync
mount -o remount,ro /overlay/lower

EOF

cat >> /root/brige_wlan_eth.sh <<'SCRIPT_EOF'
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

cat >> /root/inst.sh <<EOF
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
EOF

cat >> /etc/sysctl.conf << EOF
net.core.rmem_max = 134217728 
net.core.wmem_max = 134217728 
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.core.wmem_default = 16777216
net.ipv4.ip_local_port_range = 1024 65531
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
"新建.py,.c,.sh,.h文件，自动插入文件头"
autocmd BufNewFile *.py,*.c,*.sh,*.h exec ":call SetTitle()"
"定义函数SetTitle，自动插入文件头"
func SetTitle()
    if expand ("%:e") == 'sh'
        call setline(1, "#!/usr/bin/env bash")
        call setline(2, "readonly DIRNAME=\"$(readlink -f \"$(dirname \"$0\")\")\"")
        call setline(3, "readonly SCRIPTNAME=${0##*/}")
        call setline(4, "if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then")
        call setline(5, "    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log")
        call setline(6, "    BASH_XTRACEFD=\"5\"")
        call setline(7, "    export PS4='[\\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'")
        call setline(8, "    set -o xtrace")
        call setline(9, "fi")
        call setline(10, "[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true")
        call setline(11, "################################################################################")
        call setline(12, "main() {")
        call setline(13, "    return 0")
        call setline(14, "}")
        call setline(15, "main \"$@\"")
    endif
    if expand ("%:e") == 'py'
        call setline(1, "#!/usr/bin/env python3")
        call setline(2, "# -*- coding: utf-8 -*- ")
        call setline(3, "")
        call setline(4, "def main():")
        call setline(5, "    return 0")
        call setline(6, "")
        call setline(7, "if __name__ == '__main__':")
        call setline(8, "    main()")
    endif
endfunc

EOF
sed -i "/mouse=a/d" /usr/share/vim/vim81/defaults.vim

usermod -p '$(echo ${PASSWORD} | openssl passwd -1 -stdin)' root
# echo "root:${PASSWORD}" |chpasswd 
echo "Force Users To Change Their Passwords Upon First Login"
chage -d 0 root

apt -y install --no-install-recommends cron logrotate bsdmainutils rsyslog openssh-client wget ntpdate less wireless-tools file fonts-droid-fallback lsof strace rsync
apt -y install --no-install-recommends xz-utils zip
apt -y remove ca-certificates wireless-regdb crda --purge
apt -y autoremove --purge

exit

EOSHELL

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
kernel parm "skipoverlay" / lowerfs /etc/overlayroot.conf
OVERLAY= overlayfs lable default "OVERLAY"
SKIP_OVERLAY=

/overlay/reformatoverlay exist will format it!
overlayfs: upper fs needs to support d_type.
overlayfs: upper fs does not support tmpfile.
# mke2fs -FL OVERLAY -t ext4 -E lazy_itable_init,lazy_journal_init DEVICE
EOF

if ! grep -q "^overlay" ${DIRNAME}/buildroot/etc/initramfs-tools/modules; then
    echo overlay >> ${DIRNAME}/buildroot/etc/initramfs-tools/modules
fi

cat > ${DIRNAME}/buildroot/usr/share/initramfs-tools/hooks/overlay <<'EOF'
#!/bin/sh

. /usr/share/initramfs-tools/scripts/functions
. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/blkid
copy_exec /sbin/fsck
copy_exec /sbin/mke2fs
copy_exec /sbin/fsck.ext2
copy_exec /sbin/fsck.ext3
copy_exec /sbin/fsck.ext4
copy_exec /sbin/logsave
EOF

cat > ${DIRNAME}/buildroot/etc/overlayroot.conf<<EOF
OVERLAY=${OVERLAY_LABEL}
SKIP_OVERLAY=0
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

[ -f ${rootmnt}/etc/overlayroot.conf ] && . ${rootmnt}/etc/overlayroot.conf
OVERLAY_LABEL=${OVERLAY:-OVERLAY}
SKIP_OVERLAY=${SKIP_OVERLAY:-0}
grep -q -E '(^|\s)skipoverlay(\s|$)' /proc/cmdline && SKIP_OVERLAY=1

if [[ ${SKIP_OVERLAY-} =~ ^1|yes|true$ ]]; then
    log_begin_msg "Skipping overlay, found 'skipoverlay' in cmdline"
    log_end_msg
    exit 0
fi

log_begin_msg "Starting overlay"
log_end_msg

mkdir -p /overlay

# if we have a filesystem label of ${OVERLAY_LABEL}
# use that as the overlay, otherwise use tmpfs.
OLDEV=$(blkid -L ${OVERLAY_LABEL})
if [ -z "${OLDEV}" ]; then
    mount -t tmpfs tmpfs /overlay
else
    _checkfs_once ${OLDEV} /overlay ext4 || \
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${OLDEV}
    if ! mount -t ext4 -onoatime ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

# if you sudo touch /overlay/reformatoverlay
# next reboot will give you a fresh /overlay
if [ -f /overlay/reformatoverlay ]; then
    umount /overlay
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${OLDEV}
    if ! mount -t ext4 -onoatime ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

mkdir -p /overlay/upper
mkdir -p /overlay/work
mkdir -p /overlay/lower

# make the readonly root available
mount -n -o move ${rootmnt} /overlay/lower
mount -t overlay overlay -onoatime,lowerdir=/overlay/lower,upperdir=/overlay/upper,workdir=/overlay/work ${rootmnt}

mkdir -p ${rootmnt}/overlay
mount -n -o rbind /overlay ${rootmnt}/overlay

# fix up fstab
# cp ${rootmnt}/etc/fstab ${rootmnt}/etc/fstab.orig
# awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab.orig > ${rootmnt}/etc/fstab
# awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab >> ${rootmnt}/etc/fstab
# Already there?
# if [ -e ${rootmnt}/etc/fstab ] && grep -qE '^overlay[[:space:]]+/etc[[:space:]]' ${rootmnt}/etc/fstab; then
# 	exit 0 # Do nothing
# fi

FSTAB=$(awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab && awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab)
cat>${rootmnt}/etc/fstab<<EO_FSTAB
$FSTAB
EO_FSTAB

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
cat <<'EOF'
#ext4 boot disk
fw_setenv start_emmc_autoscript 'if ext4load mmc 1 ${env_addr} /boot/boot.ini; then env import -t ${env_addr} ${filesize}; if ext4load mmc 1 ${kernel_addr} ${image}; then if ext4load mmc 1 ${initrd_addr} ${initrd}; then if ext4load mmc 1 ${dtb_mem_addr} ${dtb}; then run boot_start;fi;fi;fi;fi;'

#boot.ini
image=/boot/vmlinuz-5.1.7
initrd=/boot/uInitrd
dtb=/boot/meson-gxl-s905d-phicomm-n1.dtb
bootargs=root=/dev/mmcblk1p1 rootflags=data=writeback rw console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0
EOF
