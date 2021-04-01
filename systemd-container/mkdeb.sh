#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("mkdeb.sh - 61b321a - 2021-03-31T13:42:14+08:00")
################################################################################
source ${DIRNAME}/os_debian_init.sh

INST_ARCH=${INST_ARCH:-amd64}
REPO=http://mirrors.163.com/debian
PASSWORD=password
NAME_SERVER=114.114.114.114
DEBIAN_VERSION=${DEBIAN_VERSION:-buster}
HOSTNAME="docker"

PKG="systemd-container,openssh-server,openssh-client,rsync"

mkdir -p ${DIRNAME}/buildroot
mkdir -p ${DIRNAME}/cache

debian_build "${DIRNAME}/buildroot" "${DIRNAME}/cache" "${PKG}"

LC_ALL=C LANGUAGE=C LANG=C chroot ${DIRNAME}/buildroot /bin/bash <<EOSHELL
    apt update
    debian_sshd_init

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

useradd -m -s /bin/bash johnyin
debian_chpasswd johnyin ${PASSWORD}

exit 0
EOSHELL

systemd-nspawn -D ${DIRNAME}/buildroot/ systemctl disable rsync.service apt-daily-upgrade.timer apt-daily.timer || true

systemd-nspawn -b --network-veth --network-bridge=br-ext -D ${DIRNAME}/buildroot/ || true

LC_ALL=C LANGUAGE=C LANG=C chroot "${DIRNAME}/buildroot/" /bin/bash <<EOSHELL
    debian_minimum_init
EOSHELL

echo "SUCCESS builde rootfs"
exit 0
