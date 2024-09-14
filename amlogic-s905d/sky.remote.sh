cat <<EOF
/etc/johnyin/remote/remoter.sh
/etc/johnyin/triggerhappy/triggers.d/sky.conf
/etc/systemd/system/osd.service
/etc/systemd/system/osd.socket
EOF
cat <<EOF > osd.socket
[Socket]
ListenFIFO=/tmp/osd.stdin
Service=osd.service
EOF
cat <<'EOF' > osd.service
[Service]
User=johnyin
Group=johnyin
Environment=DISPLAY=:0
ExecStart=/usr/bin/aosd_cat --font='DejaVu Serif:style=Book 88' --position=4 --fade-full=600 --fore-color=red --shadow-color=blue
Sockets=osd.socket
StandardInput=socket
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=4

[Install]
WantedBy=graphical.target
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
osd_message() {
    color=${1}; shift
    [ -p  /tmp/osd.stdin ] && { echo "$*" > /tmp/osd.stdin; return 0; }
    # # if aosc_cat service not exist, use commandlink mode
    echo "$*" | systemd-run --unit -osd --pipe --uid=${USER} -E DISPLAY=:0 aosd_cat --font='DejaVu Serif:style=Book 88' --position=4 --fade-full=600 --fore-color=${color} --shadow-color=blue
}
change_mode() {
    local mode=${1:-}
    log "change mode: ${mode:-default}"
    /usr/sbin/th-cmd --socket /var/run/thd.socket --mode ${mode} || true
    osd_message red "Mode ${mode:-default}"
}
# # source remoter.state in every case, to impl press same key twice or more!!
default_main() {
    local key=${1}
    local POWER_CNT=0
    case "${key}" in
        KEY_POWER)       source /tmp/remoter.state 2>/dev/null || true
                         let POWER_CNT+=1
                         log "poweroff ${POWER_CNT}"
                         [ "${POWER_CNT}" -eq 2 ] && /usr/bin/systemctl poweroff
                         osd_message red "再按POWER关机!!!"
                         ;;
        KEY_LEFT)        log "undefined default key ${key}";;
        KEY_RIGHT)       log "undefined default key ${key}";;
        KEY_UP)          log "undefined default key ${key}";;
        KEY_DOWN)        log "undefined default key ${key}";;
        KEY_F5)          log "undefined default key ${key}";;
        KEY_ESC)         systemctl -q is-active smplayer-johnyin.service || smplayer_start_stop; change_mode media;;
        KEY_VOLUMEUP)    log "undefined default key ${key}";;
        KEY_VOLUMEDOWN)  log "undefined default key ${key}";;
        *)               log "unknow key default ${key}";;
    esac
    cat <<EOSTATE > /tmp/remoter.state
POWER_CNT=${POWER_CNT}
EOSTATE
}
#############default end#########################################
#############media start#########################################
smplayer_start_stop() {
    systemctl -q is-active smplayer-johnyin.service && {
        systemctl stop smplayer-johnyin.service
        pgrep -u ${USER} smplayer >/dev/null && pkill -u ${USER} smplayer
        change_mode
        log "smplayer stop"
    } || {
        [ -e "${LIST_FILE}" ] || systemd-run --scope --uid=${USER} /usr/bin/touch ${LIST_FILE}
        # # start as systemd service, systemctl reset-failed smplayer-johnyin.service
        systemd-run --unit smplayer-johnyin --uid=${USER} -E DISPLAY=:0 smplayer -ontop ${LIST_FILE}
        log "smplayer start"
    }
}
smplayer_action() {

    systemctl -q is-active smplayer-johnyin.service || {
        osd_message green "先按POWER运行媒体播放器"
        # smplayer_start_stop,  systemd service smplayer run  maybe not before you send actoin!!.
        log "smplayer not run, action $* not send"
        return 0
    }
    systemd-run --scope --uid=${USER} -E DISPLAY=:0 smplayer -send-action $*
    log "smplayer_action $*"
    # systemd-run --uid=${USER} -E DISPLAY=:0 playerctl --player=smplayer ....act
}
media_main() {
    local key=${1}
    local RIGHT_CNT=0
    case "${key}" in
        KEY_POWER)       smplayer_start_stop;;
        KEY_LEFT)        smplayer_action rewind1;;
        KEY_RIGHT)       source /tmp/remoter.state 2>/dev/null || true; let RIGHT_CNT+=1; smplayer_action forward${RIGHT_CNT};;
        KEY_UP)          smplayer_action increase_volume;;
        KEY_DOWN)        smplayer_action decrease_volume;;
        KEY_F5)          smplayer_action mute;;
        KEY_ESC)         smplayer_action fullscreen;;
        KEY_VOLUMEUP)    smplayer_action play_or_pause;;
        KEY_VOLUMEDOWN)  log "undefined media key ${key}";;
        *)               log "unknow key media ${key}";;
    esac
    cat <<EOSTATE > /tmp/remoter.state
RIGHT_CNT=$((RIGHT_CNT%3))
EOSTATE
}
#############media end#########################################
# TH_VALUE=1 TH_EVENT=KEY_POWER ./remoter.sh default/media
# TH_VALUE=2 long press
main() {
    local mode=${1}
    # mode changed, the remoter.state shoule clear, so default/media use same state file!
    case "${mode}" in
        media)    media_main "${TH_EVENT}";;
        default)  default_main "${TH_EVENT}";;
        osd)      local color=${2}; shift 2
                  rm -f /tmp/remoter.state 2>/dev/null || true
                  log "osd message[${color}] $*"
                  osd_message "${color}" "$*";;
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
KEY_COMPOSE@           1   /etc/johnyin/remote/remoter.sh osd red "模式:None"
KEY_SELECT@media       1   @
KEY_COMPOSE@media      1   /etc/johnyin/remote/remoter.sh osd green "模式:Media"
# # default mode keydefine
KEY_POWER@             1   /etc/johnyin/remote/remoter.sh default
KEY_LEFT@              1   /etc/johnyin/remote/remoter.sh default
KEY_RIGHT@             1   /etc/johnyin/remote/remoter.sh default
KEY_UP@                1   /etc/johnyin/remote/remoter.sh default
KEY_DOWN@              1   /etc/johnyin/remote/remoter.sh default
KEY_F5@                1   /etc/johnyin/remote/remoter.sh default
KEY_ESC@               1   /etc/johnyin/remote/remoter.sh default
KEY_VOLUMEUP@          1   /etc/johnyin/remote/remoter.sh default
KEY_VOLUMEDOWN@        1   /etc/johnyin/remote/remoter.sh default
# # media mode keydefine
KEY_POWER@media        1   /etc/johnyin/remote/remoter.sh media
KEY_LEFT@media         1   /etc/johnyin/remote/remoter.sh media
KEY_RIGHT@media        1   /etc/johnyin/remote/remoter.sh media
KEY_UP@media           1   /etc/johnyin/remote/remoter.sh media
KEY_DOWN@media         1   /etc/johnyin/remote/remoter.sh media
KEY_F5@media           1   /etc/johnyin/remote/remoter.sh media
KEY_ESC@media          1   /etc/johnyin/remote/remoter.sh media
KEY_VOLUMEUP@media     1   /etc/johnyin/remote/remoter.sh media
KEY_VOLUMEDOWN@media   1   /etc/johnyin/remote/remoter.sh media
EOF
