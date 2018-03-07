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
#!/bin/sh
ip link set $IFNAME address $MAC mtu $MTU up
[ $NODENAME = node1 ] && ip addr add 10.0.1.1 dev $IFNAME
[ $NODENAME = node2 ] && ip addr add 10.0.1.2 dev $IFNAME
ip route add 10.0.1.0/24 dev $IFNAME
sysctl net.ipv4.ip_forward=1
iptables -t nat -D POSTROUTING -s 10.0.1.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE
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

