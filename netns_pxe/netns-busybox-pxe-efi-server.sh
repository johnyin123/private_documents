#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d8346a19[2023-09-22T10:18:42+08:00]:netns-busybox-pxe-efi-server.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
NBD_ROOT=${NBD_ROOT:-"LABEL=rootfs"}
NBD_SRV=${NBD_SRV:-192.168.168.1:9999/tpl}
# ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:<dns0-ip>:<dns1-ip>:<ntp0-ip>
NBD_IP=${NBD_IP:-192.168.168.198::192.168.168.1:255.255.255.0:mysrv:eth0}
DHCP_START=${DHCP_START:-201}
DHCP_END=${DHCP_END:-221}
DHCP_NETMASK=${DHCP_NETMASK:-255.255.255.0}

readonly DVD_DIR="centos_dvd"
# nbd rootfs need apt install nbd-client
readonly NBD_DIR="nbd"
#readonly DHCP_UEFI_BOOTFILE="BOOTX64.efi" #centos 6
readonly DHCP_UEFI_BOOTFILE="shim.efi"
readonly DHCP_UEFI_BOOTFILE_ARM64="grubaa64.efi"
readonly DHCP_BIOS_BOOTFILE="pxelinux.0"
readonly DHCP_BOOTFILE="booter"

#soft link here !
readonly BUSYBOX="busybox"
readonly DVD_IMG="CentOS-x86_64.iso"
readonly PXELINUX="ldlinux.c32 menu.c32 libutil.c32 pxelinux.0 "
readonly EFILINUX="grubx64.efi shim.efi grubaa64.efi"

readonly ROOTFS="${DIRNAME}/pxeroot"
#ROOTFS=$(mktemp -d --tmpdir=/${DIRNAME})
readonly PXE_DIR="/tftp" #abs path in chroot env
readonly UEFI_KS_URI="uefi.ks.cfg"
readonly BIOS_KS_URI="bios.ks.cfg"

mk_busybox_fs() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local busybox_bin="$1"
    local rootfs="$2"
    for d in /var/lib/misc /var/run /etc /lib /sbin /bin /dev /root /proc; do
        try mkdir -p ${rootfs}/$d
    done
    try cp ${busybox_bin} ${rootfs}/bin/busybox && try chmod 755 ${rootfs}/bin/busybox
    file_exists ${rootfs}/dev/random  || try mknod -m 0644 ${rootfs}/dev/random c 1 8
    file_exists ${rootfs}/dev/urandom || try mknod -m 0644 ${rootfs}/dev/urandom c 1 9
    file_exists ${rootfs}/dev/null    || try mknod -m 0666 ${rootfs}/dev/null c 1 3
    write_file ${rootfs}/etc/profile << EOF
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
export PS1="\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]**bios/uefi**:\\[\\033[33;1m\\]\\w\\[\\033[m\\]\\$"
alias bios='/bin/busybox cp -f ${PXE_DIR}/${DHCP_BIOS_BOOTFILE}  ${PXE_DIR}/${DHCP_BOOTFILE}'
alias uefi='/bin/busybox cp -f ${PXE_DIR}/${DHCP_UEFI_BOOTFILE}  ${PXE_DIR}/${DHCP_BOOTFILE}'
alias arm64_uefi='/bin/busybox cp -f ${PXE_DIR}/${DHCP_UEFI_BOOTFILE_ARM64}  ${PXE_DIR}/${DHCP_BOOTFILE}'
alias ll='/bin/busybox ls -lh'
echo 'echo ,+ | sfdisk --force -u S -N 1 /dev/vda'
echo 'echo ,4G | sfdisk --force --unit S --partno 1 /dev/vda'
echo 'echo ,+2G | sfdisk --force --unit S --partno 1 /dev/vda'
echo 'partx -u /dev/vda'
echo 'xfs_growfs /dev/vda1'
echo "add ${PXE_DIR}/cgi-bin/ipaddr.txt for ipaddr: 192.168.168.101/24 line by line"
echo "cmd : bios/uefi/arm64_uefi change mode"
/bin/sh /start.sh
EOF
    write_file ${rootfs}/etc/passwd << EOF
root:x:0:0:root:/root:/bin/sh
EOF
    # for d in /var/lib/misc /var/run /etc /lib /dev /root /proc /usr/bin /usr/sbin /sys /tmp; do
    #     try mkdir -p ${rootfs}/$d
    # done
    # ln -s usr/bin ${rootfs}/bin
    # ln -s usr/sbin ${rootfs}/sbin
    # maybe_netns_run "/bin/busybox --install -s" "" "${rootfs}"
    local als
    for als in $(${rootfs}/bin/busybox --list-long); do
        als="${als#/}"
        case "$als" in
            # strip leading /usr, we don't use it
            usr/*) als="${als#usr/}" ;;
            */*) ;;
            *) als="bin/$als" ;;  # make it into /bin
        esac
        [ -e "${rootfs}/$als" ] || try ln -s /bin/busybox ${rootfs}/$als
    done
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

    write_file ${rootfs}/etc/inetd.conf << INETEOF
69 dgram udp nowait root tftpd tftpd -l ${pxe_dir}
80 stream tcp nowait root httpd httpd -i -h ${pxe_dir}
21 stream tcp nowait root ftpd ftpd ${pxe_dir}
INETEOF

    write_file ${rootfs}/etc/udhcpd.conf << DHCPEOF
start           ${ns_ipaddr%.*}.${DHCP_START}
end             ${ns_ipaddr%.*}.${DHCP_END}
interface       eth0
siaddr          ${ns_ipaddr}
boot_file       ${dhcp_bootfile}
opt     dns     ${ns_ipaddr} 114.114.114.114
option  subnet  ${DHCP_NETMASK}
opt     router  ${ns_ipaddr}
opt     wins    ${ns_ipaddr}
option  domain  local
option  lease   864000
DHCPEOF
    try mkdir -p ${rootfs}/${pxe_dir}/cgi-bin/
    write_file ${rootfs}/${pxe_dir}/cgi-bin/reg.cgi <<'CGIEOF'
#!/bin/sh
# CGI output must start with at least empty line (or headers)
printf '\r\n'
ipaddr=$(head -1 ipaddr.txt 2>/dev/null)
sed -i '1d' ipaddr.txt > /dev/null 2>&1
prefix=${ipaddr##*/}
ipaddr=${ipaddr%/*}
prefix=${prefix:-24}
ipaddr=${ipaddr:-192.168.168.101}
#$REQUEST_METHOD
cat <<EOF >> req.txt
$QUERY_STRING === ${ipaddr}/${prefix}
EOF
printf "IPADDR=${ipaddr}\n"
printf "PREFIX=${prefix}\n"
printf "GATEWAY=${ipaddr%.*}.1\n"
CGIEOF
    try chmod 755 ${rootfs}/${pxe_dir}/cgi-bin/reg.cgi
    touch ${rootfs}/${pxe_dir}/cgi-bin/ipaddr.txt
    touch ${rootfs}/${pxe_dir}/cgi-bin/req.txt
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
    write_file "${rootfs}/start.sh" <<EOF
mount -t proc none /proc
rm -f /dhcpd.log
nohup udhcpd -f > /dhcpd.log 2>&1 &
# start-stop-daemon -S -b -q -x udhcpd
start-stop-daemon -S -b -q -x inetd
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
    local ns_ipaddr_prefix=${4:-24}
    setup_ns "${ns_name}" || return 4
    maybe_netns_setup_veth ${ns_name}-eth0 ${ns_name}-eth1 "" || return 4
    maybe_netns_bridge_addlink "${host_br}" "${ns_name}-eth1" "" || return 4
    maybe_netns_addlink "${ns_name}-eth0" "${ns_name}" "eth0" || return 4
    maybe_netns_run "ip address add ${ns_ipaddr}/${ns_ipaddr_prefix} dev eth0" "${ns_name}" || return 4
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
    write_file ${pxelinux_cfg} <<EOF
default menu.c32
prompt 0
timeout 300
ONTIMEOUT 4
menu title ########## PXE Boot Menu ##########
label 1
menu label ^1) Install Centos [BIOS] PXE+Kickstart
kernel ${DVD_DIR}/images/pxeboot/vmlinuz
append initrd=${DVD_DIR}/images/pxeboot/initrd.img inst.ks=http://${ns_ipaddr}/${ks_uri} inst.lang=en_US net.ifnames=0 biosdevname=0

label 2
menu label ^2) Install Debian [BIOS] PXE
kernel /debian/linux
append initrd=/debian/initrd.gz vga=788 --- quiet

label 3
menu label ^3) NBD ROOTFS Debian
kernel /${NBD_DIR}/vmlinuz
append initrd=/${NBD_DIR}/initrd.img nbddev=/dev/nbd0 nbdroot=${NBD_SRV} ip=${NBD_IP} root=${NBD_ROOT} net.ifnames=0 console=ttyAML0,115200n8 console=lty0

label 4
menu label ^4) Boot from local drive
localboot 0xffff
EOF
    return 0
}

gen_grub_cfg() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local menulst="$1"
    local ns_ipaddr="$2"
    local ks_uri="$3"
    write_file ${menulst} <<EOF
set timeout=30
set default="0"
menuentry 'Install Centos [UEFI] PXE+Kickstart' {
    linuxefi ${DVD_DIR}/images/pxeboot/vmlinuz inst.ks=http://${ns_ipaddr}/${ks_uri} inst.lang=en_US net.ifnames=0 biosdevname=0
    initrdefi ${DVD_DIR}/images/pxeboot/initrd.img
}
menuentry 'Install Centos [UEFI-aarch64] PXE+Kickstart' {
    linux ${DVD_DIR}/images/pxeboot/vmlinuz inst.ks=http://${ns_ipaddr}/${ks_uri} inst.lang=en_US net.ifnames=0 biosdevname=0
    initrd ${DVD_DIR}/images/pxeboot/initrd.img
}
menuentry 'Install Debian [UEFI] PXE' {
    linuxefi /debian/linux vga=788 --- quiet
    initrdefi /debian/initrd.gz
}
menuentry 'NBD ROOTFS Debian [UEFI]' {
    linuxefi /${NBD_DIR}/vmlinuz nbddev=/dev/nbd0 nbdroot=${NBD_SRV} ip=${NBD_IP} root=${NBD_ROOT} net.ifnames=0 console=ttyAML0,115200n8 console=tty1
    initrdefi /${NBD_DIR}/initrd.img
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
    local root_size=$7
    vinfo_msg <<EOF
boot disk: ${boot_driver}
      efi: ${efi}
      lvm: ${lvm}
EOF

    write_file ${kscfg} <<KSEOF
# graphical
text
firstboot --enable

url --url="http://${ns_ipaddr}/${DVD_DIR}/"

lang zh_CN.UTF-8
keyboard --xlayouts='cn'
network --onboot yes --bootproto dhcp --noipv6
network --hostname=server1
rootpw --plaintext password

firewall --disabled
selinux --disabled
# services --enabled=NetworkManager,sshd
reboot
timezone  Asia/Shanghai
# user --groups=wheel --name=admin --plaintext --password=password

# Delete all partitions
clearpart --all --initlabel --drives=${boot_driver}
# Delete MBR / GPT
zerombr
bootloader --location=mbr --driveorder=${boot_driver} --append=" console=ttyS0,115200n8 console=tty1 net.ifnames=0 biosdevname=0"
$( [ "${efi}" = "true" ] && echo "part     /boot/efi  --fstype=vfat --size=50 --ondisk=${boot_driver}")
$(if [ "${lvm:=false}" = "true" ]; then
    echo "part     /boot      --fstype=xfs  --size=200 --ondisk=${boot_driver}"
    echo "part     pv.01                    --size=${root_size} --ondisk=${boot_driver}"
    echo "volgroup vg_root pv.01"
    echo "logvol   /          --fstype=xfs  --size=1 --grow --name=lv_root --vgname=vg_root"
else
    echo "part     /          --fstype=xfs  --size=${root_size} --ondisk=${boot_driver}"
fi)

%packages
@core
lvm2
net-tools
chrony
tar
rsync
-alsa-*
-iwl*firmware
-ivtv*
%end

%post
# %post --interpreter=/bin/bash
echo "tuning sysytem!!"
curl http://${ns_ipaddr}/${ks_uri}.init.sh 2>/dev/null | bash
%end
KSEOF

    write_file ${kscfg}.init.sh <<'INITEOF'
#!/bin/bash

UUID="$(dmidecode -s system-uuid | sed 's/[ &?]/-/g')"
SN="$(dmidecode -s system-serial-number | sed 's/[ &?]/-/g')"
PROD="$(dmidecode -s system-product-name | sed 's/[ &?]/-/g')"

INITEOF
    write_file ${kscfg}.init.sh 1 <<INITEOF
curl -o /tmp/inst_info "http://${ns_ipaddr}/cgi-bin/reg.cgi?UUID=\${UUID}&SN=\${SN}&PROD=\${PROD}"
source /tmp/inst_info
INITEOF
    write_file ${kscfg}.init.sh 1 <<'INITEOF'
cat <<EOF > /etc/profile.d/os-security.sh
export readonly TMOUT=900
export readonly HISTFILE
EOF

cat >/etc/profile.d/johnyin.sh<<"EOF"
# Not bash
[ -n "${BASH_VERSION:-}" ] || return 0
# Not an interactive shell?
[[ $- == *i* ]] || return 0

export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF

#disable selinux
sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

#set sshd
sed -i 's/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/#Port.*/Port 60022/' /etc/ssh/sshd_config
sed -i 's/GSSAPIAuthentication.*/GSSAPIAuthentication no/g' /etc/ssh/sshd_config

cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=${IPADDR:-192.168.168.101}
PREFIX=${PREFIX:-24}
GATEWAY=${GATEWAY:-}
#DNS1=10.0.2.1
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
systemctl status NetworkManager.service >/dev/null 2>&1 && {
    sed -i "/NM_CONTROLLED=/d" /etc/sysconfig/network-scripts/ifcfg-eth0
    netsvc="NetworkManager.service dbus-broker.service haveged.service"
}
{
    chkconfig 2>/dev/null | egrep -v "crond|sshd|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}'
    systemctl list-unit-files -t service  | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}'
    for _s in ${netsvc}; do echo "systemctl enable $_s"; done
} | bash -x

echo "nameserver 114.114.114.114" > /etc/resolv.conf
cat << EOF > /etc/hosts
127.0.0.1       localhost $(cat /etc/hostname)
EOF

# service=(crond|sshd|NetworkManager|network|rsyslog|sysstat)
# chkconfig --list | awk '{ print $1 }' | xargs -n1 -I@ chkconfig @ off
# echo ${service[@]} | xargs -n1 | xargs -I@ chkconfig @ on
# echo ${service[@]} | xargs -n1 | xargs -I@ systemctl enable @
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
        ** all depends files: busybox-pxe-efi-server.depends.tar.gz **
            Centos7,Centos8,Rocky 8
        default values:
            NBD_ROOT="LABEL=rootfs"
            NBD_SRV=192.168.168.1:9999/tpl
            NBD_IP=192.168.168.198::192.168.168.1:255.255.255.0:mysrv:eth0
            DHCP_START=201
            DHCP_END=221
            DHCP_NETMASK=255.255.255.0

        -b|--bridge    *    <local bridge> local bridge
        -n|--ns             <ns name>   default pxe_ns
        -i|--ns_ip          <ns ipaddr> default 172.16.16.2/24
        --disk              <disn name> default vda
        --size              rootfs size (MB) default 4096
        --lvm               use lvm     default not use lvm
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local lvm=false
    local disk="vda"
    local ns_ipaddr="172.16.16.2"
    local ns_ipaddr_prefix=""
    local ns_name="pxe_ns"
    local host_br=
    local root_size=4096
    local opt_short="b:n:i:"
    local opt_long="bridge:,ns:,ns_ip:,disk:,lvm,size:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -b | --bridge)  shift; host_br=${1}; shift;;
            -n | --ns)      shift; ns_name=${1}; shift;;
            -i | --ns_ip)
                shift;
                ns_ipaddr=$(awk -F'/' '{print $1}' <<< "$1")
                ns_ipaddr_prefix=$(awk -F'/' '{print $2}' <<< "$1")
                shift
                ;;
            --disk)         shift; disk=${1}; shift;;
            --size)         shift; root_size=${1}; shift;;
            --lvm)          shift; lvm=true;;
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
    check_depend ${host_br}
    try mkdir -p ${ROOTFS}
    mk_busybox_fs "${DIRNAME}/${BUSYBOX}" "${ROOTFS}"
    gen_busybox_inetd "${DHCP_BOOTFILE}" "${ROOTFS}" "${ns_ipaddr}" "${PXE_DIR}"
    try mkdir -p ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/ && try mount "${DIRNAME}/${DVD_IMG}" "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" 2\>/dev/null
    try mkdir -p "${ROOTFS}/${PXE_DIR}/${NBD_DIR}"
    try mkdir -p "${ROOTFS}/${PXE_DIR}/"
    gen_grub_cfg "${ROOTFS}/${PXE_DIR}/grub.cfg" "${ns_ipaddr}" "${UEFI_KS_URI}"
    gen_kickstart "${ROOTFS}/${PXE_DIR}/${UEFI_KS_URI}" "${ns_ipaddr}" "${disk}" "${UEFI_KS_URI}" ${lvm} true "${root_size}"
    extract_efi_grub "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" "${ROOTFS}/${PXE_DIR}/" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "extract_efi_grub $?"

    try mkdir -p "${ROOTFS}/${PXE_DIR}/pxelinux.cfg/" 
    gen_pxelinux_cfg "${ROOTFS}/${PXE_DIR}/pxelinux.cfg/default" "${ns_ipaddr}" "${BIOS_KS_URI}"
    gen_kickstart "${ROOTFS}/${PXE_DIR}/${BIOS_KS_URI}" "${ns_ipaddr}" "${disk}" "${BIOS_KS_URI}" ${lvm} false "${root_size}"
    extract_bios_pxelinux "${ROOTFS}/${PXE_DIR}/${DVD_DIR}/" "${ROOTFS}/${PXE_DIR}/" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "extract_bios_pxelinux $?"

    add_ns ${ns_name} ${host_br} "${ns_ipaddr}" "${ns_ipaddr_prefix}"|| error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "add netns $?"
    start_ns_inetd ${ns_name} "${ROOTFS}" || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "start inetd $?"
    maybe_netns_shell "busybox" "${ns_name}" "${ROOTFS}" "busybox" "sh -l"
    try umount ${ROOTFS}/${PXE_DIR}/${DVD_DIR}/ || error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "umount $?"
    kill_ns_inetd "${ROOTFS}"|| error_clean "${ROOTFS}" "${ns_name}" "${PXE_DIR}" "kill inetd $?"
    del_ns ${ns_name}
    info_msg "Exit success\n"
    return 0
}
main "$@"
