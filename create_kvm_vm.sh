#!/bin/bash
set -o nounset -o pipefail

CEPH_MON=${CEPH_MON:-"kvm1:6789 kvm02:6789 kvm03:6789"}
KVM_USER=${KVM_USER:-root}
KVM_HOST=${KVM_HOST:-10.32.151.250}
KVM_PORT=${KVM_PORT:-22}
TIMESERVER=${TIMESERVER:-10.0.2.1}
CFG_INI=${CFG_INI:-"hosts.ini"}

VIRSH_OPT="-c qemu+ssh://${KVM_USER}@${KVM_HOST}:${KVM_PORT}/system"
SSH_OPT="-o StrictHostKeyChecking=no -p ${KVM_PORT} ${KVM_USER}@${KVM_HOST}"

readonly ZIP=gzip
readonly UNZIP=gunzip

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

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
            output "${timestamp} \e[1;33mW: ${MSG}\e[0m"
            ;;
        "error")
            output "${timestamp} \e[1;31mE: ${MSG}\e[0m"
            ;;
        "debug")
            output "${timestamp} \e[1;32mD: ${MSG}\e[0m"
            ;;
    esac
}

abort() {
    log "error" "${*}"
    exit 1
}

function fake_virsh {
    log "info" "virsh ${VIRSH_OPT} ${*}"
    virsh ${VIRSH_OPT} ${*} 2>/dev/null
}

function cleanup() {
    fake_virsh undefine ${VMNAME}-${UUID} --remove-all-storage
    mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.brk
    abort "you must manally remove vm image file define in ${VMNAME:="N/A"}-${UUID:="N/A"}.brk!!!"
}
trap cleanup TERM
trap cleanup INT

for i in pv stat ${ZIP} ${UNZIP} ssh dd mount umount parted
do
    [[ ! -x $(which $i) ]] && { abort "$i no found"; }
done

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
    local guest_prefix=$4
    local guest_route=$5
    local guest_uuid=$6
    unset VERSION_ID ID
    retval=250
    eval "$(cat ${mnt_point}/etc/*-release | grep "^VERSION_ID")"
    eval "$(cat ${mnt_point}/etc/*-release | grep  "^ID=")"
    TARGET_FUNC="change_vm_info_${ID}${VERSION_ID}"
    if [ "$(type -t ${TARGET_FUNC})" = "function" ] ; then
        eval "${TARGET_FUNC} '$1' '$2' '$3' '$4' '$5' \"$6\""
        retval=$?
    else
        log "error" "can not change vm info,[${ID} ${VERSION_ID}]"
    fi
    unset VERSION_ID ID
    return ${retval}
}

function change_vm_info_debian9() {
    local mnt_point=$1
    local guest_hostname=$2
    local guest_ipaddr=$3
    local guest_prefix=$4
    local guest_route=$5
    local guest_uuid=$6
    cat > ${mnt_point}/etc/network/interfaces.d/eth0 <<EOF
allow-hotplug eth0
iface eth0 inet static
    address ${guest_ipaddr}/${guest_prefix}
    ${guest_route}
EOF
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${guest_hostname}
${guest_ipaddr}    ${guest_hostname}
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { return 1; }
    cat > ${mnt_point}/etc/rc.local <<-EOF
#!/bin/sh -e
exit 0
EOF
    chmod 755 ${mnt_point}/etc/rc.local
    rm -f ${mnt_point}/ssh/ssh_host_*
    return 0
}
function change_vm_info_centos7() {
    local mnt_point=$1
    local guest_hostname=$2
    local guest_ipaddr=$3
    local guest_prefix=$4
    local guest_route=$5
    local guest_uuid=$6

    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
#DNS1=10.0.2.1
IPADDR=${guest_ipaddr}
PREFIX=${guest_prefix}
EOF
#    cat <<EOF | tee ${mnt_point}/etc/sysconfig/network-scripts/route-eth0
    cat > ${mnt_point}/etc/sysconfig/network-scripts/route-eth0 <<-EOF
${guest_route}
EOF
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${guest_hostname}
${guest_ipaddr}    ${guest_hostname}
EOF
    echo "${guest_hostname}" > ${mnt_point}/etc/hostname || { return 1; }
    sed -i "/^ListenAddress/d" ${mnt_point}/etc/ssh/sshd_config
    sed -i "/^Port.*$/a\ListenAddress ${guest_ipaddr}" ${mnt_point}/etc/ssh/sshd_config
    sed -i "s/#local stratum 10/local stratum 10/g" ${mnt_point}/etc/chrony.conf
    sed -i "/^server/d" ${mnt_point}/etc/chrony.conf
    sed -i "3 a server ${TIMESERVER} iburst" ${mnt_point}/etc/chrony.conf
    chmod 755 ${mnt_point}/etc/rc.d/rc.local
    rm -f ${mnt_point}/ssh/ssh_host_*
    return 0
}
# add dynamic vcpus
# <vcpu placement='static' current='1'>2</vcpu>
function genkvm_xml(){
    local vmname=$1
    local ceph_secret_uuid=$2
    local s_path=$3
    local vm_img=$4
    local title=$5
    local desc=$6
    local uuid=$7
    local kvm_bridge=$8
    local memsize=$9
    local vcpus=${10}
#<cpu mode="host-passthrough"/>
#<cpu mode='host-model'/>
    cat > ${vmname}<<EOF
<domain type='kvm'>
  <name>${vmname}</name>
  <uuid>${uuid}</uuid>
  <title>${title}</title>
  <description>${desc}</description>
  <memory unit='KiB'>${memsize}</memory>
  <currentMemory unit='KiB'>${memsize}</currentMemory>
  <vcpu>${vcpus}</vcpu>
  <cpu mode='host-passthrough'/>
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
echo "      <source file='${s_path}/${vm_img}'/>"
echo "      <backingStore/>"
echo "      <target dev='vda' bus='virtio'/>"
echo "    </disk>"
fi)
$(if [ "${STORE_TYPE}"X == "lvm"X ]; then
echo "    <disk type='block' device='disk'>"
echo "      <driver name='qemu' type='raw' cache='none' io='native'/>"
echo "      <source dev='${s_path}/${vm_img}'/>"
echo "      <backingStore/>"
echo "      <target dev='vda' bus='virtio'/>"
echo "    </disk>"
fi)
$(if [ "${STORE_TYPE}"X == "rbd"X ]; then
echo "    <disk type='network' device='disk'>"
echo "      <auth username='libvirt'>"
echo "      <secret type='ceph' uuid='${ceph_secret_uuid}'/>"
echo "      </auth>"
echo "      <source protocol='rbd' name='${s_path}/${vm_img}'>"
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
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
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
EOF
}

function rbd_GenImg() {
    local s_path=$1
    local vm_img=$2
    local tpl_img=$3
    local s_pool=$4
    filesize=$(stat --format=%s ${tpl_img})
    #fake_virsh vol-clone ${tpl_img} ${vm_img} --pool ${s_path}
    dd if=${tpl_img} 2>/dev/null | pv -s ${filesize} | ${ZIP} -c | ssh ${SSH_OPT} "${UNZIP} -c | rbd import --image-feature layering - ${s_path}/${vm_img}"
}
function file_GenImg() {
    local s_path=$1
    local vm_img=$2
    local tpl_img=$3
    local s_pool=$4
    filesize=$(stat --format=%s ${tpl_img})
    dd if=${tpl_img} 2>/dev/null | pv -s ${filesize} | ${ZIP} -c | ssh ${SSH_OPT} "${UNZIP} -c | dd of=${s_path}/${vm_img} 2>/dev/null"
}
function lvm_GenImg() {
    local s_path=$1
    local vm_img=$2
    local tpl_img=$3
    local s_pool=$4
    filesize=$(stat --format=%s ${tpl_img})
    fake_virsh vol-create-as --pool ${s_pool} --name ${vm_img} --format raw --capacity ${filesize} >/dev/null
    dd if=${tpl_img} 2>/dev/null | pv -s ${filesize} | ${ZIP} -c | ssh ${SSH_OPT} "${UNZIP} -c | dd of=${s_path}/${vm_img} 2>/dev/null"
}
function DelImg() {
    local store_pool=$1
    local vm_img=$2
    log "info" "del ${*}"
    fake_virsh vol-delete ${vm_img} --pool ${store_pool} > /dev/null
}

function getStorePath() {
    local poolname=$1
    local key="delete-$(cat /proc/sys/kernel/random/uuid)"
    { fake_virsh vol-create-as --pool ${poolname} --name ${key} --capacity 1 --format raw; } > /dev/null 2>&1
    virsh ${VIRSH_OPT} vol-path --pool ${poolname} ${key} 
    { fake_virsh pool-refresh ${poolname}; } > /dev/null 2>&1
    { fake_virsh vol-delete --pool ${poolname} ${key}; } > /dev/null 2>&1
}

function main() {
    [[ -r "${CFG_INI}" ]] || {
        cat >"${CFG_INI}" <<-EOF
[kvm]
#name
IP=10.0.2.2/24
ROUTE="default via 10.0.2.1
192.160.1.0/24 via 10.0.2.1 dev eth0"
#ROUTE="up ip r a default via 10.0.2.1 dev eth0
#    up ip r a 192.160.1.0/24 via 10.0.2.1 dev eth0"
#使用libvirt管理的net pool(可直接使用系统Bridge/ovs, virsh net-list）直接使用系统bridge
NET_TYPE=bridge
#NET_TYPE=network
#libvirt net-name
KVM_BRIDGE=br-mgr
STORE_TYPE=rbd
#STORE_TYPE=lvm
#STORE_TYPE=file
#libvirt pool-name
STORE_POOL=libvirt-pool
TEMPLATE_IMG=/tpl/CentOS7.4.tpl.raw
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
        unset IP TEMPLATE_IMG VCPUS VMEMSIZE VM_TITLE VM_DESC 
        unset NET_TYPE KVM_BRIDGE STORE_TYPE STORE_POOL ROUTE
        readini "$i" "${CFG_INI}"
        #[ ! -z "${IP}" ] && {
        #}
        PREFIX=${IP##*/}
        IP=${IP%/*}
        VM_IMG=${VMNAME}-${UUID}.raw
        VM_TITLE=${VM_TITLE:-"n/a"}
        VM_DESC=${VM_DESC:-"n/a"}
        log "info" "Create vm:${VMNAME}"
        log "info" "    vcpus:${VCPUS}"
        log "info" "   memory:${VMEMSIZE}"
        log "info" "    title:${VM_TITLE}"
        log "info" "     desc:${VM_DESC}"
        log "info" "     disk:${VM_IMG}"
        log "info" "       ip:${IP}/${PREFIX}"
        log "info" "    kvmif:${KVM_BRIDGE}"
        log "info" "  nettype:${NET_TYPE}"
        ceph_secret_uuid=$(fake_virsh secret-list | grep libvirt | awk '{ print $1}')
        store_path="$(getStorePath ${STORE_POOL})"
        [[ -z ${store_path} ]] && {
            log "warn" "null store_path in ${STORE_POOL}";
            continue;
        }
        store_path=${store_path%/*}
        log "info" "     disk:${STORE_POOL}:${store_path}/${VM_IMG}"
        log "info" " template:${TEMPLATE_IMG}"
        if  [ ! -f "${TEMPLATE_IMG}" ]; then
            log "error" " template:${TEMPLATE_IMG} no found"
            continue
        fi
        genkvm_xml "${VMNAME}-${UUID}" ${ceph_secret_uuid:-"n/a"} "${store_path}" "${VM_IMG}" "${VM_TITLE}" "${VM_DESC}" "${UUID}" "${KVM_BRIDGE}" "$(($(parse_size ${VMEMSIZE})/1024))" "${VCPUS}"
        fake_virsh define ${VMNAME}-${UUID} >/dev/null  || {
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err;
            log "warn" "   define:FAILED";
            continue;
        } 
        fake_virsh domuuid ${VMNAME}-${UUID} >/dev/null || {
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err;
            log "warn" "   status:FAILED";
            continue;
        }

        local mnt_point=/tmp/vm_mnt/
        mkdir -p ${mnt_point}
        # SectorSize * StartSector
        SectorSize=$(parted ${TEMPLATE_IMG} unit s print | awk '/Sector size/{print $4}' | awk -F "B" '{print $1}')
        sst=$(parted ${TEMPLATE_IMG} unit s print | awk '/ 1  /{print $2}')
        StartSector=${sst:0:${#sst}-1}
        OffSet=$(($StartSector*$SectorSize))
        mount -o loop,offset=${OffSet} ${TEMPLATE_IMG} ${mnt_point}
        change_vm_info "${mnt_point}" "${VMNAME}" "${IP}" "${PREFIX}" "${ROUTE}" "${UUID}"
        retval=$?
        umount ${mnt_point}
        if [[ ${retval} != 0  ]]; then
            fake_virsh undefine ${VMNAME}-${UUID}
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err
            log "error" "ErrorCode :${retval}"
            continue
        fi
        log "info" "     disk:OK ${retval}"
        log "info" "upload ${STORE_TYPE} image ${VM_IMG} in ${STORE_POOL} ..."
        eval ${STORE_TYPE}_GenImg "${store_path}" "${VM_IMG}" "${TEMPLATE_IMG}" "${STORE_POOL}"
        retval=$?
        if [[ ${retval} != 0  ]]; then
            DelImg ${STORE_POOL} ${VM_IMG}
            fake_virsh undefine ${VMNAME}-${UUID}
            mv ${VMNAME}-${UUID} ${VMNAME}-${UUID}.err
            log "error" "ErrorCode :${retval}"
            continue
        fi
        fake_virsh pool-refresh ${STORE_POOL} > /dev/null
        log "info" "   status:OK";
        log "info" "============================================================================"
    done
    return 0 
}

[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"
