#!/bin/bash
#kvm嵌套
#1. echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-nested.conf
#2. <cpu mode='host-passthrough'/>

#KVM HOST 双网卡，用于管理面、数据面
# demo:
# VM->10.0.6.0/24(gw 10.0.6.1)
# MGR->10.0.2.100/24
# switch->10.0.6.1/24

#管理IP(默认网段最小IP为GW)
#!/bin/bash

#KVM HOST 双网卡，用于管理面、数据面
# demo:
# VM->10.0.6.0/24(gw 10.0.6.1)
# MGR->10.0.2.100/24
# switch->10.0.6.1/24

# #管理IP(默认网段最小IP为GW)
# IP_MGR=10.0.2.102/24
# DEF_MGR_IFACE=ens192
# #数据面网卡和bridge设备名称
# DEF_DATA_IFACE=ens224
# DEF_BRIDGE_IFACE=kvm_br0_data

echo "管理IP(默认网段最小IP为GW,demo: 10.0.2.102/24):"
read IP_MGR
echo "管理面网卡:"
read DEF_MGR_IFACE
echo "数据面网卡:"
read DEF_DATA_IFACE
echo "数据面bridge设备名称:"
read DEF_BRIDGE_IFACE
echo "主机名:"
read DEF_HOSTNAME

TIMESERVER=10.0.2.1

DEF_YUM_GROUP=${DEF_YUM_GROUP:-"Virtualization Host"}
MGR_GATEWAY=$(ipcalc ${IP_MGR} -bn | grep HostMin | awk '{ print $2 }')
MGR_IPADDR=$(ipcalc ${IP_MGR} -bn | grep Address | awk '{ print $2 }')
MGR_NETMASK=$(ipcalc ${IP_MGR} -bn | grep Netmask | awk '{ print $2 }')

cat > ifcfg-${DEF_DATA_IFACE} <<EOF
DEVICE="${DEF_DATA_IFACE}"
ONBOOT="yes"
BRIDGE="${DEF_BRIDGE_IFACE}"
EOF

cat > ifcfg-${DEF_BRIDGE_IFACE}<<EOF
DEVICE="${DEF_BRIDGE_IFACE}"
ONBOOT="yes"
TYPE="Bridge"
BOOTPROTO="none"
STP="on"
#DELAY="0.0"
EOF

if [ "${DEF_DATA_IFACE}X" == "${DEF_MGR_IFACE}X" ]; then
    cat >> ifcfg-${DEF_BRIDGE_IFACE}<<EOF
IPADDR="${MGR_IPADDR}"
NETMASK="${MGR_NETMASK}"
GATEWAY="${MGR_GATEWAY}"
EOF
else
    cat > ifcfg-${DEF_MGR_IFACE} <<EOF
DEVICE="${DEF_MGR_IFACE}"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR="${MGR_IPADDR}"
NETMASK="${MGR_NETMASK}"
GATEWAY="${MGR_GATEWAY}"
EOF
fi
# cat > route-${DEF_MGR_IFACE} <<EOF
# ${NET_MGR} via ${MGR_GATEWAY} dev ${DEF_MGR_IFACE}
# EOF


#yum group list
cat > init_kvm.${MGR_IPADDR}.sh <<EOF

cat > /etc/sysconfig/network-scripts/ifcfg-${DEF_DATA_IFACE} <<EOFI
$(cat ifcfg-${DEF_DATA_IFACE})
EOFI

cat > /etc/sysconfig/network-scripts/ifcfg-${DEF_MGR_IFACE} <<EOFI
$(cat ifcfg-${DEF_MGR_IFACE})
EOFI

cat > /etc/sysconfig/network-scripts/ifcfg-${DEF_BRIDGE_IFACE}<<EOFI
$(cat ifcfg-${DEF_BRIDGE_IFACE})
EOFI

yum -y group install "${DEF_YUM_GROUP}"
hostnamectl set-hostname ${DEF_HOSTNAME}
echo "disable Automated Bug Reporting Tool"
systemctl disable abrt-ccpp abrt-oops abrt-vmcore abrt-xorg abrtd

sed -i "s/#local stratum 10/local stratum 10/g" /etc/chrony.conf
sed -i "/^server/d" /etc/chrony.conf
sed -i "3 a server ${TIMESERVER} iburst" /etc/chrony.conf
systemctl enable chronyd.service
systemctl start chronyd.service
timedatectl set-local-rtc 0

echo "enable libvirtd access over ssh"
sed -i "s/#unix_sock_group/unix_sock_group/g" /etc/libvirt/libvirtd.conf
sed -i "s/#unix_sock_rw_perms/unix_sock_rw_perms/g" /etc/libvirt/libvirtd.conf
systemctl restart libvirtd.service
systemctl enable libvirtd.service
usermod -G libvirt root

virsh pool-list
virsh pool-destroy default
virsh pool-delete default
virsh pool-undefine default

# NFS iso lib
# virsh pool-define-as iso --type netfs --target /kvm/iso --source-host 10.0.5.250 --source-path /pxe
# virsh pool-build iso
# virsh pool-start iso
# virsh pool-autostart iso

virsh pool-define-as linux --type dir --target /kvm/linux
virsh pool-build linux
virsh pool-start linux 
virsh pool-autostart linux 

virsh pool-define-as default --type dir --target /kvm/default
virsh pool-build default
virsh pool-start default
virsh pool-autostart default

virsh net-list --all
virsh net-undefine default
virsh net-destroy default
#performance tweaks
modprobe vhost_net


# virsh pool-define-as default --type logical --source-name libvirt_lvm --target /dev/libvirt_lvm --source-dev /dev/sda3
# virsh pool-define-as default logical - - /dev/sda3 libvirt_lvm /dev/libvirt_lvm
# virsh pool-build default 
# virsh pool-start default 

# echo "/kvm 10.0.0.0/16(rw,no_root_squash,no_all_squash,sync,anonuid=501,anongid=501)" >> /etc/exports
# exportfs -r
# systemctl enable nfs
# systemctl start nfs
# showmount -e ${BR_IPADDR}
# mount -t nfs ${BR_IPADDR}:/kvm /mnt -o proto=tcp -o nolock
EOF
rm -f ifcfg-${DEF_DATA_IFACE} ifcfg-${DEF_BRIDGE_IFACE} ifcfg-${DEF_MGR_IFACE}

