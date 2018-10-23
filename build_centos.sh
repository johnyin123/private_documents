#!/bin/bash
set -o nounset -o pipefail
dirname="$(dirname "$(readlink -e "$0")")"
SCRIPTNAME=${0##*/}

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

## start parms
SWAP_FILE=${SWAP_FILE:-false}
TOMCAT_USR=${TOMCAT_USR:-false}
REPO=${REPO:-${dirname}/local.repo}
ADDITION_PKG=${ADDITION_PKG:-""}
ADDITION_PKG="${ADDITION_PKG} wget rsync bind-utils sysstat tcpdump nmap-ncat telnet lsof unzip ftp wget strace ltrace python-virtualenv qemu-guest-agent traceroute rsync pciutils lrzsz"
ROOTFS=${ROOTFS:-${dirname}/rootfs}
NEWPASSWORD=${NEWPASSWORD:-"password"}
DISK_FILE=${DISK_FILE:-"${dirname}/disk"}
DISK_SIZE=${DISK_SIZE:-"1500M"}
DISK_LVM=${DISK_LVM:-true}
ROOTVG=${ROOTVG:-"centos"}
ROOTLV=${ROOTLV:-"root"}
NAME=${NAME:-"vmtemplate"}
IP=${IP:-"10.0.2.100/24"}
GW=${GW:-"10.0.2.1"}

YUM_OPT="-q --noplugins --nogpgcheck --config=${REPO}" #--setopt=tsflags=nodocs"
## end parms

PREFIX=${IP##*/}
IP=${IP%/*}

: ${DISK_FILE:?"ERROR: DISK_FILE must b set"}

QUIET=false
function output() {
    echo -e "${*}"
}

function log() {
    level=${1}
    shift
    MSG="${*}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    case ${level} in
        "info")
            if ! ${QUIET}; then
                output "${timestamp} I: ${MSG}"
            fi
            ;;
        "warn")
            output "${timestamp} \e[1;33mW: ${MSG}\e[0m"
            ;;
        "error")
            output "${timestamp} \e[1;31mE: ${MSG}\e[0m"
            ;;
        "debug")
            output "${timestamp} \e[1;32mD: ${MSG}\e[0m"
            ;;
    esac
}

function abort() {
    log "error" "${*}"
    exit 1
}

#command use the '|"' must be escaped with '\' 
function execute () {
    eval "${*}" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "error" "executing ${*} error"
    else
        log "info" "executing ${*} ok"
    fi
}

function fake_yum {
    log "info" "yum ${YUM_OPT} -y --installroot=${ROOTFS} ${*}"
    yum ${YUM_OPT} -y --installroot=${ROOTFS} ${*} 2>/dev/null
}

function cleanup
{
    sync;sync;sync
    mount | grep "${ROOTFS}" > /dev/null 2>&1 && execute umount -R ${ROOTFS}
    [[ "${DISK_LVM}" = "true" ]] && {
        execute vgchange -an ${ROOTVG};
        # FIX ,need twice ~~
        while pvs 2>/dev/null | awk '{print $2}' | grep "${ROOTVG}"
        do
            execute kpartx -dsv ${DISK_FILE}
            execute kpartx -asv ${DISK_FILE}
            execute vgchange -an ${ROOTVG}
            execute sleep 1
            execute kpartx -dsv ${DISK_FILE}
        done
    }
    execute kpartx -dsv ${DISK_FILE}
}
trap cleanup TERM
trap cleanup INT

function change_vm_info() {
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
    touch ${mnt_point}/etc/motd.sh
    cat >> ${mnt_point}/etc/profile << 'EOF'
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
export readonly PROMPT_COMMAND='{ msg=$(history 1 | { read x y; echo $y; });user=$(whoami); logger "$(date +%Y%m%d%H%M%S):$user:$(pwd):$msg:$(who am i)"; }'
sh /etc/motd.sh
set -o vi
EOF
    return 0
}

[[ $UID = 0 ]] || log "warn" "recommended to run as root."

[ -r ${REPO} ] || {
    cat> ${REPO} <<EOF
[centos]
name=centos
baseurl=http://10.0.2.1:8080/
gpgcheck=0

# [update]
# name=update
# baseurl=http://mirrors.163.com/centos/7.4.1708/updates/x86_64/
# #keepcache=1
# gpgcheck=0
EOF
    abort "Created ${REPO} using defaults.  Please review it/configure before running again."
}

log "warn" "file      :${DISK_FILE}"
log "warn" "size      :${DISK_SIZE}"
log "warn" "tomcat    :${TOMCAT_USR}"
log "warn" "hostname  :${NAME}"
log "warn" "ip        :${IP}/${PREFIX}"
log "warn" "gateway   :${GW}"
log "warn" "passwd    :${NEWPASSWORD}"
log "warn" "pkg       :${ADDITION_PKG}"

for i in kpartx mkfs.xfs yum blkid parted
do
    [[ ! -x $(which $i) ]] && { abort "$i no found"; }
done

execute truncate -s ${DISK_SIZE} ${DISK_FILE} 
#dd if=/dev/zero of=${DISK_FILE} bs=1 count=${DISK_SIZE}

if [ "${DISK_LVM}" = "true" ]; then
    execute parted -s ${DISK_FILE} -- mklabel msdos \
    	mkpart primary xfs 1m 200m \
    	mkpart primary xfs 201m -1s \
    	set 1 boot on \
    	set 2 lvm on
else
    execute parted -s ${DISK_FILE} -- mklabel msdos \
	    mkpart primary xfs 2048s -1s \
	    set 1 boot on
fi

DISK=$(kpartx -avs ${DISK_FILE} | grep -o "/dev/loop[1234567890]*" | tail -1)
MOUNTDEV="/dev/mapper/${DISK##*/}p1"
ROOTPV="/dev/mapper/${DISK##*/}p2"
ROOTDEV="/dev/mapper/${ROOTVG}-${ROOTLV}"

if [ "${DISK_LVM}" = "true" ]; then
    execute mkfs.xfs -f -L bootfs ${MOUNTDEV}
    execute pvcreate ${ROOTPV}
    execute vgcreate ${ROOTVG} ${ROOTPV}
    #lvcreate -L 1536M
    execute lvcreate -l 100%FREE -n ${ROOTLV} ${ROOTVG}
    execute mkfs.xfs -f -L rootfs /dev/mapper/${ROOTVG}-${ROOTLV}
    execute mkdir -p ${ROOTFS}
    execute mount /dev/mapper/${ROOTVG}-${ROOTLV} ${ROOTFS}
    execute mkdir -p ${ROOTFS}/boot
    execute mount ${MOUNTDEV} ${ROOTFS}/boot
else
    execute mkfs.xfs -f -L rootfs ${MOUNTDEV}
    execute mkdir -p ${ROOTFS}
    execute mount ${MOUNTDEV} ${ROOTFS}
    ROOTDEV="UUID=$(blkid -s UUID -o value ${MOUNTDEV})"
fi

fake_yum install filesystem
log "info" "disable new system yum repo"
execute rm -f ${ROOTFS}/etc/yum.repos.d/*
for mp in /dev /sys /proc
do
    execute mount -o bind ${mp} ${ROOTFS}${mp}
done
fake_yum groupinstall core #"Minimal Install"
fake_yum install grub2 net-tools chrony lvm2 ${ADDITION_PKG}
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
GRUB_CMDLINE_LINUX="console=ttyS0 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
EOF

log "info" "add rootfs ....."
echo "${ROOTDEV} / xfs defaults 0 0" > ${ROOTFS}/etc/fstab
if [ "${DISK_LVM}" = "true" ]; then
    echo "UUID=$(blkid -s UUID -o value ${MOUNTDEV}) /boot xfs defaults 0 0" >> ${ROOTFS}/etc/fstab
fi

if [ "${SWAP_FILE}" = "true" ]; then
    log "info" "add 512M swap ....."
    dd if=/dev/zero of=${ROOTFS}/swapfile bs=1M count=512 && chmod 600 ${ROOTFS}/swapfile && mkswap ${ROOTFS}/swapfile
    sed -i '$a\/swapfile swap swap defaults 0 0' ${ROOTFS}/etc/fstab
fi

cat > ${ROOTFS}/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "cn"
EndSection
EOF
echo 'KEYMAP="cn"' > ${ROOTFS}/etc/vconsole.conf

execute chroot ${ROOTFS} /bin/bash 2>/dev/nul <<EOF
rm -f /etc/locale.conf /etc/localtime /etc/hostname /etc/machine-id /etc/.pwd.lock
systemd-firstboot --root=/ --locale=zh_CN.utf8 --locale-messages=zh_CN.utf8 --timezone="Asia/Shanghai" --hostname="localhost" --setup-machine-id
#localectl set-locale LANG=zh_CN.UTF-8
#localectl set-keymap cn
#localectl set-x11-keymap cn
echo "${NEWPASSWORD}" | passwd --stdin root
sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/selinux/config
touch /etc/sysconfig/network
systemctl enable getty@tty1
touch /*
touch /etc/*
touch /boot/*
grub2-install --boot-directory=/boot --modules="xfs part_msdos" ${DISK}
EOF

log "info" "Rebuild the initramfs."
chroot ${ROOTFS} /bin/bash 2>/dev/nul <<'EOF'
export LATEST_VERSION="$(cd /lib/modules; ls -1vr | head -1)"
rm /boot/initramfs* /boot/vmlinuz-0-rescue-* -f
dracut -H -f --kver ${LATEST_VERSION} --show-modules -m "lvm qemu qemu-net bash nss-softokn i18n network ifcfg drm plymouth dm kernel-modules resume rootfs-block terminfo udev-rules biosdevname systemd usrmount base fs-lib shutdown"
/etc/kernel/postinst.d/51-dracut-rescue-postinst.sh ${LATEST_VERSION} /boot/vmlinuz-${LATEST_VERSION}
grub2-mkconfig -o /boot/grub2/grub.cfg
EOF
change_vm_info "${ROOTFS}" "${NAME}" "${IP}" "${PREFIX}" "${GW}" 
rm -fr ${ROOTFS}/var/cache


log "info" "tuning system ....."
execute chroot ${ROOTFS} /bin/bash 2>/dev/null <<'EOF'
systemctl set-default multi-user.target
chkconfig 2>/dev/null | egrep -v "crond|sshd|network|rsyslog|sysstat"|awk '{print "chkconfig",$1,"off"}' | bash
systemctl list-unit-files | grep service | grep enabled | egrep -v "getty|autovt|sshd.service|rsyslog.service|crond.service|auditd.service|sysstat.service|chronyd.service" | awk '{print "systemctl disable", $1}' | bash
EOF
echo "nameserver 114.114.114.114" > ${ROOTFS}/etc/resolv.conf
#set the file limit
cat >> ${ROOTFS}/etc/security/limits.conf << EOF
*           soft   nofile       102400
*           hard   nofile       102400
EOF
log "info" "disable the ipv6"
cat > ${ROOTFS}/etc/modprobe.d/ipv6.conf << EOF
install ipv6 /bin/true
EOF

log "info" "setting sshd"
execute sed -i \"s/#UseDNS.*/UseDNS no/g\" ${ROOTFS}/etc/ssh/sshd_config
execute sed -i \"s/GSSAPIAuthentication.*/GSSAPIAuthentication no/g\" ${ROOTFS}/etc/ssh/sshd_config
execute sed -i \"s/#MaxAuthTries.*/MaxAuthTries 3/g\" ${ROOTFS}/etc/ssh/sshd_config
execute sed -i \"s/#Port.*/Port 60022/g\" ${ROOTFS}/etc/ssh/sshd_config
execute sed -i \"s/#Protocol 2/Protocol 2/g\" ${ROOTFS}/etc/ssh/sshd_config
echo "Ciphers aes256-ctr,aes192-ctr,aes128-ctr" >> ${ROOTFS}/etc/ssh/sshd_config
echo "MACs    hmac-sha1" >> ${ROOTFS}/etc/ssh/sshd_config

log "info" "tune kernel parametres"
cat >> ${ROOTFS}/etc/sysctl.conf << EOF
net.core.rmem_max = 134217728 
net.core.wmem_max = 134217728 
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.core.wmem_default = 16777216
net.ipv4.ip_local_port_range = 1024 65530
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
cat >${ROOTFS}/etc/motd.sh<<'EOF'
#!/bin/bash

date=$(date "+%F %T")
head="System Time: $date"

kernel=$(uname -r)
hostname=$(echo $HOSTNAME)

#Cpu load
load1=$(cat /proc/loadavg | awk '{print $1}')
load5=$(cat /proc/loadavg | awk '{print $2}')
load15=$(cat /proc/loadavg | awk '{print $3}')

#System uptime
uptime=$(cat /proc/uptime | cut -f1 -d.)
upDays=$((uptime/60/60/24))
upHours=$((uptime/60/60%24))
upMins=$((uptime/60%60))
upSecs=$((uptime%60))
up_lastime=$(date -d "$(awk -F. '{print $1}' /proc/uptime) second ago" +"%Y-%m-%d %H:%M:%S")

#Memory Usage
mem_usage=$(free -m | grep Mem | awk '{ printf("%3.2f%%", $3*100/$2) }')
swap_usage=$(free -m | awk '/Swap/{printf "%.2f%",$3/($2+1)*100}')

#Processes
processes=$(ps aux | wc -l)

#User
users=$(users | wc -w)
USER=$(whoami)

#System fs usage
Filesystem=$(df -h | awk '/^\/dev/{print $6}')

uuid=$(dmidecode | grep UUID | awk '{print $2}')
#Interfaces
INTERFACES=$(ip -4 ad | grep 'state ' | awk -F":" '!/^[0-9]*: ?lo/ {print $2}')
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "$head"
echo "----------------------------------------------"
printf "Kernel Version:\t%s\n" $kernel
printf "HostName:\t%s\n" $hostname
printf "UUID\t\t%s\n" ${uuid}
printf "System Load:\t%s %s %s\n" $load1, $load5, $load15
printf "System Uptime:\t%s "days" %s "hours" %s "min" %s "sec"\n" $upDays $upHours $upMins $upSecs
printf "Memory Usage:\t%s\t\t\tSwap Usage:\t%s\n" $mem_usage $swap_usage
printf "Login Users:\t%s\nUser:\t\t%s\n" $users $USER
printf "Processes:\t%s\n" $processes
echo  "---------------------------------------------"
printf "Filesystem\tUsage\n"
for f in $Filesystem
do
    Usage=$(df -h | awk '{if($NF=="'''$f'''") print $5}')
    echo -e "$f\t\t$Usage"
done
echo  "---------------------------------------------"
printf "Interface\tMAC Address\t\tIP Address\n"
for i in $INTERFACES
do
    MAC=$(ip ad show dev $i | grep "link/ether" | awk '{print $2}')
    IP=$(ip ad show dev $i | awk '/inet / {print $2}')
    printf $i"\t\t"$MAC"\t$IP\n"
done
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo
EOF
execute chmod 644 ${ROOTFS}/etc/motd.sh

if [ "${TOMCAT_USR:=false}" = "true" ]
then
    log "info" "add user<tomcat>, add tomcat@ service"
    execute chroot ${ROOTFS} useradd tomcat -M -s /sbin/nologin
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
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
fi

cleanup
log "info" "${DISK_FILE} Create root/${NEWPASSWORD} OK "
exit 0


# echo "口令每 180 日便失效"
# perl -npe 's/PASS_MAX_DAYS\s+99999/PASS_MAX_DAYS 180/' -i /etc/login.defs
# echo "口令每日只可更改一次"
# perl -npe 's/PASS_MIN_DAYS\s+0/PASS_MIN_DAYS 1/g' -i /etc/login.defs
# 系统以 sha512 取代 md5 作口令的保护
# authconfig --passalgo=sha512 --update

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
# dirname="$(dirname "$(readlink -e "$0")")"
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
#    --extra-args 'ks=http://10.32.166.41:8080/ks.ks ksdevice=eth0 ip=10.3.60.100 netmask=255.255.255.128 gateway=10.3.60.1 console=ttyS0'

