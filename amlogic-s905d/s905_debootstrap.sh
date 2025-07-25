#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("c9c3ae29[2025-07-01T07:05:14+08:00]:s905_debootstrap.sh")
################################################################################
source ${DIRNAME}/os_debian_init.sh
cat <<EOF
DEBIAN_VERSION=trixie ./s905_debootstrap.sh wireguard-tools v4l-utils triggerhappy sshfs python3-pip python3-venv nmon iptables dbus-x11 cec-utils build-essential bluez bluez-tools ldap-utils gnupg apt-transport-https rng-tools-debian mesa-utils unzip xxd qemu-utils mame bind9-dnsutils polkitd-pkla python3-dev usbutils
EOF
log() { echo "$(tput setaf 141)######$*$(tput sgr0)" >&2; }
export -f log

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

BOOT_LABEL="EMMCBOOT"
ROOT_LABEL="EMMCROOT"
FS_TYPE=${FS_TYPE:-ext4}

old_ifs="$IFS" IFS=','
custom_pkgs="$*"
IFS=$old_ifs

PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools,u-boot-tools,fake-hwclock,openssh-server,busybox"
PKG+=",udev,isc-dhcp-client,netbase,console-setup,net-tools,wpasupplicant,hostapd,iputils-ping,telnet,vim,ethtool,dosfstools,iw,ipset,nmap,ipvsadm,bridge-utils,batctl,babeld,ifenslave,vlan"
PKG+=",parprouted,dhcp-helper,nbd-client,iftop,pigz,nfs-common,nfs-kernel-server,netcat-openbsd"
PKG+=",ksmbd-tools,procps"
PKG+=",systemd-container,nftables,systemd-timesyncd,zstd"
# wireless-tools,
PKG+=",cron,logrotate,bsdmainutils,openssh-client,wget,ntpdate,less,file,lsof,strace,rsync"
PKG+=",xz-utils,zip,udisks2"
PKG+=",alsa-utils,mpg123"
PKG+=",e2fsprogs,jfsutils,xfsprogs,adb,bpftool,device-tree-compiler,edid-decode,fastboot,gdisk,geoip-database,pulseaudio-module-bluetooth,usbip,usbredirect,v2ray,xvkbd,psmisc,openvpn,fdisk,usbutils"
# # tools
PKG+=",sudo,aria2,axel,curl,eject,rename,bc,socat,tmux,xmlstarlet,jq,traceroute,ipcalc,ncal,qrencode,tcpdump"
# fw_printenv/fw_setenv
PKG+=",libubootenv-tool"
# # for minidlna
PKG+=",minidlna,wireguard-tools,"
PKG+=",dnsmasq,triggerhappy,aosd-cat"
# # for xdotool, wmctrl
# PKG+=",xdotool,wmctrl,playerctl"
# xfce/lxde, DEBIAN_VERSION=bookworm use lxde
PKG+=",smplayer,smplayer-l10n"
PKG+=",lightdm,xserver-xorg-core,xinit,xserver-xorg-video-fbdev,xserver-xorg-input-all,x11-utils,x11-xserver-utils"
PKG+=",fonts-noto-cjk"
#PKG+=",fonts-droid-fallback"
PKG+=",pulseaudio,pulseaudio-utils,ffmpeg,bluetooth"
# ,pipewire,pipewire-audio-client-libraries"
log "lxde use ibus input for chinese"
case "${DEBIAN_VERSION:-bullseye}" in
    trixie | bookworm) PKG+=",lxde-core,lxterminal,lxrandr,openbox-lxde-session" ;;
    *)        PKG+=",xfce4,xfce4-terminal,pavucontrol" ;;
esac
PKG+=",policykit-1,x11vnc,wpan-tools"
PKG+=",polkitd" # for trixie
# # finally add custom packages
PKG+="${custom_pkgs:+,${custom_pkgs}}"

[ "$(id -u)" -eq 0 ] || {
    log "Must be root to run this script."
    exit 1
}

CACHE_DIR=${DIRNAME}/cache-${DEBIAN_VERSION:-bullseye}
ROOT_DIR=${DIRNAME}/rootfs-${DEBIAN_VERSION:-bullseye}
mkdir -p ${ROOT_DIR}
mkdir -p ${CACHE_DIR}

#HOSTNAME="s905d3"
#HOSTNAME="usbpc"
DEBIAN_VERSION=${DEBIAN_VERSION:-bullseye} \
    INST_ARCH=arm64 \
    REPO=${REPO:-http://mirrors.aliyun.com/debian} \
    HOSTNAME="s905d2" \
    NAME_SERVER=114.114.114.114 \
    PASSWORD=password \
    debian_build "${ROOT_DIR}" "${CACHE_DIR}"
    #debian_build "${ROOT_DIR}" "${CACHE_DIR}" "${PKG}"

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOT_DIR} /bin/bash -x <<EOSHELL
    /bin/mkdir -p /dev/pts && /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts || true
    /bin/mknod -m 666 /dev/null c 1 3 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt update
    DEBIAN_FRONTEND=noninteractive apt -y --no-install-recommends install ca-certificates
    DEBIAN_FRONTEND=noninteractive apt -y --no-install-recommends upgrade
    DEBIAN_FRONTEND=noninteractive apt -y remove wireless-regdb crda --purge  2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt -y autoremove --purge || true
    while read -d ',' pkg; do
        log "INSTALL \${pkg}"
        DEBIAN_FRONTEND=noninteractive apt -y --no-install-recommends install \${pkg} || true
    done <<< "${PKG}"

    log "Enable rootfs module(if not buildin)"
    mkdir -p /etc/initramfs-tools
    grep -q "ext4" /etc/modules 2>/dev/null || echo "ext4" >> /etc/initramfs-tools/modules
    grep -q "ext4" /etc/modules 2>/dev/null || echo "ext4" >> /etc/modules

    # log "Enable CPU FREQ"
    # grep -q "scpi-cpufreq" /etc/modules 2>/dev/null || echo "scpi-cpufreq" >> /etc/modules

    log "Enable Kernel TLS"
    grep -q "tls" /etc/modules 2>/dev/null || echo "tls" >> /etc/modules

    # cat << EOF > /etc/modprobe.d/brcmfmac.conf
    # options brcmfmac p2pon=1
    # EOF
    # if start p2p device so can not start ap & sta same time
    #漫游
    # cat << EOF > /etc/modprobe.d/brcmfmac.conf
    # options brcmfmac roamoff=1
    # EOF

    #log "修改systemd journald日志存放目录为内存，也就是/run/log目录，限制最大使用内存空间64MB"

    #sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
    #sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=64M/' /etc/systemd/journald.conf
    #sed -i "s/#Compress=.*/Compress=yes/g" /etc/systemd/journald.conf
    #sed -i "s/#RateLimitIntervalSec=.*/RateLimitIntervalSec=30s/g" /etc/systemd/journald.conf
    #sed -i "s/#RateLimitBurst=.*/RateLimitBurst=10000/g" /etc/systemd/journald.conf

    systemctl mask systemd-machine-id-commit.service

    log "add lima xorg.conf"
    mkdir -p /etc/X11/xorg.conf.d/ /etc/johnyin/display
    ln -s /etc/johnyin/display/20-lima.conf /etc/X11/xorg.conf.d/20-lima.conf
    log "avoid 'page flip error' in Xorg.0.log"
    cat <<EOF > /etc/johnyin/display/20-lima.conf
Section "Device"
    Identifier "Default Device"
    Driver "modesetting"
    Option "AccelMethod" "glamor"  ### "glamor" to enable 3D acceleration, "none" to disable.
    Option "SWcursor" "on"
    Option "PageFlip" "off"
    Option "ShadowFB" "true"
    Option "DoubleShadow" "true"
    # Option "DRI" "2"
    # Option "Dri2Vsync" "true"
    # Option "TripleBuffer" "true"
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

    log "rm hwclock data file"
    rm -f /etc/fake-hwclock.data || true

    useradd -m -s /bin/bash johnyin
    log "disable dpms auto off screen"
    # echo "DISPLAY=:0 xset -dpms" > /home/johnyin/.xsessionrc
    # echo "DISPLAY=:0 xset s off" >> /home/johnyin/.xsessionrc
    # chown johnyin:johnyin /home/johnyin/.xsessionrc
    ln -s /home/johnyin/.Xauthority /root/.Xauthority
    echo "%johnyin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/johnyin
    mkdir -p /etc/sudoers.d/johnyin && chmod 0440 /etc/sudoers.d/johnyin
    sed -i "s/^\(.*requiretty\)$/#\1/" /etc/sudoers
    log "auto login lightdm"
    sed -i "s/#autologin-user=.*/autologin-user=johnyin/g" /etc/lightdm/lightdm.conf
    log "enable lightdm allow xserver tcp"
    sed -i "s/#xserver-allow-tcp=.*/xserver-allow-tcp=true/g" /etc/lightdm/lightdm.conf
    log "auto mount RO options"
    echo "[defaults]" > /etc/udisks2/mount_options.conf || true
    echo "defaults=ro" >> /etc/udisks2/mount_options.conf || true

    gpasswd -a johnyin pulse
    gpasswd -a johnyin lp
    gpasswd -a pulse lp
    gpasswd -a johnyin audio
    gpasswd -a pulse audio

    debian_bash_init johnyin
    # timedatectl set-local-rtc 0
    log "Force Users To Change Passwords Upon First Login"
    chage -d 0 root || true
    /bin/umount /dev/pts

    debian_locale_init
    debian_sysctl_init
    debian_zswap_init 512
    debian_sshd_init
    debian_vim_init
    debain_overlay_init
EOSHELL

log "modify networking waitonline tiemout to 5s"
sed -i "s|TimeoutStartSec=.*|TimeoutStartSec=5sec|g" ${ROOT_DIR}/lib/systemd/system/networking.service

cat <<'EOF' > ${ROOT_DIR}/etc/profile.d/overlay.sh
export PROMPT_COMMAND='export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$([[ -r "/overlay/reformatoverlay" ]] && echo "[reboot factory]")$"'
EOF
chmod 644 ${ROOT_DIR}/etc/profile.d/overlay.sh

cat > ${ROOT_DIR}/etc/fstab << EOF
LABEL=${ROOT_LABEL}    /    ${FS_TYPE}    defaults,errors=remount-ro,noatime    0    0
LABEL=${BOOT_LABEL}    /boot    vfat    ro    0    0
# LABEL=EMMCSWAP    none     swap    sw,pri=-1    0    0
tmpfs /var/log  tmpfs   defaults,noatime,nosuid,nodev,noexec,size=16M  0  0
tmpfs /run      tmpfs   rw,nosuid,noexec,relatime,mode=755  0  0
tmpfs /tmp      tmpfs   rw,nosuid,relatime,mode=777  0  0
# overlayfs can not nfs exports, so use tmpfs
tmpfs /media    tmpfs   defaults,size=1M  0  0
tmpfs /home/johnyin/.cache  tmpfs mode=0700,noatime,nosuid,nodev,gid=johnyin,uid=johnyin   0  0
tmpfs /root/.cache          tmpfs mode=0700,noatime,nosuid,nodev,gid=root,uid=root  0  0
# /src /dst none defaults,bind 0 0
EOF

log "auto reformatoverlay plug usb ttl"
cat > ${ROOT_DIR}/etc/udev/rules.d/99-reformatoverlay.rules << EOF
SUBSYSTEM=="tty", ACTION=="add", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="/bin/sh -c 'touch /overlay/reformatoverlay; echo heartbeat > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
SUBSYSTEM=="tty", ACTION=="remove", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="/bin/sh -c 'rm /overlay/reformatoverlay; echo none > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
EOF

log "HDMI Auto plugin"
cat > ${ROOT_DIR}/etc/johnyin/display/97-hdmiplugin.rules << EOF
SUBSYSTEM=="drm", ACTION=="change", RUN+="/usr/bin/systemd-run --uid=johnyin -E DISPLAY=:0 /etc/johnyin/display/custom_display.sh"
EOF
ln -s /etc/johnyin/display/97-hdmiplugin.rules ${ROOT_DIR}/etc/udev/rules.d/97-hdmiplugin.rules

cat > ${ROOT_DIR}/etc/johnyin/display/custom_display.sh << 'EOF'
#!/usr/bin/env sh
{
    xset -dpms s off
    xset q
    xrandr --verbose --output HDMI-1 --mode 1280x800
} 2>/dev/null | logger -i -t custom_display
EOF
chmod 755 ${ROOT_DIR}/etc/johnyin/display/custom_display.sh
cat > ${ROOT_DIR}/etc/johnyin/display/johnyin-init.desktop<<EOF
[Desktop Entry]
Version=1.0
Name=my init here
Comment=replace ~/.xsessionrc
Exec=/etc/johnyin/display/custom_display.sh
Terminal=false
Type=Application
X-GNOME-Autostart-Phase=Initialization
X-GNOME-HiddenUnderSystemd=true
X-KDE-autostart-phase=1
EOF
ln -s /etc/johnyin/display/johnyin-init.desktop ${ROOT_DIR}/etc/xdg/autostart/johnyin-init.desktop

# cat > ${ROOT_DIR}/usr/lib/systemd/system/hdmi.service <<'EOF'
# [Unit]
# Description=auto hdmi plugin
# [Service]
# RemainAfterExit=true
# User=johnyin
# Group=johnyin
# ExecStart=/bin/env -i DISPLAY=:0 XAUTHORITY=/home/johnyin/.Xauthority /usr/bin/xrandr --verbose --output HDMI-1 --auto
# ExecStop=/bin/env -i DISPLAY=:0 XAUTHORITY=/home/johnyin/.Xauthority /usr/bin/xrandr --verbose --output HDMI-1 --off
# EOF

log "enable ttyAML0 login"
sed -i "/^ttyAML0/d" ${ROOT_DIR}/etc/securetty 2>/dev/null || true
echo "ttyAML0" >> ${ROOT_DIR}/etc/securetty

log "export nfs"
# no_root_squash(enable root access nfs)
cat > ${ROOT_DIR}/etc/exports << EOF
/media/       192.168.168.0/24(ro,sync,no_subtree_check,crossmnt,nohide,no_root_squash,no_all_squash,fsid=0)
EOF

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
    address 192.168.168.2/24

# post-up ip rule add from 192.168.168.0/24 table out.168
# post-up ip rule add to 192.168.168.0/24 table out.168
# post-up ip route add default via 192.168.168.1 dev br-ext table out.168
# post-up ip route add 192.168.168.0/24 dev br-ext src 192.168.168.2 table out.168
EOF
log "for minidlna"
sed -i "/User=minidlna/d" ${ROOT_DIR}/lib/systemd/system/minidlna.service || true
sed -i "/Group=minidlna/d" ${ROOT_DIR}/lib/systemd/system/minidlna.service || true
sed -i "/DAEMON_OPTS=/d" ${ROOT_DIR}/etc/default/minidlna
echo 'DAEMON_OPTS="-L"' >> ${ROOT_DIR}/etc/default/minidlna

cat << EOF > ${ROOT_DIR}/etc/minidlna.conf
media_dir=V,/media
# Set this to merge all media_dir base contents into the root container
# (The default is no.)
#merge_media_dirs=no
db_dir=/var/cache/minidlna
log_dir=/var/log/minidlna
#log_level=general,artwork,database,inotify,scanner,metadata,http,ssdp,tivo=warn
network_interface=wlan0,br-int
port=8200
# URL presented to clients (e.g. http://example.com:80).
#presentation_url=/
friendly_name=s905d
root_container=B
# Automatic discovery of new files in the media_dir directory.
inotify=no
notify_interval=86400
strict_dlna=no
#max_connections=50
# set this to yes to allow symlinks that point outside user-defined media_dirs.
wide_links=no
EOF
cat << "EOF" > ${ROOT_DIR}/etc/network/interfaces.d/wifi
# auto wlan0
allow-hotplug wlan0

mapping wlan0
    script /etc/johnyin/wifi_mode.sh
    map work
    map home
    map adhoc
    map ap
    map ap5g
    map ap0
    map initmode

iface ap0 inet manual
    hostapd /run/hostapd.ap0.conf
    # INTERFACE BRIDGE SSID PASSPHRASE IS_5G HIDDEN_SSID
    pre-up (/etc/johnyin/gen_hostapd.sh ap0 br-int "$(cat /etc/hostname)" "Admin@123" 1 1 || true)
    pre-up (/usr/sbin/iw phy `/usr/bin/ls /sys/class/ieee80211/` interface add ap0 type __ap)
    # # start nft rules by nftables.service, rm -f /etc/nftables.conf && ln -s /etc/johnyin/ap.ruleset /etc/nftables.conf
    # post-up (/usr/sbin/iptables-restore < /etc/iptables.rules || true)
    # post-up (/etc/johnyin/ap.ruleset || true)
    pre-up (/etc/johnyin/gen_dnsmasq.sh br-int || true)
    post-up (/usr/bin/systemd-run --unit dnsmasq-ap0 -p Restart=always /usr/sbin/dnsmasq --no-daemon --conf-file=/run/dnsmasq.conf || true)
    pre-down (/usr/bin/systemctl stop dnsmasq-ap0.service || true)
    pre-down (/usr/bin/kill -9 $(cat /run/hostapd.ap0.pid) || true)
    post-down (/usr/sbin/iw dev ap0 del || true)

iface ap inet manual
    hostapd /run/hostapd.wlan0.conf
    pre-up (/etc/johnyin/gen_hostapd.sh wlan0 br-int "$(cat /etc/hostname)" "Admin@123" 0 1 || true)
    # # start nft rules by nftables.service, rm -f /etc/nftables.conf && ln -s /etc/johnyin/ap.ruleset /etc/nftables.conf
    # post-up (/usr/sbin/iptables-restore < /etc/iptables.rules || true)
    # post-up (/etc/johnyin/ap.ruleset || true)
    pre-up (/etc/johnyin/gen_udhcpd.sh br-int || true)
    pre-up (/usr/bin/touch /var/run/udhcpd.leases || true)
    post-up (/usr/bin/systemd-run --unit udhcpd-ap -p Restart=always /usr/bin/busybox udhcpd -f /run/udhcpd.conf || true)
    pre-down (/usr/bin/systemctl stop udhcpd-ap.service || true)
    pre-down (/usr/bin/kill -9 $(cat /run/hostapd.wlan0.pid) || true)

iface ap5g inet manual
    hostapd /run/hostapd.wlan0.conf
    pre-up (/etc/johnyin/gen_hostapd.sh wlan0 br-int "$(cat /etc/hostname)" "Admin@123" 1 1 || true)
    # # start nft rules by nftables.service, rm -f /etc/nftables.conf && ln -s /etc/johnyin/ap.ruleset /etc/nftables.conf
    # post-up (/usr/sbin/iptables-restore < /etc/iptables.rules || true)
    # post-up (/etc/johnyin/ap.ruleset || true)
    pre-up (/etc/johnyin/gen_udhcpd.sh br-int || true)
    pre-up (/usr/bin/touch /var/run/udhcpd.leases || true)
    post-up (/usr/bin/systemd-run --unit udhcpd-ap5g -p Restart=always /usr/bin/busybox udhcpd -f /run/udhcpd.conf || true)
    pre-down (/usr/bin/systemctl stop udhcpd-ap5g.service || true)
    pre-down (/usr/bin/kill -9 $(cat /run/hostapd.wlan0.pid) || true)

iface work inet dhcp
    wpa_iface wlan0
    wpa_conf /etc/johnyin/work.conf
    post-up (/usr/sbin/ifup ap0 || true)
    pre-down (/usr/sbin/ifdown ap0 || true)

iface home inet static
    wpa_iface wlan0
    wpa_conf /etc/johnyin/home.conf
    address 192.168.31.194/24
    gateway 192.168.31.1
    # post-up (/usr/sbin/ifup ap0 || true)
    # pre-down (/usr/sbin/ifdown ap0 || true)

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

cat << EOF > ${ROOT_DIR}/etc/network/interfaces.d/br-int
auto br-int
iface br-int inet static
    bridge_ports none
    bridge_maxwait 0
    address 192.168.31.1/24
EOF

cat << EOF > ${ROOT_DIR}/etc/network/interfaces.d/pppoe
# auto myadsl
# iface myadsl inet ppp
#     pre-up /sbin/ip link set dev eth0 up
#     provider myadsl
#

# # apt -y install ppp
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

mkdir -p ${ROOT_DIR}/etc/johnyin
cat << 'EO_DOC' > ${ROOT_DIR}/etc/johnyin/ap.ruleset
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip saddr 192.168.168.0/24 ip daddr != 192.168.168.0/24 counter masquerade
        ip saddr 192.168.167.0/24 ip daddr != 192.168.167.0/24 counter masquerade
        ip saddr 192.168.31.0/24 ip daddr != 192.168.31.0/24 counter masquerade
    }
}
table ip filter {
    chain forward {
        type filter hook forward priority 0; policy accept;
        meta l4proto tcp tcp flags & (syn|rst) == syn counter tcp option maxseg size set rt mtu
    }
}
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# nft add element inet myblackhole blacklist '{ 192.168.168.2 }'
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
define BLACK_LIST = { }
table inet myblackhole {
    set blacklist {
        type ipv4_addr
        # flags interval
        flags dynamic,timeout
        timeout 5m
        elements = { $BLACK_LIST }
    }
    chain input {
        type filter hook input priority 0; policy accept;
        # # accept traffic originating from us
        ct state established,related accept
        # # Drop all incoming connections in blacklist, reject fast application response than drop
        ip saddr @blacklist counter reject
    }
}
EO_DOC
chmod 755 ${ROOT_DIR}/etc/johnyin/ap.ruleset

mkdir -p ${ROOT_DIR}/etc/dnsmasq
cat << "EO_DOC" > ${ROOT_DIR}/etc/dnsmasq/adblock.inc
address=/ad.youku.com/127.0.0.1
address=/013572.cn/
EO_DOC

cat << 'EO_DOC' > ${ROOT_DIR}/etc/johnyin/gen_dnsmasq.sh
#!/bin/sh
set -e
export LANG=C

if [ `id -u` -ne 0 ]; then exit 1; fi

INTERFACE=${1:-wlan0}
eval `/usr/sbin/ifquery ${INTERFACE} 2>/dev/null | /usr/bin/awk '/address:/{ print "ADDRESS="$2} /netmask:/{ print "MASK="$2}'`
ADDRESS=${ADDRESS:-192.168.31.1}
MASK=${MASK:-255.255.255.0}

cat > /run/dnsmasq.conf <<EOF
# # /usr/bin/systemd-run --unit dnsmasq-ap5g -p Restart=always dnsmasq --no-daemon --conf-file=/etc/dnsmasq/dnsmasq.conf
# # /usr/bin/systemctl stop dnsmasq-ap5g.service
####dhcp
# # Bind to only one interface, Repeat the line for more than one interface.
interface=${INTERFACE}
# except-interface=lo
# # disable DHCP and TFTP on interface
# no-dhcp-interface=
# listen-address=

dhcp-range=${ADDRESS%.*}.100,${ADDRESS%.*}.150,${MASK},12h
# # gateway
dhcp-option=option:router,${ADDRESS}
# # dns server
dhcp-option=6,${ADDRESS}
# # ntp server
# dhcp-option=option:ntp-server,192.168.0.4,10.10.0.5
# dhcp-host=11:22:33:44:55:66,192.168.0.60
strict-order
expand-hosts
filterwin2k
dhcp-authoritative
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
####dns
bind-interfaces
cache-size=10000
resolv-file=/etc/resolv.conf
# # read another file, as well as /etc/hosts
addn-hosts=/etc/hosts
# # Add other name servers here, with domain specs
server=/cn/114.114.114.114
server=/google.com/223.5.5.5
# # 屏蔽网页广告
conf-file=/etc/dnsmasq/adblock.inc
# # Include all files in a directory which end in .conf
#conf-dir=/etc/dnsmasq.d/,*.conf
# # 劫持所有域名
# address=/#/10.0.3.1
# # pxe tftp
# enable-tftp
# tftp-root=/tftpboot
# pxe-service=0,"Phicomm N1 Boot"
####log
log-queries
log-dhcp
# log-facility=/var/log/dnsmasq.log
EOF
EO_DOC
chmod 755 ${ROOT_DIR}/etc/johnyin/gen_dnsmasq.sh

cat << 'EO_DOC' > ${ROOT_DIR}/etc/johnyin/gen_udhcpd.sh
#!/bin/sh
set -e
export LANG=C

if [ `id -u` -ne 0 ]; then exit 1; fi

INTERFACE=${1:-wlan0}
eval `/usr/sbin/ifquery ${INTERFACE} 2>/dev/null | /usr/bin/awk '/address:/{ print "ADDRESS="$2} /netmask:/{ print "MASK="$2}'`
ADDRESS=${ADDRESS:-192.168.31.1}
MASK=${MASK:-255.255.255.0}

cat > /run/udhcpd.conf <<EOF
interface       ${INTERFACE}
start           ${ADDRESS%.*}.100
end             ${ADDRESS%.*}.150
option  subnet  ${MASK}
opt     router  ${ADDRESS}
opt     dns     114.114.114.114
max_leases      45

# The time period at which udhcpd will write out a dhcpd.leases
auto_time       10
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
chmod 755 ${ROOT_DIR}/etc/johnyin/gen_udhcpd.sh

cat << 'EO_DOC' > ${ROOT_DIR}/etc/johnyin/gen_hostapd.sh
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

wmm_enabled=1
# QoS support
#obss_interval=300
ieee80211n=1
require_ht=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]
ieee80211ac=1
# 802.11ac support
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
chmod 755 ${ROOT_DIR}/etc/johnyin/gen_hostapd.sh

cat << 'EO_DOC' > ${ROOT_DIR}/etc/johnyin/wifi_mode.sh
#!/bin/sh
set -e
export LANG=C
MODE_CONF=/etc/wifi_mode.conf
if [ `id -u` -ne 0 ] || [ "$1" = "" ]; then exit 1; fi
#no config wifi_mode.conf default use "initmode"
[ -r "${MODE_CONF}" ] || {
    cat >"${MODE_CONF}" <<-EOF
# |----------+-----------------------------------------------|
# | station  | desc                                          |
# |----------+-----------------------------------------------|
# | work     | station /etc/johnyin/work.conf                |
# | home     | station /etc/johnyin/home.conf                |
# | ap0      | 5G on ap0(virtual device)                     |
# | ap       | 2.4G on wlan0                                 |
# | ap5g     | 5G on wlan0                                   |
# | adhoc    | adhoc create adhoc mesh network and bridge it |
# | initmode | initmode no dhcpd no secret ap 192.168.1.1/24 |
# |----------+-----------------------------------------------|
station=initmode
EOF
}
. ${MODE_CONF}
case "$1" in
    wlan0)
        /usr/sbin/iw ${2} set power_save off >/dev/null 2>&1 || true
        echo ${station:-initmode}
        ;;
esac
exit 0
EO_DOC
chmod 755 ${ROOT_DIR}/etc/johnyin/wifi_mode.sh

cat << EO_DOC > ${ROOT_DIR}/etc/johnyin/adhoc.conf
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
cat << EO_DOC > ${ROOT_DIR}/etc/johnyin/home.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1
#ap_scan=1

network={
    id_str="home"
    priority=100
    scan_ssid=1
    ssid="johnap5g"
    #key_mgmt=wpa-psk
    psk="password"
    #disabled=1
}
EO_DOC
cat << EO_DOC > ${ROOT_DIR}/etc/johnyin/initmode.conf
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
cat << EO_DOC > ${ROOT_DIR}/etc/johnyin/p2p.conf
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
cat << EO_DOC > ${ROOT_DIR}/etc/johnyin/work.conf
#mulit ap support!
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#ap_scan=1
scan_cur_freq=1
#Whether to scan only the current frequency
# 0:  Scan all available frequencies. (Default)
# 1:  Scan current operating frequency if another VIF on the same radio is already associated.
# network={
#     id_str="work"
#     priority=100
#     scan_ssid=1
#     ssid="xk-admin"
#     #key_mgmt=wpa-psk
#     psk="ADMIN@123"
# }
# network={
#     scan_ssid=1
#     ssid="HUAZHU-Hanting"
#     key_mgmt=NONE
#     # curl -vvv www.baidu.com
#     # webbrowser-> http:/xxxxx
#     # auto wlan0
#     # allow-hotplug wlan0
#     # iface wlan0 inet dhcp
#     #      wpa_iface wlan0
#     #      wpa_conf /etc/s905.conf
# }

network={
    id_str="work"
    priority=90
    scan_ssid=1
    ssid="CNAP"
    key_mgmt=WPA-EAP
    eap=PEAP
    phase1="peaplabel=auto tls_disable_tlsv1_0=0 tls_disable_tlsv1_1=0 tls_disable_tlsv1_2=0 tls_ext_cert_check=0"
    phase2="auth=MSCHAPV2"
    identity="username"
    password="passowrd"
    eapol_flags=0
}
EO_DOC

log "enable fw_printenv command, bullseye u-boot-tools remove fw_printenv, so need copy!"
cat >${ROOT_DIR}/etc/fw_env.config <<EOF
# Device to access      offset          env size
/dev/mmcblk1            0x27400000      0x10000
EOF

# only amlogic uboot need this
# mkdir -p ${ROOT_DIR}/etc/initramfs/post-update.d/
# cat>${ROOT_DIR}/etc/initramfs/post-update.d/99-uboot<<"EOF"
# #!/bin/sh
# echo "update-initramfs: Converting to u-boot format" >&2
# tempname="/boot/uInitrd-$1"
# mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd -d $2 $tempname > /dev/null
# exit 0
# EOF
# chmod 755 ${ROOT_DIR}/etc/initramfs/post-update.d/99-uboot

cat <<EOF>${ROOT_DIR}/etc/motd
## ${VERSION[@]}
1. edit /etc/wifi_mode.conf for wifi mode modify
2. touch /overlay/reformatoverlay for factory mode after next reboot
3. fw_printenv / fw_setenv for get or set fw env
    fw_setenv bootdelay 0  #disable reboot delay hit key, bootdelay=1 enable it
4. dumpleases dump dhcp clients
    alias dumpleases='[ -f /var/lib/misc/dnsmasq.leases ] && cat /var/lib/misc/dnsmasq.leases || busybox dumpleases -f /var/run/udhcpd.leases'
5. overlayroot-chroot can chroot overlay lower fs(rw)
6. set eth0 mac address:
    fw_setenv ethaddr 5a:57:57:90:5d:01
7. set wifi0 mac address:
    sed "s/macaddr=.*/macaddr=b8:be:ef:90:5d:02/g" /lib/firmware/brcm/brcmfmac43455-sdio.txt
8. iw dev wlan0 station dump -v
9. start nfs-server: systemctl start nfs-server.service nfs-kernel-server.service
10.start vncserver: x11vnc -display :0
11.set lxde mouse cursor size: sed -i 's|.*CursorThemeSize.*|iGtk/CursorThemeSize=32|g' /etc/xdg/lxsession/LXDE/desktop.conf
12./boot/dtb/ dtb for different USB MODE, need reboot
13 start ksmbd server: systemctl enable ksmbd.service --now
                       ksmbd.adduser --add-user=user1 --password=<pass> -v
14.bluetooth head unit:
    LC_ALL=c pactl list cards === > ( Name:bluez_card.EC_FA_5C_5F_1A_AC , Profiles: handsfree_head_unit)
    pactl set-card-profile <Name> <Profile>
15.wg-quick up client/work
16.rm -rf /var/cache/minidlna/ && systemctl restart minidlna
17./etc/systemd/journald.conf
    Storage=persistent|volatile # /var/log/journal | /run/log/journal
    journalctl --rotate # rotate log"
    journalctl --vacuum-time=1s # clear log 1s ago"
EOF

cat <<'EOF'> ${ROOT_DIR}/usr/bin/overlayroot-chroot
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
chmod 755 ${ROOT_DIR}/usr/bin/overlayroot-chroot

log "add emmc_install script"

cat > ${ROOT_DIR}/root/fix_sound_out_hdmi.sh <<'EOF'
amixer -c P230Q200 sset 'AIU HDMI CTRL SRC' 'I2S'
# /var/lib/alsa/asound.state
aplay /usr/share/sounds/alsa/Noise.wav
amixer sset PCM,0 100%
speaker-test -c2 -t wav
# # su - johnyin (add to ~/.xsessionrc)
# DISPLAY=:0 xset -q
# DISPLAY=:0 xset -dpms
# DISPLAY=:0 xset s off
# DISPLAY=:0 xset dpms 0 0 0
# DISPLAY=:0 xrandr -q
# DISPLAY=:0 xrandr --output HDMI-1 --mode 1280x1024
#
# # out put bluetooth 头戴式耳机单元
LC_ALL=c pactl list cards   === > ( Name:bluez_card.EC_FA_5C_5F_1A_AC   Profiles: handsfree_head_unit)
pactl set-card-profile bluez_card.EC_FA_5C_5F_1A_AC handsfree_head_unit

# # output soundcard
# pactl set-card-profile 0 output:analog-stereo
export PULSE_SERVER="unix:/run/user/1000/pulse/native"
sudo -u johnyin pactl --server $PULSE_SERVER set-card-profile 0 output:hdmi-stereo+input:analog-stereo

cat <<EODOC > /etc/pulse/default.pa.d/hdmi_sound.pa
# pacmd list-sinks|egrep -i 'index:|name:'
### Enable all of my audio output devices
# HDMI
set-card-profile alsa_card.pci-0000_20_00.1 output:hdmi-stereo-extra3
# Line out
set-card-profile alsa_card.pci-0000_22_00.3 output:analog-stereo+input:analog-stereo
EODOC
EOF
cat > ${ROOT_DIR}/root/emmc_linux.sh <<'EOF'
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
parted -s "${DEV_EMMC}" mkpart primary ext4 684MiB 4GiB
parted -s "${DEV_EMMC}" mkpart primary ext4 4GiB 100%

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
mkfs -t ext4 -F -m 0 -q -L ${ROOT_LABEL} ${PART_ROOT}
mke2fs -FL ${OVERLAY_LABEL} -t ext4 -E lazy_itable_init,lazy_journal_init ${PART_OVERLAY}

echo "NEED MOUNT ${PART_BOOT}, and full fill zero file."
echo "Flush changes (in case they were cached.)."
sync
echo "reflush env&logo, mkfs crash it!!!!"
dd if=/tmp/env-bak of=${DEV_EMMC} bs=1024 count=8192 seek=643072
dd if=/tmp/logo-bak of=${DEV_EMMC} bs=1024 count=32768 seek=659456
EOF

# autologin-guest=false
# autologin-user=user(not root)
# autologin-user-timeout=0
# groupadd -r autologin
# gpasswd -a root autologin
log "SUCCESS build rootfs, all!!!"

log "start install you kernel&patchs"
if [ -d "${DIRNAME}/kernel" ]; then
    rsync -avzP --numeric-ids ${DIRNAME}/kernel/* ${ROOT_DIR}/ || true
    # kerver=$(ls ${ROOT_DIR}/usr/lib/modules/ | sort --version-sort -f | tail -n1)
    kerver=$(menu_select "kernel: " $(ls ${ROOT_DIR}/usr/lib/modules/ 2>/dev/null))
    dtb=$(menu_select "dtb: " $(ls ${ROOT_DIR}/boot/dtb/ 2>/dev/null))
    log "USE KERNEL ${kerver} ------>"
    cat > ${ROOT_DIR}/boot/aml_autoscript.cmd <<'EOF'
setenv bootcmd "run start_autoscript; run storeboot;"
setenv start_autoscript "if usb start; then run start_usb_autoscript; fi; if mmcinfo; then run start_mmc_autoscript; fi; run start_mmc_autoscript;"
setenv start_mmc_autoscript "if fatload mmc 0 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload mmc 1 1020000 s905_autoscript; then autoscr 1020000; fi;"
setenv start_usb_autoscript "if fatload usb 0 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 1 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 2 1020000 s905_autoscript; then autoscr 1020000; fi; if fatload usb 3 1020000 s905_autoscript; then autoscr 1020000; fi;"
setenv upgrade_step "0"
saveenv
sleep 1
reboot
EOF
    cat > ${ROOT_DIR}/boot/s905_autoscript.nfs.cmd <<'EOF'
setenv kernel_addr  "0x11000000"
setenv initrd_addr  "0x13000000"
setenv dtb_mem_addr "0x1000000"
setenv serverip 172.16.16.2
setenv ipaddr 172.16.16.168
setenv bootargs "root=/dev/nfs nfsroot=${serverip}:/nfsshare/root rw net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 rootwait"
setenv bootcmd_pxe "tftp ${kernel_addr} zImage; tftp ${initrd_addr} uInitrd; tftp ${dtb_mem_addr} dtb.img; booti ${kernel_addr} ${initrd_addr} ${dtb_mem_addr}"
run bootcmd_pxe
EOF
   cat > ${ROOT_DIR}/boot/s905_autoscript.cmd <<'EOF'
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
    echo "bootargs:  earlyprintk loglevel=9"
    cat > ${ROOT_DIR}/boot/uEnv.ini <<EOF
image=vmlinuz-${kerver}
initrd=uInitrd-${kerver}
dtb=/dtb/${dtb}
bootargs=root=LABEL=${ROOT_LABEL} rootflags=data=writeback fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 video=1280x1024@60me
# # cat /proc/tty/driver/meson_uart
# earlyprintk=aml-uart,0xc81004c0
boot_pxe=false
EOF
    cat  > ${ROOT_DIR}/boot/s905_autoscript.uboot.cmd <<'EOF'
echo "Start u-boot......"
setenv env_addr   "0x10400000"
setenv uboot_addr "0x1000000"
if fatload usb 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload usb 0 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload usb 0 ${uboot_addr} u-boot.usb.bin; then go ${uboot_addr}; fi; fi;
if fatload usb 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload usb 1 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload usb 1 ${uboot_addr} u-boot.usb.bin; then go ${uboot_addr}; fi; fi;
if fatload mmc 0 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload mmc 0 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload mmc 0 ${uboot_addr} u-boot.mmc.bin; then go ${uboot_addr}; fi; fi;
if fatload mmc 1 ${env_addr} uEnv.ini; then env import -t ${env_addr} ${filesize}; if test ${boot_pxe} = true; then if fatload mmc 1 ${uboot_addr} u-boot.pxe.bin; then go ${uboot_addr}; fi; fi; if fatload mmc 1 ${uboot_addr} u-boot.mmc.bin; then go ${uboot_addr}; fi; fi;
EOF
    mkdir -p ${ROOT_DIR}/boot/extlinux
    cat <<EOF > ${ROOT_DIR}/boot/extlinux/extlinux.conf
label PHICOMM_N1
    linux /vmlinuz-${kerver}
    initrd /initrd.img-${kerver}
    fdt /dtb/${dtb}
    append root=LABEL=${ROOT_LABEL} rootflags=data=writeback fsck.fix=yes fsck.repair=yes net.ifnames=0 console=ttyAML0,115200n8 console=tty1 no_console_suspend consoleblank=0 video=1280x1024@60me
EOF
    log "https://github.com/PuXiongfei/phicomm-n1-u-boot"
    log "5d921bf1d57baf081a7b2e969d7f70a5  u-boot.bin"
    log "ade4aa3942e69115b9cc74d902e17035  u-boot.bin.new"
    cat ${DIRNAME}/u-boot.mmc.bin 2>/dev/null > ${ROOT_DIR}/boot/u-boot.mmc.bin || true
    cat ${DIRNAME}/u-boot.usb.bin 2>/dev/null > ${ROOT_DIR}/boot/u-boot.usb.bin || true
    cat ${DIRNAME}/u-boot.pxe.bin 2>/dev/null > ${ROOT_DIR}/boot/u-boot.pxe.bin || true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOT_DIR} /bin/bash <<EOSHELL
    [ -z ${kerver} ] || depmod ${kerver}
    [ -z ${kerver} ] || update-initramfs -c -k ${kerver}
    rm -f /boot/s905_autoscript /boot/s905_autoscript /boot/s905_autoscript.uboot /boot/s905_autoscript.nfs || true
    # aml_autoscript for android to linux bootup
    mkimage -C none -A arm -T script -d /boot/aml_autoscript.cmd /boot/aml_autoscript
    mkimage -C none -A arm -T script -d /boot/s905_autoscript.cmd /boot/s905_autoscript
    mkimage -C none -A arm -T script -d /boot/s905_autoscript.uboot.cmd /boot/s905_autoscript.uboot
    mkimage -C none -A arm -T script -d /boot/s905_autoscript.nfs.cmd /boot/s905_autoscript.nfs
    rm -f /boot/aml_autoscript.cmd /boot/s905_autoscript.cmd /boot/s905_autoscript.uboot.cmd /boot/s905_autoscript.nfs.cmd || true
EOSHELL
    log "!!!!!!!!!IF USB BOOT DISK, rm -f ${ROOT_DIR}/etc/udev/rules.d/*"
fi
ls -lhR ${ROOT_DIR}/boot
log "end install you kernel&patchs"

log "patch bluetoothd for sap error, Starting bluetoothd with the option \"--noplugin=sap\" by default (as already suggested) would be one way to do it"
sed -i.bak "s|ExecStart=.*|ExecStart=/usr/libexec/bluetooth/bluetoothd --compat --noplugin=sap|g" ${ROOT_DIR}/usr/lib/systemd/system/bluetooth.service || true
log "bluetoothctl --agent KeyboardDisplay"
log "add smplayer ontop options"
sed -i "s|Exec=smplayer|Exec=smplayer -ontop|g" ${ROOT_DIR}/usr/share/applications/smplayer.desktop || true
sed -i "s|Exec=smplayer|Exec=smplayer -ontop|g" ${ROOT_DIR}/usr/share/applications/smplayer_enqueue.desktop || true
log "start chroot shell, inst firmware & disable service & do other work"
log "apt install --no-install-recommends libglu1-mesa libglw1-mesa libgles2-mesa libgl4es0 libglew2.1 mesa-utils mesa-vulkan-drivers"
log "run: usb_automount/sky.remote.sh"
chroot ${ROOT_DIR} /usr/bin/env -i PS1='\u@s905d:\w$' /bin/bash --noprofile --norc -o vi || true
log "ALL OK ###########################"
exit 0
