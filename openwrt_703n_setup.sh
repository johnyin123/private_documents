#!/usr/bin/env sh
set -o nounset -o pipefail -o errexit

wifi_name=${1:?usage: ${0} <wifi name>}
read -p "input wifi ssid:" wifi_ssid
read -p "input wifi pass:" wifi_pass
read -p "input wifi cidr ipaddr:" wifi_ipaddr
read -p "input wifi gateway:" wifi_gw
network=${wifi_name}
eval $(ipcalc.sh ${wifi_ipaddr})
uci -q set wireless.radio0.disabled='0' || true
uci -q set wireless.default_radio0.disabled='1' || true
uci set wireless.${wifi_name}=wifi-iface
uci set wireless.${wifi_name}.device='radio0'
uci set wireless.${wifi_name}.mode='sta'
uci set wireless.${wifi_name}.disabled='0'
uci set wireless.${wifi_name}.network="${network} ${network}6"
uci set wireless.${wifi_name}.ssid="${wifi_ssid}"
uci set wireless.${wifi_name}.encryption='psk2'
uci set wireless.${wifi_name}.key="${wifi_pass}"
uci -q get network.${network} && {
    uci show network.${network}
    echo "delete network ${network}"
    uci del network.${network}
}
uci set network.${network}=interface
uci set network.${network}.device="${network}"
uci set network.${network}.proto='static' #'dhcp'
uci set network.${network}.ipaddr="${IP}"
uci set network.${network}.netmask="${NETMASK}"
uci set network.${network}.gateway="${wifi_gw}"

uci -q get network.${network}6 && {
    uci show network.${network}6
    echo "delete network ${network}6"
    uci del network.${network}6
}
uci set network.${network}6=interface
uci set network.${network}6.device="@${network}"
uci set network.${network}6.proto='dhcpv6'
# uci set network.${network}6.reqaddress='try'
uci set network.${network}6.reqaddress='force' # Disables stateful DHCPv6 address request, enforcing SLAAC
uci set network.${network}6.reqprefix='no' #SLAAC-only endpoint allocation
# uci commit
cat <<'EO_SCRIPT'> /etc/hotplug.d/block/99-aria
#!/bin/sh
if [ "$ACTION" = "add" ]; then
    sleep 2
    hostname=$(uci -q get system.@system[0].hostname)
    [ -e "/mnt/${hostname}/start.sh" ] && /mnt/${hostname}/start.sh
fi
EO_SCRIPT

uci -q get firewall.${network} && {
    uci show network.${network}
} || {
    uci set firewall.${network}=zone
    uci set firewall.${network}.name="${network}"
    uci add_list firewall.${network}.network="${network}"
    uci add_list firewall.${network}.network="${network}6"

    rule_name=${network}6_dhcpv6
    uci set firewall.${rule_name}=rule
    uci set firewall.${rule_name}.name="Allow-${rule_name}"
    uci set firewall.${rule_name}.src="${network}"
    uci set firewall.${rule_name}.proto='udp'
    uci set firewall.${rule_name}.src_ip='fc00::/6'
    uci set firewall.${rule_name}.dest_ip='fc00::/6'
    uci set firewall.${rule_name}.dest_port='546'
    uci set firewall.${rule_name}.family='ipv6'
    uci set firewall.${rule_name}.target='ACCEPT'
    
    rule_name=${network}6_slaac_disc
    uci set firewall.${rule_name}=rule
    uci set firewall.${rule_name}.name="Allow-${rule_name}"
    uci set firewall.${rule_name}.src="${network}"
    uci set firewall.${rule_name}.proto='icmp'
    uci set firewall.${rule_name}.icmp_type='neighbor-advertisement'
    uci set firewall.${rule_name}.target='ACCEPT'
    uci set firewall.${rule_name}.family='ipv6'
    
    rule_name=${network}_dhcp
    uci set firewall.${rule_name}=rule
    uci set firewall.${rule_name}.name="Allow-${rule_name}"
    uci set firewall.${rule_name}.src="${network}"
    uci set firewall.${rule_name}.proto='udp'
    uci set firewall.${rule_name}.dest_port='68'
    uci set firewall.${rule_name}.target='ACCEPT'
    uci set firewall.${rule_name}.family='ipv4'
    
    rule_name=${network}_ping
    uci set firewall.${rule_name}=rule
    uci set firewall.${rule_name}.name="Allow-${rule_name}"
    uci set firewall.${rule_name}.src="${network}"
    uci set firewall.${rule_name}.proto='icmp'
    uci set firewall.${rule_name}.icmp_type='echo-request'
    uci set firewall.${rule_name}.family='ipv4'
    uci set firewall.${rule_name}.target='ACCEPT'
}
uci set firewall.${network}.input='REJECT'
uci set firewall.${network}.output='ACCEPT'
uci set firewall.${network}.forward='REJECT'
# # port redirect
nat_name=ssh
dst_ip=$(uci -q get network.lan.ipaddr)
port=60022
uci set firewall.${nat_name}=redirect
uci set firewall.${nat_name}.target='DNAT'
uci set firewall.${nat_name}.name="${nat_name} Port Redirect"
uci set firewall.${nat_name}.src="${network}"
uci set firewall.${nat_name}.proto='tcp'
uci set firewall.${nat_name}.src_dport="${port}"
uci set firewall.${nat_name}.dest='lan'
uci set firewall.${nat_name}.dest_ip="${dst_ip}"
uci set firewall.${nat_name}.dest_port="${port}"

rule_name=aria_dht
uci set firewall.${rule_name}=rule
uci set firewall.${rule_name}.name="Allow-${rule_name}"
uci set firewall.${rule_name}.src="${network}"
uci set firewall.${rule_name}.dest_port='50000 51413'
uci set firewall.${rule_name}.proto='tcp udp'
uci set firewall.${rule_name}.target='ACCEPT'

rule_name=aria_rpc
uci set firewall.${rule_name}=rule
uci set firewall.${rule_name}.name="Allow-${rule_name}"
uci set firewall.${rule_name}.src="${network}"
# uci set firewall.${rule_name}.src_ip="!${NETWORK}/${PREFIX}"
uci set firewall.${rule_name}.dest_port='6800'
uci set firewall.${rule_name}.proto='tcp'
uci set firewall.${rule_name}.target='ACCEPT'
cat <<EOF
sysctl -w net.ipv6.conf.all.accept_ra=2
sysctl -w net.ipv6.conf.default.accept_ra=2
EOF
echo "run: uci commit"
