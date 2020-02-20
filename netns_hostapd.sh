#!/bin/bash
set -o nounset -o pipefail
dirname="$(dirname "$(readlink -e "$0")")"

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

source ${dirname}/netns_vpn_shell.sh

ROUTE_IP="10.0.1.1"
DNS="114.114.114.114"
WIFI_INTERFACE=${WIFI_INTERFACE:-"wlan0"}
WIFI_OUT_INF=${WIFI_OUT_INF:-"eth0"}
function gen_conf() {
    cat > /tmp/wifi_dhcp.conf <<EOF
####dhcp
# Bind to only one interface
bind-interfaces

strict-order
expand-hosts
except-interface=lo
bind-dynamic
filterwin2k
interface=${WIFI_INTERFACE}
dhcp-range=10.0.3.2,10.0.3.5,12h
dhcp-authoritative
####dns
server=/cn/114.114.114.114
server=/google.com/223.5.5.5
#屏蔽网页广告
address=/ad.youku.com/127.0.0.1
# 劫持所有域名
# address=/#/10.0.3.1
####log
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

function setup_ap() {
    ns_name="$1"
    wifi_phy="$2"
    iw phy ${wifi_phy} set netns name ${ns_name}
    #Initial wifi interface configuration
    ip netns exec ${ns_name} ip addr add 10.0.3.1/24 dev ${WIFI_INTERFACE}
    ip netns exec ${ns_name} ip link set ${WIFI_INTERFACE} up
    #Doesn’t try to run dhcpd when already running
    if [ "$(ps -ef | grep wifi_dhcp.conf | grep -v grep)" == "" ]
    then
        ip netns exec ${ns_name} dnsmasq --conf-file=/tmp/wifi_dhcp.conf
    fi
    #start hostapd
    ip netns exec ${ns_name} hostapd -B /tmp/hostapd.conf
}

function setup_ap_iptable() {
    ns_name="$1"
    ip netns exec ${ns_name} iptables -t nat -A POSTROUTING -o ${WIFI_OUT_INF} -j MASQUERADE
    ip netns exec ${ns_name} iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    ip netns exec ${ns_name} sysctl -w net.ipv4.ip_forward=1
}

function cleanup_ns_wifi() {
    ns_name="$1"
    wifi_phy="$2"
    # TODO
    pkill -9 dnsmasq
    pkill -9 hostapd
    #To move it back to the root namespace:
    ip netns exec ${ns_name} iw phy ${wifi_phy} set netns 1
}

function hostap_main() {
    [[ $UID = 0 ]] || {
        echo "recommended to run as root.";
        exit 1;
    }
    gen_conf
    netns_exists "${NS_NAME}" && {
        ns_run "${NS_NAME}" /bin/bash
        exit 0
    }
    setup_ns "${NS_NAME}" "${IP_PREFIX}"
    setup_traffic "${NS_NAME}" "${IP_PREFIX}" "${WIFI_OUT_INF}"
    setup_nameserver "${NS_NAME}" "${DNS}"
    setup_strategy_route "${IP_PREFIX}" "${ROUTE_IP}" "${ROUTE_TBL_ID}"
    setup_ap "${NS_NAME}" phy0
    setup_ap_iptable "${NS_NAME}"
    #ns_run "${NS_NAME}" curl cip.cc
    ns_run "${NS_NAME}" /bin/bash
    cleanup_ns_wifi "${NS_NAME}" phy0
    cleanup_strategy_route "${ROUTE_TBL_ID}"
    cleanup_nameserver "${NS_NAME}"
    cleanup_traffic "${NS_NAME}" "${IP_PREFIX}" "${WIFI_OUT_INF}"
    cleanup_ns "${NS_NAME}" "${IP_PREFIX}"
    exit 0
}
[[ ${BASH_SOURCE[0]} = $0 ]] && hostap_main "$@"
