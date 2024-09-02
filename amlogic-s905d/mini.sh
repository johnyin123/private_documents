#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("465f551[2024-08-20T15:50:22+08:00]:mini.sh")
################################################################################
source ${DIRNAME}/os_debian_init.sh

ROOTFS=${1:?rootfs need input}

chroot ${ROOTFS}/ /bin/bash -xs <<EOF
    debian_minimum_init
EOF
macaddr=
case "$(cat ${ROOTFS}/etc/hostname)" in
    s905d2) macaddr=b8:be:ef:90:5d:02;;
    s905d3) macaddr=b8:be:ef:90:5d:03;;
    *)      macaddr=b8:be:ef:90:5d:99;;
esac
cat << EOF > ${ROOTFS}/etc/hosts
127.0.0.1       localhost $(cat ${ROOTFS}/etc/hostname)
EOF
sed -i "s/^macaddr=.*/macaddr=${macaddr}/g" ${ROOTFS}/usr/lib/firmware/brcm/brcmfmac43455-sdio.txt || true
grep "^macaddr=" ${ROOTFS}/usr/lib/firmware/brcm/brcmfmac43455-sdio.txt || true
sed -i "s/^macaddr=.*/macaddr=${macaddr}/g" ${ROOTFS}/usr/lib/firmware/brcm/brcmfmac43455-sdio.phicomm,n1.txt || true
grep "^macaddr=" ${ROOTFS}/usr/lib/firmware/brcm/brcmfmac43455-sdio.phicomm,n1.txt || true
# # set fake-clock
date --utc '+%Y-%m-%d %H:%M:%S' > ${ROOTFS}/etc/fake-hwclock.data
cat <<EOF
(cd ${ROOTFS}/root/tunnel/ && for i in *.sh;do find /home/johnyin/disk/mygit/github_private/ -name \$i; done | xargs -I@ cp @ .)

rsync -avzP --numeric-ids \\
    --exclude=/boot \\
    --exclude=/usr/lib/modules/ \\
    --exclude=/usr/include/ \\
    --exclude=/var/log/ \\
    --delete \\
    6.6/ 6.10/

# # sync rootfs.
rsync -avzP --numeric-ids \\
    -e 'ssh -p60022' \\
    --exclude=/usr/bin/qemu-aarch64-static \\
    --exclude=/etc/wifi_mode.conf \\
    --exclude=boot \\
    --delete \\
    ${ROOTFS}/ root@${IP:-10.32.166.32}:/overlay/lower/

# # sync boot partition.
rsync -avzP --numeric-ids \\
    -e 'ssh -p60022' \\
    --delete \\
    ${ROOTFS}/boot/ root@${IP:-10.32.166.32}:/boot/
EOF
