#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("e1d424e[2025-02-07T09:59:48+08:00]:br-hostapd.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
MODE=${MODE:-2G}
gen_hostapd() {
    local wifi_interface="${1}"
    local wifi_ssid=${2}
    local cfg_file="${3}"
    local bridge="${4:-}"
    write_file <<EOF | tee "${cfg_file}"
interface=${wifi_interface}
${bridge:+bridge=${bridge}}
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

ssid=${wifi_ssid}
macaddr_acl=0
# accept_mac_file=/etc/hostapd.accept
# deny_mac_file=/etc/hostapd.deny
auth_algs=1
# # 采用 OSA 认证算法
ignore_broadcast_ssid=1
wpa=3
# # 指定 WPA 类型
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
wpa_passphrase=Admin@123

driver=nl80211
$([ "${MODE}" = "2G" ] && { cat << EO_MODE
hw_mode=g
# # 指定802.11协议，包括 a =IEEE 802.11a, b = IEEE 802.11b, g = IEEE802.11g
channel=9
EO_MODE
} || { cat <<EO_MODE
hw_mode=a
# # a simply means 5GHz
channel=44
wmm_enabled=1
# # QoS support
ieee80211n=1
require_ht=1
ht_capab=[HT40+][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40]
ieee80211ac=1
# # 802.11ac support
require_vht=1
vht_capab=[MAX-MPDU-3895][SHORT-GI-80][SU-BEAMFORMEE]
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
basic_rates=60 90 120 180 240 360 480 540
disassoc_low_ack=0
EO_MODE
})
EOF
}

usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
        env: ${R}MODE=2G/5G${N} default 2G, 5G not work!!
        -s|--start <wifi>  * start hostapd @ wifi
        -b|--bridge <br>     bridge wifi
        --ssid <ssid>        wifi ap ssid, default: s905d100
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
)"; echo -e "${usage_doc}"
    exit 1
}

main() {
    local wifi=
    local bridge=
    local ssid="s905d100"
    local opt_short+="s:b:"
    local opt_long+="start:,bridge:,ssid:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --start)   shift; wifi=${1}; shift;;
            -b | --bridge)  shift; bridge=${1}; shift;;
            --ssid)         shift; ssid=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    is_user_root || exit_msg "root user need!!\n"
    require ip hostapd
    [ -z "${wifi}" ] && usage "wifi interface must input"
    directory_exists /sys/class/net/${wifi}/wireless || exit_msg "wireless ${wifi} nofound!!\n"
    [ -z "${bridge}" ] || { file_exists /sys/class/net/${bridge}/bridge/bridge_id || exit_msg "bridge ${bridge} nofound!!\n"; }
    gen_hostapd "${wifi}" "${ssid}" "/tmp/hostapd.conf" "${bridge}"
    info_msg "start: hostapd -B /tmp/hostapd.conf\n"
    try "start-stop-daemon --start --quiet --background --exec /sbin/hostapd -- -B /tmp/hostapd.conf"
    return 0
}
main "$@"
