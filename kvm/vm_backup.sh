#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

BACKUPDEST="${1:?backup-folder?}"
DOMAIN="${2:?domain}"
MAXBACKUPS="${3:-6}"

log "Usage: ./vm-backup <backup-folder> <domain> [max-backups]"
log "Beginning backup for $DOMAIN"

BACKUPDATE=`date "+%Y-%m-%d.%H%M%S"`
BACKUPDOMAIN="$BACKUPDEST/$DOMAIN"
BACKUP="$BACKUPDOMAIN/$BACKUPDATE"
mkdir -p "$BACKUP"

TARGETS=`virsh domblklist "$DOMAIN" --details | grep "^\s*file" | awk '{print $3}'`
IMAGES=`virsh domblklist "$DOMAIN" --details | grep "^\s*file" | awk '{print $4}'`

log "Create the snapshot."
DISKSPEC=""
for t in $TARGETS; do
    DISKSPEC="$DISKSPEC --diskspec $t,snapshot=external"
done
virsh snapshot-create-as --domain "$DOMAIN" --name backup --no-metadata --atomic --disk-only $DISKSPEC >/dev/null
if [ $? -ne 0 ]; then
    log "Failed to create snapshot for $DOMAIN"
    exit 1
fi

log "Copy disk images"
for t in $IMAGES; do
    NAME=`basename "$t"`
    cp "$t" "$BACKUP"/"$NAME"
done

log "Merge changes back."
BACKUPIMAGES=`virsh domblklist "$DOMAIN" --details | grep "^\s*file" | awk '{print $4}'`
for t in $TARGETS; do
    virsh blockcommit "$DOMAIN" "$t" --active --pivot >/dev/null
    if [ $? -ne 0 ]; then
        log "Could not merge changes for disk $t of $DOMAIN. VM may be in invalid state."
        exit 1
    fi
done

log "Cleanup left over backup images."
for t in $BACKUPIMAGES; do
    sudo rm -f "$t" || true
done

#
# Dump the configuration information.
#
virsh dumpxml "$DOMAIN" >"$BACKUP/$DOMAIN.xml"

#
# Cleanup older backups.
#
LIST=`ls -r1 "$BACKUPDOMAIN" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$'`
i=1
for b in $LIST; do
    if [ $i -gt "$MAXBACKUPS" ]; then
        log "Removing old backup "`basename $b`
        sudo rm -rf "$b" || true
    fi
    i=$[$i+1]
done

log "Finished backup"
