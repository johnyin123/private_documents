#!/bin/bash
set -u -e -o pipefail
UUID=
VMNAME=
trap 'echo "you must manally remove vm image file define in ${VMNAME}.brk!!!";virsh undefine ${VMNAME}; mv ${VMNAME} ${VMNAME}.brk; exit 1;' INT

QUIET=false
output() {
    echo "${*}"
}

log() {
    level=${1}
    shift
    MSG="${*}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    case ${level} in
        "info")
            if ! ${QUIET}; then
                output "${timestamp} I: ${MSG}"
            fi
            ;;
        "warn")
            output "${timestamp} W: ${MSG}"
            ;;
        "error")
            output "${timestamp} E: ${MSG}"
            ;;
        "debug")
            output "${timestamp} D: ${MSG}"
            ;;
    esac
}

abort() {
    log "error" "${*}"
    exit 1
}

parse_size() {(
    local SUFFIXES=('' K M G T P E Z Y)
    local MULTIPLIER=1

    shopt -s nocasematch

    for SUFFIX in "${SUFFIXES[@]}"; do
        local REGEX="^([0-9]+)(${SUFFIX}i?B?)?\$"

        if [[ $1 =~ $REGEX ]]; then
            echo $((${BASH_REMATCH[1]} * MULTIPLIER))
            return 0
        fi

        ((MULTIPLIER *= 1024))
    done

    echo "$0: invalid size \`$1'" >&2
    return 1
)}


uppercase() {
    echo "${*^^}"
}

lowercase() {
    echo "${*,,}"
}

getinientry() {
    local CONF=$1
    grep "^\[" "${CONF}" | sed "s/\[//;s/\]//"
}

readini()
{
    local ENTRY=$1
    local CONF=$2
    local INFO=$(grep -v ^$ "${CONF}"\
        | sed -n "/\[${ENTRY}\]/,/^\[/p" \
        | grep -v ^'\[') && eval "${INFO}"
}

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
local found_img=$(rbd -p ${ceph_pool} ls | grep "^${vm_img}$" >/dev/null 2>&1 && echo -n 1 || echo -n 0)
if [ "${found_img}" == "1" ]; then
    echo "image ${vm_img} exist in ${ceph_pool}"
    echo "${vm_img} create failed!!!"
    return 1
else
    #rbd copy --image-feature layering ${tpl_img} ${ceph_pool}/${vm_img} || return 1
    gunzip -c ${tpl_img} | pv | rbd import --image-feature layering - ${ceph_pool}/${vm_img} || return 1
    #qemu-img convert -f qcow2 -O raw ${tpl_img} rbd:${ceph_pool}/${vm_img} || return 1
    local dev_rbd=$(rbd map ${ceph_pool}/${vm_img})
    mount -t xfs ${dev_rbd}p1 ${mnt_point} || { rbd unmap ${dev_rbd}; return 2; }
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
    cat > ${mnt_point}/etc/hosts <<-EOF
        127.0.0.1   localhost
        ${guest_ipaddr}    ${guest_hostname}
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { umount ${mnt_point}; rbd unmap ${dev_rbd}; return 6; }
    chattr +i ${mnt_point}/etc/hostname || { umount ${mnt_point}; rbd unmap ${dev_rbd}; return 7; }
    #sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"console=ttyS0 net.ifnames=0 biosdevname=0\"/g" /etc/default/grub
    #grub2-mkconfig -o /boot/grub2/grub.cfg
    rm -f ${mnt_point}/ssh/ssh_host_*
    echo "set ip/gw/hostname/sshd_key OK"
    umount ${mnt_point} || { rbd unmap ${dev_rbd}; return 8; }
    rbd unmap ${dev_rbd} || return 9
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
    local memsize=$9
    local vcpus=${10}
    cat > ${vmname}<<EOFA
<domain type='kvm'>
  <name>${vmname}</name>
  <uuid>${uuid}</uuid>
  <title>${title}</title>
  <description>${desc}</description>
  <memory unit='KiB'>${memsize}</memory>
  <currentMemory unit='KiB'>${memsize}</currentMemory>
  <memoryBacking><hugepages/></memoryBacking>
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

CFG_INI="hosts.ini"

[[ -r "${CFG_INI}" ]] || {
    cat >"${CFG_INI}" <<EOF
[kvm001]
#name
IP=10.0.2.101
NETMASK=255.255.255.0
GATEWAY=10.0.2.1
KVM_BRIDGE=kvm-bridge
CEPH_KVM_POOL=libvirt-pool
TEMPLATE_IMG=CentOS7.4.tpl.gz
VMEMSIZE=1G
VCPUS=1
VM_TITLE="xx 熙康测试机器1"
VM_DESC="描述灭有  啊1"

EOF
    abort "Created ${CFG_INI} using defaults.  Please review it/configure before running again."
}


for i in $(getinientry "${CFG_INI}")
do
    readini "$i" "${CFG_INI}"
    #[ ! -z "${IP}" ] && {
    #}
    UUID=$(cat /proc/sys/kernel/random/uuid)
    VMNAME="$(lowercase $i)-${UUID}"
    VM_IMG=${VMNAME}.raw
 
    log "info" "Create vm:${VMNAME}"
    log "info" "    vcpus:${VCPUS}"
    log "info" "   memory:${VMEMSIZE}$(parse_size ${VMEMSIZE})"
    log "info" "    title:${VM_TITLE}"
    log "info" "     desc:${VM_DESC}"
    log "info" "     disk:${VM_IMG}"
    log "info" "       ip:${IP}"
    log "info" "  netmask:${NETMASK}"
    log "info" "       gw:${GATEWAY}"
    log "info" "   bridge:${KVM_BRIDGE}"
    log "info" "     disk:rbd:${CEPH_KVM_POOL}/${VM_IMG}"
    log "info" " template:${TEMPLATE_IMG}"

    ceph_secret_uuid=$(virsh secret-list | grep libvirt | awk '{ print $1}')
    genkvm_xml "${VMNAME}" ${ceph_secret_uuid} ${CEPH_KVM_POOL} ${VM_IMG} "${VM_TITLE}" "${VM_DESC}" ${UUID} ${KVM_BRIDGE} $(parse_size ${VMEMSIZE}) ${VCPUS}
    virsh define ${VMNAME} > /dev/null 2>&1 || {
        log "warn" "   define:FAILED";
        mv ${VMNAME} ${VMNAME}.err;
        log "info" "============================================================================";
        continue;
    } 
    virsh domuuid ${VMNAME} > /dev/null 2>&1 || {
        mv ${VMNAME} ${VMNAME}.err;
        log "warn" "   status:FAILED";
        log "info" "============================================================================";
        continue;
    }

    genceph_img ${CEPH_KVM_POOL} ${VM_IMG} ${TEMPLATE_IMG} "${VMNAME}" ${IP} ${NETMASK} ${GATEWAY}
    retval=$?
    if [[ $retval != 0  ]]; then
        rbd rm ${CEPH_KVM_POOL}/${VM_IMG}
        log "error" "ErrorCode :$retval"
        log "info" "============================================================================"
        continue
    fi
#    rm ${VMNAME} -f
    log "info" "   status:OK";
    log "info" "============================================================================"
done
exit 0
