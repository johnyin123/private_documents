#!/bin/bash
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
breed web console : 按住reset键不放再插上电三秒松开->http://192.168.1.1

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

Hope it helps, just wanted to give back my two cents to the community.



http://192.168.31.1/cgi-bin/luci/;stok=XX/api/xqsystem/init_info
http://192.168.31.1/cgi-bin/luci/;stok=XX/api/xqsystem/usbservice


# Linux dialog with timeout & default No button
# 
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


rm ./out/* -f
# wr703 # PKG_8M_ROM="libopenssl libstdcpp ip-full ipset e2fsprogs aria2 python-light python-logging rsync "  #squid"
# wr703 # PACKAGES="${PKG_8M_ROM} kmod-macvlan kmod-tun kmod-iptunnel kmod-gre kmod-vxlan kmod-pptp kmod-l2tp kmod-fs-vfat kmod-zram zram-swap block-mount kmod-fs-ext4 kmod-usb2 kmod-usb-storage kmod-wireguard wireguard firewall -swconfig " 

PACKAGES="kmod-macvlan kmod-tun kmod-iptunnel kmod-gre kmod-vxlan kmod-pptp kmod-l2tp kmod-fs-vfat kmod-zram zram-swap block-mount kmod-fs-ext4 kmod-usb2 kmod-usb-storage kmod-wireguard wireguard-tools swconfig "
PACKAGES="${PACKAGES} kmod-fs-xfs kmod-fs-jfs kmod-geneve kmod-batman-adv ip-full ipset e2fsprogs aria2 rsync lsof tcpdump sshfs tmux jq eject socat procps-ng-ps"
PACKAGES="${PACKAGES} nfs-kernel-server nfs-kernel-server-utils openssh-server openssh-sftp-server openssh-client -dropbear"

# mydir/etc/shadow
# mydir/etc/ssh/sshd_config
# #change 192.168.1.1 => 192.168.31.1
# mydir/lib/preinit/00_preinit.conf
# mydir/bin/config_generate

### Add SSH public key
if [ ! -d $(pwd)/mydir/root/.ssh ]; then
    mkdir -m0700 $(pwd)/mydir/root/.ssh
fi
cat <<EOF >$(pwd)/mydir/root/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKxdriiCqbzlKWZgW5JGF6yJnSyVtubEAW17mok2zsQ7al2cRYgGjJ5iFSvZHzz3at7QpNpRkafauH/DfrZz3yGKkUIbOb0UavCH5aelNduXaBt7dY2ORHibOsSvTXAifGwtLY67W4VyU/RBnCC7x3HxUB6BQF6qwzCGwry/lrBD6FZzt7tLjfxcbLhsnzqOG2y76n4H54RrooGn1iXHBDBXfvMR7noZKbzXAUQyOx9m07CqhnpgpMlGFL7shUdlFPNLPZf5JLsEs90h3d885OWRx9Kp+O05W2gPg4kUhGeqO6IY09EPOcTupw77PRHoWOg4xNcqEQN2v2C1lr09Y9 root@yinzh
EOF
chmod 0600 $(pwd)/mydir/root/.ssh/authorized_keys

### Add PS1
if [ ! -d $(pwd)/mydir/etc/profile.d ]; then
    mkdir -m0755 $(pwd)/mydir/etc/profile.d
fi
cat <<EOF >$(pwd)/mydir/etc/profile.d/johnyin.sh
export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]$"
set -o vi
EOF


# wr703 # make image PROFILE="tl-wr703n-v1" \
make image PROFILE="miwifi-mini" \
PACKAGES="${PACKAGES}" \
BIN_DIR="$(pwd)/out/" \
FILES="$(pwd)/mydir" \
FILES_REMOVE="files_remove"

#ip-full  blkid block-mount kmod-fs-ext4 kmod-usb2 kmod-usb-uhci kmod-usb-ohci kmod-usb-storage
#kmod-zram zram-swap swap-utils
cat << 'EOF'

# 域名劫持
# uci add dhcp domain
# uci set dhcp.@domain[-1].name='www.facebook.com'
# uci set dhcp.@domain[-1].ip='1.2.3.4'
# uci commit dhcp

# 更改dhcp DNS(6=DNS, 3=Default Gateway, 44=WINS)
# uci set dhcp.@dnsmasq[0].dhcp_option='6,192.168.1.1,8.8.8.8'
# uci commit dhcp
# uci set dhcp.@dnsmasq[0].rebind_protection=0

uci add fstab swap
uci set fstab.@swap[0].device='/swapfile'
uci set fstab.@swap[0].enabled='1'
uci commit fstab
block detect > /etc/config/fstab

uci add fstab mount
uci set fstab.@mount[0].target='/overlay'
uci set fstab.@mount[0].uuid='uuid'
uci set fstab.@mount[0].fstype='ext4'
uci set fstab.@mount[0].options='rw,noatime'
uci set fstab.@mount[0].enabled='1'
uci commit fstab

#banner
(*V*) add  /dropbear/authorized_keys /uci-defaults/setup

#dropbear
config dropbear
	option PasswordAuth 'off'
	option RootPasswordAuth 'on'
	option Port         '60022'
#	option BannerFile   '/etc/banner'

#system
config system
	option hostname 'routeos'
	option timezone 'UTC'
	option ttylogin '0'
	option log_size '64'
	option urandom_seed '0'

config timeserver 'ntp'
	option enabled '1'
	option enable_server '0'
	list server '0.lede.pool.ntp.org'
	list server '1.lede.pool.ntp.org'
	list server '2.lede.pool.ntp.org'
	list server '3.lede.pool.ntp.org'
#uci-defaults/setup

uci set wireless.@wifi-device[0].disabled=0
uci delete wireless.default_radio0
uci commit wireless

#创建wwan接口
uci set network.wwan=interface
uci set network.wwan.proto=dhcp
uci commit network

#disable dhcp on wwan
uci set dhcp.wwan=dhcp
uci set dhcp.wwan.interface='wwan'
uci set dhcp.wwan.ignore=1
uci commit dhcp

#连接上级路由
uci set wireless.toxkadmin='wifi-iface'
uci set wireless.toxkadmin.device='radio0'
uci set wireless.toxkadmin.network=wwan
uci set wireless.toxkadmin.mode=sta
uci set wireless.toxkadmin.ssid=xk-admin
uci set wireless.toxkadmin.encryption=psk2
uci set wireless.toxkadmin.key='Admin@123'
uci commit wireless
#做AP
uci set wireless.mywifi='wifi-iface'
uci set wireless.mywifi.device='radio0'
uci set wireless.mywifi.network='lan'
uci set wireless.mywifi.mode='ap'
uci set wireless.mywifi.ssid='johnap'
uci set wireless.mywifi.encryption='psk2'
uci set wireless.mywifi.key='Admin@123'
uci commit wireless

#wireguard
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="xxx"
uci set network.wg0.listen_port="port"
uci add_list network.wg0.addresses="IP/24"
#uci set firewall.0.network="${firewall_zone} wg_${firewall_zone}"
uci set network.wg0.mtu='1420'

uci add network  wireguard_wg0
uci set network.@wireguard_wg0[-1].public_key="key1"
uci set network.@wireguard_wg0[-1].preshared_key="psk"
uci set network.@wireguard_wg0[-1].description="desc"
uci add_list network.@wireguard_wg0[-1].allowed_ips="1.1.1.2/32"
uci set network.@wireguard_wg0[-1].route_allowed_ips='1'
uci set network.@wireguard_wg0[-1].persistent_keepalive='25'

uci commit

opkg update
opkg install libopenssl libstdcpp
cp gvpe..
EOF
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
