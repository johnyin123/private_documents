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

rm ./out/* -f
PKG_8M_ROM="libopenssl libstdcpp ip-full ipset e2fsprogs aria2 python-light python-logging rsync "  #squid"
PACKAGES="${PKG_8M_ROM} kmod-macvlan kmod-tun kmod-iptunnel kmod-gre kmod-vxlan kmod-pptp kmod-l2tp kmod-fs-vfat kmod-zram zram-swap block-mount kmod-fs-ext4 kmod-usb2 kmod-usb-storage kmod-wireguard wireguard firewall -swconfig " 

echo "${PACKAGES}" > $(pwd)/mydir/etc/banner

make image PROFILE="tl-wr703n-v1" \
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
