#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("3eae815[2023-11-16T12:51:53+08:00]:virt_createvm.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
LOGFILE=""
gen_tpl() {
    cat <<'EOF'
# https://libvirt.org/formatdomain.html
<domain type='kvm'>
  <name>{{ vm_name }}-{{ vm_uuid }}</name>
  <uuid>{{ vm_uuid }}</uuid>
  <title>{{ vm_name }}</title>
  <description>{{ vm_desc | default("") }}</description>
  <memory unit='MiB'>{{ vm_ram_mb_max | default(8192)}}</memory>
  <memoryBacking><source type='memfd'/><access mode='shared'/></memoryBacking>
  <currentMemory unit='MiB'>{{ vm_ram_mb | default(1024) }}</currentMemory>
  <vcpu placement='static' current='{{ vm_vcpus | default(1) }}'>{{ vm_vcpus_max | default(8) }}</vcpu>
{%- if vm_arch == 'x86_64' %}
  {%- set __machine__ = "q35" %}
  <cpu match='exact'><model fallback='allow'>kvm64</model></cpu>
{%- else %}
  {%- set __machine__ = "virt" %}
  <cpu mode='host-passthrough' check='none'/>
{%- endif %}
  <os>
    <type arch='{{ vm_arch }}' machine='{{ __machine__ }}'>hvm</type>
{%- if vm_uefi is defined %}
    <loader readonly='yes' type='pflash'>{{ vm_uefi }}</loader>
{%- endif %}
  </os>
  <features><acpi/><apic/><pae/><gic version='3'/></features>
  <on_poweroff>destroy</on_poweroff>
  <devices>
    <serial type='pty'><target port='0'/></serial>
    <console type='pty'><target type='serial' port='0'/></console>
{%- if vm_arch == 'x86_64' %}
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <video><model type='vga' heads='1' primary='yes'/></video>
{%- endif %}
    <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>
    <memballoon model='virtio'/>
    <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
  </devices>
</domain>
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -K|--kvmhost    <ipaddr>  kvm host address
        -U|--kvmuser    <str>     kvm host ssh user
        -P|--kvmport    <int>     kvm host ssh port
        --kvmpass       <password>kvm host ssh password
        -t|--tpl    *   <file>    vm tpl file
        -u|--uuid       <uuid>    default autogen
        -N|--name       <str>     default vm-uuid
        -D|--desc       <str>     default ""
        -c|--cpus       <int>     default 1
        -m|--mem        <int>     default 1024
        --arch          <str>     default x86_64 # aarch64/x86_64/..
        --uefi          <str>     if use uefi bootup, assian uefi file name
                                    virsh domcapabilities | xmlstarlet sel -t -v "/domainCapabilities/os/loader/value"
                                    /usr/share/OVMF/OVMF_CODE.fd
                                    /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
        --maxcpu        <int>     default 8
        --maxmem        <int>     default 8192
        -e|--env        <key>=<val> addition keyval pair
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    exam:
    <cputune>
      <!-- unitless value to determine how much CPU a VM get when the host is on 100% load
       A normal process has a priority of 1024, so if two processes require CPU,
       they will get even amounts of CPU if they have a share setting of 1024.
       A share setting of 512 means it will receive a correspondingly smaller ratio of the available time.
      -->
      <shares>1000</shares>
    </cputune>
    # virsh schedinfo <UUID> --config --live --set cpu_shares=512
    <blkiotune><weight>250</weight></blkiotune>
    # assign a weight to the machine for block device I/O.
    # The default weight is 500, and smaller values mean that the VM has less weight
    # virsh blkiotune <UUID> --config --live --weight 250
    <graphics type='vnc' port='5900' autoport='no' websocket='5700' listen='127.0.0.1'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
        uuid=$(cat /proc/sys/kernel/random/uuid)
        disk=vda-\${uuid}.raw
        echo "create disk"
        ./virt_createvol.sh -p default -n \${disk} -f raw -s 2GiB
        echo "upload template disk"
        ./virt-volupload.sh -p default -v \${disk} -t ~/debian.amd64.guestos.raw
        echo "create vm"
        ./virt_createvm.sh -t vm.tpl -u \${uuid} -N myserver -D "test server" -c 2 -m 2048
        echo "attach network, persistent"
        ./virt_attach.sh -t br-ext.tpl -u \${uuid} --persistent
        echo "attach disk, persistent"
        ./virt_attach.sh -t default_store.tpl -u \${uuid} -e format=raw -e store_path=/storage/\${disk} --persistent
        # cat domain.xml | virt-xml-validate - domain && echo OK 
        # Add cloud-init iso image
        cdrom=meta-\${uuid}.iso
        ISO_FNAME=\${cdrom} VM_NAME=vmsrv UUID=\${uuid} PASSWORD=password IPADDR=192.168.168.222/24 GATEWAY=192.168.168.1 ./gen_cloud_init_iso.sh
        ./virt_createvol.sh -p default -n \${cdrom} -f raw -s 1MiB
        ./virt-volupload.sh -p default -v \${cdrom} -t \${cdrom}
        # non persistent cdrom
        ./virt_attach.sh -t cdrom.j2 -u \${uuid} -e store_path=/storage/\${cdrom}
EOF
    exit 1
}
main() {
    declare -A tpl_env
    local kvmhost="" kvmuser="" kvmport="" kvmpass=""
    local tpl="" uuid="" uefi="" desc="" name="vm" cpus="1" mem="1024" arch="x86_64" maxcpu="8" maxmem="8192"
    local opt_short="K:U:P:t:u:N:D:c:m:e:"
    local opt_long="kvmhost:,kvmuser:,kvmport:,kvmpass:,tpl:,uuid:,name:,desc:,cpus:,mem:,arch:,uefi:,maxcpu:,maxmem:,env:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -K | --kvmhost) shift; kvmhost=${1}; shift;;
            -U | --kvmuser) shift; kvmuser=${1}; shift;;
            -P | --kvmport) shift; kvmport=${1}; shift;;
            --kvmpass)      shift; kvmpass=${1}; shift;;
            -t | --tpl)     shift; tpl=${1}; shift;;
            -u | --uuid)    shift; uuid="${1}"; shift;;
            -N | --name)    shift; name="${1}"; shift;;
            -D | --desc)    shift; desc="${1}"; shift;;
            -c | --cpus)    shift; cpus="${1}"; shift;;
            -m | --mem)     shift; mem="${1}"; shift;;
            --arch)         shift; arch="${1}"; shift;;
            --uefi)         shift; uefi="${1}"; shift;;
            --maxcpu)       shift; maxcpu="${1}"; shift;;
            --maxmem)       shift; maxmem="${1}"; shift;;
            -e | --env)     shift; { IFS== read _tvar _tval; } <<< ${1}; _tvar="$(trim ${_tvar})"; _tval="$(trim ${_tval})"; array_set tpl_env "${_tvar}" "${_tval}"; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; gen_tpl;usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    require j2 virsh
    defined QUIET || LOGFILE="-a /dev/stderr"
    [ -z "${tpl}" ] && usage "tpl must input"
    [ -z ${kvmpass} ]  || set_sshpass "${kvmpass}"
    uuid=${uuid:-$(uuid)}
    cat <<EOF | tee ${LOGFILE} | j2 --format=yaml ${tpl} | tee ${LOGFILE} | virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" define --file /dev/stdin || exit_msg "${uuid} create ERROR\n"

vm_uuid: "${uuid}"
vm_name : "${name}"
vm_desc : "${desc}"
vm_ram_mb_max: ${maxmem}
vm_ram_mb: ${mem}
vm_vcpus: ${cpus}
vm_vcpus_max: ${maxcpu}
vm_arch: "${arch}"
${uefi:+vm_uefi: ${uefi}}
$(for _k in $(array_print_label tpl_env); do
echo "$_k: \"$(array_get tpl_env $_k)\""
done)
EOF
    info_msg "${uuid} create OK\n"
    return 0
}
main "$@"
