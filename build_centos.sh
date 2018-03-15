#!/bin/bash
set -o errexit -o nounset -o pipefail

ADDITION_PKG="lvm2 wget rsync" #sysstat
ADDITION_PKG="${ADDITION_PKG} bind-utils sysstat tcpdump nmap-ncat telnet lsof unzip ftp wget strace ltrace python-virtualenv"
ROOTFS=${ROOTFS:-/root/rootfs}
NEWPASSWORD=${NEWPASSWORD:-"password"}
DISK_FILE=${DISK_FILE:-"/root/disk"}
DISK_SIZE=${DISK_SIZE:-"1500"}       #MB

NAME=${NAME:-"vmtemplate"}
IP=${IP:-"10.0.2.100"}
NETMASK=${NETMASK:-"255.255.255.0"}
GW=${GW:-"10.0.2.1"}

#for demo
: ${ROOTFS:?"ERROR: ROOTFS must be set"}

trap 'for mp in /dev /sys /proc; do umount ${ROOTFS}${mp}; done; umount ${ROOTFS}; losetup -D; rm -f /tmp/local.repo;echo "EXIT"' EXIT

YUM_OPT="-q --nogpgcheck --config=/tmp/local.repo --disablerepo=* --enablerepo=centos" #--setopt=tsflags=nodocs"
cat> /tmp/local.repo <<EOF
[centos]
name=centos
baseurl=http://10.0.2.1:8080/
failovermethod=priority
gpgcheck=0
EOF

function change_vm_info() {
    local mnt_point=$1
    local guest_hostname=$2
    local guest_ipaddr=$3
    local guest_netmask=$4
    local guest_gw=$5
    local guest_uuid=$6

    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
#DNS1=10.0.2.1
IPADDR=${guest_ipaddr}
NETMASK=${guest_netmask}
#GATEWAY=${guest_gw}
EOF
    cat > ${mnt_point}/etc/sysconfig/network-scripts/route-eth0 <<-EOF
default via ${guest_gw} dev eth0
EOF
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost
${guest_ipaddr}    ${guest_hostname}
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { return 1; }
    [[ -r "${mnt_point}/etc/johnyin" ]] && chattr -i ${mnt_point}/etc/johnyin 
    echo "$(date +%Y%m%d_%H%M%S) ${guest_uuid}" > ${mnt_point}/etc/johnyin || { return 2; }
    chattr +i ${mnt_point}/etc/johnyin || { return 3; }
    #sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"console=ttyS0 net.ifnames=0 biosdevname=0\"/g" /etc/default/grub
    #grub2-mkconfig -o /boot/grub2/grub.cfg
	sed -i "s/#ListenAddress 0.0.0.0/ListenAddress ${guest_ipaddr}/g" ${mnt_point}/etc/ssh/sshd_config
    rm -f ${mnt_point}/ssh/ssh_host_*
    return 0
}

truncate -s ${DISK_SIZE}M ${DISK_FILE} 
#dd if=/dev/zero of=${DISK_FILE} bs=1M count=${DISK_SIZE}

parted -s ${DISK_FILE} -- mklabel msdos \
	mkpart primary xfs 2048s -1s \
	set 1 boot on

fdisk -l ${DISK_FILE}
DISK=$(losetup -fP --show ${DISK_FILE})
MOUNTDEV=${DISK}p1
mkfs.xfs -L rootfs ${MOUNTDEV} >/dev/null
UUID=`blkid -s UUID -o value ${MOUNTDEV}`
FSTYPE=`blkid -s TYPE -o value ${MOUNTDEV}`

mkdir -p ${ROOTFS}
mount ${MOUNTDEV} ${ROOTFS}
yum ${YUM_OPT} -y --installroot=${ROOTFS} install filesystem
for mp in /dev /sys /proc
do
    mount -o bind ${mp} ${ROOTFS}${mp}
done

# can edit  /root/rootfs/etc/yum.repos.d/....
yum ${YUM_OPT} -y --installroot=${ROOTFS} groupinstall core #"Minimal Install"
yum ${YUM_OPT} -y --installroot=${ROOTFS} install grub2 net-tools chrony ${ADDITION_PKG}
yum ${YUM_OPT} -y --installroot=${ROOTFS} -C -y remove --setopt="clean_requirements_on_remove=1" \
	firewalld \
	NetworkManager \
	NetworkManager-team \
	NetworkManager-tui \
	NetworkManager-wifi \
	aic94xx-firmware \
	alsa-firmware \
	ivtv-firmware \
	iwl100-firmware \
	iwl1000-firmware \
	iwl105-firmware \
	iwl135-firmware \
	iwl2000-firmware \
	iwl2030-firmware \
	iwl3160-firmware \
	iwl3945-firmware \
	iwl4965-firmware \
	iwl5000-firmware \
	iwl5150-firmware \
	iwl6000-firmware \
	iwl6000g2a-firmware \
	iwl6000g2b-firmware \
	iwl6050-firmware \
	iwl7260-firmware \
	iwl7265-firmware

cat > ${ROOTFS}/etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*\$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttyS0 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
EOF
echo "UUID=${UUID} / xfs defaults 0 0" > ${ROOTFS}/etc/fstab

cat > ${ROOTFS}/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "cn"
EndSection
EOF
echo 'KEYMAP="cn"' > ${ROOTFS}/etc/vconsole.conf

chroot ${ROOTFS} /bin/bash -x <<EOF
rm -f /etc/locale.conf /etc/localtime /etc/hostname /etc/machine-id /etc/.pwd.lock
systemd-firstboot --root=/ --locale=zh_CN.utf8 --locale-messages=zh_CN.utf8 --timezone="Asia/Shanghai" --hostname="localhost" --setup-machine-id
#localectl set-locale LANG=zh_CN.UTF-8
#localectl set-keymap cn
#localectl set-x11-keymap cn
grub2-mkconfig -o /boot/grub2/grub.cfg
grub2-install --boot-directory=/boot --modules="xfs part_msdos" /dev/loop0
echo "${NEWPASSWORD}" | passwd --stdin root
sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
touch /etc/sysconfig/network
systemctl enable getty@tty1
touch /*
touch /etc/*
touch /boot/*
EOF

# chroot ${ROOTFS} yum upgrade

echo "tuning system ....."

chroot ${ROOTFS} /bin/bash -x <<EOF
systemctl set-default multi-user.target
echo "disable services START"
chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",\$1,"off"}' | bash
systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", \$1}' | bash
echo "disable services OK"
EOF
echo "nameserver 114.114.114.114" > ${ROOTFS}/etc/resolv.conf
#set the file limit
cat >> ${ROOTFS}/etc/security/limits.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
echo "disable the ipv6"
cat > ${ROOTFS}/etc/modprobe.d/ipv6.conf << EOF
install ipv6 /bin/true
EOF
#set ssh
sed -i 's/#UseDNS.*/UseDNS no/g' ${ROOTFS}/etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' ${ROOTFS}/etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/g' ${ROOTFS}/etc/ssh/sshd_config
echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> ${ROOTFS}/etc/ssh/sshd_config
echo "MACs    hmac-sha1" >> ${ROOTFS}/etc/ssh/sshd_config
#tune kernel parametres
cat >> ${ROOTFS}/etc/sysctl.conf << EOF
net.core.netdev_max_backlog = 30000
net.core.rmem_max=16777216
net.core.somaxconn = 65535
net.core.wmem_max=16777216
net.ipv4.ip_local_port_range = 1024 65500
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
cat >> ${ROOTFS}/etc/profile << EOF
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$"
export readonly PROMPT_COMMAND='{ msg=\$(history 1 | { read x y; echo \$y; });user=\$(whoami); echo \$(date "+%Y-%m-%d%H:%M:%S"):\$user:`pwd`/:\$msg ---- \$(who am i); } >> \$HOME/.history.'
set -o vi
EOF
change_vm_info "${ROOTFS}" "${NAME}" "${IP}" "${NETMASK}" "${GW}" "${UUID}"

for mp in /dev /sys /proc
do
    umount ${ROOTFS}${mp}
done
rm -f /tmp/local.repo
umount ${ROOTFS}
losetup -d ${DISK}
exit 0
# #extract a single partition from image
# dd if=image of=partitionN skip=offset_of_partition_N count=size_of_partition_N bs=512 conv=sparse
# #put the partition back into image
# dd if=partitionN of=image seek=offset_of_partition_N count=size_of_partition_N bs=512 conv=sparse,notrunc

# #linear.table起始扇区  扇区个数  线性映射  目标设备 目标设备上的起始扇区
# 0     2048     linear /dev/loop0  0
# 2048  2095104  linear /dev/loop1  0

# #kpartx -au hdr
# #kpartx -au data
# #dmsetup create linear_test linear.table
# dmsetup remove_all
