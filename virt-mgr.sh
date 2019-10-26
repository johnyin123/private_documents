#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
KVM_USER=${KVM_USER:-root}
KVM_HOST=${KVM_HOST:-10.32.166.33}
KVM_PORT=${KVM_PORT:-60022}

VIRSH_OPT="-q -c qemu+ssh://${KVM_USER}@${KVM_HOST}:${KVM_PORT}/system"
VIRSH="virsh ${VIRSH_OPT}"

#N/A value must set in kv file
readonly MUST_SET_VAL="N/A"
declare -A VM_DEFAULTS=(
    [VM_UUID]="${MUST_SET_VAL}"
    [VM_NAME]="vm"
    [VM_CPUS]="2"
    [VM_MEM]="2097152"
    [VM_TITLE]="vm"
    [VM_DESC]="no desc"
    [SYS_POOL]="default"
    [SYS_SIZE]="4G"
    [SYS_TPL]=""
    [SYS_NET]="${MUST_SET_VAL}"
)

declare -A APP_ERRORS=(
    [0]="Success"
    [1]="vol-create-as"
    [2]="vol-path"
    [3]="vol-resize"
    [4]="vol-upload"
    [5]="attach-device"
    [6]="VM_UUID/SYS_NET NULL"
    [7]="Domain Exists"
    [8]="define"
    [9]="Domain Not Exists"
)
# xmlstarlet ed -s '/disk' -t elem -n target --var target '$prev' -i '$target' -t attr -n dev -v 'vda' -i '$target' -t attr -n bus -v virtio dev.xml
# [POOL]=xml
declare -A DEVICE_TPL=(
    [default]="
<disk type='file' device='disk'>
   <driver name='qemu' type='raw' cache='none' io='native'/>
   <source file='/storage/vda-\${UUID}.raw'/>
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

_set_vm_defaults() {
    declare -n _org=${1}
    declare -n _defaults=${2}
    for name in $(array_print_label _defaults)
    do
        array_idx_exist _org ${name} || array_set _org "${name}" "$(array_get _defaults '${name}')"
        [[ "$(array_get _org ${name})" = "${MUST_SET_VAL}" ]] && return 6
    done
    return 0
}

_domain_live() {
    local uuid=$1
    ${VIRSH} list --state-running --uuid | grep ${uuid} && echo "--live" || echo ""
}

_get_pool_type() {
    local pool=$1
    #${VIRSH} pool-dumpxml "${pool}" | xmlstarlet sel -t -v "/pool/@type"
    ${VIRSH} pool-dumpxml "${pool}" | xmllint --xpath "string(/pool/@type)" -
}

_get_disk_dev() {
    local disks=("vda" "vdb" "vdc" "vdd" "vde" "vdf" "vdg" "vdh" "vdi" "vdj")
    local uuid=$1
    local last_disk=
    local xml=$(${VIRSH} dumpxml ${uuid})
    for ((i=1;i<10;i++))
    do
        last_disk=$(printf "$xml" | xmllint --xpath "string(/domain/devices/disk[$i]/target/@dev)" -)
        [[ -z "${last_disk}" ]] && { echo ${disks[((i-1))]} ; return 0; }
    done
    return 0
}

usage() {
    cat <<EOF
${SCRIPTNAME} 
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
VM_UUID=xxxxxxxxxxxxxxxxxxxxxxx
# VM_NAME=
# VM_CPUS=
# VM_MEM=
# VM_TITLE=
# VM_DESC=
############################################
#SYS_POOL=default
#SYS_SIZE=4G
#SYS_TPL=/home/johnyin/disk/myvm/tpl.raw
############################################
SYS_NET=br-mgr
EOF
    exit 1
}

device_is_disk() {
    local type=$1
	printf "${DEVICE_TPL[${type}]}" | xmlstarlet sel -t -v "/*/@device" >/dev/null 2>&1 && return 0 || return 1
}

attach_device() {
    declare -n __ref=$1
    local type=$2
    local uuid="$(array_get __ref 'VM_UUID')"
    printf "${DEVICE_TPL[${type}]}\n" | render_tpl vm | try ${VIRSH} attach-device ${uuid} --file /dev/stdin --persistent $(_domain_live "${uuid}") || return 5
    return 0
}

attach_disk() {
    local parm=$1
    declare -A vm
    read_kv "${parm}" vm
    _set_vm_defaults vm VM_DEFAULTS || return $?
    local uuid="$(array_get vm 'VM_UUID')"
    local exists="$(${VIRSH} list --all --uuid | grep ${uuid})"
    [[ -z "${exists}" ]] && return 9
    local last_disk="$(_get_disk_dev $uuid)"
    local disk=${last_disk}_${uuid}.raw
    local disk_tpl="$(array_get vm 'SYS_TPL')"
    local pool="$(array_get vm 'SYS_POOL')"
    local type="$(_get_pool_type ${pool})"
    local size="$(array_get vm 'SYS_SIZE')"
    try ${VIRSH} vol-create-as --pool ${pool} --name ${disk} --capacity 1M --format raw || return 1
    local store_path=$(${VIRSH} vol-path --pool ${pool} ${disk})
    [[ -z "${store_path}" ]] && {
        try ${VIRSH} vol-delete ${disk} --pool ${pool}
        return 2
    }
    try ${VIRSH} vol-resize --pool ${pool} --vol ${disk} --capacity ${size} || return 3
    [[ -z "${disk_tpl}" ]] || { try ${VIRSH} vol-upload --pool ${pool} --vol ${disk} --file ${disk_tpl} || return 4; }
    array_set vm  "STORE_PATH" "${store_path}"
    array_set vm  "LAST_DISK" "${last_disk}"
    attach_device vm "${type}"
    return $?
}

create_domain() {
    local parm=$1
    local tpl=$2
    declare -A vm
    read_kv "${parm}" vm
    _set_vm_defaults vm VM_DEFAULTS || return $?
    local uuid="$(array_get vm 'VM_UUID')"
    local exists="$(${VIRSH} list --all --uuid | grep ${uuid})"
    [[ -z "${exists}" ]] || return 7
    cat "${tpl}" | render_tpl vm | try ${VIRSH} define --file /dev/stdin || return 8
    attach_device vm "network_device"
    return $?
}

attach() {
    local parm=$1
    [ -d "${parm}" ] && {
        for parm in "${1}/*"; do
            attach_disk "${parm}" && { info_msg "attach ${parm} ok\n"; } || { error_msg "attach ${parm}: $(array_get APP_ERRORS $? $?) error\n"; }
        done ;
    } || {
        attach_disk "${parm}" && { info_msg "attach ${parm} ok\n"; } || { error_msg "attach ${parm}: $(array_get APP_ERRORS $? $?) error\n"; }
    }
    return 0
}

create() {
    local parm=$1
    local tpl=$2
    local attach=${3:-false}
    [ -d "${parm}" ] && {
        for parm in "${1}/*"; do
            create_domain "${parm}" "${tpl}" || { error_msg "create ${parm} with tpl(${tpl}): $(array_get APP_ERRORS $? $?) error\n"; return $?; }
            info_msg "create ${parm} with tpl(${tpl}) ok\n";
            [[ "${attach}" = "true" ]] && { attach "${parm}"; return $?; } ;
        done ;
    } || {
        create_domain "${parm}" "${tpl}" || { error_msg "create ${parm} with tpl(${tpl}): $(array_get APP_ERRORS $? $?) error\n"; return $?; }
        info_msg "create ${parm} with tpl(${tpl}) ok\n";
        [[ "${attach}" = "true" ]] && { attach "${parm}"; return $?; } ;
    }
    return 0
}
test() {
	for t in $(array_print_label DEVICE_TPL)
	do
		info_msg "%s\n" "$(device_is_disk $t) $?"
	done
	exit 21
}
main() {
    local CREATE=false
    local ATTACH=false
    local TEMPLATE="domain.tpl"
    local TARGET="host.kv"
test
    while test $# -gt 0
    do
        opt="$1"
        shift
        case "${opt}" in
            -a | --attach)
                ATTACH=true
                ;;
            -c | --create)
                CREATE=true
                ;;
            -t | --template)
                TEMPLATE=${1}; shift
                ;;
            -q | --quiet)
                QUIET=1
                ;;
            -l | --log)
                set_loglevel ${1}; shift
                ;;
            -V | --version)
                exit_msg "${SCRIPTNAME} version\n"
                ;;
            -d | --dryrun)
                DRYRUN=1
                ;;
            -h | --help)
                usage
                ;;
            * )
                TARGET=${opt}
                ;;
        esac
    done
    info_msg "C=%s,A=%s,T=%s\n" $CREATE $ATTACH $TARGET
    [ "${CREATE}" = "true" -a ${ATTACH} = "true" ] && { create "${TARGET}" "${TEMPLATE}" true; return $?; }
    [ "${CREATE}" = "true" ] && { create "${TARGET}" "${TEMPLATE}"; return $?; }
    [ "${ATTACH}" = "true" ] && { attach "${TARGET}"; return $?; }
    usage
}
main "$@"
