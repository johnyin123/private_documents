#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("554409e[2022-07-04T11:10:55+08:00]:mk_nbd_img.sh")
# [ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
source ${DIRNAME}/os_debian_init.sh

NBD_DEV=
LABEL=${LABEL:-rootfs}
trap cleanup EXIT TERM INT
cleanup() {
    [ -z "${NBD_DEV}" ] || qemu-nbd -d ${NBD_DEV}
    echo "Exit!"
}
prepare_disk_img() {
    local image=${1}
    local size=${2}
    local fmt=${3}
    local i=""
    qemu-img create -f ${fmt} ${image} ${size}
    modprobe nbd max_part=16 || return 1
    for i in /dev/nbd*; do
        qemu-nbd -f ${fmt} -c $i ${image} && { NBD_DEV=$i; break; }
    done
    [ "${NBD_DEV}" == "" ] && return 2
    echo "Connected ${image} to ${NBD_DEV}"
    parted -s "${NBD_DEV}" "mklabel msdos"
    # parted -s "${NBD_DEV}" "mkpart primary fat32 1MiB 65MiB"
    parted -s "${NBD_DEV}" "mkpart primary ext4 1MiB 100%"
    echo "Format the partitions."
    # mkfs.vfat -n ${BOOT_LABEL} ${PART_BOOT}
    # mkswap -L EMMCSWAP "${PART_SWAP}"
    mkfs -t ext4 -m 0 -L "${LABEL}" ${NBD_DEV}p1
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local rootfs=nbdroot image=nbdroot.qcow2 size=1G
    local PKG="libc-bin,tzdata,locales,dialog,apt-utils,systemd-sysv,dbus-user-session,ifupdown,initramfs-tools,u-boot-tools,fake-hwclock,openssh-server,busybox,nbd-client"
    local opt_short="r:p:s:f:"
    local opt_long="rootfs:,pkg:,size:,image:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -r | --rootfs)  shift; rootfs=${1}; shift;;
            -p | --pkg)     shift; PKG+=",${1}"; shift;;
            -s | --size)    shift; size=${1}; shift;;
            -f | --image)   shift; image=${1}; shift;;
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
    local fmt=qcow2
    prepare_disk_img ${image} ${size} ${fmt} && {
        mount ${NBD_DEV}p0 ${rootfs}
    } || echo "ERROR: prepare_disk_img return = $?"

    mkdir -p "${DIRNAME}/cache"
    DEBIAN_VERSION=${DEBIAN_VERSION:-bullseye} \
        INST_ARCH=arm64 \
        REPO=${REPO:-http://mirrors.aliyun.com/debian} \
        HOSTNAME="nbd" \
        NAME_SERVER=114.114.114.114 \
        PASSWORD=password \
        debian_build "${rootfs}" "${DIRNAME}/cache" "${PKG}"
    LC_ALL=C LANGUAGE=C LANG=C chroot ${rootfs} /bin/bash <<EOSHELL
/bin/mkdir -p /dev/pts && /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts || true
/bin/mknod -m 666 /dev/null c 1 3 || true

debian_zswap_init 512
debian_sshd_init
debian_sysctl_init
systemctl mask systemd-machine-id-commit.service
# fix hwclock
rm -f /etc/fake-hwclock.data || true
echo "Force Users To Change Passwords Upon First Login"
chage -d 0 root || true
/bin/umount /dev/pts
exit
EOSHELL

    cat > ${rootfs}/etc/fstab << EOF
LABEL=${LABEL}    /    ext4    defaults,errors=remount-ro,noatime    0    1
tmpfs /run      tmpfs   rw,nosuid,noexec,relatime,mode=755  0  0
tmpfs /tmp      tmpfs   rw,nosuid,relatime,mode=777  0  0
EOF
    # enable ttyAML0 login
    sed -i "/^ttyAML0/d" ${rootfs}/etc/securetty 2>/dev/null || true
    echo "ttyAML0" >> ${rootfs}/etc/securetty

    cat << EOF > ${rootfs}/etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF

    cat << EOF > ${rootfs}/etc/network/interfaces.d/br-ext
auto eth0
allow-hotplug eth0
iface eth0 inet static
    address 192.168.168.4/24
EOF
    /usr/bin/env -i \
        SHELL=/bin/bash \
        HISTFILE= \
        PS1="${NBD_DEV} #" \
        /bin/bash --noprofile --norc -o vi || true
    return 0
}
main "$@"
