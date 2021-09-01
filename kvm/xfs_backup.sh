#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit
LC_ALL=C
LANG=C
VERSION+=("xfs_backup.sh - 92dad02 - 2021-09-01T14:05:58+08:00")
################################################################################
# number of backups copys(1-10), Max 0..9
NUM=${NUM:-10}
VG=${VG-:datavg}
LV=${LV:-datalv}
# backup storage dir
BACKUP_DIR=${BACKUP_DIR:-/storage}
LABEL=${LABEL:-"mybackup"}

for cmd in seq lvcreate lvremove xfsdump mount umount mkdir rm mv; do
    command -v "${cmd}" &> /dev/null || {
        echo "require $cmd"
        exit 1
    }
done
# <level> 0 full backup, level 1-9 increase backup
level=
timestamp=$(date +%s)
snapvol="backsnap${timestamp}"
session="backup-session-${LABEL}"
for level in $(seq 0 ${NUM}); do
    [ -e "${BACKUP_DIR}/${LABEL}_${level}" ] && continue
    break
done

[ "${level}" = "${NUM}" ] && level=0

echo "$(date '+%Y%m%d%H%M%S') begin /dev/${VG}/${LV} --> ${BACKUP_DIR}/${LABEL}_${level}"
# snapshot it
lvcreate --snapshot "/dev/${VG}/${LV}" --name "${snapvol}" -l '80%FREE' || true
# backup it, -f - to stdio
[ -b "/dev/${VG}/${snapvol}" ] || {
    echo "snapshot create error!"
    exit 1
}
mkdir -p /tmp/${snapvol} || true
mount -v -o ro,nouuid "/dev/${VG}/${snapvol}" "/tmp/${snapvol}" || true
# full backup exist
[ "${level}" = "0" ] && {
    rm -fv ${BACKUP_DIR}/${LABEL}_0.bak || true
    mv "${BACKUP_DIR}/${LABEL}_0" "${BACKUP_DIR}/${LABEL}_0.bak" 2>/dev/null || true
}
xfsdump -L "${session}" -M "${LABEL}" -l ${level} -f ${BACKUP_DIR}/${LABEL}_${level} /dev/${VG}/${snapvol} && {
    [ "${level}" = "0" ] && {
        echo "##########OK##########FULL BACKUP(${timestamp})"
        # remove all increase backup & full backup
        rm -fv ${BACKUP_DIR}/${LABEL}_{1..9} ${BACKUP_DIR}/${LABEL}_0.bak || true
    } || {
        echo "##########OK##########INCREASE BACKUP(${timestamp})"
    }
} || {
    echo "**********ERROR**********(${timestamp})"
}
umount -v "/tmp/${snapvol}" || true
rm -rfv "/tmp/${snapvol}" || true
# demo restore
#xfsrestore -I 
#xfsrestore  -f ${BACKUP_DIR}/${LABEL}_0 restore/
#xfsrestore  -f ${BACKUP_DIR}/${LABEL}_1 restore/
# remove snapshot
lvremove -f "/dev/${VG}/${snapvol}" || true
[ -b "/dev/${VG}/${snapvol}" ] && echo "snapshot remove error!(${timestamp})"
echo "$(date '+%Y%m%d%H%M%S') end /dev/${VG}/${LV} --> ${BACKUP_DIR}/${LABEL}_${level}"
exit 0

:<<"EOF"
date --date="@$(date +%s)"
pvcreate /dev/vdb1
vgcreate datavg /dev/vdb1
lvcreate -l 100%FREE -n datalv datavg
mkfs.xfs /dev/mapper/datavg-datalv 
mount /dev/mapper/datavg-datalv /mnt/

pvcreate /dev/vdb2
vgextend datavg /dev/vdb2

lvcreate --snapshot /dev/datavg/datalv  --name "snap-$(date +%s)"  -l '80%FREE'

lvremove -f "/dev/${VG}/${SNAPVOL}"
EOF
