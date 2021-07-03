#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("br-hostapd.sh - 5b59e21 - 2021-05-25T09:17:48+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################

gen_hostapd() {
    local wifi_interface="${1}"
    local wifi_ssid=${2}
    local cfg_file="${3}"
    local bridge="${4:-}"
    cat <<EOF | tee "${cfg_file}"
interface=${wifi_interface}
${bridge:+bridge=${bridge}}
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
# hw_mode=a             # a simply means 5GHz
# channel=0             # the channel to use, 0 means the AP will search for the channel with the least interferences 
# ieee80211d=1          # limit the frequencies used to those allowed in the country
# country_code=FR       # the country code
# ieee80211n=1          # 802.11n support
# ieee80211ac=1         # 802.11ac support
# wmm_enabled=1         # QoS support

ssid=${wifi_ssid}
macaddr_acl=0
#accept_mac_file=/etc/hostapd.accept
#deny_mac_file=/etc/hostapd.deny
auth_algs=1
# 采用 OSA 认证算法 
ignore_broadcast_ssid=1
wpa=3
# 指定 WPA 类型 
wpa_key_mgmt=WPA-PSK             
wpa_pairwise=TKIP 
rsn_pairwise=CCMP 
wpa_passphrase=Admin@123
# 连接 ap 的密码 

driver=nl80211
# 设定无线驱动 
hw_mode=g
# 指定802.11协议，包括 a =IEEE 802.11a, b = IEEE 802.11b, g = IEEE802.11g 
channel=9
# 指定无线频道 
EOF
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} 
        -s|--start <wifi>  * start hostapd @ wifi
        -b|--bridge <br>     bridge wifi
        --ssid <ssid>        wifi ap ssid, default: s905d100
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local wifi=
    local bridge=
    local ssid="s905d100"
    local opt_short+="s:b:"
    local opt_long+="start:,bridge:,ssid:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
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
