#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("netns-busybox-pxe-efi-server.sh - 99bb60a - 2021-01-20T14:41:56+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
readonly DVD_DIR="centos_dvd"
#readonly DHCP_UEFI_BOOTFILE="BOOTX64.efi" #centos 6
readonly DHCP_UEFI_BOOTFILE="shim.efi"
readonly DHCP_BIOS_BOOTFILE="pxelinux.0"
readonly DHCP_BOOTFILE="booter"

#soft link here !
readonly BUSYBOX="busybox"
readonly DVD_IMG="CentOS-7-x86_64-Minimal.iso"
readonly PXELINUX="ldlinux.c32 menu.c32 libutil.c32 pxelinux.0 "
readonly EFILINUX="grubx64.efi shim.efi"

readonly ROOTFS="${DIRNAME}/pxeroot"
#ROOTFS=$(mktemp -d --tmpdir=/${DIRNAME})
readonly PXE_DIR="/tftp" #abs path in chroot env
readonly UEFI_KS_URI="uefi.ks.cfg"
readonly BIOS_KS_URI="bios.ks.cfg"

mk_busybox_fs() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local busybox_bin="$1"
    local rootfs="$2"
    for d in /var/lib/misc /var/run /etc /lib /bin /dev /root /proc; do
        try mkdir -p ${rootfs}/$d
    done
    try cp ${busybox_bin} ${rootfs}/bin/busybox && try chmod 755 ${rootfs}/bin/busybox
    file_exists ${rootfs}/dev/random  || try mknod -m 0644 ${rootfs}/dev/random c 1 8
    file_exists ${rootfs}/dev/urandom || try mknod -m 0644 ${rootfs}/dev/urandom c 1 9
    file_exists ${rootfs}/dev/null    || try mknod -m 0666 ${rootfs}/dev/null c 1 3

    try cat \> ${rootfs}/etc/profile << EOF
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
export PS1="\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]**bios/uefi**:\\[\\033[33;1m\\]\\w\\[\\033[m\\]\\$"
alias bios='/bin/busybox cp -f ${PXE_DIR}/${DHCP_BIOS_BOOTFILE}  ${PXE_DIR}/${DHCP_BOOTFILE}'
alias uefi='/bin/busybox cp -f ${PXE_DIR}/${DHCP_UEFI_BOOTFILE}  ${PXE_DIR}/${DHCP_BOOTFILE}'
alias ll='/bin/busybox ls -lh'
echo "add ${PXE_DIR}/cgi-bin/ipaddr.txt for ipaddr: 192.168.168.2/24 line by line"
echo "cmd : bios/uefi change mode"
/bin/sh /start.sh
EOF
    try cat \> ${rootfs}/etc/passwd << EOF
root:x:0:0:root:/root:/bin/sh
EOF
    try chroot ${rootfs} /bin/busybox --install -s /bin
    return 0
}

gen_busybox_inetd() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local dhcp_bootfile="$1"
    local rootfs="$2"
    local ns_ipaddr="$3"
    local pxe_dir="$4"

    try mkdir -p ${rootfs}/${pxe_dir}/
    for cmd in tftpd httpd ftpd udhcpd; do
        ${rootfs}/bin/busybox --list | grep $cmd > /dev/null && debug_msg "check $cmd ok\n" || exit_msg "check $cmd error"
    done
    link_exists ${rootfs}/bin/tftpd  || try ln -s /bin/busybox ${rootfs}/bin/tftpd
    link_exists ${rootfs}/bin/httpd  || try ln -s /bin/busybox ${rootfs}/bin/httpd
    link_exists ${rootfs}/bin/ftpd   || try ln -s /bin/busybox ${rootfs}/bin/ftpd
    link_exists ${rootfs}/bin/udhcpd || try ln -s /bin/busybox ${rootfs}/bin/udhcpd

    try cat \> ${rootfs}/etc/inetd.conf << INETEOF
69 dgram udp nowait root tftpd tftpd -l ${pxe_dir}
80 stream tcp nowait root httpd httpd -i -h ${pxe_dir}
21 stream tcp nowait root ftpd ftpd ${pxe_dir}
INETEOF

    try cat \> ${rootfs}/etc/udhcpd.conf << DHCPEOF
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
    try mkdir -p ${rootfs}/${pxe_dir}/cgi-bin/
    try cat <<'CGIEOF' \> ${rootfs}/${pxe_dir}/cgi-bin/reg.cgi
#!/bin/sh
# CGI output must start with at least empty line (or headers)
printf '\r\n'
ipaddr=$(head -1 ipaddr.txt 2>/dev/null)
sed -i '1d' ipaddr.txt > /dev/null 2>&1
prefix=${ipaddr##*/}
ipaddr=${ipaddr%/*}
#$REQUEST_METHOD
cat <<EOF >> req.txt
$QUERY_STRING === ${ipaddr:-192.168.168.100}/${prefix:-24}
EOF
printf "IPADDR=${ipaddr:-192.168.168.100}\n"
printf "PREFIX=${prefix:-24}\n"
printf "GATEWAY=\${IPADDR%%.*}.1\n"
CGIEOF
    try chmod 755 ${rootfs}/${pxe_dir}/cgi-bin/reg.cgi

    return 0
}

kill_ns_inetd() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local rootfs="$1"
    file_exists "${rootfs}/var/run/inetd.pid"  && try kill -9 $(cat ${rootfs}/var/run/inetd.pid)
    file_exists "${rootfs}/var/run/udhcpd.pid" && try kill -9 $(cat ${rootfs}/var/run/udhcpd.pid)
    return 0
}

start_ns_inetd() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    local rootfs="$2"
    maybe_netns_run "mount -t proc none /proc" "${ns_name}" "${rootfs}" || return 3
    cat<<EOF>"${rootfs}/start.sh"
    start-stop-daemon -S -b -q -x /bin/udhcpd
    start-stop-daemon -S -b -q -x  /bin/inetd
EOF
    try chmod 755 "${rootfs}/start.sh"
}

del_ns() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    #try brctl delif br-ext ${ns_name}-eth1
    maybe_netns_bridge_dellink ${ns_name}-eth1 "" || true
    cleanup_ns "${ns_name}" || true
    try rm -rf "/etc/netns/${ns_name}" || true
    return 0
}

add_ns() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    local host_br="$2"
    local ns_ipaddr="$3"
    setup_ns "${ns_name}" || return 4
    maybe_netns_setup_veth ${ns_name}-eth0 ${ns_name}-eth1 "" || return 4
    maybe_netns_bridge_addlink "${host_br}" "${ns_name}-eth1" "" || return 4
    maybe_netns_addlink "${ns_name}-eth0" "${ns_name}" "eth0" || return 4
    maybe_netns_run "ip address add ${ns_ipaddr}/24 dev eth0" "${ns_name}" || return 4
    return 0
}

extract_bios_pxelinux() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local dvdroot="$1"
    local dest="$2"
    for fn in ${PXELINUX}; do 
        try cp "${DIRNAME}/$fn" "${dest}"
    done
    return 0
}

#grub2-efi-x64*.x86_64.rpm shim-x64*.x86_64.rpm 
extract_efi_grub() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local dvdroot="$1"
    local dest="$2"
    for fn in ${EFILINUX}; do 
        try cp "${DIRNAME}/$fn" "${dest}"
    done
    return 0
}

gen_pxelinux_cfg() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local pxelinux_cfg="$1"
    local ns_ipaddr="$2"
    local ks_uri="$3"
    #http://mirrors.163.com/debian/dists/Debian10.3/main/installer-amd64/current/images/netboot/netboot.tar.gz
    try cat \> ${pxelinux_cfg} <<EOF
default menu.c32
prompt 0
timeout 300
ONTIMEOUT 3
menu title ########## PXE Boot Menu ##########
label 1
menu label ^1) Install Centos [BIOS] PXE+Kickstart
kernel ${DVD_DIR}/images/pxeboot/vmlinuz
append initrd=${DVD_DIR}/images/pxeboot/initrd.img ks=http://${ns_ipaddr}/${ks_uri} net.ifnames=0 biosdevname=0

label 2
menu label ^2) Install Debian [BIOS] PXE
kernel /debian/linux
append initrd=/debian/initrd.gz vga=788 --- quiet

label 3
menu label ^3) Boot from local drive
localboot 0xffff
EOF
    return 0
}

gen_grub_cfg() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local menulst="$1"
    local ns_ipaddr="$2"
    local ks_uri="$3"
    try cat \> ${menulst} <<EOF
set timeout=30
set default="0"
menuentry 'Install Centos [UEFI] PXE+Kickstart' {
    linuxefi ${DVD_DIR}/images/pxeboot/vmlinuz ks=http://${ns_ipaddr}/${ks_uri} net.ifnames=0 biosdevname=0
    initrdefi ${DVD_DIR}/images/pxeboot/initrd.img
}
menuentry 'Install Debian [UEFI] PXE' {
    linuxefi /debian/linux vga=788 --- quiet
    initrdefi /debian/initrd.gz
}
menuentry 'Start' {
    boot
}
EOF
    return 0
}

gen_kickstart() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local kscfg="$1"
    local ns_ipaddr="$2"
    local boot_driver="$3"
    local ks_uri="$4"
    local lvm=$5
    local efi=$6
    local ipaddr=$7
    local prefix=${ipaddr##*/}
    ipaddr=${ipaddr%/*}
    vinfo_msg <<EOF
ipaddress: ${ipaddr}/${prefix}
boot disk: ${boot_driver}
      efi: ${efi}
      lvm: ${lvm}
EOF

    try cat \> ${kscfg} <<KSEOF
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

    try cat \>\> ${kscfg} <<'KSEOF'
#rootpw --plaintext password
rootpw --iscrypted $6$Tevn5ihz1h7MHhMV$Zt7r1ocJqZXhNfVntdsDuGWU42BkQKdpqp0EosOhaYS46zzOEcYALmH5mkDWoYmRvFBs0lBNM/LUiGJAmmx7Q.
#password

firewall --disabled
authconfig --enableshadow --passalgo=sha512
selinux --disabled
# services --enabled=NetworkManager,sshd
reboot
timezone  Asia/Shanghai

#user --groups=wheel --name=admin --plaintext --password=password
KSEOF

    try cat \>\> ${kscfg} <<KSEOF
# Delete all partitions
clearpart --all --initlabel
# Delete MBR / GPT
zerombr
bootloader --location=mbr --driveorder=${boot_driver} --append=" console=ttyS0 net.ifnames=0 biosdevname=0"

$( [[ ${efi} = "true" ]] && echo "part     /boot/efi  --fstype=vfat --size=50 --ondisk=${boot_driver}")
part     /boot      --fstype="xfs"  --size=200 --ondisk=${boot_driver}
$(if [ "${lvm:=false}" = "true" ]; then
    echo "part     pv.01                      --size=1500 --ondisk=${boot_driver}"
    echo "volgroup vg_root pv.01"
    echo "logvol   /          --fstype=xfs  --size=1500 --name=lv_root --vgname=vg_root"
else
    echo "part     /          --fstype=xfs  --size=1500 --ondisk=${boot_driver}"
fi)
# part pv.02 --size=2048
# volgroup vg_swap pv.02
# logvol swap --vgname=vg_swap --size=1 --grow --name=lv_swap
KSEOF

    try cat \>\> ${kscfg} <<KSEOF
%packages
@core
lvm2
net-tools
chrony
-alsa-*
-iwl*firmware
-ivtv*
%end
KSEOF
    try cat \>\> ${kscfg} <<KSEOF
%addon com_redhat_kdump --disable --reserve-mb='auto'
%end
KSEOF
    try cat \>\> ${kscfg} <<KSEOF
%post
echo "tuning sysytem!!"
curl http://${ns_ipaddr}/${ks_uri}.init.sh 2>/dev/null | bash
%end
KSEOF

    try cat \> ${kscfg}.init.sh <<'INITEOF'
#!/bin/bash

UUID="$(dmidecode -s system-uuid)"
SN="$(dmidecode -s system-serial-number | sed 's/[ &?]/-/g')"
PROD="$(dmidecode -s system-product-name | sed 's/[ &?]/-/g')"

INITEOF
    try cat \>\> ${kscfg}.init.sh <<INITEOF
IPADDR=${ipaddr}
PREFIX=${prefix}
GATEWAY=
curl -o /tmp/inst_info "http://${ns_ipaddr}/cgi-bin/reg.cgi?UUID=\${UUID}&SN=\${SN}&PROD=\${PROD}"
source /tmp/inst_info
INITEOF
    try cat \>\> ${kscfg}.init.sh <<'INITEOF'
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
GRUB_CMDLINE_LINUX="console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
EOF

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=${IPADDR}
PREFIX=${PREFIX}
GATEWAY=${GATEWAY}
#DNS1=10.0.2.1
EOF
cat > /etc/sysconfig/network-scripts/route-eth0 <<-EOF
#xx.xx.xx.xx via xxx dev eth0
EOF
### Add SSH public key
if [ ! -d /root/.ssh ]; then
    mkdir -m0700 /root/.ssh
fi
cat <<EOF >/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
chmod 0600 /root/.ssh/authorized_keys

systemctl set-default multi-user.target
systemctl enable getty@tty1

netsvc=network
[[ -r /etc/os-release ]] && source /etc/os-release
[[ ${VERSION_ID:-} = 8 ]] && sed -i "/NM_CONTROLLED=/d" /etc/sysconfig/network-scripts/ifcfg-eth0
[[ ${VERSION_ID:-} = 8 ]] && netsvc=NetworkManager

chkconfig 2>/dev/null | egrep -v "crond|sshd|${netsvc}|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep enabled | egrep -v "${netsvc}|getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash
INITEOF
    return 0
}

error_clean() {
    local rootfs="$1";shift 1
    local ns_name="$1";shift 1
    local pxe_dir="$1";shift 1
    try umount ${rootfs}/${pxe_dir}/${DVD_DIR}/ || true
    kill_ns_inetd "${rootfs}" 1>/dev/null 2>&1 || true
    del_ns ${ns_name} 1>/dev/null 2>&1 || true
    exit_msg "clean over! $* error\n";
}

check_depend() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local host_br=$1
    file_exists "/sys/class/net/$host_br" || exit_msg "$host_br bridge no found!!\n"
    for fn in $PXELINUX $EFILINUX $BUSYBOX $DVD_IMG; do
        file_exists "${DIRNAME}/$fn" || exit_msg "${DIRNAME}/$fn no found!!\n"
    done
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -b|--bridge    *    <local bridge> local bridge
        -n|--ns             <ns name>   default pxe_ns
        -i|--ns_ip          <ns ipaddr> default 172.16.16.2
        --disk              <disn name> default vda
        --lvm               use lvm     default not use lvm
        --guest_ipaddr      <guest ip>  default 192.168.168.101/24
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local IPADDR=${IPADDR:-"192.168.168.101/24"}
    local LVM=${LVM:-false}
    local DISK=${DISK:-"vda"}
    local ns_ipaddr=${NS_IPADDR:-"172.16.16.2"}
    local ns_name=${NS_NAME:-"pxe_ns"}
    local host_br=
    local opt_short="b:n:i:"
    local opt_long="bridge:,ns:,ns_ip:,disk:,lvm,guest_ipaddr:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -b | --bridge)  shift; host_br=${1}; shift;;
            -n | --ns)      shift; ns_name=${1}; shift;;
            -i | --ns_ip)   shift; ns_ipaddr=${1}; shift;;
            --disk)         shift; DISK=${1}; shift;;
            --lvm)          shift; LVM=true;;
            --guest_ipaddr) shift; IPADDR=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [[ -z "${host_br}" ]] && usage "bridge must input"
    bridge_exists "${host_br}" || exit_msg "bridge no found\n"
    check_depend ${host_br}
    try mkdir -p ${ROOTFS}
    mk_busybox_fs "${DIRNAME}/${BUSYBOX}" "${ROOTFS}"
    gen_busybox_inetd "${DHCP_BOOTFILE}" "${ROOTFS}" "${ns_ipaddr}" "${PXE_DIR}"
    try mkdir -p ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/ && try mount "${DIRNAME}/${DVD_IMG}" "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" 2\>/dev/null
    try mkdir -p "${ROOTFS}/${PXE_DIR}/"
    gen_grub_cfg "${ROOTFS}/${PXE_DIR}/grub.cfg" "${ns_ipaddr}" "${UEFI_KS_URI}"
    gen_kickstart "${ROOTFS}/${PXE_DIR}/${UEFI_KS_URI}" "${ns_ipaddr}" "${DISK}" "${UEFI_KS_URI}" ${LVM} true "${IPADDR}"
    extract_efi_grub "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" "${ROOTFS}/${PXE_DIR}/" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "extract_efi_grub $?"

    try mkdir -p "${ROOTFS}/${PXE_DIR}/pxelinux.cfg/" 
    gen_pxelinux_cfg "${ROOTFS}/${PXE_DIR}/pxelinux.cfg/default" "${ns_ipaddr}" "${BIOS_KS_URI}"
    gen_kickstart "${ROOTFS}/${PXE_DIR}/${BIOS_KS_URI}" "${ns_ipaddr}" "${DISK}" "${BIOS_KS_URI}" ${LVM} false "${IPADDR}"
    extract_bios_pxelinux "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" "${ROOTFS}/${PXE_DIR}/" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "extract_bios_pxelinux $?"

    add_ns ${ns_name} ${host_br} "${ns_ipaddr}" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "add netns $?"
    start_ns_inetd ${ns_name} "${ROOTFS}" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "start inetd $?"
    maybe_netns_shell "busybox" "${ns_name}" "${ROOTFS}" "busybox" "sh -l"
    try umount ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/ || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "umount $?"
    kill_ns_inetd "${ROOTFS}"|| error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "kill inetd $?"
    del_ns ${ns_name}
    info_msg "Exit success\n"
    return 0
}
main "$@"
