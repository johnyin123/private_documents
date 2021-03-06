#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("init-pc.sh - 167c393 - 2021-05-28T09:01:02+08:00")
################################################################################
source ${DIRNAME}/os_debian_init.sh

DEBIAN_VERSION=buster
PASSWORD=password
IPADDR=192.168.168.124/24
GATEWAY=192.168.168.1
NAME_SERVER=114.114.114.114
#512 M
ZRAM_SIZE=512

debian_apt_init ${DEBIAN_VERSION}
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

echo "nameserver ${NAME_SERVER:-114.114.114.114}" > /etc/resolv.conf
debian_chpasswd root ${PASSWORD:-password}
debian_locale_init
debian_limits_init
debian_sysctl_init
debian_bash_init root
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
apt -y install bridge-utils
cat << EOF | tee /etc/network/interfaces.d/br-ext
auto eth0
allow-hotplug eth0
iface eth0 inet manual

auto br-ext
iface br-ext inet static
    bridge_ports eth0
    #bridge_ports none
    address ${IPADDR:-10.32.166.31/25}
    gateway ${GATEWAY:-10.32.166.1}

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

sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0 ipv6.disable=1\"/g" /etc/default/grub
update-initramfs -c -k $(uname -r)
grub-mkconfig -o /boot/grub/grub.cfg

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

echo "install packages!"
apt -y install systemd-container \
    hostapd wpasupplicant wireless-tools \
    android-tools-adb android-tools-fastboot \
    bzip2 pigz p7zip-full arj zip rar mscompress unar eject bc less vim rename \
    ftp telnet nmap tftp ntpdate lsof strace \
    tcpdump ethtool aria2 axel curl wget mpg123 nmon sysstat arping dnsutils \
    minicom socat git git-flow net-tools \
    manpages-dev manpages-posix manpages-posix-dev manpages build-essential \
    nscd nbd-client iftop netcat-openbsd sshfs squashfs-tools graphviz nftables \
    rsync tmux wireguard-tools \
    xserver-xorg xfce4 xfce4-terminal xfce4-screenshooter xscreensaver qt4-qtconfig \
    gnome-icon-theme lightdm \
    galculator medit gpicview qpdfview rdesktop xvnc4viewer wireshark \
    fbreader alsa-utils pulseaudio pulseaudio-utils vlc \
    virt-manager gir1.2-spiceclientgtk-3.0 \
    fcitx-ui-classic fcitx-tools fcitx fcitx-sunpinyin fcitx-config-gtk \
    libvirt-daemon libvirt-clients libvirt-daemon-driver-storage-rbd libvirt-daemon-system \
    qemu-kvm qemu-utils xmlstarlet jq sudo debootstrap kpartx binwalk

apt -y install traceroute ipcalc qrencode
# qrencode -8  -o - -t UTF8 "massage"

wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list && \
apt update && apt -y install google-chrome-stable
# wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
# wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

id johnyin &>/dev/null && {
    echo "login johnyin and run 'systemctl enable pulseaudio.service --user' to enable pulse audio"
    mkdir -p /home/johnyin/.config/libvirt
    echo 'uri_default = "qemu:///system"' > /home/johnyin/.config/libvirt/libvirt.conf
    chown -R johnyin.johnyin /home/johnyin/.config
    usermod -G libvirt johnyin

    echo "add group[johnyin] to sudoers"
    echo "%johnyin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/johnyin
    chmod 0440 /etc/sudoers.d/johnyin
    cp /etc/sudoers /etc/sudoers.orig
    sed -i "s/^\(.*requiretty\)$/#\1/" /etc/sudoers

    echo "enable root user run X app"
    ln -s /home/johnyin/.Xauthority /root/.Xauthority

    debian_bash_init johnyin
}

id johnyin &>/dev/null && debian_chpasswd johnyin ${PASSWORD}
echo "Force Users To Change Passwords Upon First Login"
chage -d 0 root || true
chage -d 0 johnyin || true

#debian_minimum_init => remove manpage doc
apt clean
find /var/log/ -type f | xargs rm -f
rm -rf /var/cache/apt/* /var/lib/apt/lists/* /root/.bash_history /root/.viminfo /root/.vim/

cat<<'EOF'
# install new kernel
apt -y install linux-image-5.10.0-0.bpo.3-amd64

#new disk copy install
grub-install --target=i386-pc --boot-directory=${mntpoint}/boot --modules="xfs part_msdos" ${DISK}

NEW_UUID=$(blkid -s UUID -o value ${DISK_PART})
sed -i "s/........-....-....-....-............/${NEW_UUID}/g" ${mntpoint}/boot/grub/grub.cfg
sed -i "s/........-....-....-....-............/${NEW_UUID}/g" ${mntpoint}/etc/fstab
# bootup run "update-initramfs -c -k $(uname -r)"

# install debain multimedia

cat <<LST_EOF >> /etc/apt/sources.list
# deb http://www.deb-multimedia.org buster main non-free
# deb http://www.deb-multimedia.org buster-backports main
deb http://ftp.cn.debian.org/debian-multimedia buster main non-free
deb http://ftp.cn.debian.org/debian-multimedia buster-backports main
LST_EOF

apt-get update -oAcquire::AllowInsecureRepositories=true
apt-get install deb-multimedia-keyring
EOF

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
EODOC

echo "ALL DONE!!!!!!!!!!!!!!!!"

exit 0
