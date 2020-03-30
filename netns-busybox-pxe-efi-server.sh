#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
readonly DVD_DIR="centos_dvd"
#readonly DHCP_BOOTFILE="BOOTX64.efi" #centos 6
readonly DHCP_BOOTFILE="shim.efi"
#soft link here !
readonly BUSYBOX="${DIRNAME}/busybox"
readonly DVD_IMG="${DIRNAME}/CentOS-7-x86_64-Minimal.iso"
readonly ROOTFS="${DIRNAME}/pxeroot"
readonly PXE_DIR="/tftp" #abs path in chroot env
readonly KS_URI="uefi.ks.cfg"

mk_busybox_fs() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local busybox_bin="$1"
    local rootfs="$2"
    for d in /var/lib/misc /var/run /etc /lib /bin /dev /root; do
        try mkdir -p ${rootfs}/$d
    done
    try cp ${busybox_bin} ${rootfs}/bin/busybox && try chmod 755 ${rootfs}/bin/busybox
    [ -e ${rootfs}/dev/random  ] || try mknod -m 0644 ${rootfs}/dev/random c 1 8
    [ -e ${rootfs}/dev/urandom ] || try mknod -m 0644 ${rootfs}/dev/urandom c 1 9
    [ -e ${rootfs}/dev/null    ] || try mknod -m 0666 ${rootfs}/dev/null c 1 3

        cat > ${rootfs}/etc/profile << EOF
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
export PS1="\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]**busybox**:\\[\\033[33;1m\\]\\w\\[\\033[m\\]\\$"
alias ll='/bin/busybox ls -lh'
EOF
        cat > ${rootfs}/etc/passwd << EOF
root:x:0:0:root:/root:/bin/sh
EOF
    try chroot ${rootfs} /bin/busybox --install -s /bin
    return 0
}

gen_busybox_inetd() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local dhcp_bootfile="$1"
    local rootfs="$2"
    local ns_ipaddr="$3"
    local pxe_dir="$4"

    mkdir -p ${rootfs}/${pxe_dir}/
    for cmd in tftpd httpd ftpd udhcpd; do
        ${rootfs}/bin/busybox --list | grep $cmd > /dev/null && info_msg "check $cmd ok\n" || exit_msg "check $cmd error"
    done
    [ -e ${rootfs}/bin/tftpd   ] || try ln -s /bin/busybox ${rootfs}/bin/tftpd
    [ -e ${rootfs}/bin/httpd   ] || try ln -s /bin/busybox ${rootfs}/bin/httpd
    [ -e ${rootfs}/bin/ftpd    ] || try ln -s /bin/busybox ${rootfs}/bin/ftpd
    [ -e ${rootfs}/bin/udhcpd  ] || try ln -s /bin/busybox ${rootfs}/bin/udhcpd

        cat > ${rootfs}/etc/inetd.conf << INETEOF
69 dgram udp nowait root tftpd tftpd -l ${pxe_dir}
80 stream tcp nowait root httpd httpd -i -h ${pxe_dir}
21 stream tcp nowait root ftpd ftpd ${pxe_dir}
INETEOF

        cat > ${rootfs}/etc/udhcpd.conf << DHCPEOF
start           ${ns_ipaddr%.*}.201
end             ${ns_ipaddr%.*}.221
interface       eth0
siaddr          ${ns_ipaddr}
boot_file       ${dhcp_bootfile}
opt     dns     ${ns_ipaddr} 114.114.114.114
option  subnet  255.255.255.0
opt     router  ${ns_ipaddr}
opt     wins    ${ns_ipaddr}
option  domain  local
option  lease   864000
DHCPEOF

    return 0
}

kill_ns_inetd() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local rootfs="$1"
    [ -e "${rootfs}/var/run/inetd.pid" ] && try kill -9 $(cat ${rootfs}/var/run/inetd.pid)
    [ -e "${rootfs}/var/run/udhcpd.pid" ] && try kill -9 $(cat ${rootfs}/var/run/udhcpd.pid)
    return 0
}

start_ns_inetd() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    local rootfs="$2"
    # ip netns exec ${ns_name} chroot ${rootfs} /usr/sbin/dnsmasq --user=root --group=root
    try ip netns exec ${ns_name} chroot ${rootfs} /bin/busybox udhcpd || return 1
    try ip netns exec ${ns_name} chroot ${rootfs} /bin/busybox inetd || return 2
    return 0
}

del_ns() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    #try brctl delif br-ext ${ns_name}-eth1
    try ip link set ${ns_name}-eth1 promisc off || true
    try ip link set ${ns_name}-eth1 down || true
    try ip link set dev ${ns_name}-eth1 nomaster || true
    try ip netns del ${ns_name} || true
    ip link delete ${ns_name}-eth1 || true
    try rm -rf "/etc/netns/${ns_name}" || true
    return 0
}

add_ns() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    local host_br="$2"
    local ns_ipaddr="$3"
    try ip netns add ${ns_name} || return 4
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo || return 4
    try ip netns exec ${ns_name} ip link set lo up || return 4
    try ip link add ${ns_name}-eth0 type veth peer name ${ns_name}-eth1 || return 4
    #try brctl addif br-ext ${ns_name}-eth1
    try ip link set dev ${ns_name}-eth1 promisc on || return 4
    try ip link set dev ${ns_name}-eth1 up || return 4
    try ip link set dev ${ns_name}-eth1 master ${host_br} || return 4
    try ip link set ${ns_name}-eth0 netns ${ns_name} || return 4
    ip netns exec ${ns_name} ip link set dev ${ns_name}-eth0 name eth0 up || return 4
    ip netns exec ${ns_name} ip address add ${ns_ipaddr}/24 dev eth0 || return 4
    return 0
}

extract_efi_grub() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local dvdroot="$1"
    local dest="$2"
    local tmpdir=${dest}/tmp_efi
    local efipkg="grub2-efi-x64*.x86_64.rpm shim-x64*.x86_64.rpm"
    try mkdir -p "${tmpdir}"
    for pkg in ${efipkg}; do
        try rpm2cpio ${dvdroot}/Packages/${pkg} \| cpio -id -D ${tmpdir}
    done
    try find ${tmpdir} -name grubx64.efi \| xargs -I@ cp @  "${dest}"
    try find ${tmpdir} -name shim.efi \| xargs -I@ cp @  "${dest}"/shim.efi
    try rm -rf "${tmpdir}"
    return 0
}

gen_grub_cfg() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local menulst="$1"
    local ns_ipaddr="$2"
    local ks_uri="$3"
        cat > ${menulst} <<EOF
set timeout=30
set default="0"
menuentry 'Install Centos [UEFI] PXE+Kickstart' {
    linuxefi ${DVD_DIR}/images/pxeboot/vmlinuz ks=http://${ns_ipaddr}/${ks_uri} net.ifnames=0 biosdevname=0
    initrdefi ${DVD_DIR}/images/pxeboot/initrd.img
}
menuentry 'Start' {
    boot
}
EOF
    return 0
}

gen_kickstart() {
    info_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local kscfg="$1"
    local ns_ipaddr="$2"
    local boot_driver="$3"
    local ks_uri="$4"
    local lvm=$5
    local ipaddr=$6
    local prefix=${ipaddr##*/}
    ipaddr=${ipaddr%/*}
    info_msg "os ipaddress: ${ipaddr}/${prefix}\n"
    info_msg "   boot disk: ${boot_driver}\n"
    info_msg "         lvm: ${lvm}\n"
    cat > ${kscfg} <<KSEOF
firewall --disabled
install

text
firstboot --enable

url --url="http://${ns_ipaddr}/${DVD_DIR}/"

lang zh_CN.UTF-8
keyboard us
network --onboot yes --bootproto dhcp --noipv6
network --hostname=server1
KSEOF

    cat >> ${kscfg} <<'KSEOF'
rootpw  --iscrypted $6$Tevn5ihz1h7MHhMV$Zt7r1ocJqZXhNfVntdsDuGWU42BkQKdpqp0EosOhaYS46zzOEcYALmH5mkDWoYmRvFBs0lBNM/LUiGJAmmx7Q.
#password

firewall --disabled
authconfig --enableshadow --passalgo=sha512
selinux --disabled
# services --enabled=NetworkManager,sshd
reboot
timezone  Asia/Shanghai

#user --groups=wheel --name=admin --password=password
KSEOF

    cat >> ${kscfg} <<KSEOF
# Delete all partitions
clearpart --all --initlabel
# Delete MBR / GPT
zerombr
bootloader --location=mbr --driveorder=${boot_driver} --append=" console=ttyS0 net.ifnames=0 biosdevname=0"

part     /boot/efi  --fstype="vfat" --size=50
part     /boot      --fstype="xfs"  --size=200
$(if [ "${lvm:=false}" = "true" ]; then
    echo "part     pv.01                      --size=1500 --grow"
    echo "volgroup vg_root pv.01"
    echo "logvol   /          --fstype="xfs"  --size=1500 --name=lv_root --vgname=vg_root"
else
    echo "part     /          --fstype="xfs"  --size=1500 --grow"
fi)
# part pv.02 --size=2048
# volgroup vg_swap pv.02
# logvol swap --vgname=vg_swap --size=1 --grow --name=lv_swap
KSEOF

    cat >> ${kscfg} <<KSEOF
%packages
@core
lvm2
net-tools
chrony
%end
KSEOF
    cat >> ${kscfg} <<KSEOF
%addon com_redhat_kdump --disable --reserve-mb='auto'
%end
KSEOF
    cat >> ${kscfg} <<KSEOF
%post
echo "tuning sysytem!!"
curl http://${ns_ipaddr}/${ks_uri}.init.sh 2>/dev/null | bash
%end
KSEOF

    cat > ${kscfg}.init.sh <<'INITEOF'
#!/bin/bash
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
INITEOF
    cat >> ${kscfg}.init.sh <<INITEOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
#DNS1=10.0.2.1
IPADDR=${ipaddr}
PREFIX=${prefix}
#GATEWAY=172.16.16.1
EOF
cat > /etc/sysconfig/network-scripts/route-eth0 <<-EOF
#xx.xx.xx.xx via xxx dev eth0
EOF
INITEOF
    cat >> ${kscfg}.init.sh <<'INITEOF'
### Add SSH public key cloudkey.pub for Ansible login after reboot
if [ ! -d /root/.ssh ]; then
    mkdir -m0700 /root/.ssh
fi
cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
# set permissions
chmod 0600 /root/.ssh/authorized_keys

systemctl set-default multi-user.target
systemctl enable getty@tty1
chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash
INITEOF
    return 0
}

error_clean() {
    local rootfs="$1";shift 1
    local ns_name="$1";shift 1
    local pxe_dir="$1";shift
    umount ${rootfs}/${pxe_dir}/${DVD_DIR}/
    kill_ns_inetd "${rootfs}"
    del_ns ${ns_name}
    exit_msg "$* error";
}

main() {
    local HOST_BR=${1:-"br-ext"}
    local IPADDR=${IPADDR:-"192.168.168.101/24"}
    local LVM=${LVM:-false}
    local DISK=${DISK:-"vda"}
    local NS_IPADDR=${NS_IPADDR:-"172.16.16.2"}
    local NS_NAME=${NS_NAME:-"pxe_ns"}
    mkdir -p ${ROOTFS}
    mk_busybox_fs "${BUSYBOX}" "${ROOTFS}"
    gen_busybox_inetd "${DHCP_BOOTFILE}" "${ROOTFS}" "${NS_IPADDR}" "${PXE_DIR}"
    try mkdir -p "${ROOTFS}/${PXE_DIR}/"
    gen_grub_cfg "${ROOTFS}/${PXE_DIR}/grub.cfg" "${NS_IPADDR}" "${KS_URI}"
    gen_kickstart "${ROOTFS}/${PXE_DIR}/${KS_URI}" "${NS_IPADDR}" "${DISK}" "${KS_URI}" ${LVM} "${IPADDR}"
    try mkdir -p ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/ && try mount ${DVD_IMG} ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/
    extract_efi_grub "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" "${ROOTFS}/${PXE_DIR}/"

    add_ns ${NS_NAME} ${HOST_BR} "${NS_IPADDR}" || error_clean "${ROOTFS}" ${NS_NAME} "add netns $?"
    start_ns_inetd ${NS_NAME} "${ROOTFS}" || error_clean "${ROOTFS}" ${NS_NAME} "start inetd $?"

    ip netns exec ${NS_NAME} chroot "${ROOTFS}" /bin/busybox sh -l || true

    try umount ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/ || error_clean "${ROOTFS}" ${NS_NAME} "${PXE_DIR}" "umount $?"
    kill_ns_inetd "${ROOTFS}"|| error_clean "${ROOTFS}" ${NS_NAME} "kill inetd $?"
    del_ns ${NS_NAME}
    return 0
}
main "$@"
