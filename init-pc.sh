#!/bin/bash

DEBIAN_VERSION=buster
PASSWORD=password
ROOT_LABEL=ROOTFS
#512 M
ZRAM_SIZE=512
ZRAMSWAP="udisks2"
#ZRAMSWAP="zram-tools"

echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
echo 'APT::Install-Recommends "0";'> /etc/apt/apt.conf.d/71-no-recommends
echo 'APT::Install-Suggests "0";'> /etc/apt/apt.conf.d/72-no-suggests

# auto reformatoverlay plug usb ttl
#cat > /etc/udev/rules.d/99-reformatoverlay.rules << EOF
#SUBSYSTEM=="tty", ACTION=="add", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="//bin/sh -c 'touch /overlay/reformatoverlay; echo heartbeat > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
#SUBSYSTEM=="tty", ACTION=="remove", ENV{ID_VENDOR_ID}=="1a86", ENV{ID_MODEL_ID}=="7523", RUN+="//bin/sh -c 'rm /overlay/reformatoverlay; echo none > /sys/devices/platform/leds/leds/n1\:white\:status/trigger'"
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
echo "zram" >> /etc/modules
cat << EOF > /usr/local/lib/zram.conf.d/zram0-env
ZRAM_NUM_STR=lzo
ZRAM_DEV_SIZE=$((${ZRAM_SIZE}*1024*1024))
SWAP=y
EOF

cat << EOF > /etc/hosts
127.0.0.1       localhost $(cat /etc/hostname)
EOF

cat > /etc/fstab << EOF
LABEL=${ROOT_LABEL}    /    jfs    defaults,errors=remount-ro,noatime    0    1
#tmpfs /var/log  tmpfs   defaults,noatime,nosuid,nodev,noexec,size=16M  0  0
EOF

#Installing packages without docs
cat >  /etc/dpkg/dpkg.cfg.d/01_nodoc <<EOF
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

apt -y install openssh-server
dpkg-reconfigure -f noninteractive openssh-server
sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/g' /etc/ssh/sshd_config
sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
(grep -v -E "^Ciphers|^MACs" /etc/ssh/sshd_config ; echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr"; echo "MACs    hmac-sha1"; ) | tee /etc/ssh/sshd_config

cat << EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

echo "install network bridge"
apt -y install bridge-utils
cat << EOF > /etc/network/interfaces.d/br-ext
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

cat << "EOF" > /etc/network/interfaces.d/wifi
auto wlan0
allow-hotplug wlan0
iface wlan0 inet manual
    wpa-roam /etc/wpa.conf
#    pre-up (iw dev wlan0 set power_save off || true)
iface xkadmin inet dhcp
#    post-up (ip r a default via 10.32.166.129||true)
EOF

cat << EOF > /etc/wpa.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
#update_config=1

ap_scan=1
network={
    ssid="xk-admin"
    scan_ssid=1
    #key_mgmt=wpa-psk
    psk="ADMIN@123"
    id_str="xkadmin"
    #frequency=2412 use in adhoc
}
EOF

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
cat > /root/aptrom.sh <<EOF
#!/usr/bin/env bash

mount -o remount,rw /overlay/lower
cp /overlay/lower/etc/apt/sources.list ~/sources.list.bak

mount -o remount,rw /overlay/lower

chroot /overlay/lower apt update
chroot /overlay/lower apt install \$*

rm -rf /overlay/lower/var/cache/apt/* /overlay/lower/var/lib/apt/lists/* /overlay/lower/var/log/*
rm -rf /overlay/lower/root/.bash_history /overlay/lower/root/.viminfo /overlay/lower/root/.vim/
sync
mount -o remount,ro /overlay/lower
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

"新建.py,.cc,.sh,.javp文件，自动插入文件头"
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

echo "start install overlay_rootfs ====================="
cat <<EOF
kernel parm "skipoverlay"
overlayfs lable "OVERLAY"
/overlay/reformatoverlay exist will format it!
EOF

if ! grep -q "^overlay" /etc/initramfs-tools/modules; then
    echo overlay >> /etc/initramfs-tools/modules
fi

cat > /usr/share/initramfs-tools/hooks/overlay <<'EOF'
#!/bin/sh

. /usr/share/initramfs-tools/scripts/functions
. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/blkid
copy_exec /sbin/fsck
copy_exec /sbin/fsck.jfs
copy_exec /sbin/mkfs.jfs
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

if grep -q -E '(^|\s)skipoverlay(\s|$)' /proc/cmdline; then
    log_begin_msg "Skipping overlay, found 'skipoverlay' in cmdline"
    log_end_msg
    exit 0
fi

log_begin_msg "Starting overlay"
log_end_msg

mkdir -p /overlay

# if we have a filesystem label of OVERLAY
# use that as the overlay, otherwise use tmpfs.
OLDEV=`blkid -L OVERLAY`
if [ -z "${OLDEV}" ]; then
    mount -t tmpfs tmpfs /overlay
else
    _checkfs_once ${OLDEV} /overlay >> /log.txt 2>&1 ||  \
    mkfs.jfs -L OVERLAY ${OLDEV}
    if ! mount ${OLDEV} /overlay; then
        mount -t tmpfs tmpfs /overlay
    fi
fi

# if you sudo touch /overlay/reformatoverlay
# next reboot will give you a fresh /overlay
if [ -f /overlay/reformatoverlay ]; then
    umount /overlay
    mkfs.jfs -L OVERLAY ${OLDEV}
    if ! mount ${OLDEV} /overlay; then
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
cp ${rootmnt}/etc/fstab ${rootmnt}/etc/fstab.orig
awk '$2 != "/" {print $0}' ${rootmnt}/etc/fstab.orig > ${rootmnt}/etc/fstab
awk '$2 == "'${rootmnt}'" { $2 = "/" ; print $0}' /etc/mtab >> ${rootmnt}/etc/fstab

exit 0
EOF

chmod 755 /usr/share/initramfs-tools/hooks/overlay
chmod 755 /etc/initramfs-tools/scripts/init-bottom/init-bottom-overlay

echo "end install overlay_rootfs"
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0\"/g" /etc/default/grub
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

echo "install packages!"
apt -y install bzip2 pigz p7zip-full arj zip mscompress unar eject bc less vim ftp telnet nmap tftp ntpdate screen lsof strace
apt -y install manpages tcpdump ethtool aria2 axel curl mpg123 nmon sysstat arping dnsutils minicom socat git git-flow

usermod -p "$(echo ${PASSWORD} | openssl passwd -1 -stdin)" root
usermod -p "$(echo ${PASSWORD} | openssl passwd -1 -stdin)" johnyin
# echo "root:${PASSWORD}" |chpasswd 
echo "Force Users To Change Passwords Upon First Login"
chage -d 0 root
chage -d 0 johnyin

apt clean
find /var/log/ -type f | xargs rm
exit 0
