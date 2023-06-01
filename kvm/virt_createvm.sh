#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("1944d21[2023-06-01T13:06:00+08:00]:virt_createvm.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
VIRSH_OPT="-q ${KVM_HOST:+-c qemu+ssh://${KVM_USER:-root}@${KVM_HOST}:${KVM_PORT:-60022}/system}"
VIRSH="virsh ${VIRSH_OPT}"
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
  <features><acpi/><apic/><pae/></features>
  <on_poweroff>preserve</on_poweroff>
  <devices>
    <controller type='pci' index='0' model='pcie-root'/>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
{%- if vm_arch == 'x86_64' %}
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
    </graphics>
    <video>
      <model type='vga' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
{%- endif %}
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x7'/>
    </controller>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </memballoon>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </rng>
  </devices>
</domain>
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
        KVM_HOST: default <not define, local>
        KVM_USER: default root
        KVM_PORT: default 60022
        -t|--tpl    *   <file>    vm tpl file
        -u|--uuid       <uuid>    default autogen
        -N|--name       <str>
        -D|--desc       <str>
        -c|--cpus       <int>     default 1
        -m|--mem        <int>     default 1024
        --arch          <str>     default x86_64 # aarch64/x86_64/..
        --uefi          <str>     if use uefi bootup, assian uefi file name
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
        uuid=$(cat /proc/sys/kernel/random/uuid)
        disk=vda-\${uuid}.raw
        echo "create disk"
        ./virt_createvol.sh -p default -n \${disk} -f raw -s 2GiB
        echo "upload template disk"
        ./virt-volupload.sh -p default -v \${disk} -t ~/debian.amd64.guestos.raw
        echo "create vm"
        ./virt_createvm.sh -t vm.tpl -u \${uuid} -N myserver -D "test server" -c 2 -m 2048
        echo "attach network"
        ./virt_attach.sh -t br-ext.tpl -u \${uuid}
        echo "attach disk"
        ./virt_attach.sh -t default_store.tpl -u \${uuid} -e format=raw -e store_path=/storage/\${disk}
        # cat domain.xml | virt-xml-validate - domain && echo OK 
EOF
    exit 1
}
main() {
    declare -A tpl_env
    local tpl="" uuid="" name="" desc="" cpus="" mem="" arch="" uefi="" maxcpu="" maxmem=""
    local opt_short="t:u:N:D:c:m:e:"
    local opt_long="tpl:,uuid:,name:,desc:,cpus:,mem:,arch:,uefi:,maxcpu:,maxmem:,env:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    uuid=${uuid:-$(cat /proc/sys/kernel/random/uuid)}
    cat <<EOF | tee ${LOGFILE} | j2 --format=yaml ${tpl} | tee ${LOGFILE} | ${VIRSH} define --file /dev/stdin || exit_msg "${uuid} create ERROR\n"
vm_uuid: "${uuid}"
vm_name : "${name:-vm}"
vm_desc : "${desc:-}"
vm_ram_mb_max: ${maxmem:-8192}
vm_ram_mb: ${mem:-1024}
vm_vcpus: ${cpus:-1}
vm_vcpus_max: ${maxcpu:-8}
vm_arch: "${arch:-x86_64}"
${uefi:+vm_uefi: ${uefi}}
$(for _k in $(array_print_label tpl_env); do
echo "$_k: \"$(array_get tpl_env $_k)\""
done)
EOF
    info_msg "${uuid} create OK\n"
    return 0
}
main "$@"
