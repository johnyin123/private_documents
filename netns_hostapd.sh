#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
source ${dirname}/netns_vpn_shell.sh

ROUTE_IP="10.0.1.1"
DNS="114.114.114.114"
WIFI_INTERFACE=${WIFI_INTERFACE:-"wlan0"}
WIFI_OUT_INF=${WIFI_OUT_INF:-"eth0"}
gen_conf() {
    cat > /tmp/wifi_dhcp.conf <<EOF
#### dhcp
# Bind to only one interface
interface=${WIFI_INTERFACE}
dhcp-range=10.0.3.2,10.0.3.5,255.255.255.0,12h
# gateway
dhcp-option=option:router,10.0.3.1
# # dns server
# dhcp-option=6,192.168.0.90,192.168.0.98
# # ntp server
# dhcp-option=option:ntp-server,192.168.0.4,10.10.0.5
# dhcp-host=11:22:33:44:55:66,192.168.0.60
bind-interfaces
except-interface=lo
strict-order
expand-hosts
bind-dynamic
filterwin2k
dhcp-authoritative
#### dns
server=/cn/114.114.114.114
server=/google.com/223.5.5.5
# 屏蔽网页广告
address=/ad.youku.com/127.0.0.1
# 劫持所有域名
# address=/#/10.0.3.1
#### log
log-queries
log-facility=/tmp/dnsmasq.log
EOF
    cat >/tmp/hostapd.conf <<EOF
interface=${WIFI_INTERFACE}
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
ssid=johnyin
# 0 = accept unless in deny list
# 1 = deny unless in accept list
# 2 = use external RADIUS server (accept/deny lists are searched first)
macaddr_acl=0
#accept_mac_file=/etc/hostapd.accept
#deny_mac_file=/etc/hostapd.deny
auth_algs=1
# 采用 OSA 认证算法 
ignore_broadcast_ssid=0 
wpa=3
# 指定 WPA 类型 
wpa_key_mgmt=WPA-PSK             
wpa_pairwise=TKIP 
rsn_pairwise=CCMP 
wpa_passphrase=password123
# 连接 ap 的密码 
driver=nl80211
# 设定无线驱动 
hw_mode=g
# 指定802.11协议，包括 a =IEEE 802.11a, b = IEEE 802.11b, g = IEEE802.11g 
channel=9
# 指定无线频道 
EOF
}

setup_ap() {
    ns_name="$1"
    wifi_phy="$2"
    iw phy ${wifi_phy} set netns name ${ns_name}
    #Initial wifi interface configuration
    maybe_netns_run "ip addr add 10.0.3.1/24 dev ${WIFI_INTERFACE}" "${ns_name}"
    maybe_netns_run "ip link set ${WIFI_INTERFACE} up" "${ns_name}"
    #Doesn’t try to run dhcpd when already running
    if [ "$(ps -ef | grep wifi_dhcp.conf | grep -v grep)" == "" ]
    then
        maybe_netns_run "dnsmasq --conf-file=/tmp/wifi_dhcp.conf" "${ns_name}"
    fi
    #start hostapd
    maybe_netns_run "hostapd -B /tmp/hostapd.conf" "${ns_name}"
}

setup_ap_iptable() {
    ns_name="$1"
    maybe_netns_run "iptables -t nat -A POSTROUTING -o ${WIFI_OUT_INF} -j MASQUERADE" "${ns_name}"
    maybe_netns_run "iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu" "${ns_name}"
    maybe_netns_run "sysctl -w net.ipv4.ip_forward=1" "${ns_name}"
}

cleanup_ns_wifi() {
    ns_name="$1"
    wifi_phy="$2"
    # TODO
    pkill -9 dnsmasq
    pkill -9 hostapd
    #To move it back to the root namespace:
    maybe_netns_run "iw phy ${wifi_phy} set netns 1" "${ns_name}"
}

hostap_main() {
    is_user_root || exit_msg "root user need!!\n"
    gen_conf
    netns_exists "${NS_NAME}" && {
        maybe_netns_shell "hostap" "${NS_NAME}"
        exit 0
    }
    init_ns_env "${NS_NAME}" "${IP_PREFIX}"
    setup_traffic "${NS_NAME}" "${IP_PREFIX}" "${WIFI_OUT_INF}"
    setup_nameserver "${NS_NAME}" "${DNS}"
    setup_strategy_route "${IP_PREFIX}" "${ROUTE_IP}" "${ROUTE_TBL_ID}"
    local phy="$(printf '%s\n' /sys/class/ieee80211/*/device/net/${WIFI_INTERFACE} | awk -F'/' '{ print $5 }')"
    setup_ap "${NS_NAME}" ${phy}
    setup_ap_iptable "${NS_NAME}"
    maybe_netns_shell "hostap" "${NS_NAME}"
    #ns_run "${NS_NAME}" curl cip.cc
    cleanup_ns_wifi "${NS_NAME}" ${phy}
    cleanup_strategy_route "${ROUTE_TBL_ID}"
    cleanup_nameserver "${NS_NAME}"
    cleanup_traffic "${NS_NAME}" "${IP_PREFIX}" "${WIFI_OUT_INF}"
    deinit_ns_env "${NS_NAME}" "${IP_PREFIX}"
    exit 0
}
[[ ${BASH_SOURCE[0]} = $0 ]] && hostap_main "$@"
