#!/bin/bash
set -o nounset -o pipefail
dirname="$(dirname "$(readlink -e "$0")")"

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi


WIFI_INTERFACE=${WIFI_INTERFACE:-"wlan0"}
OUT_INTERFACE=${OUT_INTERFACE:-"br-ext"}

#Initial wifi interface configuration
ifconfig ${WIFI_INTERFACE} up 10.0.3.1 netmask 255.255.255.0
sleep 2
###########Start DHCP, comment out / add relevant section##########
cat > /${dirname}/wifi_dhcp.conf <<EOF
####dhcp
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
####log
log-queries
log-facility=/${dirname}/dnsmasq.log
EOF
#Doesn’t try to run dhcpd when already running
if [ "$(ps -ef | grep wifi_dhcp.conf | grep -v grep)" == "" ]
then
    dnsmasq --conf-file=/${dirname}/wifi_dhcp.conf
fi
###########
#Enable NAT
iptables -t nat -C POSTROUTING -o ${OUT_INTERFACE} -j MASQUERADE || iptables -t nat -A POSTROUTING -o ${OUT_INTERFACE} -j MASQUERADE
iptables -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
sysctl -w net.ipv4.ip_forward=1
#start hostapd
cat >/${dirname}/hostapd.conf <<EOF
interface=${WIFI_INTERFACE}
logger_syslog=-1
logger_syslog_level=2
logger_stdout=-1
logger_stdout_level=2
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
ssid=johnyin
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
hostapd /${dirname}/hostapd.conf
