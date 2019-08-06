#!/bin/bash

PXE_NS=pxe
PXE_IP=192.168.1.1/24
#EXT_BRIDGE=virbr0
#PXE_IP=10.32.166.44/25
EXT_BRIDGE=br-ext


BASEDIR="$(readlink -f "$(dirname "$0")")"

mkdir -p ${BASEDIR}/var/lib/misc/ ${BASEDIR}/var/run ${BASEDIR}/etc ${BASEDIR}/lib ${BASEDIR}/tftpd


[ -e ${BASEDIR}/bin/tftpd   ] || ln -s /bin/busybox ${BASEDIR}/bin/tftpd
[ -e ${BASEDIR}/bin/httpd   ] || ln -s /bin/busybox ${BASEDIR}/bin/httpd
[ -e ${BASEDIR}/bin/ftpd    ] || ln -s /bin/busybox ${BASEDIR}/bin/ftpd
[ -e ${BASEDIR}/bin/udhcpd  ] || ln -s /bin/busybox ${BASEDIR}/bin/udhcpd

[ -e ${BASEDIR}/dev/random  ] || mknod -m 0644 ${BASEDIR}/dev/random c 1 8
[ -e ${BASEDIR}/dev/urandom ] || mknod -m 0644 ${BASEDIR}/dev/urandom c 1 9
[ -e ${BASEDIR}/dev/null    ] || mknod -m 0666 ${BASEDIR}/dev/null c 1 3
[ -e ${BASEDIR}/etc/profile ] || {
    cat > ${BASEDIR}/etc/profile << EOF
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
export PS1="\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]**${PXE_NS}**:\\[\\033[33;1m\\]\\w\\[\\033[m\\]\\$"
alias ll='ls -lh'
EOF
}
[ -e ${BASEDIR}/etc/passwd ] || {
    cat > ${BASEDIR}/etc/passwd << EOF
root:x:0:0:root:/tftpd:/bin/sh
EOF
}
[ -e ${BASEDIR}/etc/inetd.conf ] || {
    cat > ${BASEDIR}/etc/inetd.conf << EOF
69 dgram udp nowait root tftpd tftpd -l /tftpd/
80 stream tcp nowait root httpd httpd -i -h /tftpd/
21 stream tcp nowait root ftpd ftpd /tftpd/
EOF
}
[ -e ${BASEDIR}/etc/udhcpd.conf ] || {
    cat > ${BASEDIR}/etc/udhcpd.conf << EOF
start           192.168.1.20
end             192.168.1.254
interface       eth0
siaddr          192.168.1.1
boot_file       pxelinux.0
opt     dns     192.168.1.1 192.168.10.10
option  subnet  255.255.255.0
opt     router  192.168.1.1
opt     wins    192.168.1.1
option  domain  local
option  lease   864000
EOF
}

ip netns add ${PXE_NS}
ip netns exec ${PXE_NS} ip link set dev lo up
#ip netns exec ${PXE_NS} sysctl -w net.ipv4.conf.default.forwarding=1
ip link add ${PXE_NS}-eth0 type veth peer name ${PXE_NS}-eth1
echo "add "
#brctl addif br-ext ${PXE_NS}-eth1
ip link set dev ${PXE_NS}-eth1 promisc on
ip link set dev ${PXE_NS}-eth1 up
ip link set dev ${PXE_NS}-eth1 master ${EXT_BRIDGE}

ip link set ${PXE_NS}-eth0 netns ${PXE_NS}
ip netns exec ${PXE_NS} ip link set dev ${PXE_NS}-eth0 name eth0 up
ip netns exec ${PXE_NS} ip address add ${PXE_IP} dev eth0
# ip netns exec ${PXE_NS} ip route add default via 10.32.166.1 dev eth0

mount /home/johnyin/disk/iso/CentOS-7-x86_64-Everything-1708.iso ${BASEDIR}/tftpd/dvdrom/

# ip netns exec ${PXE_NS} chroot ${BASEDIR} /usr/sbin/dnsmasq --user=root --group=root
ip netns exec ${PXE_NS} chroot ${BASEDIR} busybox udhcpd 
ip netns exec ${PXE_NS} chroot ${BASEDIR} busybox inetd
ip netns exec ${PXE_NS} chroot ${BASEDIR} /bin/busybox sh -l

umount ${BASEDIR}/tftpd/dvdrom/

kill -9 $(cat ${BASEDIR}/var/run/inetd.pid)
kill -9 $(cat ${BASEDIR}/var/run/udhcpd.pid)
#brctl delif br-ext ${PXE_NS}-eth1
ip link set ${PXE_NS}-eth1 promisc off
ip link set ${PXE_NS}-eth1 down
ip link set dev ${PXE_NS}-eth1 nomaster

ip netns del ${PXE_NS}
ip link delete ${PXE_NS}-eth1
exit 0
