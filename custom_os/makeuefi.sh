#!/usr/bin/env bash
TPL=${1:-debian_bullseye_amd64_guestos.tpl}
FS=${2:-ext4}
SIZE=1500M
DISK_IMG=${DISK_IMG:-disk.img}
rm -rf ${DISK_IMG}
# mkdir -p tpl_tmp && mount ${TPL} tpl_tmp
# SIZE=$(echo $(($(du -sb tpl_tmp | cut -f1) + 34569216)) | numfmt --to=iec --round=up --format="%1f")
# umount tpl_tmp && rm -rf tpl_tmp
qemu-img create -f raw ${DISK_IMG} ${SIZE}
parted -s ${DISK_IMG} "mklabel gpt"
parted -s ${DISK_IMG} "mkpart primary fat32 1M 64M"
parted -s ${DISK_IMG} "mkpart primary ${FS} 64M 100%"
parted -s ${DISK_IMG} "set 1 boot on"
./nbd_attach.sh -a ${DISK_IMG} -f raw
./tpl2disk.sh -t ${TPL} -d /dev/nbd0 --uefi /dev/mapper/nbd0p1 -p /dev/mapper/nbd0p2 --fs ${FS} || true
./nbd_attach.sh -d /dev/nbd0
qemu-img convert -c -f raw -O qcow2 ${DISK_IMG} ${TPL}.qcow2
rm -f ${DISK_IMG}
