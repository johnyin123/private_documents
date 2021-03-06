#!/bin/bash
set -o errexit -o nounset -o pipefail

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

CEPH_MON=${CEPH_MON:-"kvm01:6789 kvm02:6789 kvm03:6789"}
QUIET=false
output() {
    echo -e "${*}"
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
            output "${timestamp} \e[0;34mW: ${MSG}\e[0m"
            ;;
        "error")
            output "${timestamp} \e[1;31mE: ${MSG}\e[0m"
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

function cleanup() {
    virsh undefine ${VMNAME}-${UUID}
    mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.brk
    abort "you must manally remove vm image file define in ${VMNAME:="N/A"}-${UUID:="N/A"}.brk!!!"
}
trap cleanup TERM
trap cleanup INT

[[ ! -x $(which pv) ]] && { abort "NO pv found!!"; }


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
    log "error" "$0: invalid size \`$1'" >&2
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

function change_vm_info() {
    local mnt_point=$1
    local guest_hostname=$2
    local guest_ipaddr=$3
    local guest_netmask=$4
    local guest_gw=$5
    local guest_uuid=$6

    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
#DNS1=10.0.2.1
IPADDR=${guest_ipaddr}
NETMASK=${guest_netmask}
GATEWAY=${guest_gw}
EOF
    cat <<EOF | tee ${mnt_point}/etc/sysconfig/network-scripts/route-eth0
${ROUTE:-""}
EOF
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost
${guest_ipaddr}    ${guest_hostname}
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { return 1; }
    sed -i "/^ListenAddress/d" ${mnt_point}/etc/ssh/sshd_config
    sed -i "/^Port.*$/a\ListenAddress ${guest_ipaddr}" ${mnt_point}/etc/ssh/sshd_config
    rm -f ${mnt_point}/ssh/ssh_host_*

    [[ -r "${mnt_point}/etc/.johnyin" ]] && chattr -i ${mnt_point}/etc/.johnyin 
    echo "$(date +%Y%m%d_%H%M%S) ${guest_uuid}" > ${mnt_point}/etc/.johnyin || { return 2; }
    chattr +i ${mnt_point}/etc/.johnyin || { return 3; }
    log "info" "set ip/gw/hostname/sshd_key OK"
    return 0
}

function genfile_img() {
    local kvm_pool=$1
    local vm_img=$2
    local tpl_img=$3
    local guest_hostname=$4
    local guest_ipaddr=$5
    local guest_netmask=$6
    local guest_gw=$7
    local guest_uuid=$8
    
    local mnt_point=/tmp/vm_mnt/
    mkdir -p ${mnt_point}
    [[ -r "${kvm_pool}/${vm_img}" ]] && {
        log "error" "image ${vm_img} exist in ${kvm_pool}";
        log "error"  "${vm_img} create failed!!!";
        return 1;
    }
    gunzip -c ${tpl_img} | pv | dd of=${kvm_pool}/${vm_img} || return 2
    # SectorSize * StartSector
    mount -o loop,offset=1048576 ${kvm_pool}/${vm_img} ${mnt_point}
    change_vm_info ${mnt_point} ${guest_hostname} ${guest_ipaddr} ${guest_netmask} ${guest_gw} ${guest_uuid}
    retval=$?
    umount ${mnt_point}
    #kpartx -dv /dev/${kvm_pool}/${vm_img}
    log "info" "     disk:OK ${retval}"
    return ${retval}
}
function genlvm_img() {
    local kvm_pool=$1
    local vm_img=$2
    local tpl_img=$3
    local guest_hostname=$4
    local guest_ipaddr=$5
    local guest_netmask=$6
    local guest_gw=$7
    local guest_uuid=$8
    
    local mnt_point=/tmp/vm_mnt/
    mkdir -p ${mnt_point}
    [[ -r "/dev/${kvm_pool}/${vm_img}" ]] && {
        log "error" "image ${vm_img} exist in ${kvm_pool}";
        log "error"  "${vm_img} create failed!!!";
        return 1;
    }
    filesize=$(stat --format=%s ${tpl_img}) 
    #lvcreate -L ${filesize}b -n ${vm_img} ${kvm_pool} || return 1
    lvcreate -L 8G -n ${vm_img} ${kvm_pool} || return 1
    gunzip -c ${tpl_img} | pv | dd of=/dev/${kvm_pool}/${vm_img} || return 2
    #lvremove -f ....
    kpartx -av /dev/${kvm_pool}/${vm_img} || return 3
    mount /dev/mapper/$(kpartx -l /dev/${kvm_pool}/${vm_img} | awk '{print $1}') ${mnt_point}
    change_vm_info ${mnt_point} ${guest_hostname} ${guest_ipaddr} ${guest_netmask} ${guest_gw} ${guest_uuid}
    retval=$?
    umount ${mnt_point}
    kpartx -dv /dev/${kvm_pool}/${vm_img}
    log "info" "     disk:OK ${retval}"
    return ${retval}
}

function genceph_img() {
    local ceph_pool=$1
    local vm_img=$2
    local tpl_img=$3
    local guest_hostname=$4
    local guest_ipaddr=$5
    local guest_netmask=$6
    local guest_gw=$7
    local guest_uuid=$8
    
    local mnt_point=/tmp/vm_mnt/
    mkdir -p ${mnt_point}
    local found_img=$(rbd -p ${ceph_pool} ls | grep "^${vm_img}$" >/dev/null 2>&1 && echo -n 1 || echo -n 0)
    if [ "${found_img}" == "1" ]; then
        log "error" "image ${vm_img} exist in ${ceph_pool}"
        log "error"  "${vm_img} create failed!!!"
        return 1
    fi 
    #rbd copy --image-feature layering ${tpl_img} ${ceph_pool}/${vm_img} || return 1
    gunzip -c ${tpl_img} | pv | rbd import --image-feature layering - ${ceph_pool}/${vm_img} || return 1
    #qemu-img convert -f qcow2 -O raw ${tpl_img} rbd:${ceph_pool}/${vm_img} || return 1
    local dev_rbd=$(rbd map ${ceph_pool}/${vm_img})
    mount -t xfs -o nouuid ${dev_rbd}p1 ${mnt_point} || { rbd unmap ${dev_rbd}; return 2; }
    change_vm_info ${mnt_point} ${guest_hostname} ${guest_ipaddr} ${guest_netmask} ${guest_gw} ${guest_uuid}
    retval=$?
    umount ${mnt_point} || { rbd unmap ${dev_rbd}; return 8; }
    rbd unmap ${dev_rbd} || return 9
    log "info" "     disk:OK ${retval}"
    return ${retval}
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
$(if [ "${STORE_TYPE}"X == "file"X ]; then
echo "   <disk type='file' device='disk'>"
echo "      <driver name='qemu' type='raw' cache='none' io='native'/>"
echo "      <source file='${ceph_pool}/${vm_img}'/>"
echo "      <backingStore/>"
echo "      <target dev='vda' bus='virtio'/>"
echo "    </disk>"
fi)
$(if [ "${STORE_TYPE}"X == "lvm"X ]; then
echo "    <disk type='block' device='disk'>"
echo "      <driver name='qemu' type='raw' cache='none' io='native'/>"
echo "      <source dev='/dev/${ceph_pool}/${vm_img}'/>"
echo "      <backingStore/>"
echo "      <target dev='vda' bus='virtio'/>"
echo "    </disk>"
fi)
$(if [ "${STORE_TYPE}"X == "rbd"X ]; then
echo "    <disk type='network' device='disk'>"
echo "      <auth username='libvirt'>"
echo "      <secret type='ceph' uuid='${ceph_secret_uuid}'/>"
echo "      </auth>"
echo "      <source protocol='rbd' name='${ceph_pool}/${vm_img}'>"
for mon in ${CEPH_MON}
do
echo "        <host name='${mon%%:*}' port='${mon##*:}'/>"
done
echo "      </source>"
echo "      <target dev='vda' bus='virtio'/>"
echo "    </disk>"
fi)
    <interface type='${NET_TYPE}'>
      <source ${NET_TYPE}='${kvm_bridge}'/>
      <model type='virtio'/>
      <driver name="vhost"/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
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
[kvm]
#name
IP=10.0.2.2
NETMASK=255.255.255.0
#ROUTE="10.0.100.1 via 10.0.2.1
#192.160.1.1 via 10.0.2.1"
GATEWAY=10.0.2.1
#使用libvirt管理的net pool(可直接使用系统Bridge/ovs, virsh net-list）直接使用系统bridge
NET_TYPE=network
#NET_TYPE=bridge
KVM_BRIDGE=br-mgr
STORE_TYPE=rbd
#STORE_TYPE=lvm
#STORE_TYPE=file
STORE_POOL=libvirt-pool
TEMPLATE_IMG=CentOS7.4.tpl.gz
VMEMSIZE=1G
VCPUS=1
VM_TITLE="xx测试机1"
VM_DESC="描述灭有1"

EOF
    abort "Created ${CFG_INI} using defaults.  Please review it/configure before running again."
}


for i in $(getinientry "${CFG_INI}")
do
    UUID=$(cat /proc/sys/kernel/random/uuid)
    VMNAME="$(lowercase $i)"
    unset IP NETMASK GATEWAY TEMPLATE_IMG VCPUS VMEMSIZE VM_TITLE VM_DESC 
    unset NET_TYPE KVM_BRIDGE STORE_TYPE STORE_POOL ROUTE
    readini "$i" "${CFG_INI}"
    #[ ! -z "${IP}" ] && {
    #}
    VM_IMG=${VMNAME}-${UUID}.raw
    VM_TITLE=${VM_TITLE:-"n/a"}
    VM_DESC=${VM_DESC:-"n/a"}

    log "info" "Create vm:${VMNAME}"
    log "info" "    vcpus:${VCPUS}"
    log "info" "   memory:${VMEMSIZE}"
    log "info" "    title:${VM_TITLE}"
    log "info" "     desc:${VM_DESC}"
    log "info" "     disk:${VM_IMG}"
    log "info" "       ip:${IP}"
    log "info" "  netmask:${NETMASK}"
    log "info" "       gw:${GATEWAY}"
    log "info" "    kvmif:${KVM_BRIDGE}"
    log "info" "  nettype:${NET_TYPE}"
    if [ "${STORE_TYPE}"X == "rbd"X ]; then
        log "info" "     disk:rbd:${STORE_POOL}/${VM_IMG}"
    fi
    if [ "${STORE_TYPE}"X == "lvm"X ]; then
        log "info" "     disk:lvm:${STORE_POOL}/${VM_IMG}"
    fi
    log "info" " template:${TEMPLATE_IMG}"
    if  [ ! -f "${TEMPLATE_IMG}" ]; then
        log "error" " template:${TEMPLATE_IMG} no found"
        log "info" "============================================================================";
        continue
    fi

    ceph_secret_uuid=$(virsh secret-list | grep libvirt | awk '{ print $1}')
    genkvm_xml "${VMNAME}-${UUID}" ${ceph_secret_uuid:-"n/a"} ${STORE_POOL} ${VM_IMG} "${VM_TITLE}" "${VM_DESC}" ${UUID} ${KVM_BRIDGE} $(($(parse_size ${VMEMSIZE})/1024)) ${VCPUS}
    virsh define ${VMNAME}-${UUID} > /dev/null 2>&1 || {
        log "warn" "   define:FAILED";
        mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err;
        log "info" "============================================================================";
        continue;
    } 
    virsh domuuid ${VMNAME}-${UUID} > /dev/null 2>&1 || {
        mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err;
        log "warn" "   status:FAILED";
        log "info" "============================================================================";
        continue;
    }
    if [ "${STORE_TYPE}"X == "rbd"X ]; then
        genceph_img ${STORE_POOL} ${VM_IMG} ${TEMPLATE_IMG} "${VMNAME}" ${IP} ${NETMASK} ${GATEWAY} ${UUID}
        retval=$?
        if [[ $retval != 0  ]]; then
            rbd rm ${STORE_POOL}/${VM_IMG}
            virsh undefine ${VMNAME}-${UUID}
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err
            log "error" "ErrorCode :$retval"
            log "info" "============================================================================"
            continue
        fi
    fi
    if [ "${STORE_TYPE}"X == "lvm"X ]; then
        genlvm_img ${STORE_POOL} ${VM_IMG} ${TEMPLATE_IMG} "${VMNAME}" ${IP} ${NETMASK} ${GATEWAY} ${UUID}
        retval=$?
        if [[ $retval != 0  ]]; then
            virsh undefine ${VMNAME}-${UUID}
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err
#lvremove -f /dev/${STORE_POOL}/${VM_IMG}
            log "error" "ErrorCode :$retval"
            log "info" "============================================================================"
            continue
        fi
    fi
    if [ "${STORE_TYPE}"X == "file"X ]; then
        genfile_img ${STORE_POOL} ${VM_IMG} ${TEMPLATE_IMG} "${VMNAME}" ${IP} ${NETMASK} ${GATEWAY} ${UUID}
        retval=$?
        if [[ $retval != 0  ]]; then
            virsh undefine ${VMNAME}-${UUID}
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err
            log "error" "ErrorCode :$retval"
            log "info" "============================================================================"
            continue
        fi
    fi
    log "info" "   status:OK";
    log "info" "============================================================================"
done
exit 0
