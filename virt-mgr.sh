#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
# KVM_USER=${KVM_USER:-root}
# KVM_HOST=${KVM_HOST:-127.0.0.1}
# KVM_PORT=${KVM_PORT:-60022}
VIRSH_OPT="-q ${KVM_HOST:+-c qemu+ssh://${KVM_USER:-root}@${KVM_HOST}:${KVM_PORT:-60022}/system}"
VIRSH="virsh ${VIRSH_OPT}"

declare -A APP_ERRORS=(
    [0]="success"
    [1]="vol-create-as"
    [2]="vol-path"
    [3]="vol-resize"
    [4]="vol-upload"
    [5]="attach-device"
    [6]="uuid/net must set parm is null"
    [7]="set last disk dev(too many disk)"
    [8]="domain define"
    [9]="domain exists/not exists"
    [10]="template not exists"
)
# xmlstarlet ed -s '/disk' -t elem -n target --var target '$prev' -i '$target' -t attr -n dev -v 'vda' -i '$target' -t attr -n bus -v virtio dev.xml

set_last_disk() {
    local disks=("vda" "vdb" "vdc" "vdd" "vde" "vdf" "vdg" "vdh" "vdi" "vdj" "vdk" "vdl" "vdm" "vdn" "vdo")
    local arr=$1
    local uuid="$(array_get ${arr} 'UUID')"
    local last_disk=
    local xml=$(${VIRSH} dumpxml ${uuid} 2>/dev/null)
    [[ -z "${xml}" ]] && return 9
    for ((i=1;i<10;i++))
    do
        #last_disk=$(printf "$xml" | xmllint --xpath "string(/domain/devices/disk[$i]/target/@dev)" -)
        last_disk=$(printf "$xml" | xmlstarlet sel -t -v "/domain/devices/disk[$i]/target/@dev")
        [[ -z "${last_disk}" ]] && { array_set ${arr} "LAST_DISK" "${disks[((i-1))]}" ; return 0; }
    done
    return 7
}

domain_live_arg() {
    local uuid=$1
    ${VIRSH} list --state-running --uuid | grep -q ${uuid} && echo "--live" || echo ""
}

attach_device() {
    local arr=$1
    local type=$2
    local uuid="$(array_get ${arr} 'UUID')"
    local live=$(domain_live_arg "${uuid}")
    info_msg "${uuid}(${live:-shut off}) attach ${type} device\n"
    array_label_exist DEVICE_TPL ${type} || return 10
    printf "${DEVICE_TPL[${type}]}\n" | render_tpl2 ${arr} | try ${VIRSH} attach-device --domain ${uuid} --file /dev/stdin --persistent ${live} || return 5;
    return 0;
}

create_vol() {
    local arr=$1
    local pool="$(array_get ${arr} 'POOL')"
    local fmt="$(array_get ${arr} 'FORMAT')"
    local name="$(array_get ${arr} 'LAST_DISK')-$(array_get ${arr} 'UUID').${fmt}"
    local size="$(array_get ${arr} 'SIZE')"
    local backing_vol="$(array_get ${arr} 'BACKING_VOL')"
    local backing_fmt="$(array_get ${arr} 'BACKING_FMT')"
    info_msg "create vol ${name} on ${pool} size ${size}\n"
    try ${VIRSH} vol-create-as --pool ${pool} --name ${name} --capacity 1M --format ${fmt} \
        ${backing_vol:+--backing-vol ${backing_vol} --backing-vol-format ${backing_fmt} } || return 1
    try ${VIRSH} vol-resize --pool ${pool} --vol ${name} --capacity ${size} || return 3
    local val=$(${VIRSH} vol-path --pool "${pool}" "${name}") || return 2
    array_set ${arr} "STORE_PATH" "${val}"
    return 0
}

create_domain() {
    local arr=$1
    local uuid="$(array_get ${arr} 'UUID')"
    local tpl="$(array_get ${arr} 'DOMAIN_TPL')"
    array_label_exist DOMAIN_TPL "${tpl}" || return 10
    printf "${DOMAIN_TPL[${tpl}]}\n" | render_tpl2 ${arr} | try ${VIRSH} define --file /dev/stdin || return 8;
    set_last_disk ${arr} || return $?
    create_vol ${arr} || return $?
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
        [FORMAT]="raw"
        [SIZE]="4G"
        [DESC]="no desc"
        [NAME]="vm"
        [DOMAIN_TPL]="default"
        [LAST_DISK]="runtime set"
        [STORE_PATH]="runtime set"
        [BACKING_VOL]=""
        [BACKING_FMT]=""
    )
    declare -n _org=${1}
    for name in $(array_print_label VM_DEFAULTS)
    do
        array_label_exist _org ${name} || array_set _org "${name}" "$(array_get VM_DEFAULTS '${name}')"
        [[ "$(array_get _org ${name})" = "${MUST_SET_VAL}" ]] && return 6
    done
    return 0
}

failed_destroy_vm() {
    declare -n __ref=$1
    local err=$2
    local uuid="$(array_get __ref 'UUID')"
    local pool="$(array_get __ref 'POOL')"
    local fmt="$(array_get ${arr} 'FORMAT')"
    local disk="$(array_get __ref 'LAST_DISK')-${uuid}.${fmt}"
    local tpl="$(array_get __ref 'DOMAIN_TPL')"
    error_msg "create ${uuid} with tpl(${tpl}): $(array_get APP_ERRORS $err $err)\n$(print_kv vm)\n"
    try ${VIRSH} vol-delete "${disk}" --pool "${pool}" || error_msg "vol-delete ${disk} in ${pool}\n"
    try ${VIRSH} pool-refresh "${pool}" || true
    try ${VIRSH} undefine "${uuid}" --remove-all-storage || error_msg "undefine ${uuid} with --remove-all-storage\n"
    return 0
}

create() {
    declare -A vm
    local opt_short="ql:dVhu:c:m:n:p:f:s:b:F:D:N:"
    local opt_long="quite,log:,dryrun,version,help,uuid:,cpus:,mem:,net:,pool:,format:,size:,back:,bfmt:,desc:,name:"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -u | --uuid)   array_set vm "UUID" "${2}"; shift 2;;
            -c | --cpus)   array_set vm "CPUS" "${2}"; shift 2;;
            -m | --mem)    array_set vm "MEM" "${2}"; shift 2;;
            -n | --net)    array_set vm "NET" "${2}"; shift 2;;
            -p | --pool)   array_set vm "POOL" "${2}"; shift 2;;
            -f | --format) array_set vm "FORMAT" "${2}"; shift 2;;
            -s | --size)   array_set vm "SIZE" "${2}"; shift 2;;
            -b | --back)   array_set vm "BACKING_VOL" "${2}"; shift 2;;
            -F | --bfmt)   array_set vm "BACKING_FMT" "${2}"; shift 2;;
            -D | --desc)   array_set vm "DESC" "${2}"; shift 2;;
            -N | --name)   array_set vm "NAME" "${2}"; shift 2;;
            -q | --quiet) QUIET=1; shift 1;;
            -l | --log) set_loglevel ${2}; shift 2;;
            -d | --dryrun) DRYRUN=1; shift 1;;
            -V | --version) exit_msg "${SCRIPTNAME} version\n";;
            -h | --help) shift 1; usage;;
            --) shift 1; break;;
        esac
    done
    array_set vm "DOMAIN_TPL" "${1:?$(usage)}"
    set_vm_defaults vm || return $?
    local uuid="$(array_get vm 'UUID')"
    info_msg "${uuid} create as:\n$(print_kv vm)\n"
    set_last_disk vm && { error_msg "create ${uuid}: domain exists!!"; return 9; }
    create_domain vm || { err=$?; failed_destroy_vm vm $err; return $err; }
    info_msg "${uuid} create success ====================\n"
    return 0
}

attach() {
    declare -A vm
    # set default disk format
    array_set vm "FORMAT" "raw"
    array_set vm "BACKING_VOL" ""
    array_set vm "BACKING_FMT" ""
    local opt_short="ql:dVhu:n:p:s:b:F:f:"
    local opt_long="quite,log:,dryrun,version,help,uuid:,net:,pool:,size:,format:,back:,bfmt:"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -u | --uuid)   array_set vm "UUID" "${2}"; shift 2;;
            -n | --net)    array_set vm "NET" "${2}"; shift 2;;
            -p | --pool)   array_set vm "POOL" "${2}"; shift 2;;
            -s | --size)   array_set vm "SIZE" "${2}"; shift 2;;
            -f | --format) array_set vm "FORMAT" "${2}"; shift 2;;
            -b | --back)   array_set vm "BACKING_VOL" "${2}"; shift 2;;
            -F | --bfmt)   array_set vm "BACKING_FMT" "${2}"; shift 2;;
            -q | --quiet) QUIET=1; shift 1;;
            -l | --log) set_loglevel ${2}; shift 2;;
            -d | --dryrun) DRYRUN=1; shift 1;;
            -V | --version) exit_msg "${SCRIPTNAME} version\n";;
            -h | --help) shift 1; usage;;
            --) shift 1; break;;
            *)  error_msg "Unexpected option: $1.\n"; usage;;
        esac
    done
    array_label_exist vm 'UUID' || usage
    local uuid="$(array_get vm 'UUID')"
    info_msg "vm ${uuid} add device as:\n"
    print_kv vm | vinfo_msg
    set_last_disk vm || { err=$?; error_msg "attach ${uuid}: $(array_get APP_ERRORS $err $err)\n"; return $err; }
    array_label_exist vm 'POOL' && {
        array_label_exist vm 'SIZE' || usage
        local pool="$(array_get vm 'POOL')"
        local fmt="$(array_get vm 'FORMAT')"
        local size="$(array_get vm 'SIZE')"
        local disk="$(array_get vm 'LAST_DISK')-${uuid}.${fmt}"
        create_vol vm || { err=$?; error_msg "attach ${uuid}: $(array_get APP_ERRORS $err $err)\n"; return $err; }
        attach_device vm "$(array_get vm 'POOL')" || {
                err=$?;
                error_msg "attach disk ${uuid}: $(array_get APP_ERRORS $err $err)\n$(print_kv vm)\n"; 
                info_msg "remove ${disk} on ${pool} ${size}\n";
                try ${VIRSH} vol-delete "${disk}" --pool "${pool}" || error_msg "vol-delete ${disk} in ${pool}\n";
                try ${VIRSH} pool-refresh "${pool}";
                return $err;
        }
        info_msg "add ${disk} ${size} in ${pool}\n";
    }
    array_label_exist vm 'NET' && {
        attach_device vm "$(array_get vm 'NET')" || {
            err=$?;
            error_msg "attach device ${uuid}: $(array_get APP_ERRORS $err $err) error\n$(print_kv vm)\n";
            return $err;
        } && {
            info_msg "add device $(array_get vm 'NET')\n";
        }
    }
    info_msg "${uuid} attach success ====================\n"
    return 0
}
usage() {
cat <<EOF
${SCRIPTNAME} <cmd> <arg>
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit

cmd:create <arg> [domain_template in cfg]
        create domain with configurations
    -u|--uuid <uuid>           *             domain uuid
    -c|--cpus <cpu>
    -m|--mem <mem KB>
    -n|--net <tpl-name>        *             network template name in cfg
    -p|--pool <pool>                         kvm storage pool
    -f|--format <fmt>                        disk format,default raw
    -s|--size <size>                         <size> GB/MB/KB
    -b|--back <backing vol>                  disk backing vol file
    -F|--bfmt <backing format>               disk backing vol format
    -D|--desc <desc>                         desc
    -N|--name <title>                        name(title)

cmd:attach <arg>
        attach device(net/disk/etc)
    -u|--uuid <uuid>           *             domain uuid
    -n|--net <tpl-name>        *             network template name in cfg
    -p|--pool <pool>           *             kvm storage pool
    -s|--size <size>           *             <size> GB/MB/KB
    -f|--format <fmt>                        disk format,default raw
    -b|--back <backing vol>                  disk backing vol file
    -F|--bfmt <backing format>               disk backing vol format
EOF
exit 1
} >&2

main() {
    local CFG_INI=${CFG_INI:-"mgr.conf"}
    [[ -r "${CFG_INI}" ]] || {
        cat >"${CFG_INI}" <<'EOF'
declare -A DOMAIN_TPL=(
    [default]="
<domain type='kvm'>
  <name>{{NAME}}-{{UUID}}</name>
  <uuid>{{UUID}}</uuid>
  <title>{{NAME}}</title>
  <description>{{DESC}}</description>
  <memory unit='KiB'>8388608</memory>
  <currentMemory unit='KiB'>{{MEM}}</currentMemory>
  <vcpu placement='static' current='{{CPUS}}'>8</vcpu>
  <cpu match='exact'><model fallback='allow'>Westmere</model></cpu>
  <os><type arch='x86_64'>hvm</type>
    <loader readonly='yes' type='pflash'>/usr/share/OVMF/OVMF_CODE.fd</loader>
    <nvram>/var/lib/libvirt/qemu/nvram/rhel8-unknown_VARS.fd</nvram>
  </os>
  <features><acpi/><apic/><pae/></features>
  <on_poweroff>preserve</on_poweroff>
  <devices>
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
   <driver name='qemu' type='{{FORMAT}}' cache='none' io='native'/>
   <source file='{{STORE_PATH}}'/>
   <backingStore/>
   <target dev='{{LAST_DISK}}' bus='virtio'/>
</disk>"
    [lvm]="
<disk type='block' device='disk'>
  <driver name='qemu' type='{{FORMAT}}' cache='none' io='native'/>
  <source dev='{{STORE_PATH}}'/>
  <backingStore/>
  <target dev='{{LAST_DISK}}' bus='virtio'/>
</disk>"
    [cephpool]="
<disk type='network' device='disk'>
  <driver name='qemu' type='{{FORMAT}}'/>
  <auth username='libvirt'>
  <secret type='ceph' uuid='2dfb5a49-a4e9-493a-a56f-4bd1bf26a149'/>
  </auth>
  <source protocol='rbd' name='{{STORE_PATH}}'>
    <host name='node01' port='6789'/>
    <host name='node02' port='6789'/>
    <host name='node03' port='6789'/>
    <host name='node04' port='6789'/>
    <host name='node05' port='6789'/>
    <host name='node06' port='6789'/>
    <host name='node07' port='6789'/>
  </source>
  <target dev='{{LAST_DISK}}' bus='virtio'/>
</disk>"
    [br-ext]="
<interface type='network'>
  <source network='br_mgmt.2430'/>
  <model type='virtio'/>
  <driver name='vhost'/>
</interface>"
    [br_mgmt.2430]="
<interface type='network'>
  <source network='br_mgmt.2430'/>
  <model type='virtio'/>
  <driver name='vhost'/>
</interface>"
)
EOF
        ${EDITOR:-vi} ${CFG_INI} || true
        exit_msg "Created ${CFG_INI} using defaults.  Please review it/configure before running again.\n"
    }
    source "${CFG_INI}"
    info_msg "DOMAIN TEMPLATE:\n"
    array_print_label DOMAIN_TPL | sed "s/\(.*\)/    [\1]/g" | vinfo_msg
    info_msg "DEVICE TEMPLATE:\n"
    array_print_label DEVICE_TPL | sed "s/\(.*\)/    [\1]/g" | vinfo_msg
    local opt="${1:?$(usage)}"
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
