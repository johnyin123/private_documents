#!/bin/bash

VERSION+=("init-pc.sh - 1c38edb - 2021-01-17T04:40:43+08:00")

DEBIAN_VERSION=buster
PASSWORD=password
#512 M
ZRAM_SIZE=512
ZRAMSWAP="udisks2"
#ZRAMSWAP="zram-tools"

echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
echo 'APT::Install-Recommends "0";'> /etc/apt/apt.conf.d/71-no-recommends
echo 'APT::Install-Suggests "0";'> /etc/apt/apt.conf.d/72-no-suggests

# auto reformatoverlay plug usb ttl
#cat > /etc/udev/rules.d/99-reformatoverlay.rules << EOF
#SUBSYSTEM=="tty", ACTION=="add", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="/bin/sh -c 'touch /overlay/reformatoverlay; echo heartbeat > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
#SUBSYSTEM=="tty", ACTION=="remove", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="/bin/sh -c 'rm /overlay/reformatoverlay; echo none > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
#EOF

cat > /etc/apt/sources.list << EOF
deb http://mirrors.163.com/debian ${DEBIAN_VERSION} main non-free contrib
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-proposed-updates main non-free contrib
deb http://mirrors.163.com/debian-security ${DEBIAN_VERSION}/updates main contrib non-free
deb http://mirrors.163.com/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

apt update

echo "add group[johnyin] to sudoers"
apt -y install sudo
echo "%johnyin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/johnyin
chmod 0440 /etc/sudoers.d/johnyin
cp /etc/sudoers /etc/sudoers.orig
sed -i "s/^\(.*requiretty\)$/#\1/" /etc/sudoers

echo "xk-yinzh" > /etc/hostname
apt -y install ${ZRAMSWAP}
echo "Enable udisk2 ${ZRAM_SIZE}M zram swap"
mkdir -p /usr/local/lib/zram.conf.d/
(grep -v -E "zram" /etc/modules; echo "zram"; ) | tee /etc/modules
cat << EOF > /usr/local/lib/zram.conf.d/zram0-env
ZRAM_NUM_STR=lzo
ZRAM_DEV_SIZE=$((${ZRAM_SIZE}*1024*1024))
SWAP=y
EOF

cat << EOF > /etc/hosts
127.0.0.1       localhost $(cat /etc/hostname)
EOF

echo "maybe need modify fstab"
cat << EOF >> /etc/fstab
#tmpfs /var/log  tmpfs   defaults,noatime,nosuid,nodev,noexec,size=16M  0  0
EOF

#Installing packages without docs
cat > /etc/dpkg/dpkg.cfg.d/01_nodoc <<EOF
# lintian stuff is small, but really unnecessary
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
# remove noused locale
path-include /usr/share/locale/zh_CN/*
path-exclude /usr/share/locale/*
EOF
#dpkg-reconfigure locales
sed -i "s/^# *zh_CN.UTF-8/zh_CN.UTF-8/g" /etc/locale.gen
locale-gen
echo -e 'LANG="zh_CN.UTF-8"\nLANGUAGE="zh_CN:zh"\nLC_ALL="zh_CN.UTF-8"\n' > /etc/default/locale

#echo "Asia/Shanghai" > /etc/timezone
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata
# confing console fonts
# dpkg-reconfigure console-setup

apt -y install openssh-server
dpkg-reconfigure -f noninteractive openssh-server
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/g' /etc/ssh/sshd_config
sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
(grep -v -E "^Ciphers|^MACs" /etc/ssh/sshd_config ; echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr"; echo "MACs    hmac-sha1"; ) | tee /etc/ssh/sshd_config.bak
mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config

cat << EOF | tee /etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

echo "install network bridge"
apt -y install bridge-utils
cat << EOF | tee /etc/network/interfaces.d/br-ext
auto eth0
allow-hotplug eth0
iface eth0 inet manual

auto br-ext
iface br-ext inet static
    bridge_ports eth0
    #bridge_ports none
    address 10.32.166.31/25
    gateway 10.32.166.1

# auto bond0
# iface bond0 inet manual
#         up ifconfig bond0 0.0.0.0 up
#         slaves eth4 eth5
#         # bond-mode 4 = 802.3ad
#         bond-mode 4
#         bond-miimon 100
#         bond-downdelay 200
#         bond-updelay 200
#         bond-lacp-rate 1
#         bond-xmit-hash-policy layer2+3
# auto vlan1023
# iface vlan1023 inet static
#         vlan-raw-device bond0
EOF

cat << "EOF" | tee /etc/network/interfaces.d/wifi
auto wlan0
allow-hotplug wlan0

mapping wlan0
    script /etc/johnyin/wifi_mode.sh
    map work
    map home
    map adhoc
    map initmode

iface work inet dhcp
    #pre-up (/usr/sbin/ifup ap0 || true)
    wpa_iface wlan0
    wpa_conf /etc/johnyin/work.conf

iface home inet dhcp
    pre-up (/usr/sbin/ifup ap0 || true)
    wpa_iface wlan0
    wpa_conf /etc/johnyin/home.conf

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
    wpa_conf /etc/johnyin/adminap.conf
    address 192.168.1.1/24

iface ap0 inet manual
    hostapd /etc/johnyin/hostap.conf
    pre-up (/usr/sbin/iw phy `/usr/bin/ls /sys/class/ieee80211/` interface add ap0 type __ap)
    pre-up (touch /var/lib/misc/udhcpd.leases || true)
    post-up (iptables-restore < /etc/iptables.rules || true)
    post-up (/usr/bin/busybox udhcpd -S /etc/johnyin/udhcpd.conf || true)
    pre-down (/usr/bin/kill -9 $(cat /var/run/udhcpd-wlan0.pid) || true)
    post-down (/usr/sbin/iw dev ap0 del)
EOF

mkdir -p /etc/johnyin/
cat << 'EOF_WIFI' > /etc/johnyin/wifi_mode.sh
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

# adhoc create adhoc mesh network and bridge it.
# station=adhoc

# initmode no dhcpd no secret ap 192.168.1.1/24
station=initmode
EOF
}
. ${MODE_CONF}
iw wlan0 set power_save off || true
echo ${station:-initmode}
exit 0
EOF_WIFI
chmod 755 /etc/johnyin/wifi_mode.sh

cat << 'EOF_WIFI' > /etc/johnyin/work.conf
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
EOF_WIFI
cat << 'EOF_WIFI' > /etc/johnyin/home.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
#ap_scan=1

network={
    id_str="home"
    priority=100
    scan_ssid=1
    ssid="johnap"
    #key_mgmt=wpa-psk
    psk="Admin@123"
    #disabled=1
}
EOF_WIFI
cat << 'EOF_WIFI' > /etc/johnyin/adhoc.conf
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
EOF_WIFI
cat << 'EOF_WIFI' > /etc/johnyin/adminap.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
#ap_scan=1

network={
    id_str="admin"
    priority=70
    #frequency=60480
    ssid="s905d2-admin"
    mode=2
    key_mgmt=NONE
}
EOF_WIFI
cat << 'EOF_WIFI' > /etc/johnyin/hostap.conf
interface=ap0
bridge=br-ext
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

ssid=s905d2
macaddr_acl=0
#accept_mac_file=/etc/hostapd.accept
#deny_mac_file=/etc/hostapd.deny
auth_algs=1
# 采用 OSA 认证算法 
ignore_broadcast_ssid=0 
wpa=2
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
channel=3
# 指定无线频道 


# DHCP server for FILS HLP
# If configured, hostapd will act as a DHCP relay for all FILS HLP requests
# that include a DHCPDISCOVER message and send them to the specific DHCP
# server for processing. hostapd will then wait for a response from that server
# before replying with (Re)Association Response frame that encapsulates this
# DHCP response. own_ip_addr is used as the local address for the communication
# with the DHCP server.
#dhcp_server=127.0.0.1
#dhcp_server_port=67
#dhcp_relay_port=67
# DHCP rapid commit proxy
# If set to 1, this enables hostapd to act as a DHCP rapid commit proxy to
# allow the rapid commit options (two message DHCP exchange) to be used with a
# server that supports only the four message DHCP exchange. This is disabled by
# default (= 0) and can be enabled by setting this to 1.
#dhcp_rapid_commit_proxy=0

# Wait time for FILS HLP (dot11HLPWaitTime) in TUs
# default: 30 TUs (= 30.72 milliseconds)
#fils_hlp_wait_time=30

# Proxy ARP
# 0 = disabled (default)
# 1 = enabled
#proxy_arp=1
EOF_WIFI
cat << 'EOF_WIFI' > /etc/johnyin/udhcpd.conf
start           192.168.168.100
end             192.168.168.150
interface       br-ext
max_leases      45
lease_file      /var/lib/misc/udhcpd.leases
pidfile         /var/run/udhcpd-wlan0.pid
option  domain  local
option  lease   86400
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
EOF_WIFI

cat << EOF > /etc/rc.local
#!/bin/sh -e
exit 0
EOF
chmod 755 /etc/rc.local

cat >/etc/profile.d/johnyin.sh<<"EOF"
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"

[ -e /usr/lib/git-core/git-sh-prompt ] && {
    source /usr/lib/git-core/git-sh-prompt
    export GIT_PS1_SHOWDIRTYSTATE=1
    export readonly PROMPT_COMMAND='__git_ps1 "\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]\\h:\\[\\033[33;1m\\]\\w\\[\\033[m\\]"  "\\\\\$ "'
}
set -o vi
EOF

#set the file limit
cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
cat << "EOF" > /root/aptrom.sh
#!/usr/bin/env bash

mount -o remount,rw /overlay/lower
cp /overlay/lower/etc/apt/sources.list ~/sources.list.bak

mount -o remount,rw /overlay/lower

chroot /overlay/lower apt update
chroot /overlay/lower apt install $*

rm -rf /overlay/lower/var/cache/apt/* /overlay/lower/var/lib/apt/lists/* /overlay/lower/var/log/*
rm -rf /overlay/lower/root/.bash_history /overlay/lower/root/.viminfo /overlay/lower/root/.vim/
sync
mount -o remount,ro /overlay/lower
EOF

cat <<EOF
net.ipv4.ip_local_port_range = 1024 65531
net.ipv4.tcp_fin_timeout = 10
# (65531-1024)/10 = 6450 sockets per second.
EOF

cat << EOF > /etc/sysctl.conf
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

echo "Install vim editor"
apt -y install vim
cat <<'EOF' > /etc/vim/vimrc.local
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
"disable .viminfo file
set viminfo=
let g:is_bash=1

"新建.py,.sh文件，自动插入文件头"
autocmd BufNewFile *.py,*.c,*.sh,*.h exec ":call SetTitle()"
"定义函数SetTitle，自动插入文件头"
func SetTitle()
    if expand ("%:e") == 'sh'
        call setline(1, "#!/usr/bin/env bash")
        call setline(2, "readonly DIRNAME=\"$(readlink -f \"$(dirname \"$0\")\")\"")
        call setline(3, "readonly SCRIPTNAME=${0##*/}")
        call setline(4, "if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then")
        call setline(5, "    exec 5> \"${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log\"")
        call setline(6, "    BASH_XTRACEFD=\"5\"")
        call setline(7, "    export PS4='[\\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'")
        call setline(8, "    set -o xtrace")
        call setline(9, "fi")
        call setline(10, "VERSION+=()")
        call setline(11, "[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true")
        call setline(12, "################################################################################")
        call setline(13, "usage() {")
        call setline(14, "    [ \"$#\" != 0 ] && echo \"$*\"")
        call setline(15, "    cat <<EOF")
        call setline(16, "${SCRIPTNAME}")
        call setline(17, "        -q|--quiet")
        call setline(18, "        -l|--log <int> log level")
        call setline(19, "        -V|--version")
        call setline(20, "        -d|--dryrun dryrun")
        call setline(21, "        -h|--help help")
        call setline(22, "EOF")
        call setline(23, "    exit 1")
        call setline(24, "}")
        call setline(25, "main() {")
        call setline(26, "    local opt_short=\"\"")
        call setline(27, "    local opt_long=\"\"")
        call setline(28, "    opt_short+=\"ql:dVh\"")
        call setline(29, "    opt_long+=\"quite,log:,dryrun,version,help\"")
        call setline(30, "    __ARGS=$(getopt -n \"${SCRIPTNAME}\" -o ${opt_short} -l ${opt_long} -- \"$@\") || usage")
        call setline(31, "    eval set -- \"${__ARGS}\"")
        call setline(32, "    while true; do")
        call setline(33, "        case \"$1\" in")
        call setline(34, "            ########################################")
        call setline(35, "            -q | --quiet)   shift; QUIET=1;;")
        call setline(36, "            -l | --log)     shift; set_loglevel ${1}; shift;;")
        call setline(37, "            -d | --dryrun)  shift; DRYRUN=1;;")
        call setline(38, "            -V | --version) shift; for _v in \"${VERSION[@]}\"; do echo \"$_v\"; done; exit 0;;")
        call setline(39, "            -h | --help)    shift; usage;;")
        call setline(40, "            --)             shift; break;;")
        call setline(41, "            *)              usage \"Unexpected option: $1\";;")
        call setline(42, "        esac")
        call setline(43, "    done")
        call setline(44, "    return 0")
        call setline(45, "}")
        call setline(46, "main \"$@\"")
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

echo "start install overlay_rootfs ====================="
cat <<EOF
kernel parm "skipoverlay" / lowerfs /etc/overlayroot.conf
OVERLAY= overlayfs lable default "OVERLAY"
SKIP_OVERLAY=

/overlay/reformatoverlay exist will format it!
overlayfs: upper fs needs to support d_type.
overlayfs: upper fs does not support tmpfile.
# mke2fs -FL OVERLAY -t ext4 -E lazy_itable_init,lazy_journal_init DEVICE
EOF

(grep -v -E "^overlay" /etc/initramfs-tools/modules; echo "overlay"; ) | tee /etc/initramfs-tools/modules

cat > /usr/share/initramfs-tools/hooks/overlay <<'EOF'
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
cat > /etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay <<'EOF'
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

if [ "${SKIP_OVERLAY-}" = 1 ]; then
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
    if ! mount -t ext4 ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

# if you sudo touch /overlay/reformatoverlay
# next reboot will give you a fresh /overlay
if [ -f /overlay/reformatoverlay ]; then
    umount /overlay
    mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${OLDEV}
    if ! mount -t ext4 ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

mkdir -p /overlay/upper
mkdir -p /overlay/work
mkdir -p /overlay/lower

# make the readonly root available
mount -n -o move ${rootmnt} /overlay/lower
mount -t overlay overlay -olowerdir=/overlay/lower,upperdir=/overlay/upper,workdir=/overlay/work ${rootmnt}

mkdir -p ${rootmnt}/overlay
mount -n -o rbind /overlay ${rootmnt}/overlay

# fix up fstab
# cp ${rootmnt}/etc/fstab ${rootmnt}/etc/fstab.orig
# awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab.orig > ${rootmnt}/etc/fstab
# awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab >> ${rootmnt}/etc/fstab
# Already there?
if [ -e ${rootmnt}/etc/fstab ] && grep -qE ''^overlay[[:space:]]+/[[:space:]]+overlay'' ${rootmnt}/etc/fstab; then
    exit 0 # Do nothing
fi

FSTAB=$(awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab && awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab)
cat>${rootmnt}/etc/fstab<<EO_FSTAB
$FSTAB
EO_FSTAB

exit 0
EOF

chmod 755 /usr/share/initramfs-tools/hooks/overlay
chmod 755 /etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay

echo "end install overlay_rootfs"
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0 ipv6.disable=1\"/g" /etc/default/grub
update-initramfs -c -k $(uname -r)
grub-mkconfig -o /boot/grub/grub.cfg

[ -r "motd.sh" ] && {
    cat motd.sh >/etc/update-motd.d/11-motd
    touch /etc/logo.txt
    chmod 755 /etc/update-motd.d/11-motd
}

echo "Add SSH public key"
[ ! -d /root/.ssh ] && mkdir -m0700 /root/.ssh
cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
chmod 0600 /root/.ssh/authorized_keys

echo "use tcp dns query"
cat <<EOF
single-request-reopen (glibc>=2.9) 发送 A 类型请求和 AAAA 类型请求使用不同的源端口。
single-request (glibc>=2.10) 避免并发，改为串行发送 A 类型和 AAAA 类型请求，没有了并发，从而也避免了冲突。
echo 'options use-vc' >> /etc/resolv.conf
EOF

echo "install packages!"
apt -y install bzip2 pigz p7zip-full arj zip mscompress unar eject bc less vim ftp telnet nmap tftp ntpdate screen lsof strace
apt -y install man-db manpages tcpdump ethtool aria2 axel curl mpg123 nmon sysstat arping dnsutils minicom socat git git-flow net-tools
apt -y install nscd nbd-client iftop

id root &>/dev/null && { usermod -p "$(echo ${PASSWORD} | openssl passwd -1 -stdin)" root; }
id johnyin &>/dev/null && {usermod -p "$(echo ${PASSWORD} | openssl passwd -1 -stdin)" johnyin; }
# echo "root:${PASSWORD}" |chpasswd 
echo "Force Users To Change Passwords Upon First Login"
chage -d 0 root || true
chage -d 0 johnyin || true

apt clean
find /var/log/ -type f | xargs rm -f
rm -rf /var/cache/apt/* /var/lib/apt/lists/* /root/.bash_history /root/.viminfo /root/.vim/

exit 0
