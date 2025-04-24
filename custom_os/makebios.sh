#!/usr/bin/env bash
TPL=${1:?TPL FILENAME??}
FS=${2:-xfs}
SIZE=1450M
DISK_IMG=${DISK_IMG:-disk.img}
rm -rf ${DISK_IMG}
# mkdir -p tpl_tmp && mount ${TPL} tpl_tmp
# SIZE=$(echo $(($(du -sb tpl_tmp | cut -f1) + 34569216)) | numfmt --to=iec --round=up --format="%1f")
# umount tpl_tmp && rm -rf tpl_tmp
qemu-img create -f raw ${DISK_IMG} ${SIZE}
parted -s ${DISK_IMG} "mklabel msdos"
parted -s ${DISK_IMG} "mkpart primary ${FS} 1M 100%"
./nbd_attach.sh -a ${DISK_IMG} -f raw
./tpl2disk.sh -t ${TPL} -d /dev/nbd0 -p /dev/mapper/nbd0p1 --fs ${FS}
./nbd_attach.sh -d /dev/nbd0
qemu-img convert -c -f raw -O qcow2 ${DISK_IMG} ${TPL}.qcow2
rm -f ${DISK_IMG}
