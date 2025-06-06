#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("7a839434[2025-06-06T15:12:55+08:00]:init-pc.sh")
################################################################################
source ${DIRNAME}/os_debian_init.sh
# https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
source <(grep -E "^\s*(VERSION_CODENAME|ID)=" /etc/os-release)
PASSWORD=password
IPADDR=192.168.168.124/24
GATEWAY=192.168.168.1
NAME_SERVER=114.114.114.114
#512 M
ZRAM_SIZE=512
apt_install() {
    for pkg in $*; do
        apt -y -oAcquire::http::User-Agent=dler install ${pkg} || true
    done
}

debian_apt_init
apt update
apt -y upgrade

echo "xk-yinzh" > /etc/hostname

cat << EOF > /etc/hosts
127.0.0.1       localhost $(cat /etc/hostname)
EOF

cat << EOF > /etc/rc.local
#!/bin/sh -e
exit 0
EOF
chmod 755 /etc/rc.local

echo "Fix error iwlwifi_yoyo.bin "
echo "dell laptop iwwifi hardblock, should close powermanager ont wifi, set it in bios"
echo 'options iwlwifi enable_ini=N' > /etc/modprobe.d/iwlwifi.conf

echo "nameserver ${NAME_SERVER:-114.114.114.114}" > /etc/resolv.conf
debian_chpasswd root ${PASSWORD:-password}
debian_locale_init
debian_limits_init
debian_sysctl_init
debian_vim_init
debian_zswap_init ${ZRAM_SIZE}
debian_sshd_init
debain_overlay_init
debian_bash_init root

cat << EOF | tee /etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

echo "install network bridge"
apt_install bridge-utils
cat << EOF | tee /etc/network/interfaces.d/br-int
auto br-int
iface br-int inet manual
    bridge_ports none
    bridge_maxwait 0
EOF
cat << EOF | tee /etc/network/interfaces.d/br-ext
# auto eth0
allow-hotplug eth0
iface eth0 inet manual
    hwaddress 9e:7f:97:92:78:74

auto br-ext
iface br-ext inet static
    bridge_ports eth0
    bridge_maxwait 0
    #bridge_ports none
    hwaddress 00:be:43:53:2c:b9
    address ${IPADDR:-10.32.166.31/25}
    ${GATEWAY:+gateway ${GATEWAY}}

# auto bond0
# iface bond0 inet manual
#         up ifconfig bond0 0.0.0.0 up
#         bond-slaves eth4 eth5
#         # bond-mode 4 = 802.3ad
#         bond-mode 4
#         bond-miimon 100
#         bond-downdelay 200
#         bond-updelay 200
#         bond-lacp-rate 1
#         bond-xmit-hash-policy layer3+4
# auto bond0.1023
# iface bond0.1023 inet static
#         vlan-raw-device bond0
EOF

cat << "EOF" | tee /etc/network/interfaces.d/wifi
# auto wlan0
allow-hotplug wlan0

# iface wlan0 inet dhcp
#     wpa_iface wlan0
#     wpa_conf /etc/work.conf
EOF

cat << 'EOF_WIFI' > /etc/work.conf
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
network={
    priority=90
    scan_ssid=1
    ssid="Neusoft"
    key_mgmt=WPA-EAP
    eap=PEAP
    phase1="peaplabel=auto tls_disable_tlsv1_0=0 tls_disable_tlsv1_1=0 tls_disable_tlsv1_2=0 tls_ext_cert_check=0"
    phase2="auth=MSCHAPV2"
    identity="uid"
    password="pass"
    eapol_flags=0
}

EOF_WIFI

cat << "EOF" > /root/aptrom.sh
#!/usr/bin/env bash

mount -o remount,rw /overlay/lower

chroot /overlay/lower apt update
chroot /overlay/lower apt install $*

rm -rf /overlay/lower/var/cache/apt/* /overlay/lower/var/lib/apt/lists/* /overlay/lower/var/log/*
rm -rf /overlay/lower/root/.bash_history /overlay/lower/root/.viminfo /overlay/lower/root/.vim/
sync
mount -o remount,ro /overlay/lower
EOF

debian_grub_init
# update-initramfs -c -k $(uname -r)
# grub-mkconfig -o /boot/grub/grub.cfg

[ -r "${DIRNAME}/motd.sh" ] && {
    cat ${DIRNAME}/motd.sh >/etc/update-motd.d/11-motd
    touch /etc/logo.txt
    chmod 755 /etc/update-motd.d/11-motd
}


echo "use tcp dns query"
: <<EOF
single-request-reopen (glibc>=2.9) 发送 A 类型请求和 AAAA 类型请求使用不同的源端口。
single-request (glibc>=2.10) 避免并发，改为串行发送 A 类型和 AAAA 类型请求，没有了并发，从而也避免了冲突。
echo 'options use-vc' >> /etc/resolv.conf
EOF

echo "install packages! pbzip2 pigz pixz parallel version bzip2/gz/xz"
apt_install systemd-container \
    hostapd wpasupplicant wireless-tools \
    android-tools-adb android-tools-fastboot \
    pbzip2 pigz pixz xz-utils zstd p7zip-full brotli arj zip rar mscompress \
    unar eject bc less vim rename lunar wrk \
    ftp telnet nmap tftp ntpdate lsof strace \
    tcpdump ethtool aria2 axel curl wget mpg123 lame \
    nmon sysstat arping dnsutils openvpn \
    minicom socat git git-flow net-tools file genisoimage \
    manpages-dev manpages-posix manpages-posix-dev manpages man-db \
    build-essential bison flex patch pahole j2cli \
    nscd nbd-client mtools iftop netcat-openbsd sshfs vlan \
    squashfs-tools graphviz nftables stunnel4 \
    rsync tmux virt-viewer sqlite3 dnsmasq ncal \
    qemu-kvm qemu-system-gui qemu-utils qemu-block-extra \
    xmlstarlet jq sudo debootstrap kpartx \
    crudini usbredirect usbip wpan-tools
    #binwalk

apt_install iotop iputils-tracepath traceroute ipcalc ipset iputils-ping subnetcalc qrencode ncal
# qrencode -8 -o - -t UTF8 "massage"

# bat(batcat): cat(1) clone with syntax highlighting and git integration
apt_install bat
[ "${XFCE:-false}" == "true" ] && {
    echo "modify xfce4 default Panel layer"
    apt_install lightdm xserver-xorg xfce4 xfce4-terminal xfce4-screenshooter xscreensaver
} || {
    apt_install lightdm xserver-xorg lxde-core lxterminal lxrandr openbox-lxde-session xscreensaver
    sed -i "/font place=/,/font/ s/<name>.*<\/name>/<name>DejaVu Sans Mono<\/name>/" /etc/xdg/openbox/LXDE/rc.xml
    sed -i "/font place=/,/font/ s/<size>.*<\/size>/<size>14<\/size>/" /etc/xdg/openbox/LXDE/rc.xml
    sed -i "/<desktops>/,/<desktops>/ s/<number>.*<\/number>/<number>1<\/number>/" /etc/xdg/openbox/LXDE/rc.xml
    sed -i 's/fontname=.*/fontname=DejaVu Sans Mono 14/g' /usr/share/lxterminal/lxterminal.conf
    echo 'color_preset=xterm' >> /usr/share/lxterminal/lxterminal.conf
    sed -i 's/edge=bottom/edge=top/g' /etc/xdg/lxpanel/LXDE/panels/panel
    sed -i "/type\s*=\s*dclock/,/Config/ s/Config\s{/Config {\nIconOnly=1/g" /etc/xdg/lxpanel/LXDE/panels/panel
    sed -i "s/pcmanfm.desktop/pcmanfm.desktop\n}\nButton {\nid=lxterminal.desktop/g" /etc/xdg/lxpanel/LXDE/panels/panel
    sed -i 's/background\s*=\s*1/background=0/g' /etc/xdg/lxpanel/LXDE/panels/panel
    sed -i "s/wallpaper\s*=.*/wallpaper=\/usr\/share\/lxde\/wallpapers\/lxde_blue.jpg/g" /etc/xdg/pcmanfm/LXDE/pcmanfm.conf
    sed -i "s/\[desktop\]/[desktop]\ndesktop_font=DejaVu Sans Mono 14/" /etc/xdg/pcmanfm/LXDE/pcmanfm.conf
    sed -i "s/side_pane_mode\s*=.*/side_pane_mode=dirtree/g" /etc/xdg/pcmanfm/LXDE/pcmanfm.conf
    sed -i "s/view_mode\s*=.*/view_mode=list/g" /etc/xdg/pcmanfm/LXDE/pcmanfm.conf
    sed -i 's|.*CursorThemeSize.*|iGtk/CursorThemeSize=32|g' /etc/xdg/lxsession/LXDE/desktop.conf
    sed -i 's|.*FontName.*|sGtk/FontName=DejaVu Sans Mono 14|g' /etc/xdg/lxsession/LXDE/desktop.conf


}
apt_install xtv x2x rfkill x11vnc gvncviewer aosd-cat

echo "xtv -d <remote_ip:0> #xtv see remote desktop"
echo "x2x -to <remote_ip:0.0> -west # mouse move left, then appear remote desktop!!!"
echo "ssh -p22 root@ip 'ffmpeg -f x11grab -r 25 -i :0.0 -f mpeg -' | mpv -"
echo 'ffmpeg -f alsa -i pulse -f x11grab -draw_mouse 1 -i ip:0.0 -f mpeg - | mpv -'
sed -i "s/enabled=.*/enabled=False/g" /etc/xdg/user-dirs.conf 2>/dev/null || true

XFCE_TERM=
XFCE_FILE=
XFCE_WEB=
XFCE_MAIL=

case "$VERSION_CODENAME" in
    buster)
        apt_install qt4-qtconfig medit xvnc4viewer
        apt_install fcitx-ui-classic fcitx-tools fcitx fcitx-sunpinyin fcitx-config-gtk
        XFCE_TERM=exo-terminal-emulator.desktop
        XFCE_FILE=exo-file-manager.desktop
        XFCE_WEB=exo-web-browser.desktop
        XFCE_MAIL=exo-mail-reader.desktop
        ;;
    bullseye | *)
        apt_install bsdmainutils fonts-noto-cjk xpad
        apt_install fcitx5 fcitx5-pinyin fcitx5-chinese-addons fcitx5-frontend-gtk2 fcitx5-frontend-gtk3 fcitx5-frontend-qt5
        XFCE_TERM=xfce4-terminal-emulator.desktop
        XFCE_FILE=xfce4-file-manager.desktop
        XFCE_WEB=xfce4-web-browser.desktop
        XFCE_MAIL=xfce4-mail-reader.desktop
        ;;
esac
sed -i "s/#xserver-allow-tcp=.*/xserver-allow-tcp=true/g" /etc/lightdm/lightdm.conf || true
[ "${XFCE:-false}" == "true" ] && cat<<EOF > /etc/xdg/xfce4/panel/default.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="30"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="7"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="3"/>
        <value type="int" value="15"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="14"/>
        <value type="int" value="2"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="button-title" type="string" value="Program"/>
      <property name="show-button-title" type="bool" value="false"/>
    </property>
    <property name="plugin-2" type="string" value="actions">
      <property name="items" type="array">
        <value type="string" value="+lock-screen"/>
        <value type="string" value="-switch-user"/>
        <value type="string" value="-separator"/>
        <value type="string" value="-suspend"/>
        <value type="string" value="-hibernate"/>
        <value type="string" value="-separator"/>
        <value type="string" value="-shutdown"/>
        <value type="string" value="-restart"/>
        <value type="string" value="-separator"/>
        <value type="string" value="-logout"/>
        <value type="string" value="-logout-dialog"/>
      </property>
      <property name="appearance" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="tasklist"/>
    <property name="plugin-15" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="pager"/>
    <property name="plugin-5" type="string" value="clock">
      <property name="tooltip-format" type="string" value="%R,%a,%b%-d日"/>
      <property name="digital-format" type="string" value="%b%-d日%R,%a"/>
      <property name="digital-time-format" type="string" value="%R,%a,%b%-d日"/>
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-font" type="string" value="Sans 12"/>
    </property>
    <property name="plugin-6" type="string" value="systray"/>
    <property name="plugin-7" type="string" value="showdesktop"/>
    <property name="plugin-9" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${XFCE_TERM}"/>
      </property>
    </property>
    <property name="plugin-10" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${XFCE_FILE}"/>
      </property>
    </property>
    <property name="plugin-11" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${XFCE_WEB}"/>
      </property>
    </property>
    <property name="plugin-12" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="${XFCE_MAIL}"/>
      </property>
    </property>
    <property name="plugin-8" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
    </property>
    <property name="plugin-14" type="string" value="screenshooter"/>
  </property>
</channel>
EOF
apt_install galculator gpicview qpdfview rdesktop wireshark fbreader virt-manager

apt_install alsa-utils pulseaudio pulseaudio-utils

apt_install smplayer smplayer-l10n ffmpeg mkvtoolnix

apt_install systemd-timesyncd recordmydesktop

id johnyin &>/dev/null || useradd johnyin --create-home --home-dir /home/johnyin/ --shell /bin/bash
debian_bash_init johnyin
debian_chpasswd johnyin ${PASSWORD}
{
    echo "login johnyin and run 'systemctl enable pulseaudio.service --user' to enable pulse audio"
    mkdir -p /home/johnyin/.config/libvirt
    echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"'
    echo 'uri_default = "qemu:///system"' > /home/johnyin/.config/libvirt/libvirt.conf
    cat <<'EOF' > /home/johnyin/.gitconfig
[user]
name = johnyin
email = johnyin.news@163.com
[core]
    editor = /usr/bin/vim
[alias]
    lg = log --color --graph --pretty=format:'[%cd] %Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=short --
# [http]
# 	proxy = http://127.0.0.1:58891
# git config --global http.sslVerify "false"
EOF
    chown -R johnyin.johnyin /home/johnyin/
    usermod -a -G libvirt johnyin || true

    echo "add group[johnyin] to sudoers"
    echo "%johnyin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/johnyin
    chmod 0440 /etc/sudoers.d/johnyin
    sed -i.orig "s/^\(.*requiretty\)$/#\1/" /etc/sudoers

    echo "enable root user run X app"
    rm -f /root/.Xauthority && ln -s /home/johnyin/.Xauthority /root/.Xauthority
    debian_bash_init johnyin
}

echo "Force Users To Change Passwords Upon First Login"
chage -d 0 root || true
chage -d 0 johnyin || true

echo "init libvirt env"
systemctl start libvirtd || true
systemctl status libvirtd >/dev/null && {
    pool_name=default
    dir=/storage
    net_name=br-ext
    mkdir -p ${dir}
    # ln -s .... ${dir}
    virsh pool-destroy default || true
    virsh pool-undefine default || true
    virsh net-destroy default || true
    virsh net-undefine default || true
    #virsh pool-define-as default --type dir --target /storage
    #virsh pool-build default
    cat <<EPOOL | tee | virsh pool-define /dev/stdin
<pool type='dir'>
  <name>${pool_name}</name>
  <target>
    <path>${dir}</path>
  </target>
</pool>
EPOOL
    virsh pool-start ${pool_name}
    virsh pool-autostart ${pool_name}
    cat <<ENET | tee | virsh net-define /dev/stdin
<network>
  <name>${net_name}</name>
  <forward mode='bridge'/>
  <bridge name='${net_name}'/>
</network>
ENET
    virsh net-start ${net_name}
    virsh net-autostart ${net_name}
    net_name=br-int
    cat <<ENET | tee | virsh net-define /dev/stdin
<network>
  <name>${net_name}</name>
  <forward mode='bridge'/>
  <bridge name='${net_name}'/>
</network>
ENET
    virsh net-start ${net_name}
    virsh net-autostart ${net_name}
} || true
# ###Source NAT
# #iptables -t nat -A POSTROUTING -s 192.168.1.1 -j SNAT --to-source 1.1.1.1
# #iptables -t nat -A POSTROUTING -s 192.168.2.2 -j SNAT --to-source 2.2.2.2
# #nft add rule nat postrouting snat to ip saddr map { 192.168.1.1 : 1.1.1.1, 192.168.2.2 : 2.2.2.2 }
# #nft add rule nat postrouting ip saddr 192.168.168.0/24 oif br-ext snat to 10.32.166.33
# nft flush ruleset
# nft add table nat
# nft 'add chain nat postrouting { type nat hook postrouting priority 100 ; }'
# nft add rule nat postrouting ip saddr 192.168.168.0/24
# nft add rule nat postrouting masquerade
# nft list ruleset
# table ip nat {
# 	chain postrouting {
# 		type nat hook postrouting priority srcnat; policy accept;
# 		ip saddr 192.168.168.0/24
# 		masquerade
# 	}
# }
# ###NAT pooling
# #It is possible to specify source NAT pooling:
# nft add rule inet nat postrouting snat ip to 10.0.0.2/31
# nft add rule inet nat postrouting snat ip to 10.0.0.4-10.0.0.127
# # With transport protocol source port mapping:
# nft add rule inet nat postrouting ip protocol tcp snat ip to 10.0.0.1-10.0.0.100:3000-4000
# ###Destination NAT
# #You need to add the following table and chain configuration:
# nft 'add chain nat prerouting { type nat hook prerouting priority -100; }'
# #Then, you can add the following rule:
# nft 'add rule nat prerouting iif eth0 tcp dport { 80, 443 } dnat to 192.168.1.120'
# ###Redirect
# #NOTE: redirect is available starting with Linux Kernel 3.19.
# #By using redirect, packets will be forwarded to local machine. Is a special case of DNAT where the destination is the current machine.
# nft add rule nat prerouting redirect
# #This example redirects 22/tcp traffic to 2222/tcp:
# nft add rule nat prerouting tcp dport 22 redirect to 2222
# #This example redirects outgoing 53/tcp traffic to a local proxy listening on port 10053/tcp:
# nft add rule nat output tcp dport 853 redirect to 10053

cat <<'EOF'>/etc/nftables.conf
#!/usr/sbin/nft -f
flush ruleset

# define CAN_ACCESS_IPS = { 20.205.243.166, 101.71.33.11, 111.124.200.227, 120.55.105.209, 47.97.242.13, 183.131.227.249}
define CAN_ACCESS_IPS = { }
table ip nat {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		ip saddr 192.168.167.10 counter masquerade
		ip saddr 192.168.167.20 counter masquerade
		ip saddr 192.168.168.0/24 ip daddr != 192.168.168.0/24 counter masquerade
		ip saddr 192.168.169.0/24 ip daddr != 192.168.169.0/24 counter masquerade
		ip saddr 192.168.32.0/24 ip daddr != 192.168.32.0/24 counter masquerade
	}
}
table ip filter {
	chain forward {
		type filter hook forward priority 0; policy accept;
		meta l4proto tcp tcp flags & (syn|rst) == syn counter tcp option maxseg size set rt mtu
	}
}
table inet mangle {
	set canouts4 {
		typeof ip daddr
		flags interval
		elements = { $CAN_ACCESS_IPS }
	}

	chain output {
		type route hook output priority mangle; policy accept;
		ip daddr @canouts4 meta l4proto { tcp, udp } meta mark set 0x00000440
	}
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# flush table inet myblackhole
# delete table inet myblackhole
# # block ip for 5m, can remove blacklist set timeout properties
# nft add element inet myblackhole blacklist '{ 192.168.168.2 }'
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
define BLACK_LIST = { }
table inet myblackhole {
    set blacklist {
        type ipv4_addr
        flags dynamic,timeout
        timeout 5m
        elements = { $BLACK_LIST }
    }
    chain input {
        type filter hook input priority 0; policy accept;
        # iifname "lo" accept comment "Accept anything from lo interface"
        # accept traffic originating from us
        ct state established,related accept
        # tcp dport { 80, 8443 } ct state new limit rate 10/second accept
        # ct state vmap { invalid : drop, established : accept, related : accept }
        # # Drop all incoming connections in blacklist, reject fast application response than drop
        ip saddr @blacklist counter reject
		#ip protocol . th dport vmap {tcp . 8080 : jump HTTP, tcp . 22 : jump SSH, udp . 53: accept, tcp . !=8080|80|22|53 : jump AOB}
    }
}
EOF
chmod 755 /etc/nftables.conf

systemctl set-default graphical.target

#debian_minimum_init => remove manpage doc
apt clean
find /var/log/ -type f | xargs rm -f
rm -rf /var/cache/apt/* /var/lib/apt/lists/* /root/.bash_history /root/.viminfo /root/.vim/

cat <<'EODOC'
# systemctl disable networking.service NetworkManager
# systemctl enable systemd-networkd.service

BR_NAME=br-ext
ETHER_DEV=eth0
ADDRESS=192.168.168.124/24
GATEWAY=192.168.168.1

cat <<EOF >/etc/systemd/network/${ETHER_DEV}.network
[Match]
Name=${ETHER_DEV}

[Network]
Bridge=${BR_NAME}
EOF

cat <<EOF >/etc/systemd/network/${BR_NAME}.netdev
[NetDev]
Name=${BR_NAME}
Kind=bridge
EOF

cat <<EOF >/etc/systemd/network/${BR_NAME}.network
[Match]
Name=${BR_NAME}

[Network]
Address=${ADDRESS}
[Route]
#for speedup reason move gateway here
Gateway=${GATEWAY}
EOF

BR_NAME=br-sy
cat <<EOF >/etc/systemd/network/${BR_NAME}.netdev
[NetDev]
Name=${BR_NAME}
Kind=bridge
EOF

BR_NAME=br-dl
cat <<EOF >/etc/systemd/network/${BR_NAME}.netdev
[NetDev]
Name=${BR_NAME}
Kind=bridge
EOF

BR_NAME=br-bj
cat <<EOF >/etc/systemd/network/${BR_NAME}.netdev
[NetDev]
Name=${BR_NAME}
Kind=bridge
EOF
echo '/home/johnyin/disk/storage /storage none defaults,bind 0 4' >> /etc/fstab
# wireguard-tools need install debian kernel
apt -y -oAcquire::http::User-Agent=dler --no-install-recommends install wireguard-tools
touch /etc/default/google-chrome
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
echo "deb [arch=amd64 trusted=yes] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list && \
apt update && apt -y install google-chrome-stable || true
rm -f /etc/apt/sources.list.d/google.list /etc/cron.daily/google-chrome /etc/default/google-chrome
# wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
# wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
EODOC

echo "ALL DONE!!!!!!!!!!!!!!!!"

exit 0
