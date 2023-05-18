#!/usr/bin/env bash

password=tsd@2023

cat <<EOF
yum -y install ceph ceph-radosgw rbd-mirror rbd-nbd
yum -y groupinstall "Virtualization Host"
yum -y install telnet bridge-utils vconfig chrony
rpm -Uvh --oldpackage https://repo.huaweicloud.com/openeuler/openEuler-20.03-LTS-SP3/everything/x86_64/Packages/snappy-1.1.8-1.oe1.x86_64.rpm
usermod -G libvirt root
usermod -G libvirt admin

sed -i "/^\s*server\s/d" /etc/chrony.conf
sed -i "/^\s*pool\s/d" /etc/chrony.conf
sed -i "3 a server time.neusoft.com iburst" /etc/chrony.conf
EOF

for root_dir in ${*?need rootfs dirs}; do
    echo ${root_dir}
    # rm ${root_dir} -rf
    # unsquashfs -d ${root_dir} ${fn}
    # rm -fr ${root_dir}/usr/lib/firmware/*
    echo "nameserver 202.107.117.11" > ${root_dir}/etc/resolv.conf 
    cat <<'EOSHELL' | tee ${root_dir}/etc/rc.local
#!/bin/sh -e
exit 0
EOSHELL
    chmod 755 ${root_dir}/etc/rc.local
    chmod 755 ${root_dir}/etc/rc.d/rc.local
    sed -i '/motd.sh/d' ${root_dir}/etc/profile
    echo 'sh /etc/motd.sh' >> ${root_dir}/etc/profile
    touch ${root_dir}/etc/logo.txt ${root_dir}/etc/motd.sh
chroot "${root_dir}" /bin/bash -x <<EOSHELL
id admin || useradd -m -s /bin/bash admin
chage -d0 admin
passwd -d root
source /etc/os-release || true
case "\${ID:-}" in
    debian)
        echo "admin:${password}" |chpasswd
        ;;
    *)
        echo "${password}" | passwd --stdin admin
        yum -y remove security-tool || true
        ;;
esac
echo "add admin to sudoers"
# openeuler 20.03 sudoers not include sudoer.d
grep -q sudoers.d /etc/sudoers && echo OK || echo "#includedir /etc/sudoers.d" >> /etc/sudoers
echo "%admin ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/admin
chmod 0440 /etc/sudoers.d/admin
mkdir -p /home/admin/.config/libvirt
echo 'uri_default = "qemu:///system"' > /home/admin/.config/libvirt/libvirt.conf
chown admin:admin /home/admin/.config -R

yum clean all
EOSHELL

[ ! -d ${root_dir}/home/admin/.ssh ] && mkdir -m0700 ${root_dir}/home/admin/.ssh
    cat <<EOF >${root_dir}/home/admin/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDIcCEBlGLWfQ6p/6/QAR1LncKGlFoiNvpV3OUzPEoxJfw5ChIc95JSqQQBIM9zcOkkmW80ZuBe4pWvEAChdMWGwQLjlZSIq67lrpZiql27rL1hsU25W7P03LhgjXsUxV5cLFZ/3dcuLmhGPbgcJM/RGEqjNIpLf34PqebJYqPz9smtoJM3a8vDgG3ceWHrhhWNdF73JRzZiDo8L8KrDQTxiRhWzhcoqTWTrkj2T7PZs+6WTI+XEc8IUZg/4NvH06jHg8QLr7WoWUtFvNSRfuXbarAXvPLA6mpPDz7oRKB4+pb5LpWCgKnSJhWl3lYHtZ39bsG8TyEZ20ZAjluhJ143GfDBy8kLANSntfhKmeOyolnz4ePf4EjzE3WwCsWNrtsJrW3zmtMRab7688vrUUl9W2iY9venrW0w6UL7Cvccu4snHLaFiT6JSQSSJS+mYM5o8T0nfIzRi0uxBx4m9/6nVIl/gs1JApzgWyqIi3opcALkHktKxi76D0xBYAgRvJs= admin@liveos
EOF
    chmod 0600 ${root_dir}/home/admin/.ssh/authorized_keys
    chroot ${root_dir} chown admin:admin /home/admin/.ssh -R || true
    cat > ${root_dir}/etc/security/limits.d/tun.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
    cat <<EOF > ${root_dir}/etc/profile.d/os-security.sh
export readonly TMOUT=900
export readonly HISTFILE
export readonly HISTCONTROL=erasedups
EOF

    cat >${root_dir}/etc/profile.d/johnyin.sh<<"EOF"
# Not bash
[ -n "${BASH_VERSION:-}" ] || return 0
# Not an interactive shell?
[[ $- == *i* ]] || return 0

export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF

    cat << EOF > ${root_dir}/etc/sysctl.conf
fs.file-max = 1000000
net.ipv4.ping_group_range = 0   2147483647
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
#net.ipv4.ip_forward = 1
EOF
    cat << EOF > ${root_dir}/etc/sysctl.d/90-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    cat << EOF > ${root_dir}/etc/sysctl.d/90-perf.conf
kernel.sched_autogroup_enabled = 0
vm.min_free_kbytes = 131072
sysctl vm.dirty_ratio = 60
EOF
    cat <<"EOF" > ${root_dir}/etc/ssh/sshrc
logger -i -t ssh "$(date '+%Y%m%d%H%M%S') $USER $SSH_CONNECTION"
EOF
    [ ! -d ${root_dir}/root/.ssh ] && mkdir -m0700 ${root_dir}/root/.ssh
    cat <<EOF >${root_dir}/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0600 ${root_dir}/root/.ssh/authorized_keys

    cat <<EOF > ${root_dir}/etc/sysconfig/network-scripts/ifcfg-eth0 
DEVICE="eth0"
ONBOOT="yes"
IPV6INIT=no
BOOTPROTO="none"
MASTER=bond0
SLAVE=yes
EOF
    cat <<EOF > ${root_dir}/etc/sysconfig/network-scripts/ifcfg-bond0
DEVICE=bond0
NAME=bond0
TYPE=Bond
ONBOOT=yes
BOOTPROTO=none
BONDING_MASTER=yes
TYPE=Ethernet
BONDING_OPTS="mode=802.3ad miimon=100 xmit_hash_policy=layer3+4"
# below for temp use, when switch in trunk mode, remove it
IPADDR=192.168.168.2
PREFIX=24
GATEWAY=192.168.168.1
EOF
    cat <<EOF > ${root_dir}/etc/sysconfig/network-scripts/ifcfg-bond0.3006 
DEVICE="bond0.3006"
ONBOOT="yes"
BRIDGE="br-ext"
VLAN=yes
EOF
    cat <<EOF > ${root_dir}/etc/sysconfig/network-scripts/ifcfg-br-ext
DEVICE="br-ext"
ONBOOT="yes"
TYPE="Bridge"
BOOTPROTO="none"
#STP="on"
EOF
    rm -f ${root_dir}/root/.bash_history ${root_dir}/admin/.bash_history
    find ${root_dir}/var/log/ -type f | xargs -I@ truncate -s0 @
    ./tpl_pack.sh -c xz ${root_dir}/ ${root_dir}.tpl
done
