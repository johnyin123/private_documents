#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("mkdeb.sh - initversion - 2021-03-17T16:37:30+08:00")
################################################################################
INST_ARCH=${INST_ARCH:-amd64}
REPO=http://mirrors.163.com/debian
PASSWORD=password
export DEBIAN_VERSION=${DEBIAN_VERSION:-buster}
HOSTNAME="docker"

PKG="openssh-server openssh-client rsync"

cleanup() {
    trap '' INT TERM EXIT
    echo "ERROR .... EXIT!!!"
}

mkdir -p ${DIRNAME}/buildroot
mkdir -p ${DIRNAME}/cache

trap cleanup EXIT
trap cleanup TERM
trap cleanup INT

debootstrap --verbose --cache-dir=${DIRNAME}/cache --no-check-gpg --arch ${INST_ARCH} --variant=minbase --include=systemd-container,whiptail,tzdata,locales,busybox --foreign ${DEBIAN_VERSION} ${DIRNAME}/buildroot ${REPO}

unset PROMPT_COMMAND
LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /debootstrap/debootstrap --second-stage

cat > ${DIRNAME}/buildroot/etc/profile.d/johnyin.sh<<"EOF"
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
umask 022
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -lh'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
set -o vi
alias ip="$(which ip || echo busybox ip)"
alias ping="$(which ping || echo busybox ping)"
alias ifconfig="$(which ifconfig || echo busybox ifconfig)"
alias netstat="$(which netstat || echo busybox netstat)"
alias vi="$(which vi || echo busybox vi)"
EOF

LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL

echo ${HOSTNAME} > /etc/hostname

cat << EOF > /etc/hosts
127.0.0.1       localhost ${HOSTNAME} 
EOF

echo 'Acquire::http::User-Agent "debian dler";' > /etc/apt/apt.conf
echo 'APT::Install-Recommends "0";'> /etc/apt/apt.conf.d/71-no-recommends
echo 'APT::Install-Suggests "0";'> /etc/apt/apt.conf.d/72-no-suggests

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

cat <<EOF
To get configure a static IP address on the container,
we need to override the system /usr/lib/systemd/network/80-container-host0.network file,
which provides a DHCP configuration for the host0 network interface of the container.
This can be done by placing the configuration into /etc/systemd/network/80-container-host0.network.
EOF
cat <<EOF >/etc/systemd/network/br-ext.netdev
[NetDev]
Name=br-ext
Kind=bridge
EOF

cat <<EOF >/etc/systemd/network/br-ext.network
[Match]
Name=br-ext
 
[Network]
Address=192.168.168.169/24
Gateway=192.168.168.1
EOF

cat <<EOF >/etc/systemd/network/80-container-host0.network
[Match]
Name=host0

[Network]
Bridge=br-ext
EOF

systemctl enable systemd-networkd

cat << EOF > /etc/rc.local
#!/bin/sh -e
exit 0
EOF
chmod 755 /etc/rc.local

echo "修改systemd journald日志存放目录为内存，也就是/run/log目录，限制最大使用内存空间64MB"
sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
sed -i 's/#RuntimeMaxUse=/RuntimeMaxUse=64M/' /etc/systemd/journald.conf

#set the file limit
cat > /etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF

usermod -p '$(echo ${PASSWORD} | openssl passwd -1 -stdin)' root
#echo "Force Users To Change Their Passwords Upon First Login"
#chage -d 0 root
useradd -m -s /bin/bash johnyin
usermod -p '$(echo ${PASSWORD} | openssl passwd -1 -stdin)' johnyin

exit 0
EOSHELL


[ -z ${PKG} ] || systemd-nspawn -D ${DIRNAME}/buildroot/ apt -y install --no-install-recommends ${PKG}
#dpkg-reconfigure -f noninteractive openssh-server
[ -e "${DIRNAME}/buildroot/etc/ssh/sshd_config" ] && {
    sed -i 's/#UseDNS.*/UseDNS no/g'                   ${DIRNAME}/buildroot/etc/ssh/sshd_config
    sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g'        ${DIRNAME}/buildroot/etc/ssh/sshd_config
    sed -i 's/#Port.*/Port 60022/g'                    ${DIRNAME}/buildroot/etc/ssh/sshd_config
    echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> ${DIRNAME}/buildroot/etc/ssh/sshd_config
    echo "MACs    hmac-sha1" >>                        ${DIRNAME}/buildroot/etc/ssh/sshd_config
    echo "PermitRootLogin yes">>                       ${DIRNAME}/buildroot/etc/ssh/sshd_config
}

systemd-nspawn -D ${DIRNAME}/buildroot/ systemctl disable rsync.service apt-daily-upgrade.timer apt-daily.timer || true

systemd-nspawn -b --network-veth --network-bridge=br-ext -D ${DIRNAME}/buildroot/ || true

systemd-nspawn -D ${DIRNAME}/buildroot/ apt clean

rm ${DIRNAME}/buildroot/dev/* ${DIRNAME}/buildroot/var/log/* -fr || true
# Remove all doc files
find "${DIRNAME}/buildroot/usr/share/doc" -depth -type f ! -name copyright -print0 | xargs -0 rm || true
find "${DIRNAME}/buildroot/usr/share/doc" -empty -print0 | xargs -0 rm -rf || true
# Remove all man pages and info files
rm -rf "${DIRNAME}/buildroot/usr/share/man" "${DIRNAME}/buildroot/usr/share/groff" "${DIRNAME}/buildroot/usr/share/info" "${DIRNAME}/buildroot/usr/share/lintian" "${DIRNAME}/buildroot/usr/share/linda" "${DIRNAME}/buildroot/var/cache/man" || true

trap '' EXIT TERM INT
echo "SUCCESS builde rootfs"
exit 0
