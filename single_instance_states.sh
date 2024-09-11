#!/usr/bin/env bash
set -o nounset
set -o errexit

STATS=('SMPLAYER' 'DESKTOP')
CUR_STATS=
DATE=

write_stats() {
    let CUR_STATS+=1
    CUR_STATS=$((CUR_STATS%${#STATS[@]}))
    cat << EOF | lock_write
DATE="$(date)"
CUR_STATS="${CUR_STATS}"
EOF
}

main() {
    echo "single instance scipt, with states saved!!"
    [ -f "${LOCK_FILE}" ] && source "${LOCK_FILE}"
    echo "date=${DATE}"
    echo "CUR_STATS=${CUR_STATS}, ${STATS[${CUR_STATS}]}"
    # # wrap next one
    write_stats
}

log() { logger -t triggerhappy $*; }
LOCK_FILE=/tmp/skyremote.lock
LOCK_FD=
lock_write() { cat; } >&${LOCK_FD}
noflock () { log "lock ${LOCK_FILE} ${LOCK_FD} not acquired, giving up"; exit 1; }
( flock -n ${LOCK_FD} || noflock; main "$@"; ) {LOCK_FD}<>${LOCK_FILE}
