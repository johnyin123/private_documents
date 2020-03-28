#!/bin/bash
set -o nounset -o pipefail
set -o errexit

export LANG=C

BASEDIR="$(readlink -f "$(dirname "$0")")"

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

PXE_NS=pxe
PXE_IP=192.168.1.1
EXT_BRIDGE=br-ext
DVD=/home/johnyin/disk/iso/CentOS-7-x86_64-Everything-1708.iso
BUSYBOX=/home/johnyin/disk/private/shell/busybox-tools/busybox
PXELINUX_DIR=${BASEDIR}/pxelinux/

mkdir -p ${BASEDIR}/var/lib/misc/ ${BASEDIR}/var/run ${BASEDIR}/etc ${BASEDIR}/lib
mkdir -p ${BASEDIR}/bin/ ${BASEDIR}/dev/ ${BASEDIR}/tftpd/dvdrom/ ${BASEDIR}/tftpd/pxelinux.cfg/

for cmd in tftpd httpd ftpd udhcpd
do
    ${BUSYBOX} --list | grep $cmd > /dev/null && echo "check $cmd ok" || { echo "check $cmd error"; exit 1; }
done

cp ${BUSYBOX} ${BASEDIR}/bin/
cp ${PXELINUX_DIR}/* ${BASEDIR}/tftpd/

[ -e ${BASEDIR}/bin/tftpd   ] || ln -s /bin/busybox ${BASEDIR}/bin/tftpd
[ -e ${BASEDIR}/bin/httpd   ] || ln -s /bin/busybox ${BASEDIR}/bin/httpd
[ -e ${BASEDIR}/bin/ftpd    ] || ln -s /bin/busybox ${BASEDIR}/bin/ftpd
[ -e ${BASEDIR}/bin/udhcpd  ] || ln -s /bin/busybox ${BASEDIR}/bin/udhcpd

[ -e ${BASEDIR}/dev/random  ] || mknod -m 0644 ${BASEDIR}/dev/random c 1 8
[ -e ${BASEDIR}/dev/urandom ] || mknod -m 0644 ${BASEDIR}/dev/urandom c 1 9
[ -e ${BASEDIR}/dev/null    ] || mknod -m 0666 ${BASEDIR}/dev/null c 1 3
[ -e ${BASEDIR}/etc/profile ] || {
    cat > ${BASEDIR}/etc/profile << EOF
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
export PS1="\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]**${PXE_NS}**:\\[\\033[33;1m\\]\\w\\[\\033[m\\]\\$"
alias ll='/bin/busybox ls -lh'
EOF
}
[ -e ${BASEDIR}/etc/passwd ] || {
    cat > ${BASEDIR}/etc/passwd << EOF
root:x:0:0:root:/tftpd:/bin/sh
EOF
}
[ -e ${BASEDIR}/etc/inetd.conf ] || {
    cat > ${BASEDIR}/etc/inetd.conf << EOF
69 dgram udp nowait root tftpd tftpd -l /tftpd/
80 stream tcp nowait root httpd httpd -i -h /tftpd/
21 stream tcp nowait root ftpd ftpd /tftpd/
EOF
}
[ -e ${BASEDIR}/etc/udhcpd.conf ] || {
    cat > ${BASEDIR}/etc/udhcpd.conf << EOF
start           ${PXE_IP%.*}.20
end             ${PXE_IP%.*}.254
interface       eth0
siaddr          ${PXE_IP} 
boot_file       pxelinux.0
opt     dns     ${PXE_IP} 114.114.114.114
option  subnet  255.255.255.0
opt     router  ${PXE_IP}
opt     wins    ${PXE_IP} 
option  domain  local
option  lease   864000
EOF
}

[ -e ${BASEDIR}/tftpd/ks.cfg ] || {
    cat > ${BASEDIR}/tftpd/ks.cfg <<KSEOF
firewall --disabled
install

text
firstboot --enable

url --url="http://${PXE_IP}/dvdrom/"
KSEOF

    cat >> ${BASEDIR}/tftpd/ks.cfg <<'KSEOF'
lang zh_CN.UTF-8
keyboard us
network --onboot yes --bootproto dhcp --noipv6
network --hostname=server1
rootpw  --iscrypted $6$Tevn5ihz1h7MHhMV$Zt7r1ocJqZXhNfVntdsDuGWU42BkQKdpqp0EosOhaYS46zzOEcYALmH5mkDWoYmRvFBs0lBNM/LUiGJAmmx7Q.
#password

firewall --disabled
authconfig --enableshadow --passalgo=sha512
selinux --disabled
# services --enabled=NetworkManager,sshd
#
# Reboot after installation
reboot
#timezone --utc America/New_York
timezone  Asia/Shanghai

#user --groups=wheel --name=admin --password=password

bootloader --location=mbr --driveorder=sda --append=" console=ttyS0 net.ifnames=0 biosdevname=0"
# The following is the partition information you requested
# Note that any partitions you deleted are not expressed
# here so unless you clear all partitions first, this is
# not guaranteed to work
#clearpart --none
#ignoredisk --only-use=sda

#part / --fstype=ext4 --grow --size=200
clearpart --all
# part / --asprimary --size=2048 --ondisk=vda
# part swap --asprimary --size=1024 --ondisk=vda
# lvm 
part /boot --fstype="xfs" --size=200
part pv.01 --size=1500 --grow
volgroup vg_root pv.01
logvol / --vgname=vg_root --size=1500 --name=lv_root
# part pv.02 --size=2048
# volgroup vg_swap pv.02
# logvol swap --vgname=vg_swap --size=1 --grow --name=lv_swap                

#part / --fstype ext4 --size=100 --grow --ondisk=sda
#net.ifnames=0 biosdevname=0 ...........eth0
#grub2-mkconfig -o /boot/grub2/grub.cfg
%packages
@core
lvm2
bridge-utils
wget
rsync
bind-utils
sysstat
tcpdump
nmap-ncat
telnet
lsof
unzip
ftp
wget
curl
strace
ltrace
python-virtualenv
net-tools
chrony
traceroute
lrzsz
iotop

%end
KSEOF

    cat >> ${BASEDIR}/tftpd/ks.cfg <<KSEOF
%post
curl http://${PXE_IP}/init.sh 2>/dev/null | bash
%end
KSEOF
}

[ -e ${BASEDIR}/tftpd/init.sh ] || {
    cat > ${BASEDIR}/tftpd/init.sh <<'INITEOF'
#!/bin/bash
# echo "闲置用户在 15 分钟后会被删除"
echo "export readonly TMOUT=900" >> /etc/profile.d/os-security.sh
echo "export readonly HISTFILE" >> /etc/profile.d/os-security.sh
chmod 755 /etc/profile.d/os-security.sh

cat >/etc/profile.d/johnyin.sh<<"EOF"
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF
chmod 755 /etc/profile.d/johnyin.sh

cat >> /etc/security/limits.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
#disable selinux
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
#set sshd
sed -i 's/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/' /etc/ssh/sshd_config
sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config
sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/g' /etc/ssh/sshd_config
echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
echo "MACs    hmac-sha1" >> /etc/ssh/sshd_config
#tune kernel parametres
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
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_tw_reuse = 0
EOF
cp /etc/default/grub /root/grub.default
cat > /etc/default/grub <<'EOF'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttyS0 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
EOF

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
#DNS1=10.0.2.1
IPADDR=10.0.2.168
PREFIX=24
GATEWAY=10.0.2.1
EOF
cat > /etc/sysconfig/network-scripts/route-eth0 <<-EOF
#xx.xx.xx.xx via xxx dev eth0
EOF

systemctl set-default multi-user.target
systemctl enable getty@tty1
chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash
INITEOF
}
[ -e ${BASEDIR}/tftpd/pxelinux.cfg/default ] || {
    cat > ${BASEDIR}/tftpd/pxelinux.cfg/default <<EOF
default menu.c32
prompt 0
timeout 60
ONTIMEOUT 1
menu title ########## PXE Boot Menu ##########
label 1
menu label ^1) Install CentOS 7 x64 with Local Repo
kernel /dvdrom/images/pxeboot/vmlinuz
append initrd=/dvdrom/images/pxeboot/initrd.img ks=http://${PXE_IP}/ks.cfg net.ifnames=0 biosdevname=0
label 2
menu label ^2) Boot from local drive
localboot 0xffff
EOF
}

ip netns add ${PXE_NS}
ip netns exec ${PXE_NS} ip link set dev lo up
#ip netns exec ${PXE_NS} sysctl -w net.ipv4.conf.default.forwarding=1
ip link add ${PXE_NS}-eth0 type veth peer name ${PXE_NS}-eth1
#brctl addif br-ext ${PXE_NS}-eth1
ip link set dev ${PXE_NS}-eth1 promisc on
ip link set dev ${PXE_NS}-eth1 up
ip link set dev ${PXE_NS}-eth1 master ${EXT_BRIDGE}

ip link set ${PXE_NS}-eth0 netns ${PXE_NS}
ip netns exec ${PXE_NS} ip link set dev ${PXE_NS}-eth0 name eth0 up
ip netns exec ${PXE_NS} ip address add ${PXE_IP}/24 dev eth0
# ip netns exec ${PXE_NS} ip route add default via 10.32.166.1 dev eth0

mount ${DVD} ${BASEDIR}/tftpd/dvdrom/
# mount -t proc none /proc
# mount -t devtmpfs none /dev
# mount -t devpts none /dev/pts
# mount -t tmpfs none /run

# ip netns exec ${PXE_NS} chroot ${BASEDIR} /usr/sbin/dnsmasq --user=root --group=root
ip netns exec ${PXE_NS} chroot ${BASEDIR} /bin/busybox udhcpd 
ip netns exec ${PXE_NS} chroot ${BASEDIR} /bin/busybox inetd
ip netns exec ${PXE_NS} chroot ${BASEDIR} /bin/busybox sh -l

umount ${BASEDIR}/tftpd/dvdrom/

kill -9 $(cat ${BASEDIR}/var/run/inetd.pid)
kill -9 $(cat ${BASEDIR}/var/run/udhcpd.pid)
#brctl delif br-ext ${PXE_NS}-eth1
ip link set ${PXE_NS}-eth1 promisc off
ip link set ${PXE_NS}-eth1 down
ip link set dev ${PXE_NS}-eth1 nomaster

ip netns del ${PXE_NS}
ip link delete ${PXE_NS}-eth1

echo "for dnsmasq version support UEFI and more"
cat << 'EOF'
########################################
## mod_install_server
log-dhcp
log-queries
# interface selection
interface=$INTERFACE_ETH0
#bridge#interface=$INTERFACE_BR0
# NTP Server
dhcp-option=$INTERFACE_ETH0, option:ntp-server, 0.0.0.0
#bridge#dhcp-option=$INTERFACE_BR0, option:ntp-server, 0.0.0.0
# TFTP_ETH0 (enabled)
enable-tftp
#tftp-lowercase
tftp-root=$DST_TFTP_ETH0/, $INTERFACE_ETH0
#bridge#tftp-root=$DST_TFTP_ETH0_BR0/, $INTERFACE_BR0
# DHCP
# do not give IPs that are in pool of DSL routers DHCP
dhcp-range=$INTERFACE_ETH0, $IP_ETH0_START, $IP_ETH0_END, 24h
#bridge#dhcp-range=$INTERFACE_BR0, $IP_BR0_START, $IP_BR0_END, 24h
dhcp-option=$INTERFACE_ETH0, option:tftp-server, $IP_ETH0
#bridge#dhcp-option=$INTERFACE_BR0, option:tftp-server, $IP_BR0
# DNS (enabled)
port=53
dns-loop-detect
# PXE (enabled)
# warning: unfortunately, a RPi3 identifies itself as of architecture x86PC (x86PC=0)
# luckily the RPi3 seems to use always the same UUID 44444444-4444-4444-4444-444444444444
dhcp-match=set:UUID_RPI3, option:client-machine-id, 00:44:44:44:44:44:44:44:44:44:44:44:44:44:44:44:44
dhcp-match=set:ARCH_0, option:client-arch, 0
dhcp-match=set:x86_UEFI, option:client-arch, 6
dhcp-match=set:x64_UEFI, option:client-arch, 7
dhcp-match=set:x64_UEFI, option:client-arch, 9
# test if it is a RPi3 or a regular x86PC
tag-if=set:ARM_RPI3, tag:ARCH_0, tag:UUID_RPI3
tag-if=set:x86_BIOS, tag:ARCH_0, tag:!UUID_RPI3
pxe-service=tag:ARM_RPI3,0, \"Raspberry Pi Boot   \", bootcode.bin
pxe-service=tag:x86_BIOS,x86PC, \"PXE Boot Menu (BIOS 00:00)\", $DST_PXE_BIOS/lpxelinux
pxe-service=6, \"PXE Boot Menu (UEFI 00:06)\", $DST_PXE_EFI32/bootia32.efi
pxe-service=x86-64_EFI, \"PXE Boot Menu (UEFI 00:07)\", $DST_PXE_EFI64/bootx64.efi
pxe-service=9, \"PXE Boot Menu (UEFI 00:09)\", $DST_PXE_EFI64/bootx64.efi
dhcp-boot=tag:ARM_RPI3, bootcode.bin
dhcp-boot=tag:x86_BIOS, $DST_PXE_BIOS/lpxelinux.0
dhcp-boot=tag:x86_UEFI, $DST_PXE_EFI32/bootia32.efi
dhcp-boot=tag:x64_UEFI, $DST_PXE_EFI64/bootx64.efi
EOF
cat <<EOF
# Don't function as a DNS server
port=0
enable-tftp
tftp-root=/srv/tftpboot/
# Boot file
dhcp-boot=/srv/tftpboot/pxelinux.0
# Kill multicast
dhcp-option=vendor:PXECleint,6,2b
# Disable re-use of DHCP servername and filename fields as extra options space
dhcp-no-override
#
pxe-service=X86PC, "Boot from network...", /srv/tftpboot/pxelinux
pxe-service=X86PC, "Boot from local hard drive", 0
pxe-service=X86-64_EFI, "Boot from network...", /srv/tftpboot/EFIx64/syslinux.efi
pxe-service=IA64_EFI, "Boot from network...", /srv/tftpboot/EFIia64/syslinux.efi
dhcp-range=10.10.10.2,proxy,255.255.255.0
EOF
exit 0
