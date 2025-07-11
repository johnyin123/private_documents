#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d8346a19[2023-09-22T10:18:42+08:00]:build_centos.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
cat <<"EOF"
sed -e 's|^mirrorlist=|#mirrorlist=|g' \
    -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.sjtug.sjtu.edu.cn/rocky|g' \
    -i.bak \
    /etc/yum.repos.d/Rocky-*.repo
恢复官方源：
sed -e 's|^#mirrorlist=|mirrorlist=|g' \
    -e 's|^baseurl=https://mirrors.sjtug.sjtu.edu.cn/rocky|#baseurl=http://dl.rockylinux.org/$contentdir|g' \
    -i.bak \
    /etc/yum.repos.d/Rocky-*.repo
EOF

: <<'EOF'
# Create a folder for our new root structure
$ export centos_root='/centos_image/rootfs'
$ mkdir -p $centos_root
# initialize rpm database
$ rpm --root $centos_root --initdb
# download and install the centos-release package, it contains our repository sources
$ yumdownloader --destdir=. centos-release
# $ yum reinstall --downloadonly --downloaddir . centos-release
$ rpm --root $centos_root -ivh --nodeps centos-release*.rpm
$ rpm --root $centos_root --import  $centos_root/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
# install yum without docs and install only the english language files during the process
$ yum -y --installroot=$centos_root --setopt=tsflags='nodocs' --setopt=override_install_langs=en_US.utf8 install yum
# configure yum to avoid installing of docs and other language files than english generally
$ sed -i "/distroverpkg=centos-release/a override_install_langs=en_US.utf8\ntsflags=nodocs" $centos_root/etc/yum.conf
# chroot to the environment and install some additional tools
$ cp /etc/resolv.conf $centos_root/etc
# mount the device tree, as its required by some programms
$ mount -o bind /dev $centos_root/dev
$ chroot $centos_root /bin/bash <<EOF
yum install -y procps-ng iputils initscripts openssh-server rsync openssh-clients passwd
yum clean all
$ rm -f $centos_root/etc/resolv.conf
$ umount $centos_root/dev
EOF
## start parms
TOMCAT_USR=${TOMCAT_USR:-false}
REPO=${REPO:-${DIRNAME}/local.repo}
ADDITION_PKG=${ADDITION_PKG:-""}
ADDITION_PKG="${ADDITION_PKG} wget rsync bind-utils sysstat tcpdump nmap-ncat telnet lsof unzip ftp strace ltrace python-virtualenv qemu-guest-agent traceroute pciutils lrzsz iotop iftop"
ADDITION_PKG="${ADDITION_PKG} nscd" 
ROOTFS=${ROOTFS:-${DIRNAME}/rootfs}
NEWPASSWORD=${NEWPASSWORD:-"password"}
DISK_FILE=${DISK_FILE:-"${DIRNAME}/disk"}
DISK_SIZE=${DISK_SIZE:-"1500M"}
DISK_LVM=${DISK_LVM:-true}
ROOTVG=${ROOTVG:-"centos"}
ROOTLV=${ROOTLV:-"root"}
NAME=${NAME:-"vmtemplate"}
IP=${IP:-"10.0.2.100/24"}
GW=${GW:-"10.0.2.1"}

YUM_OPT="--disablerepo=* --enablerepo=centos -q --noplugins --nogpgcheck --config=${REPO}" #--setopt=tsflags=nodocs"
## end parms

PREFIX=${IP##*/}
IP=${IP%/*}

: ${DISK_FILE:?"ERROR: DISK_FILE must b set"}

fake_yum() {
    try "yum ${YUM_OPT} -y --installroot=${ROOTFS} ${*} 2>/dev/null"
}

cleanup() {
    sync;sync;sync
    mount | grep "${ROOTFS}" > /dev/null 2>&1 && try umount -R ${ROOTFS}
    [[ "${DISK_LVM}" = "true" ]] && {
        try vgchange -an ${ROOTVG};
        # FIX ,need twice ~~
        while pvs 2>/dev/null | awk '{print $2}' | grep "${ROOTVG}"
        do
            try kpartx -dsv ${DISK_FILE}
            try kpartx -asv ${DISK_FILE}
            try vgchange -an ${ROOTVG}
            try sleep 1
            try kpartx -dsv ${DISK_FILE}
            #dmsetup remove /dev/.....
        done
    }
    try kpartx -dsv ${DISK_FILE}
    # blockdev --rereadpt /dev/sda
}
trap cleanup TERM
trap cleanup INT

change_vm_info() {
    local mnt_point=$1
    local guest_hostname=$2
    local guest_ipaddr=$3
    local guest_prefix=$4
    local guest_gw=$5

    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
#DNS1=10.0.2.1
IPADDR=${guest_ipaddr}
PREFIX=${guest_prefix}
GATEWAY=${guest_gw}
EOF
    cat > ${mnt_point}/etc/sysconfig/network-scripts/route-eth0 <<-EOF
#xx.xx.xx.xx via ${guest_gw} dev eth0
EOF
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${guest_hostname}
${guest_ipaddr}    ${guest_hostname}
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { return 1; }
    chmod 755 ${mnt_point}/etc/rc.d/rc.local
    rm -f ${mnt_point}/ssh/ssh_host_*
    return 0
}

is_user_root || exit_msg "recommended to run as root.\n"
require kpartx mkfs.xfs yum blkid parted

[ -r ${REPO} ] || {
    cat> ${REPO} <<'EOF'
[centos]
name=centos
# baseurl=http://mirrors.163.com/centos/7.7.1908/os/x86_64/
baseurl=http://10.0.2.1:8080/
gpgcheck=0

# [update]
# name=update
# baseurl=http://mirrors.163.com/centos/7.4.1708/updates/x86_64/
# #keepcache=1
# gpgcheck=0
EOF
    exit_msg "Created ${REPO} using defaults.  Please review it/configure before running again.\n"
}

info_msg "file      :${DISK_FILE}\n"
info_msg "size      :${DISK_SIZE}\n"
info_msg "tomcat    :${TOMCAT_USR}\n"
info_msg "hostname  :${NAME}\n"
info_msg "ip        :${IP}/${PREFIX}\n"
info_msg "gateway   :${GW}\n"
info_msg "passwd    :${NEWPASSWORD}\n"
info_msg "pkg       :${ADDITION_PKG}\n"


try truncate -s ${DISK_SIZE} ${DISK_FILE} 
#dd if=/dev/zero of=${DISK_FILE} bs=1 count=${DISK_SIZE}

if [ "${DISK_LVM}" = "true" ]; then
    try parted -s ${DISK_FILE} -- mklabel msdos \
    	mkpart primary xfs 1m 200m \
    	mkpart primary xfs 201m -1s \
    	set 1 boot on \
    	set 2 lvm on
else
    try parted -s ${DISK_FILE} -- mklabel msdos \
	    mkpart primary xfs 2048s -1s \
	    set 1 boot on
fi

DISK=$(kpartx -avs ${DISK_FILE} | grep -o "/dev/loop[1234567890]*" | tail -1)
MOUNTDEV="/dev/mapper/${DISK##*/}p1"
ROOTPV="/dev/mapper/${DISK##*/}p2"
ROOTDEV="/dev/mapper/${ROOTVG}-${ROOTLV}"

if [ "${DISK_LVM}" = "true" ]; then
    try mkfs.xfs -f -L bootfs ${MOUNTDEV}
    try pvcreate ${ROOTPV}
    try vgcreate ${ROOTVG} ${ROOTPV}
    #lvcreate -L 1536M
    try lvcreate -l 100%FREE -n ${ROOTLV} ${ROOTVG}
    try mkfs.xfs -f -L rootfs /dev/mapper/${ROOTVG}-${ROOTLV}
    try mkdir -p ${ROOTFS}
    try mount /dev/mapper/${ROOTVG}-${ROOTLV} ${ROOTFS}
    try mkdir -p ${ROOTFS}/boot
    try mount ${MOUNTDEV} ${ROOTFS}/boot
else
    try mkfs.xfs -f -L rootfs ${MOUNTDEV}
    try mkdir -p ${ROOTFS}
    try mount ${MOUNTDEV} ${ROOTFS}
    ROOTDEV="UUID=$(blkid -s UUID -o value ${MOUNTDEV})"
fi

fake_yum install filesystem
info_msg "disable new system yum repo\n"
try rm -f ${ROOTFS}/etc/yum.repos.d/*
for mp in /dev /sys /proc
do
    try mount -o bind ${mp} ${ROOTFS}${mp}
done
fake_yum groupinstall core #"Minimal Install"
fake_yum install initscripts iproute openssh-server openssh-clients passwd yum grub2 net-tools chrony lvm2 ${ADDITION_PKG}
fake_yum remove -C --setopt="clean_requirements_on_remove=1" \
	firewalld \
	NetworkManager \
	NetworkManager-team \
	NetworkManager-tui \
	NetworkManager-wifi \
    linux-firmware* \
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

cat > ${ROOTFS}/etc/default/grub <<'EOF'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 console=tty1 net.ifnames=0 biosdevname=0 selinux=0"
GRUB_DISABLE_RECOVERY="true"
EOF

info_msg "add rootfs .....\n"
echo "${ROOTDEV} / xfs defaults 0 0" > ${ROOTFS}/etc/fstab
if [ "${DISK_LVM}" = "true" ]; then
    echo "UUID=$(blkid -s UUID -o value ${MOUNTDEV}) /boot xfs defaults 0 0" >> ${ROOTFS}/etc/fstab
fi

cat > ${ROOTFS}/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "cn"
EndSection
EOF
echo 'KEYMAP="cn"' > ${ROOTFS}/etc/vconsole.conf

try chroot ${ROOTFS} /bin/bash 2>/dev/nul <<EOF
rm -f /etc/locale.conf /etc/localtime /etc/hostname /etc/machine-id /etc/.pwd.lock
systemd-firstboot --root=/ --locale=zh_CN.UTF-8 --locale-messages=zh_CN.UTF-8 --timezone="Asia/Shanghai" --hostname="localhost" --setup-machine-id
#localectl set-locale LANG=zh_CN.UTF-8
#localectl set-keymap cn
#localectl set-x11-keymap cn
echo "${NEWPASSWORD}" | passwd --stdin root
touch /etc/sysconfig/network
systemctl enable getty@tty1
touch /*
touch /etc/*
touch /boot/*
grub2-install --target=i386-pc --boot-directory=/boot --modules="xfs part_msdos" ${DISK}
EOF

info_msg "Rebuild the initramfs.\n"
chroot ${ROOTFS} /bin/bash 2>/dev/nul <<'EOF'
export LATEST_VERSION="$(cd /lib/modules; ls -1vr | head -1)"
rm /boot/initramfs* /boot/vmlinuz-0-rescue-* -f
dracut -H -f --kver ${LATEST_VERSION} --show-modules -m "lvm qemu qemu-net bash nss-softokn i18n network ifcfg drm plymouth dm kernel-modules resume rootfs-block terminfo udev-rules biosdevname systemd usrmount base fs-lib shutdown"
/etc/kernel/postinst.d/51-dracut-rescue-postinst.sh ${LATEST_VERSION} /boot/vmlinuz-${LATEST_VERSION}
grub2-mkconfig -o /boot/grub2/grub.cfg
EOF
change_vm_info "${ROOTFS}" "${NAME}" "${IP}" "${PREFIX}" "${GW}" 
rm -fr ${ROOTFS}/var/cache

info_msg "tuning system .....\n"
try chroot ${ROOTFS} /bin/bash 2>/dev/null <<'EOF'
systemctl set-default multi-user.target
chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash
EOF

info_msg "setting sshd\n"
try sed -i \"s/#UseDNS.*/UseDNS no/g\" ${ROOTFS}/etc/ssh/sshd_config
try sed -i \"s/GSSAPIAuthentication.*/GSSAPIAuthentication no/g\" ${ROOTFS}/etc/ssh/sshd_config
try sed -i \"s/#MaxAuthTries.*/MaxAuthTries 3/g\" ${ROOTFS}/etc/ssh/sshd_config
try sed -i \"s/#Port.*/Port 60022/g\" ${ROOTFS}/etc/ssh/sshd_config
try sed -i \"s/#Protocol 2/Protocol 2/g\" ${ROOTFS}/etc/ssh/sshd_config
try chroot ${ROOTFS} userdel shutdown \|\| true

if [ "${TOMCAT_USR:=false}" = "true" ]
then
    info_msg "add user<tomcat>, add tomcat@ service\n"
    try chroot ${ROOTFS} useradd tomcat -M -s /sbin/nologin
    cat >> ${ROOTFS}/lib/systemd/system/tomcat@.service << 'EOF'
[Unit]
Description=Apache Tomcat Web in /opt/%i
After=syslog.target network.target

[Service]
Type=forking
LimitNOFILE=102400
EnvironmentFile=-/etc/default/tomcat@%I
Environment='TC_DIR=%i'
ExecStart=/bin/bash /opt/${TC_DIR}/bin/startup.sh
ExecStop=/bin/bash /opt/${TC_DIR}/bin/shutdown.sh
SuccessExitStatus=0
User=tomcat
Group=tomcat
# UMask=0007
Restart=on-failure
# service will be restarted when the process exits with a non-zero exit code,
RestartSec=5s
# time to sleep before restarting a service
OOMScoreAdjust=

#Sets the adjustment level for the Out-Of-Memory killer for executed processes.
#Takes an integer between -1000 (to disable OOM killing for this process) and 1000 (to make killing of this process under memory pressure very likely). See proc.txt for details.
#OOMScoreAdjust=1000

[Install]
WantedBy=multi-user.target
EOF
fi

cleanup
info_msg "${DISK_FILE} Create root/${NEWPASSWORD} OK \n"
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


# #!/bin/bash
# set -o nounset -o pipefail -o errexit
# UUID=$(cat /proc/sys/kernel/random/uuid)
# 
# KVM_USER=${KVM_USER:-root}
# KVM_HOST=${KVM_HOST:-10.3.60.4}
# KVM_PORT=${KVM_PORT:-60022}
# STORE_POOL=${STORE_POOL:-"cephpool"}
# SIZE=${SIZE:-8G}
# 
# if [ "${DEBUG:=false}" = "true" ]; then
#     export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#     set -o xtrace
# fi
# CONNECTION="qemu+ssh://${KVM_USER}@${KVM_HOST}:${KVM_PORT}/system"
# 
# VER=$(virt-install --version)
# 
# function cleanup
# {
#     echo "ERROR"
#     virsh -c ${CONNECTION} vol-remove --pool ${STORE_POOL} ${UUID}.raw
# }
# trap cleanup TERM
# trap cleanup INT
# 
# function fake_virsh {
#     virsh -c ${CONNECTION} ${*}
# }
# 
# fake_virsh vol-create-as --pool ${STORE_POOL} --name ${UUID}.raw --capacity ${SIZE} --format raw
# virt-install \
#    --connect ${CONNECTION} \
#    --force \
#    --name ${UUID} \
#    --ram 4096 \
#    --vcpus 2 --cpu host \
#    --os-type linux \
#    --location http://10.32.166.41:8080/dvdrom \
#    --disk vol=${STORE_POOL}/${UUID}.raw,bus=virtio \
#    --accelerate \
#    --graphics none \
#    --network bridge=br-mgr,model=virtio \
#    --extra-args 'ks=http://10.32.166.41:8080/ks.ks ksdevice=eth0 ip=10.3.60.100 netmask=255.255.255.128 gateway=10.3.60.1 console=ttyS0,115200n8'
#  virt-install \
#     --name=Windows10 \
#     --ram=4096 \
#     --cpu host --hvm \
#     --vcpus=2 \
#     --os-type=windows \
#     --os-variant=win8.1 \
#     --disk /var/lib/libvirt/images/vms-win10,size=60,bus=virtio \
#     --disk /var/lib/libvirt/boot/win-10-64bit-english.iso,device=cdrom,bus=ide \
#     --disk /var/lib/libvirt/boot/virtio-win-drivers-20120712-1.iso,device=cdrom,bus=ide \
#     --network bridge=br0 \
#     --graphics vnc,listen=0.0.0.0
#  virt-install \
#  --name $IMGNAME \
#  --ram 1024 \
#  --cpu host \
#  --vcpus 1 \
#  --nographics \
#  --os-type=linux \
#  --os-variant=rhel6 \
#  --location=http://mirror.catn.com/pub/centos/6/os/x86_64 \
#  --initrd-inject=../kickstarts/$KICKSTART \
#  --extra-args="ks=file:/$KICKSTART text console=tty1 utf8 console=ttyS0,115200n8" \
#  --network bridge=virbr0 \
#  --disk path=/var/lib/libvirt/images/$IMGNAME.$EXT,size=10,bus=virtio,format=qcow2 \
#  --force \
#  --noreboot
