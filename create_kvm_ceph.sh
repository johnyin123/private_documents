#!/bin/bash
set -u

# rbd map libvirt-pool/template.raw
# rbd resize libvirt-pool/template.raw --size 8G
# growpart /dev/rbd0 1
# mount /dev/rbd0p1 /mnt
# xfs_growfs -d  -l  /mnt
# umount /mnt
# xfs_repair /dev/rbd0p1
# rbd unmap /dev/rbd0

# qemu-img convert -f qcow2 -O raw debian_squeeze.qcow2 rbd:data/squeeze
# virsh start $VMNAME
# ping -c1 -W2 ${ip} >/dev/null 2>&1 && echo OK || echo ERR

# mount -o loop,offset=32256,uid=1000,gid=1000  fat32.dsk  ${mnt_point}
# modprobe nbd max_part=63
# qemu-nbd -c /dev/nbd0 fat32.dsk
# mount /dev/nbd0p1 -o uid=1000,gid=1000 ${mnt_point}
# qemu-nbd -d /dev/nbd0


# qemu-img resize -f raw demo.disk +1G
# fdisk demo.disk #add new partitions
# fdisk -l demo.disk
# kpartx -av demo.disk 
# ll /dev/mapper/loop0p1 
# mkfs.xfs /dev/mapper/loop0p2 
# kpartx -d demo.disk 

BASEDIR="$(readlink -f "$(dirname "$0")")"

if test -f ${BASEDIR}/vm.cfg; then
    . ${BASEDIR}/vm.cfg
fi

CEPH_KVM_POOL=${CEPH_KVM_POOL:-kvm_os_pool}
TPL_IMG=${TPL_IMG:-CentOS7.4.tpl.raw.qcow2}
MEMSIZE=${MEMSIZE:-$((1024*1024*1))}
VCPUS=${VCPUS-:1}

function genceph_img() {
local ceph_pool=$1
local vm_img=$2
local tpl_img=$3
local guest_hostname=$4
local guest_ipaddr=$5
local guest_netmask=$6
local guest_gw=$7
local mnt_point=/tmp/vm_mnt/
mkdir -p ${mnt_point}
local FOUND_IMG=$(rbd -p ${ceph_pool} ls | grep "^${vm_img}$" >/dev/null 2>&1 && echo -n 1 || echo -n 0)
if [ "${FOUND_IMG}" == "1" ]; then
    echo "image ${vm_img} exist in ${ceph_pool}"
    echo "${vm_img} create failed!!!"
    return 1
else
    #rbd copy --image-feature layering ${tpl_img} ${ceph_pool}/${vm_img} || return 1
    gunzip -c ${tpl_img} | pv | rbd import --image-feature layering - ${ceph_pool}/${vm_img} || return 1
    #qemu-img convert -f qcow2 -O raw ${tpl_img} rbd:${ceph_pool}/${vm_img} || return 1
    local DEV_RBD=$(rbd map ${ceph_pool}/${vm_img})
    mount -t xfs ${DEV_RBD}p1 ${mnt_point} || { rbd unmap ${DEV_RBD}; return 2; }
    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
        DEVICE="eth0"
        ONBOOT="yes"
        BOOTPROTO="none"
        DNS1=10.0.2.1
        IPADDR=${guest_ipaddr}
        NETMASK=${guest_netmask}
        GATEWAY=${guest_gw}
EOF
    cat > ${mnt_point}/etc/sysconfig/network-scripts/route-eth0 <<-EOF
        default via ${guest_gw} dev eth0
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { umount ${mnt_point}; rbd unmap ${DEV_RBD}; return 6; }
    chattr +i ${mnt_point}/etc/hostname || { umount ${mnt_point}; rbd unmap ${DEV_RBD}; return 7; }
    #sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"console=ttyS0 net.ifnames=0 biosdevname=0\"/g" /etc/default/grub
    #grub2-mkconfig -o /boot/grub2/grub.cfg
    rm -f ${mnt_point}/ssh/ssh_host_*
    echo "set ip/gw/hostname/sshd_key OK"
    umount ${mnt_point} || { rbd unmap ${DEV_RBD}; return 8; }
    rbd unmap ${DEV_RBD} || return 9
    echo "     disk:OK"
    return 0
fi
}

function genkvm_xml(){
    local vmname=$1
    local ceph_secret_uuid=$2
    local ceph_pool=$3
    local vm_img=$4
    local title=$5
    local desc=$6
    local uuid=$7
    local kvm_bridge=$8

    cat > ${vmname}<<EOFA
<domain type='kvm'>
  <name>${vmname}</name>
  <uuid>${uuid}</uuid>
  <title>${title}</title>
  <description>${desc}</description>
  <memory unit='KiB'>${MEMSIZE}</memory>
  <currentMemory unit='KiB'>${MEMSIZE}</currentMemory>
  <memoryBacking><hugepages/></memoryBacking>
  <vcpu>${VCPUS}</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
  </os>
  <features>
    <acpi/><apic/><pae/>
  </features>
  <on_poweroff>preserve</on_poweroff>
  <devices>
    <disk type='network' device='disk'>
      <auth username='libvirt'>
      <secret type='ceph' uuid='${ceph_secret_uuid}'/>
      </auth>
      <source protocol='rbd' name='${ceph_pool}/${vm_img}'>
        <host name='kvm1' port='6789'/>
      </source>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='bridge'>
      <source bridge='${kvm_bridge}'/>
      <model type='virtio'/>
      <driver name="vhost"/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/1'/>
      <target port='0'/>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/1'>
      <source path='/dev/pts/1'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
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
}

[[ -r "hosts.conf" ]] || {
    cat >"hosts.conf" <<EOF
#IP          hostname-prefix(小写-)  netmask        gateway   bridge_dev    title         desc
10.0.2.100   kvm                     255.255.255.0  10.0.2.1  kvm-bridge    熙康测试机器  描述灭有啊
EOF
    echo "Created hosts.conf using defaults.  Please review it/configure before running again."
    exit 1
}

CONF='cat hosts.conf | grep -v -e "^$" -e "^#"'
IPS=$(eval $CONF | awk '{print $1}')

for ip in $IPS
do
    VMNAME=$(eval $CONF | grep "${ip}[\t| ]" | awk '{print $2}')
    UUID=$(cat /proc/sys/kernel/random/uuid)
    NETMASK=$(eval $CONF | grep "${ip}[\t| ]" | awk '{print $3}')
    GATEWAY=$(eval $CONF | grep "${ip}[\t| ]" | awk '{print $4}')
    VM_IMG=${VMNAME}-${UUID}.raw
    KVM_BRIDGE=$(eval $CONF | grep "${ip}[\t| ]" | awk '{print $5}')
    VM_TITLE=$(eval $CONF | grep "${ip}[\t| ]" | awk '{print $6}')
    VM_DESC=$(eval $CONF | grep "${ip}[\t| ]" | awk '{print $7}')

    echo "Create vm:${VMNAME}-${UUID}"
    echo "    title:${VM_TITLE}"
    echo "     desc:${VM_DESC}"
    echo "     disk:${VM_IMG}"
    echo "       ip:${ip}"
    echo "       gw:${GATEWAY}"

    genceph_img ${CEPH_KVM_POOL} ${VM_IMG} ${TPL_IMG} "${VMNAME}-${UUID}" ${ip} ${NETMASK} ${GATEWAY}
    retval=$?
    if [[ $retval != 0  ]]; then
        echo "   failed: $retval"
        exit 1 
    fi
    ceph_secret_uuid=$(virsh secret-list  | grep libvirt | awk '{ print $1}')
    genkvm_xml "${VMNAME}-${UUID}" ${ceph_secret_uuid} ${CEPH_KVM_POOL} ${VM_IMG} ${VM_TITLE} ${VM_DESC} ${UUID} ${KVM_BRIDGE}
    virsh define ${VMNAME}-${UUID} > /dev/null 2>&1 
    virsh list --title --all | grep "${VMNAME}-${UUID}" > /dev/null 2>&1  && echo "    staus:OK" || echo "    staus:FAILED"
    rm ${VMNAME}-${UUID} -f
    echo "================================================================="
done
echo "OK"
exit 0
