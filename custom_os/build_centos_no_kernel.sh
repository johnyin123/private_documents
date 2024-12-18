#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("ced6a03[2023-09-22T16:02:32+08:00]:build_centos_no_kernel.sh")
[ -e ${DIRNAME}/os_centos_init.sh ] && . ${DIRNAME}/os_centos_init.sh || { echo '**ERROR: os_centos_init.sh nofound!'; exit 1; }
################################################################################
log() { echo "######$*" >&2; }
export -f log

PKG="efibootmgr"

case "${INST_ARCH:-}" in
    aarch64)
        PKG+=" shim grub2-efi-aa64 grub2-common grub2-tools"
        ;;
    *)
        PKG+=" grub2 shim-x64 grub2-efi-x64 grub2-efi-x64-modules grub2-pc grub2-pc-modules grub2-common grub2-tools-minimal grub2-tools-extra grub2-tools"
        # biosdevname"
        ;;
esac

PKG+=" xfsprogs iputils openssh-server rsync openssh-clients net-tools"
PKG+=" $*"
echo "$PKG"
ROOT_DIR=${DIRNAME}/rootfs-centos
CACHE_DIR=${DIRNAME}/cache

RELEASE_VER=${RELEASE_VER:-7.9.2009} \
    HOSTNAME="srv1" \
    NAME_SERVER=${NAME_SERVER:-114.114.114.114} \
    PASSWORD=password \
    centos_build "${ROOT_DIR}" "${CACHE_DIR}" "${PKG}" || true
log "INIT............"
touch ${ROOT_DIR}/etc/fstab
touch ${ROOT_DIR}/etc/sysconfig/network
cat > ${ROOT_DIR}/etc/default/grub <<'EOF'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0 selinux=0"
GRUB_DISABLE_RECOVERY="true"
EOF
mkdir -p ${ROOT_DIR}/etc/X11/xorg.conf.d
cat > ${ROOT_DIR}/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "cn"
EndSection
EOF
echo 'KEYMAP="cn"' > ${ROOT_DIR}/etc/vconsole.conf
mkdir -p ${ROOT_DIR}/etc/sysconfig/network-scripts/
cat > ${ROOT_DIR}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=192.168.168.101
PREFIX=24
GATEWAY=192.168.168.1
EOF
source ${ROOT_DIR}/etc/os-release
case "${VERSION_ID:-}" in
    7)
        ;;
    *)
        sed -i "/NM_CONTROLLED=/d" ${ROOT_DIR}/etc/sysconfig/network-scripts/ifcfg-eth0
        ;;
esac
cat > ${ROOT_DIR}/etc/hosts <<-EOF
127.0.0.1   localhost $(cat ${ROOT_DIR}/etc/hostname)
EOF
log "tunning sshd"
centos_sshd_init "${ROOT_DIR}"
log "change firewalld ssh port"
sed -i.orig -E -e "s/port\s*=\s*\"22\"/port=\"60022\"/g" ${ROOT_DIR}/usr/lib/firewalld/services/ssh.xml || true
log "disable selinux"
centos_disable_selinux "${ROOT_DIR}"

log "need centos_tuning.sh"
log 'dracut -H -f --kver 5.10.xx --show-modules -m "qemu qemu-net bash network ifcfg drm dm kernel-modules resume rootfs-block terminfo udev-rules biosdevname systemd usrmount base fs-lib shutdown" --add-drivers xfs'
if [ -d "${DIRNAME}/kernel" ]; then
    log "start install you kernel&patchs"
    rsync -azP --numeric-ids ${DIRNAME}/kernel/* ${ROOT_DIR}/ || true
    kerver=$(ls ${ROOT_DIR}/usr/lib/modules/ | sort --version-sort -f | tail -n1)
    log "USE KERNEL ${kerver} ------>"
fi
for mp in /dev /sys /proc
do
    mount -o bind ${mp} ${ROOT_DIR}${mp} || true
done
[ -z "${kerver:-}" ] || {
    chroot ${ROOT_DIR} depmod ${kerver} || true
    # chroot ${ROOT_DIR} dracut -H -f --kver ${kerver} --show-modules -m "qemu qemu-net bash network ifcfg drm dm kernel-modules resume rootfs-block terminfo udev-rules biosdevname systemd usrmount base fs-lib shutdown" --add-drivers xfs || true
    chroot ${ROOT_DIR} kernel-install add ${kerver} /boot/vmlinuz-${kerver} || true
}
chroot ${ROOT_DIR} || true
log "clean up system"
chroot ${ROOT_DIR} yum clean all || true
for mp in /dev /sys /proc
do
    umount -R -v ${ROOT_DIR}${mp} || true
done
centos_minimum_init "${ROOT_DIR}"
echo 'kylin Linux use tpl2disk.sh gen error grub.cfg, fix it!!'
echo ' machine=`uname -m`'
echo ''
echo ' if $isubootft; then'
echo '-#       machine="ubootft"'
echo '+       machine="ubootft"'
echo '        case "x$fttype" in'
echo '        x0x660) GRUB_DEFAULT_DTB="u-boot-general.dtb" ;;'
log "ALL OK"
