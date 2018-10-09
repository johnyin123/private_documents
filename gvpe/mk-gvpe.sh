#!/bin/bash
dirname="$(dirname "$(readlink -e "$0")")"

cd ${dirname}/openssl-1.0.2n
./config no-shared
make
cd ${dirname}/gvpe-3.0
./configure --prefix= --datarootdir=/usr/share --with-openssl-include=${dirname}/openssl-1.0.2n/include/ --with-openssl-lib=${dirname}/openssl-1.0.2n/ --enable-static-daemon
make
mkdir -p ${dirname}/target
make install DESTDIR=${dirname}/target

mkdir -p ${dirname}/target/usr/lib/systemd/system/
cat > ${dirname}/target/usr/lib/systemd/system/gvpe@.service <<EOF
[Unit]
Description=gvpe service for node %i
After=network.target

[Service]
Type=forking
PIDFile=/var/run/gvpe.pid
ExecStart=/sbin/gvpe %i

[Install]
WantedBy=multi-user.target
EOF
mkdir -p ${dirname}/target/etc/gvpe/
cat > ${dirname}/target/etc/gvpe/if-up <<EOF
#!/bin/bash
ip link set $IFNAME address $MAC mtu $MTU up

# 依據不同的Node name設定虛擬網卡的IP
# Node name必須與gvpe.conf中設定的一樣
[ "$NODENAME" = "A" ] && ip addr add 192.168.1.254 broadcast 192.168.1.255 dev "$IFNAME"
[ "$NODENAME" = "B" ] && ip addr add 192.168.2.254 broadcast 192.168.2.255 dev "$IFNAME"
[ "$NODENAME" = "C" ] && ip addr add 192.168.3.254 broadcast 192.168.3.255 dev "$IFNAME"

# 設定VPN的預設路由
ip route add 192.168.0.0/16 dev "$IFNAME"

# 依據不同的網段設定路由
# eth0被設計為內部網段的網卡，以eth0的IP第三組數字確定網段
IN_NIC="eth0"
IN_IP=`ifconfig "$IN_NIC"|grep -w "inet addr"|cut -d':' -f2|cut -d' ' -f1`
IN_IP_SUB=`echo "$IN_IP"|cut -d. -f3`
for i in 1 2 3
do
    if [ "$i" = "$IN_IP_SUB" ] 
   then
       continue
   fi
   route add -net 192.168.$i.0 netmask 255.255.255.0 gw 192.168."$i".1
done
EOF
chmod 755 ${dirname}/target/etc/gvpe/if-up
cat > ${dirname}/target/etc/gvpe/gvpe.conf <<EOF
enable-udp = yes        # udp is spoken almost everywhere
enable-tcp = no         # tcp is not spoken everywhere
enable-rawip = no       # rawip is not spoken everywhere
enable-icmp = no        # most hosts don't bother to icmp

udp-port = 50000 # the external port to listen on (configure your firewall)
mtu = 1500       # minimum MTU of all outgoing interfaces on all hosts
ifname = vpn0    # the local network device name

node = node1       # just a nickname
hostname = xxx.com # the DNS name or IP address of the host

node = node2
# http-proxy-host=
# http-proxy-port=
# http-proxy-auth=user:password
connect = ondemand
EOF
mkdir -p ${dirname}/target/etc/gvpe/pubkey
touch ${dirname}/target/etc/gvpe/hostkey

cd ${dirname}/
fpm -s dir -t rpm -C ${dirname}/target --name gvpe-johnyin --version 3.0 --iteration 1 --depends zlib --description "gvpe vpn which openssl 1.0.2n static link"
fpm -s dir -t deb -C ${dirname}/target --name gvpe-johnyin --version 3.0 --iteration 1 --depends zlib1g --description "gvpe vpn which openssl 1.0.2n static link"

cat <<EOF
openwrt-sdk:
./scripts/feeds update
./scripts/feeds update packages
./scripts/feeds install libopenssl
make menuconfig
make V=99
export STAGING_DIR=/root/sdk/staging_dir/toolchain-mips_24kc_gcc-7.3.0_musl/
./configure --prefix= --datarootdir=/usr/share --with-openssl-include=/root/sdk/staging_dir/target-mips_24kc_musl/usr/include/ --with-openssl-lib=/root/sdk/staging_dir/target-mips_24kc_musl/usr/lib/ --host=mips-openwrt-linux
make

EOF

