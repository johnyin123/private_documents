cat <<EOF
/etc/johnyin/remote/remoter.sh
ln -s /etc/johnyin/remote/sky.conf /etc/johnyin/triggerhappy/triggers.d/sky.conf
ln -s /etc/johnyin/remote/osd.service /etc/systemd/system/osd.service
ln -s /etc/johnyin/remote/osd.socket /etc/systemd/system/osd.socket
ln -s /etc/johnyin/remote/21-sky.conf /etc/X11/xorg.conf.d/21-sky.conf
rm -f /lib/udev/rules.d/60-triggerhappy.rules && ls -s /etc/johnyin/remote/60-triggerhappy.rules /lib/udev/rules.d/60-triggerhappy.rules
sed -i "s/^#HandlePowerKey=.*/HandlePowerKey=ignore/g" /etc/systemd/logind.conf
systemctl disable triggerhappy.socket
systemctl enable triggerhappy.service
sed -i "s|ExecStart=.*|ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root|g" /lib/systemd/system/triggerhappy.service
EOF
cat > 60-triggerhappy.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="input", \
	ATTRS{name}=="SKYWORTH_0120 Keyboard", \
	RUN+="/usr/sbin/th-cmd --socket /var/run/thd.socket --passfd --udev --grab"
EOF
cat > 21-sky.conf <<'EOF'
Section "InputClass"
    Identifier "SKYWORTH_0120 BLE REMOTE"
    MatchProduct "SKYWORTH_0120"
    Option "Ignore" "true"
EndSection
EOF
cat <<EOF > osd.socket
[Socket]
ListenFIFO=/tmp/osd.stdin
Service=osd.service
RemoveOnStop=true
EOF
cat <<'EOF' > osd.service
[Service]
User=johnyin
Group=johnyin
Environment=DISPLAY=:0
ExecStart=/usr/bin/aosd_cat --font='DejaVu Serif:style=Book 88' --position=4 --fade-full=500 --fore-color=red --shadow-color=blue
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
    local color=${1}; shift
    [ -p  /tmp/osd.stdin ] && { echo "$*" > /tmp/osd.stdin; return 0; }
    # # if aosc_cat service not exist, use commandlink mode
    echo "$*" | systemd-run --unit johnyin-osd --pipe --uid=${USER} -E DISPLAY=:0 aosd_cat --font='DejaVu Serif:style=Book 88' --position=4 --fade-full=500 --fore-color=${color} --shadow-color=blue
}
change_mode() {
    local mode=${1:-}
    log "change mode: ${mode:-default}"
    /usr/sbin/th-cmd --socket /var/run/thd.socket --mode ${mode} || true
    osd_message red "Mode ${mode:-default}"
}
minidlna_rescan() {
    osd_message green "重扫Minidlna"
    log "rescan minidlna"
    rm -rf /var/cache/minidlna/ && systemctl restart minidlna || true
}
default_main() {
    local key=${1}
    local state=${2} # long/short press
    local D_POWER_CNT=0 D_SELECT_CNT=0
    case "${key}" in
        KEY_POWER)       source /tmp/remoter.state 2>/dev/null || true
                         let D_POWER_CNT+=1
                         log "poweroff ${D_POWER_CNT}"
                         [ "${D_POWER_CNT}" -eq 2 ] && { /usr/bin/systemctl poweroff; D_POWER_CNT=0; } || osd_message red "再按POWER关机!!!"
                         ;;
        KEY_SELECT)      source /tmp/remoter.state 2>/dev/null || true
                         let D_SELECT_CNT+=1
                         log "clear minidlna ${D_SELECT_CNT}"
                         [ "${D_SELECT_CNT}" -eq 2 ] && { minidlna_rescan; D_SELECT_CNT=0; } || osd_message red "再按SELECT重扫Minidlna"
                         ;;
        KEY_LEFT)        log "undefined default key ${key}";;
        KEY_RIGHT)       log "undefined default key ${key}";;
        KEY_UP)          log "undefined default key ${key}";;
        KEY_DOWN)        log "undefined default key ${key}";;
        KEY_F5)          log "undefined default key ${key}";;
        KEY_ESC)         pgrep -u ${USER} smplayer >/dev/null || smplayer_start_stop; change_mode media;;
        KEY_VOLUMEUP)    log "undefined default key ${key}";;
        KEY_VOLUMEDOWN)  log "undefined default key ${key}";;
        *)               log "unknow key default ${key}";;
    esac
    cat <<EOSTATE > /tmp/remoter.state
D_POWER_CNT=${D_POWER_CNT}
D_SELECT_CNT=${D_SELECT_CNT}
EOSTATE
}
#############default end#########################################
#############media start#########################################
smplayer_start_stop() {
    pgrep -u ${USER} smplayer >/dev/null && {
        systemctl stop smplayer-johnyin.service 2>/dev/null
        pgrep -u ${USER} smplayer >/dev/null && pkill -u ${USER} smplayer
        change_mode
        log "smplayer stop"
    } || {
        [ -e "${LIST_FILE}" ] || systemd-run --scope --uid=${USER} /usr/bin/touch ${LIST_FILE}
        # # start as systemd service, systemctl reset-failed smplayer-johnyin.service
        systemd-run --unit smplayer-johnyin --uid=${USER} -E DISPLAY=:0 smplayer -ontop ${LIST_FILE}
        # # -E XDG_CURRENT_DESKTOP=XFCE, fix xfce smplayer font size small
        log "smplayer start"
    }
}
smplayer_action() {
    # use pgrep, not systemctl -q is-active
    # when start smplayer by hand, is not a service
    pgrep -u ${USER} smplayer >/dev/null || {
        osd_message green "运行媒体播放器"
        smplayer_start_stop
        log "smplayer not run, action $* not send, first run smplayer"
        return 0
    }
    systemd-run --scope --uid=${USER} -E DISPLAY=:0 smplayer -send-action $*
    log "smplayer_action $*"
    # systemd-run --uid=${USER} -E DISPLAY=:0 playerctl --player=smplayer ....act
}
media_main() {
    local key=${1}
    local state=${2} # long/short press
    local M_POWER_CNT=0 M_VOLUP_CNT=0 M_VOLDOWN_CNT=0
    case "${key}" in
        KEY_POWER)       source /tmp/remoter.state 2>/dev/null || true
                         let M_POWER_CNT+=1
                         log "media key ${key} ${M_POWER_CNT}"
                         [ "${M_POWER_CNT}" -eq 2 ] && { smplayer_start_stop; M_POWER_CNT=0; } || osd_message red "再按POWER关闭媒体播放器!!!"
                         ;;
        KEY_SELECT)      smplayer_action play_or_pause;;
        KEY_LEFT)        smplayer_action rewind${state};;
        KEY_RIGHT)       smplayer_action forward${state};;
        KEY_UP)          smplayer_action increase_volume;;
        KEY_DOWN)        smplayer_action decrease_volume;;
        KEY_F5)          smplayer_action mute;;
        KEY_ESC)         smplayer_action fullscreen;;
        KEY_VOLUMEUP)    source /tmp/remoter.state 2>/dev/null || true
                         let M_VOLUP_CNT+=1
                         log "media key ${key} ${M_VOLUP_CNT}"
                         [ "${M_VOLUP_CNT}" -eq 2 ] && { smplayer_action pl_prev; M_VOLUP_CNT=0; } || osd_message red "再按VOLUP上一首"
                         ;;
        KEY_VOLUMEDOWN)  source /tmp/remoter.state 2>/dev/null || true
                         let M_VOLDOWN_CNT+=1
                         log "media key ${key} ${M_VOLDOWN_CNT}"
                         [ "${M_VOLDOWN_CNT}" -eq 2 ] && { smplayer_action pl_next; M_VOLDOWN_CNT=0; } || osd_message red "再按VOLDOWN下一首"
                         ;;
        *)               log "unknow key media ${key}";;
    esac
    cat <<EOSTATE > /tmp/remoter.state
M_POWER_CNT=${M_POWER_CNT}
M_VOLUP_CNT=${M_VOLUP_CNT}
M_VOLDOWN_CNT=${M_VOLDOWN_CNT}
EOSTATE
}
#############media end#########################################
# TH_VALUE=1 TH_EVENT=KEY_POWER ./remoter.sh default/media
# TH_VALUE=2 long press
main() {
    local mode=${1}
    # mode changed, the remoter.state shoule clear, so default/media use same state file!
    case "${mode}" in
        media|default) ${mode}_main "${TH_EVENT:-}" "${TH_VALUE:-1}";;
        @*)            mode=${mode##*@}
                       change_mode "${mode}"
                       rm -f /tmp/remoter.state 2>/dev/null || true
                       ;;
    esac
}

LOCK_FILE=/tmp/skyremote.lock
LOCK_FD=
noflock () { log "lock ${LOCK_FILE} ${LOCK_FD} not acquired, giving up"; exit 1; }
( flock -n ${LOCK_FD} || noflock; main "$@"; ) {LOCK_FD}<>${LOCK_FILE}
EOF
cat <<EOF > sky.conf
# # mode select keydefine
KEY_COMPOSE@           1   /etc/johnyin/remote/remoter.sh @media
KEY_COMPOSE@media      1   /etc/johnyin/remote/remoter.sh @
# # default mode keydefine
KEY_POWER@             1   /etc/johnyin/remote/remoter.sh default
KEY_SELECT@            1   /etc/johnyin/remote/remoter.sh default
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
KEY_SELECT@media       1   /etc/johnyin/remote/remoter.sh media
KEY_LEFT@media         1   /etc/johnyin/remote/remoter.sh media
KEY_RIGHT@media        1   /etc/johnyin/remote/remoter.sh media
KEY_UP@media           1   /etc/johnyin/remote/remoter.sh media
KEY_DOWN@media         1   /etc/johnyin/remote/remoter.sh media
KEY_F5@media           1   /etc/johnyin/remote/remoter.sh media
KEY_ESC@media          1   /etc/johnyin/remote/remoter.sh media
KEY_VOLUMEUP@media     1   /etc/johnyin/remote/remoter.sh media
KEY_VOLUMEDOWN@media   1   /etc/johnyin/remote/remoter.sh media
KEY_LEFT@media         2   /etc/johnyin/remote/remoter.sh media
KEY_RIGHT@media        2   /etc/johnyin/remote/remoter.sh media
EOF
