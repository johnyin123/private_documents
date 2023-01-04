#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("54ae240[2023-01-04T09:26:04+08:00]:build_centos_no_kernel.sh")
[ -e ${DIRNAME}/os_centos_init.sh ] && . ${DIRNAME}/os_centos_init.sh || { echo '**ERROR: os_centos_init.sh nofound!'; exit 1; }
################################################################################
log() { echo "######$*" >&2; }
export -f log

PKG="grub2-common grub2-tools-minimal grub2-tools-extra grub2-efi-x64 grub2-pc-modules grub2-tools grub2-pc grub2 dracut-network biosdevname systemd-sysv"
PKG+=" iputils openssh-server rsync openssh-clients"
PKG+=" $*"

ROOT_DIR=${DIRNAME}/rootfs-centos
mkdir -p ${ROOT_DIR}

RELEASE_VER=${RELEASE_VER:-7.9.2009} \
HOSTNAME="srv1" \
NAME_SERVER=114.114.114.114 \
PASSWORD=password \
centos_build "${ROOT_DIR}" "${PKG}"

log "INIT............"
touch ${ROOT_DIR}/etc/fstab
cat > ${ROOT_DIR}/etc/default/grub <<'EOF'
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
EOF
cat > ${ROOT_DIR}/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "cn"
EndSection
EOF
echo 'KEYMAP="cn"' > ${ROOT_DIR}/etc/vconsole.conf
log "need centos_tuning.sh"
log 'dracut -H -f --kver 5.10.xx --show-modules -m "qemu qemu-net bash nss-softokn network ifcfg drm dm kernel-modules resume rootfs-block terminfo udev-rules biosdevname systemd usrmount base fs-lib shutdown" --add-drivers xfs'
log "ALL OK"
