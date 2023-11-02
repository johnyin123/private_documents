#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("5aa2e4b[2023-11-01T08:03:49+08:00]:os_install.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
           VCPU: default 1
           VMEM: default 2048
        -n|--name     *  <str>               vm name
        -i|--iso      *  <remote iso file>   iso image, remote isofile
        -p|--pool     *  <pool>              vm disk libvirt store pool
        -s|--size        <int>               image size, default 20G
        -b|--bridge   *  <str>               network bridge name
        --ostype         <str>               ostype, default linux
        --osvariant      <str>               osvarian, default rocky-unknown
        -K|--kvmhost     <ipaddr>            kvm host address
        -U|--kvmuser     <str>               kvm host ssh user
        -P|--kvmport     <int>               kvm host ssh port
        --kvmpass        <password>          kvm host ssh password
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
virt_inst_aarch64_x86() {
    local host="${1}"
    local port="${2}"
    local user="${3}"
    local vm_type=${4}
    local os_type=${5}
    local os_variant=${6}
    local store_pool=${7}
    local size=${8}
    local net_br=${9}
    local iso_img=${10}
    local fmt="raw"
    local CONNECTION=${host:+qemu+ssh://${user:+${user}@}${host}${port:+:${port}}/system}
    try virsh ${CONNECTION:+-c ${CONNECTION}} -q pool-refresh ${store_pool} || true
    try virsh ${CONNECTION:+-c ${CONNECTION}} -q vol-create-as --pool ${store_pool} --name ${vm_type}.${fmt} --capacity ${size} --format ${fmt} || return 1
    # --disk path=/storage/test.img
    # --print-xml \
    try virt-install -q ${CONNECTION:+--connect ${CONNECTION}} \
       --virt-type kvm --accelerate \
       --os-type ${os_type} --os-variant ${os_variant} \
       --vcpus ${VCPU:-1} --memory ${VMEM:-2048} \
       --name=${vm_type}_template\
       --disk vol=${store_pool}/${vm_type}.${fmt},format=${fmt},sparse=true,bus=virtio,discard=unmap \
       --network bridge=${net_br},model=virtio \
       --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
       --graphics vnc,listen=0.0.0.0 \
       --console pty,target_type=virtio \
       --cdrom ${iso_img} \
       --boot cdrom,hd,network,menu=on \
       --noreboot
}
virt_inst() {
    local vm_type=$1
    local store_pool=$2
    local size=$3
    local net_br=$4
    local iso_img=$5
    local media="--location ${iso_img}"
    local fmt="qcow2"
    try virsh ${CONNECTION:+-c ${CONNECTION}} -q vol-create-as --pool ${store_pool} --name ${vm_type}.${fmt} --capacity ${size} --format ${fmt} || return 1
    case "$(to_lower ${vm_type})" in
        debian*)
            gen_debian_preseed vda   > /tmp/debian.cfg
            media+=" --extra-args=\"console=tty0 console=ttyS0,115200n8\" --initrd-inject=/tmp/debian.cfg"
            ;;
        centos*)
            gen_centos_kickstart vda > /tmp/centos.ks
            media+=" --extra-args=\"ks=file:/centos.ks\" --initrd-inject=/tmp/centos.ks"
            # echo ks.cfg | cpio -c -o >> initrd.img
            ;;
    esac
    info_msg "${media}\n"
    # --graphics none --video none  --os-variant=rhel8.0\
    # --controller type=scsi,model=virtio-scsi \
    try virt-install -q ${CONNECTION:+--connect ${CONNECTION}} \
        --virt-type kvm --cpu kvm64 --accelerate \
        --vcpus 1 --memory 2048 \
        --name=${vm_type} --metadata title="${vm_type}" \
        --disk vol=${store_pool}/${vm_type}.${fmt},format=${fmt},sparse=true,bus=virtio,discard=unmap \
        --network bridge=${net_br},model=virtio \
        \
        --channel spicevmc,target_type=virtio,name=com.redhat.spice.0 \
        --channel unix,target_type=virtio,name=org.qemu.guest_agent.0 \
        --graphics spice,listen=none --video qxl \
        --console pty,target_type=virtio \
        ${media} --noreboot || true
    try rm -f /tmp/debian.cfg /tmp/centos.ks || true
}

gen_centos_kickstart() {
    local boot_disk=$1
    cat <<EOF
cdrom
text

firstboot --enable
poweroff

# geography
lang zh_CN.UTF-8
keyboard us
timezone Asia/Shanghai
firewall --disabled
selinux --disabled

# network
network --onboot yes --bootproto dhcp --noipv6
network --hostname=server1

# users
rootpw password
# user --name=myuser --password=password

# disk
# Delete all partitions
clearpart --all --initlabel
# Delete MBR / GPT
zerombr
bootloader --location=mbr --driveorder=${boot_disk} --append=" console=tty0 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0"
part     /          --fstype=xfs  --size=5000 --ondisk=${boot_disk}

# packages
%packages
@core
lvm2
net-tools
-alsa-*
-iwl*firmware
-ivtv*
%end
%addon com_redhat_kdump --disable --reserve-mb='auto'
%end
%post
systemctl enable fstrim.timer
%end
EOF
}

gen_debian_preseed() {
    local boot_disk=$1
    # debconf-get-selections --installer >> file
    # debconf-get-selections >> file
    # 为了在安装之前测试您的预置文件是否有效，您可以使用 debconf-set-selections -c preseed.cfg

    cat <<EOF
d-i debian-installer/locale string en_GB.UTF-8
d-i keyboard-configuration/xkb-keymap select uk

d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/get_ipaddress string 192.168.1.2
d-i netcfg/get_netmask string 255.255.255.0
d-i netcfg/get_gateway string 192.168.1.1
d-i netcfg/get_nameservers string 192.168.1.1
d-i netcfg/confirm_static boolean true
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain
d-i netcfg/hostname string busterps
d-i netcfg/wireless_wep string

d-i mirror/protocol string ftp

d-i passwd/root-password password password
d-i passwd/root-password-again password password
d-i passwd/user-fullname string simon
d-i passwd/username string simon
d-i passwd/user-password password password
d-i passwd/user-password-again password password

d-i clock-setup/utc boolean true
d-i time/zone string GMT

d-i partman-auto/method string lvm
d-i partman-auto-lvm/guided_size string max
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i partman-md/confirm boolean true
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i apt-setup/use_mirror boolean false
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/cdrom/set-next boolean false
d-i apt-setup/cdrom/set-failed boolean false

tasksel tasksel/first multiselect
d-i pkgsel/include string openssh-server net-tools

popularity-contest popularity-contest/participate boolean false

d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true
d-i grub-installer/bootdev  string /dev/${boot_disk}

d-i finish-install/reboot_in_progress note d-i debian-installer/exit/poweroff boolean true

d-i preseed/late_command string sed -i 's/^# deb http/deb http/;s/^deb cdrom.*//' /target/etc/apt/sources.list ; echo "deb http://deb.debian.org/debian/ buster main" >> /target/etc/apt/sources.list
EOF
}

main() {
    local kvmhost="" kvmuser="" kvmport="" kvmpass=""
    local name="" iso="" pool="" bridge=""
    local size=20G ostype=linux osvariant=rocky-unknown
    local opt_short="n:i:p:s:b:K:U:P:"
    local opt_long="name:,iso:,pool:,size:,bridge:,ostype:,osvariant:,kvmhost:,kvmuser:,kvmport:,kvmpass:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -n | --name)   shift; name=${1}; shift;;
            -i | --iso)    shift; iso=${1}; shift;;
            -p | --pool)   shift; pool=${1}; shift;;
            -s | --size)   shift; size=${1}; shift;;
            -b | --bridge) shift; bridge=${1}; shift;;
            --ostype)      shift; ostype=${1}; shift;;
            --osvariant)   shift; osvariant=${1}; shift;;
            -K | --kvmhost) shift; kvmhost=${1}; shift;;
            -U | --kvmuser) shift; kvmuser=${1}; shift;;
            -P | --kvmport) shift; kvmport=${1}; shift;;
            --kvmpass)      shift; kvmpass=${1}; shift;;
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
    [ -z "${name}" ] || [ -z "${pool}" ] || [ -z "${bridge}" ] || [ -z "${iso}" ] || virt_inst_aarch64_x86 "${kvmhost}" "${kvmport}" "${kvmuser}" "${name}" "${ostype}" "${osvariant}" "${pool}" "${size}" "${bridge}" "${iso}"
    # virt_inst "${vm_type}" "${store_pool}" "${size_gb}" "${net_br}" "${iso_img}"
    return 0
}
main "$@"
