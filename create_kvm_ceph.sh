#!/bin/bash
set -u

function genceph_img() {
local ceph_pool=$1
local vm_img=$2
local tpl_img=$3
local guest_hostname=$4
local guest_ipaddr=$5
local guset_netmask=$6
local guest_gw=$7

local FOUND_IMG=$(rbd -p ${ceph_pool} ls | grep "^${vm_img}$" >/dev/null 2>&1 && echo -n 1 || echo -n 0)
if [ "${FOUND_IMG}" == "1" ]; then
    echo "image ${vm_img} exist in ${ceph_pool}"
    echo "${vm_img} create failed!!!"
    return 1
else
    rbd copy ${tpl_img} ${ceph_pool}/${vm_img}
    local DEV_RBD=$(rbd map ${ceph_pool}/${vm_img})
    mount ${DEV_RBD}p2 /mnt
    sed -i "s/^IPADDR=.*/IPADDR=\"${guest_ipaddr}\"/g"    /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
    sed -i "s/^NETMASK=.*/NETMASK=\"${guset_netmask}\"/g" /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
    sed -i "s/^GATEWAY=.*/GATEWAY=\"${guest_gw}\"/g"      /mnt/etc/sysconfig/network-scripts/ifcfg-eth0
    echo "${guest_hostname}" > /mnt/etc/hostname
    chattr +i /mnt/etc/hostname
    rm -f /mnt/ssh/ssh_host_*
    umount /mnt
    rbd showmapped 
    rbd unmap ${DEV_RBD}
    rbd showmapped 
    echo "copy vmimage, OK"
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

    local memsize=$((1024*1024*1))
    local vcpus=1
    cat > ${VMNAME}<<EOFA
<domain type='kvm'>
  <name>${VMNAME}</name>
  <title>${title}</title>
  <description>${desc}</description>
  <memory unit='KiB'>${memsize}</memory>
  <currentMemory unit='KiB'>${memsize}</currentMemory>
  <vcpu>${vcpus}</vcpu>
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
        <host name='kvm2' port='6789'/>
        <host name='kvm3' port='6789'/>
      </source>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='bridge'>
      <source bridge='kvm-bridge'/>
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
}

CEPH_KVM_POOL=kvm_os_pool
TPL_IMG=CentOS7.4.tpl.raw

[[ -r "hosts.conf" ]] || {
	cat >"hosts.conf" <<- EOF
#IP          hostname(小写-)  netmask	gateway title   desc
10.0.2.100   kvm1         255.255.255.0 10.0.2.1  熙康测试机器  描述灭有啊

EOF
	echo "Created hosts.conf using defaults.  Please review it/configure before running again."
	exit 1
}
CONF='cat hosts.conf | grep -v -e "^$" -e "^#"'
IPS=$(eval $CONF | awk '{print $1}')


for ip in $IPS
do

    VMNAME=$(eval $CONF | grep ${ip} | awk '{print $2}')
    NETMASK=$(eval $CONF | grep ${ip} | awk '{print $3}')
    GATEWAY=$(eval $CONF | grep ${ip} | awk '{print $4}')
    VM_IMG=${VMNAME}.raw

    genceph_img ${CEPH_KVM_POOL} ${VM_IMG} ${TPL_IMG} ${VMNAME} ${ip} ${NETMASK} ${GATEWAY}
    echo "RETURN $?  xxxxxxxxxxxxxxxxxx"
    if [[ $? == 1  ]]; then
        echo "xxxxxxxxxxxxxxxx"
    fi

    VM_TITLE=$(eval $CONF | grep ${ip} | awk '{print $5}')
    VM_DESC=$(eval $CONF | grep ${ip} | awk '{print $6}')
    ceph_secret_uuid=$(virsh secret-list  | grep libvirt | awk '{ print $1}')
    genkvm_xml ${VMNAME} ${ceph_secret_uuid} ${CEPH_KVM_POOL} ${VM_IMG} ${VM_TITLE} ${VM_DESC}

    read -p "Create VM ${VMNAME}[y|n]" yn
    case "${yn}" in
        y|Y|yes|YES)
            virsh define ${VMNAME}
            virsh list --all
            ;;
        *)
            rbd remove ${CEPH_KVM_POOL}/${VM_IMG}
            ;;
    esac
    rm ${VMNAME} -f
done
