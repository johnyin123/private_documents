#!/bin/bash

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

# echo "/kvm 10.0.0.0/16(rw,no_root_squash,no_all_squash,sync,anonuid=501,anongid=501)" >> /etc/exports
# exportfs -r
# systemctl enable nfs
# systemctl start nfs
# showmount -e ${BR_IPADDR}
# mount -t nfs ${BR_IPADDR}:/kvm /mnt -o proto=tcp -o nolock

cat > newvm.sh<<EOFI
echo "vm name:"
read VMNAME

CEPH_KVM_POOL=kvm_os_pool
TPL_IMG=CentOS7.4.tpl.raw

VM_IMG=\\\${VMNAME}.raw

cat > \\\${VMNAME}<<EOFA
<domain type='kvm'>
  <name>\\\${VMNAME}</name>
  <title>\\\${VMNAME}</title>
  <description>desc
xxx
  </description>
  <memory unit='KiB'>2097152</memory>
  <currentMemory unit='KiB'>2097152</currentMemory>
  <vcpu>1</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <on_poweroff>preserve</on_poweroff>
  <devices>
    <disk type='network' device='disk'>
      <auth username='libvirt'>
      <secret type='ceph' uuid='\\\$(virsh secret-list  | grep libvirt | awk '{ print \\\$1}')'/>
      </auth>
      <source protocol='rbd' name='\\\${CEPH_KVM_POOL}/\\\${VM_IMG}'>
        <host name='kvm1' port='6789'/>
        <host name='kvm2' port='6789'/>
        <host name='kvm3' port='6789'/>
      </source>
      <target dev='vda' bus='virtio'/>
    </disk>

    <interface type='bridge'>
      <source bridge='${DEF_BRIDGE_IFACE}'/>
      <model type='virtio'/>
      <driver name="vhost"/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>

    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
    </graphics>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x7'/>
    </controller>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOFA

FOUND_IMG=\\\$(rbd -p \\\${CEPH_KVM_POOL} ls | grep "^\\\${VM_IMG}\\\$" >/dev/null 2>&1 && echo -n 1 || echo -n 0)
if [ "\\\${FOUND_IMG}" == "1" ]; then
    echo "image \\\${VM_IMG} exist in \\\${CEPH_KVM_POOL}"
    exit 1
else
    rbd copy \\\${TPL_IMG} \\\${CEPH_KVM_POOL}/\\\${VM_IMG}
    DEV_RBD=\\\$(rbd map \\\${CEPH_KVM_POOL}/\\\${VM_IMG})
    mount \\\${DEV_RBD}p2 /mnt
    sed -i / "s/^IPADDR=.*/IPADDR=\"\\\${IPADDR}\"/g"    /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
    sed -i / "s/^NETMASK=.*/NETMASK=\"\\\${NETMASK}\"/g" /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
    sed -i / "s/^GATEWAY=.*/GATEWAY=\"\\\${GATEWAY}\"/g" /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
    echo "\\\${GUEST_HOSTNAME}" > /etc/hostname
    umount /mnt
    rbd showmapped
    rbd unmap \\\${DEV_RBD}
    rbd showmapped
    echo "copy vmimage, OK"
fi
read -p "Create VM \\\${VMNAME}[y|n]" yn
case "\\\${yn}" in
    y|Y|yes|YES)
        virsh define \\\${VMNAME}
        ;;
    *)
        rbd remove \\\${CEPH_KVM_POOL}/\\\${VM_IMG}
        ;;
esac

EOFI
#virsh define xxx
EOF
rm -f ifcfg-${DEF_DATA_IFACE} ifcfg-${DEF_BRIDGE_IFACE} ifcfg-${DEF_MGR_IFACE}

