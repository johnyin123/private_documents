#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit
LC_ALL=C
LANG=C
VERSION+=("xfs_backup.sh - a7ded0f - 2021-09-02T09:18:37+08:00")
################################################################################
KEEP_FULL=${KEEP_FULL:-}
ZIP=${ZIP:-}
# number of backups copys(1-10), Max 0..9
NUM=${NUM:-10}
VG=${VG-:datavg}
LV=${LV:-datalv}
# backup storage dir
BACKUP_DIR=${BACKUP_DIR:-/storage}
LABEL=${LABEL:-"mybackup"}

for cmd in seq lvcreate lvremove xfsdump mount umount findmnt mkdir rm mv; do
    command -v "${cmd}" &> /dev/null || {
        echo "require $cmd"
        exit 1
    }
done
# <level> 0 full backup, level 1-9 increase backup
level=
for level in $(seq 0 ${NUM}); do
    [ -e "${BACKUP_DIR}/${LABEL}_${level}${ZIP:+.gz}" ] || break
done
level="$((level % NUM))"
timestamp=$(date +%s)
snapname="backsnap${timestamp}"
session="backup-session-${LABEL}"
out_name="${BACKUP_DIR}/${LABEL}_${level}${ZIP:+.gz}"
orig_inc="${BACKUP_DIR}/${LABEL}_{1..9}${ZIP:+.gz}"
orig_full="${out_name}.${timestamp}.orig"
target_vol="/dev/${VG}/${LV}"
snap_vol="/dev/${VG}/${snapname}"
snap_mnt="/tmp/${snapname}"
echo "$(date '+%Y%m%d%H%M%S') begin level(${level}) ${target_vol} --> ${out_name}"
[ "$(findmnt --noheadings --output FSTYPE ${target_vol})" = "xfs" ] || {
    lvremove -f "${snap_vol}" || true
    echo "snapshot fstype error! exit"
    exit 1
}
# snapshot it
lvcreate --snapshot "${target_vol}" --name "${snapname}" -l "80%FREE" || true
# backup it, -f - to stdio
[ -b "${snap_vol}" ] || {
    echo "snapshot create error! exit"
    exit 1
}
mkdir -p ${snap_mnt} && mount -v -o ro,nouuid "${snap_vol}" "${snap_mnt}" || true
# full backup exist
[ "${level}" = "0" ] && mv "${out_name}" "${orig_full}" 2>/dev/null || true
eval -- xfsdump -L "${session}" -M "${LABEL}" -l ${level} - ${snap_vol} ${ZIP:+| ${ZIP}} > ${out_name} && {
    [ "${level}" = "0" ] && {
        echo "##########OK##########FULL BACKUP(${timestamp})"
        # remove all increase backup & full backup
        [[ "${!KEEP_FULL-X}" == "${!KEEP_FULL-Y}" ]] || rm -fv {orig_full} || true
        eval -- rm -fv ${orig_inc} || true
    } || {
        echo "##########OK##########INCREASE BACKUP(${timestamp})"
    }
} || {
    echo "**********ERROR**********(${timestamp}) $?"
}
umount -v "${snap_mnt}" || true
rm -rfv "${snap_mnt}" || true
# demo restore
#xfsrestore -I 
#xfsrestore  -f ${BACKUP_DIR}/${LABEL}_0 restore/
#xfsrestore  -f ${BACKUP_DIR}/${LABEL}_1 restore/
# remove snapshot
lvremove -f "${snap_vol}" || true
[ -b "${snap_vol}" ] && echo "snapshot remove error!(${timestamp})"
echo "$(date '+%Y%m%d%H%M%S') end ${target_vol} --> ${out_name}"
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
