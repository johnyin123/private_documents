#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
KVM_USER=${KVM_USER:-root}
KVM_HOST=${KVM_HOST:-10.32.166.33}
KVM_PORT=${KVM_PORT:-60022}

VIRSH_OPT="-q -c qemu+ssh://${KVM_USER}@${KVM_HOST}:${KVM_PORT}/system"
VIRSH="virsh ${VIRSH_OPT}"

declare -A APP_ERRORS=(
    [0]="Success"
    [1]="vol-create-as"
    [2]="vol-path"
    [3]="vol-resize"
    [4]="vol-upload"
    [5]="attach-device"
    [6]="UUID/NET must set parm is null"

    [8]="define"
    [9]="Domain Not Exists"
)
# xmlstarlet ed -s '/disk' -t elem -n target --var target '$prev' -i '$target' -t attr -n dev -v 'vda' -i '$target' -t attr -n bus -v virtio dev.xml

domain_disk_dev() {
    local disks=("vda" "vdb" "vdc" "vdd" "vde" "vdf" "vdg" "vdh" "vdi" "vdj")
    local uuid=$1
    local last_disk=
    local xml=$(${VIRSH} dumpxml ${uuid})
    for ((i=1;i<10;i++))
    do
        #last_disk=$(printf "$xml" | xmllint --xpath "string(/domain/devices/disk[$i]/target/@dev)" -)
        last_disk=$(printf "$xml" | xmlstarlet sel -t -v "/domain/devices/disk[$i]/target/@dev")
        [[ -z "${last_disk}" ]] && { echo ${disks[((i-1))]} ; return 0; }
    done
    return 0
}

domain_live() {
    local uuid=$1
    ${VIRSH} list --state-running --uuid | grep ${uuid} && echo "--live" || echo ""
}

attach_device() {
    local arr=$1
    local type=$2
    local uuid="$(array_get ${arr} 'UUID')"
    local live=$(_domain_live "${uuid}")
    info_msg "${uuid} attach ${type} device ${live}\n"
    printf "${DEVICE_TPL[${type}]}\n" | render_tpl ${arr} | try ${VIRSH} attach-device ${uuid} --file /dev/stdin --persistent ${live} || return 5;
    return 0
}

create_vol() {
    local arr=$1
    local pool="$(array_get ${arr} 'POOL')"
    local name="$(array_get ${arr} 'LAST_DISK')-$(array_get ${arr} 'UUID').raw"
    info_msg "${name} create\n"
    local size="$(array_get ${arr} 'SIZE')"
    local disk_tpl="$(array_get ${arr} 'DISK_TPL')"
    try ${VIRSH} vol-create-as --pool ${pool} --name ${name} --capacity 1M --format raw || return 1
    try ${VIRSH} vol-resize --pool ${pool} --vol ${name} --capacity ${size} || return 3
    [[ -z "${disk_tpl}" ]] || { try ${VIRSH} vol-upload --pool ${pool} --vol ${name} --file ${disk_tpl} || return 4; }
    return 0
}

get_storepath() {
    local pool=$1
    local name=$2
    ${VIRSH} vol-path --pool "${pool}" "${name}" 
}

create_domain() {
    local arr=$1
    local uuid="$(array_get ${arr} 'UUID')"
    local tpl="$(array_get ${arr} 'DOMAIN_TPL')"
    printf "${DOMAIN_TPL[${tpl}]}\n" | render_tpl ${arr} | try ${VIRSH} define --file /dev/stdin || return 8;
    array_set vm "LAST_DISK" "$(domain_disk_dev $uuid)"
    create_vol ${arr} || return $?
    #name must same as create_vol()
    local name="$(array_get ${arr} 'LAST_DISK')-${uuid}.raw"
    local store_path="$(get_storepath $(array_get ${arr} 'POOL') ${name})" || return 2
    array_set vm "STORE_PATH" "${store_path}"
    attach_device ${arr} "$(array_get ${arr} 'POOL')" || return $?
    attach_device ${arr} "$(array_get ${arr} 'NET')" || return $?
    return 0
}

set_vm_defaults() {
    #N/A value must set in kv file
    readonly MUST_SET_VAL="must input"
    declare -A VM_DEFAULTS=(
        [UUID]="${MUST_SET_VAL}"
        [NET]="${MUST_SET_VAL}"
        [CPUS]="2"
        [MEM]="2097152"
        [POOL]="default"
        [SIZE]="4G"
        [DISK_TPL]=""
        [DESC]="no desc"
        [NAME]="vm"
        [DOMAIN_TPL]="default"
        [LAST_DISK]="runtime set"
        [STORE_PATH]="runtime set"
    )
    declare -n _org=${1}
    for name in $(array_print_label VM_DEFAULTS)
    do
        array_idx_exist _org ${name} || array_set _org "${name}" "$(array_get VM_DEFAULTS '${name}')"
        [[ "$(array_get _org ${name})" = "${MUST_SET_VAL}" ]] && return 6
    done
    return 0
}

failed_destroy_vm() {
    declare -n __ref=$1
    local err=$2
    local uuid="$(array_get __ref 'UUID')"
    local pool="$(array_get __ref 'POOL')"
    local disk="$(array_get __ref 'LAST_DISK')-${uuid}.raw"
    local tpl="$(array_get __ref 'DOMAIN_TPL')"
    error_msg "create ${uuid} with tpl(${tpl}): $(array_get APP_ERRORS $err $err) error\n"
    print_kv vm
    try ${VIRSH} vol-delete "${disk}" --pool "${pool}" || error_msg "vol-delete ${disl} in ${pool} error\n"
    try ${VIRSH} pool-refresh "${pool}"
    try ${VIRSH} undefine "${uuid}" --remove-all-storage || error_msg "undefine ${uuid} with --remove-all-storage error\n"
    return 0
}

create() {
    local val=
    declare -A vm
    while test $# -gt 0
    do
        local opt="$1"
        shift
        case "${opt}" in
            -u|--uuid)
                val=${1:?uuid must input};shift 1
                array_set vm "UUID" "${val}"
                ;;
            -c|--cpus)
                val=${1:?cpu must input};shift 1
                array_set vm "CPUS" "${val}"
                ;;
            -m|--mem)
                val=${1:?mem must input};shift 1
                array_set vm "MEM" "${val}"
                ;;
            -n|--net)
                val=${1:?net tpl need input};shift 1
                array_set vm "NET" "${val}"
                ;;
            -p|--pool)
                val=${1:?disk pool need input};shift 1
                array_set vm "POOL" "${val}"
                ;;
            -s|--size)
                val=${1:?disk size need input};shift 1
                array_set vm "SIZE" "${val}"
                ;;
            -t|--template)
                val=${1:?disk template must input};shift 1
                array_set vm "DISK_TPL" "${val}"
                ;;
            -D|--desc)
                val=${1:?desc must input};shift 1
                array_set vm "DESC" "${val}"
                ;;
            -N|--name)
                val=${1:?name(title) must input};shift 1
                array_set vm "NAME" "${val}"
                ;;


            -q | --quiet)
                QUIET=1
                ;;
            -l | --log)
                set_loglevel ${1}; shift
                ;;
            -d | --dryrun)
                DRYRUN=1
                ;;
            -h | --help)
                usage
                ;;
            *)
                array_set vm "DOMAIN_TPL" "${opt}"
                ;;
        esac
    done
    set_vm_defaults vm || return $?
    local uuid="$(array_get vm 'UUID')"
    info_msg "create vm ${uuid} as:\n$(print_kv vm)\n"

    local exists="$(${VIRSH} list --all --uuid | grep ${uuid})"
    [[ -z "${exists}" ]] || { error_msg "Domain ${uuid} exists!!\n"; return 0; }
    create_domain vm || { err=$?; failed_destroy_vm vm $err; return $err; }
    info_msg "==========================\n"
    return 0
}

attach() {
    exit_msg "NEED impl\n"
    local val=
    declare -A vm
    while test $# -gt 0
    do
        local opt="$1"
        shift
        case "${opt}" in
            -u|--uuid)
                val=${1:?uuid must input};shift 1
                array_set vm "UUID" "${val}"
                ;;
            -n|--net)
                val=${1:?net tpl need input};shift 1
                array_set vm "NET" "${val}"
                ;;
            -p|--pool)
                val=${1:?disk pool need input};shift 1
                array_set vm "POOL" "${val}"
                ;;
            -s|--size)
                val=${1:?disk size need input};shift 1
                array_set vm "SIZE" "${val}"
                ;;

            -q | --quiet)
                QUIET=1
                ;;
            -l | --log)
                set_loglevel ${1}; shift
                ;;
            -d | --dryrun)
                DRYRUN=1
                ;;
            -h | --help)
                usage
                ;;
            *)
                array_set vm "DOMAIN_TPL" "${opt}"
                ;;
        esac
    done
    set_vm_defaults vm || return $?
    local uuid="$(array_get vm 'UUID')"
    info_msg "create vm ${uuid} as:\n$(print_kv vm)\n"

    local exists="$(${VIRSH} list --all --uuid | grep ${uuid})"
    [[ -z "${exists}" ]] || { error_msg "Domain ${uuid} exists!!\n"; return 0; }
    create_domain vm || { err=$?; failed_destroy_vm vm $err; return $err; }
    info_msg "==========================\n"
    return 0
}
usage() {
cat <<EOF
${SCRIPTNAME} <cmd> arg [domain_template]
cmd:create
    -u|--uuid <uuid>           *             domain uuid
    -c|--cpus <cpu>
    -m|--mem <mem KB>
    -n|--net <tpl-name>        *             network template name in cfg
    -p|--pool <pool>                         kvm storage pool
    -s|--size <size>                         <size> GB/MB/KB
    -t|--template <tpl>                      disk_template for upload if exists 
    -D|--desc <desc>                         desc
    -N|--name <title>                        name(title)

cmd:attach
    -u|--uuid <uuid>                         domain uuid
    -a|--attach <tpl>                        attach device (can multi)
    -D|--disk <pool> <size>                  attach addtition disk with disk_template (can multi)
    -q|--quiet
    -l|--log <int>                           log level
    -V|--version
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit
EOF
exit 1
}

main() {
    local CFG_INI=${CFG_INI:-"mgr.conf"}
    [[ -r "${CFG_INI}" ]] || {
        cat >"${CFG_INI}" <<'EOF'
declare -A DOMAIN_TPL=(
    [default]="
<domain type='kvm'>
  <name>\${NAME}-\${UUID}</name>
  <uuid>\${UUID}</uuid>
  <title>\${NAME}</title>
  <description>\${DESC}</description>
  <memory unit='KiB'>8388608</memory>
  <currentMemory unit='KiB'>\${MEM}</currentMemory>
  <vcpu placement='static' current='\${CPUS}'>8</vcpu>
  <cpu match='exact'><model fallback='allow'>Westmere</model></cpu>
  <os><type arch='x86_64'>hvm</type></os>
  <features><acpi/><apic/><pae/></features>
  <on_poweroff>preserve</on_poweroff>
  <devices>
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
</domain>"
)
#![vol-pool]="<disk>..</disk>"
declare -A DEVICE_TPL=(
    [default]="
<disk type='file' device='disk'>
   <driver name='qemu' type='raw' cache='none' io='native'/>
   <source file='\${STORE_PATH}'/>
   <backingStore/>
   <target dev='\${LAST_DISK}' bus='virtio'/>
</disk>"
    [lvm]="
<disk type='block' device='disk'>
  <driver name='qemu' type='raw' cache='none' io='native'/>
  <source dev='TH}'/>
  <backingStore/>
  <target dev='\${LAST_DISK}' bus='virtio'/>
</disk>"
    [cephpool]="
<disk type='network' device='disk'>
  <auth username='libvirt'>
  <secret type='ceph' uuid='2dfb5a49-a4e9-493a-a56f-4bd1bf26a149'/>
  </auth>
  <source protocol='rbd' name='\${STORE_PATH}'>
    <host name='node01' port='6789'/>
    <host name='node02' port='6789'/>
    <host name='node03' port='6789'/>
    <host name='node04' port='6789'/>
    <host name='node05' port='6789'/>
    <host name='node06' port='6789'/>
    <host name='node07' port='6789'/>
  </source>
  <target dev='\${LAST_DISK}' bus='virtio'/>
</disk>"
    [br_mgmt.2430]="
<interface type='network'>
  <source network='br_mgmt.2430'/>
  <model type='virtio'/>
  <driver name='vhost'/>
</interface>"
)
EOF
        exit_msg "Created ${CFG_INI} using defaults.  Please review it/configure before running again."
    }
    source "${CFG_INI}"

    local opt="${1:?at least one parm}"
    shift 1
    case "${opt}" in
        create)
            create "$@"
            return $?
            ;;
        attach)
            attach "$@"
            return $?
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
