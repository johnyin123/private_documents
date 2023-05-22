#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-05-22T16:57:16+08:00]:virt_createvm.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
gen_tpl() {
    local cfg=${1}
    cat <<'EOF' > ${cfg}
<domain type='kvm'>
  <name>{{ vm_name }}-{{ vm_uuid }}</name>
  <uuid>{{ vm_uuid }}</uuid>
  <title>{{ vm_name }}</title>
  <description>{{ vm_desc }}</description>
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
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
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
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </rng>
  </devices>
</domain>
EOF
}
gen_yaml() {
    cat <<'EOF'
vm_uuid
vm_name 
vm_desc 
# default 8192
vm_ram_mb_max
# default 1024
vm_ram_mb
# default 1
vm_vcpus
# default 8
vm_vcpus_max
# aarch64/x86_64
vm_arch
# /usr/share/OVMF/OVMF_CODE.fd
# /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
vm_uefi 
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"

    local TPL_FILE=${TPL_FILE:-"vm.j2"}
    CPU=${CPU:-kvm64}
    #CPU=Westmere
    [[ -r "${TPL_FILE}" ]] || {
        gen_tpl "${TPL_FILE}"
        gen_yaml
        ${EDITOR:-vi} ${TPL_FILE} || true
        exit_msg "Created ${TPL_FILE} using defaults.  Please review it/configure before running again.\n"
    }
    while true; do
        case "$1" in
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    cat <<EOF | j2 --format=yaml ${TPL_FILE} | tee /dev/stderr | virsh define /dev/stdin
vm_uuid: "$(cat /proc/sys/kernel/random/uuid)"
vm_name : "vmname"
vm_desc : "desc test 中而"
# default 8192
vm_ram_mb_max: 9999
# default 1024
vm_ram_mb: 1024
# default 1
vm_vcpus: 2
# default 8
vm_vcpus_max: 8
# aarch64/x86_64
vm_arch: "x86_64"
# /usr/share/OVMF/OVMF_CODE.fd: ""
# /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw: ""
# vm_uefi : "uefi/file"
EOF
    echo "ALL OK"
    return 0
}
main "$@"
