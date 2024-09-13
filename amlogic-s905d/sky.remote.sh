cat <<EOF
/etc/remote/osd.sh
/etc/remote/remoter.sh
/etc/triggerhappy/triggers.d/sky.conf
EOF
cat <<'EOF' > osd.sh
#!/usr/bin/env bash
color=${1}
shift
echo "$*" | aosd_cat --font='DejaVu Serif:style=Book 32' --position=4 --fade-full=${TM:-800} --fore-color=${color} --shadow-opacity=0
EOF

cat <<'EOF' > remoter.sh
#!/usr/bin/env bash

USER=johnyin
LIST_FILE=/home/${USER}/Desktop/list.m3u
if [ -f /etc/skyworth_120.conf ]; then
  . /etc/skyworth_120.conf
fi
log() { logger -t triggerhappy $*; }
#############default start#########################################
change_mode() {
    /usr/sbin/th-cmd --socket /var/run/thd.socket --mode ${1} || true
    /usr/bin/systemd-run --unit osd --uid=${USER} -E TM=700 -E DISPLAY=:0 /etc/remote/osd.sh red "Mode ${1}"
}
default_main() {
    local key=${1}
    local POWER_CNT=0
    source /tmp/default.state 2>/dev/null || true
    case "${key}" in
        KEY_POWER)       let POWER_CNT+=1
                         [ "${POWER_CNT}" -eq 2 ] && /usr/bin/systemctl poweroff
                         /usr/bin/systemd-run --unit osd --uid=${USER} -E DISPLAY=:0 /etc/remote/osd.sh red "再按关机!!!"
                         ;;
        KEY_LEFT)        change_mode @media;;
        KEY_RIGHT)       change_mode @;;
        KEY_UP)          change_mode @media;;
        KEY_DOWN)        change_mode @media;;
        KEY_F5)          ;;
        KEY_ESC)         ;;
        KEY_VOLUMEUP)    ;;
        KEY_VOLUMEDOWN)  ;;
        *)               log "unknow key default ${key}";;
    esac
    cat <<EOSTATE > /tmp/default.state
POWER_CNT=${POWER_CNT}
EOSTATE
}
#############default end#########################################
#############media start#########################################
smplayer_start_stop() {
    systemctl -q is-active smplayer-johnyin.service && {
        systemctl stop smplayer-johnyin.service
        pgrep -u ${USER} smplayer >/dev/null && pkill -u ${USER} smplayer
        change_mode @
        log "smplayer stop"
    } || {
        [ -e "${LIST_FILE}" ] || systemd-run --scope --uid=${USER} /usr/bin/touch ${LIST_FILE}
        # # start as systemd service, systemctl reset-failed smplayer-johnyin.service
        systemd-run --unit smplayer-johnyin --uid=${USER} -E DISPLAY=:0 smplayer -ontop ${LIST_FILE}
        log "smplayer start"
    }
}
smplayer_action() {
    systemctl -q is-active smplayer-johnyin.service || smplayer_start_stop
    systemd-run --scope --uid=${USER} -E DISPLAY=:0 smplayer -send-action $*
    log "smplayer_action $*"
    # systemd-run --uid=${USER} -E DISPLAY=:0 playerctl --player=smplayer ....act
}
media_main() {
    local key=${1}
    local RIGHT_CNT=0
    source /tmp/media.state 2>/dev/null || true
    case "${key}" in
        KEY_POWER)       smplayer_start_stop;;
        KEY_LEFT)        smplayer_action rewind1;;
        KEY_RIGHT)       let RIGHT_CNT+=1
                         smplayer_action forward${RIGHT_CNT};;
        KEY_UP)          smplayer_action increase_volume;;
        KEY_DOWN)        smplayer_action decrease_volume;;
        KEY_F5)          smplayer_action mute;;
        KEY_ESC)         smplayer_action fullscreen;;
        KEY_VOLUMEUP)    smplayer_action play_or_pause;;
        KEY_VOLUMEDOWN)  ;;
        *)               log "unknow key media ${key}";;
    esac
    cat <<EOSTATE > /tmp/media.state
RIGHT_CNT=$((RIGHT_CNT%3))
EOSTATE
}
#############media end#########################################
# TH_VALUE=1 TH_EVENT=KEY_POWER ./remoter.sh default/media
# TH_VALUE=2 long press
main() {
    local mode=${1}
    case "${mode}" in
        media)    media_main "${TH_EVENT}";;
        default)  default_main "${TH_EVENT}";;
        *)        log "unknow mode ${mode}";;
    esac
}

LOCK_FILE=/tmp/skyremote.lock
LOCK_FD=
noflock () { log "lock ${LOCK_FILE} ${LOCK_FD} not acquired, giving up"; exit 1; }
( flock -n ${LOCK_FD} || noflock; main "$@"; ) {LOCK_FD}<>${LOCK_FILE}
EOF

cat <<EOF > sky.conf
# # mode select keydefine
KEY_SELECT@            1   @media
KEY_COMPOSE@           1   /usr/bin/systemd-run --unit osd --uid=johnyin -E DISPLAY=:0 /etc/remote/osd.sh red "模式:None"
KEY_SELECT@media       1   @
KEY_COMPOSE@media      1   /usr/bin/systemd-run --unit osd --uid=johnyin -E DISPLAY=:0 /etc/remote/osd.sh green "模式:Media"
# # default mode keydefine
KEY_POWER@             1   /etc/remote/remoter.sh default
KEY_LEFT@              1   /etc/remote/remoter.sh default
KEY_RIGHT@             1   /etc/remote/remoter.sh default
KEY_UP@                1   /etc/remote/remoter.sh default
KEY_DOWN@              1   /etc/remote/remoter.sh default
KEY_F5@                1   /etc/remote/remoter.sh default
KEY_ESC@               1   /etc/remote/remoter.sh default
KEY_VOLUMEUP@          1   /etc/remote/remoter.sh default
KEY_VOLUMEDOWN@        1   /etc/remote/remoter.sh default
# # media mode keydefine
KEY_POWER@media        1   /etc/remote/remoter.sh media
KEY_LEFT@media         1   /etc/remote/remoter.sh media
KEY_RIGHT@media        1   /etc/remote/remoter.sh media
KEY_UP@media           1   /etc/remote/remoter.sh media
KEY_DOWN@media         1   /etc/remote/remoter.sh media
KEY_F5@media           1   /etc/remote/remoter.sh media
KEY_ESC@media          1   /etc/remote/remoter.sh media
KEY_VOLUMEUP@media     1   /etc/remote/remoter.sh media
KEY_VOLUMEDOWN@media   1   /etc/remote/remoter.sh media
EOF
