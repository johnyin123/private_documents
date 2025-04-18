#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("5323b3ee[2025-01-11T20:25:13+08:00]:virt_attach.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
LOGFILE=""
gen_tpl() {
    cat <<'EOF'
# only vm_last_disk is buildin var
# disk tpl demo
<disk type='file' device='disk'>
   <driver name='qemu' type='{{ format }}' cache='none' io='native'/>
   <source file='{{ store_path }}'/>
   <backingstore/>
   <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
</disk>
# raw dev
<disk type='block' device='disk'>
  <driver name='qemu' type='raw' cache='none' io='native'/>
  <source dev='{{ store_path }}'/>
  <backingStore/>
  <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
  <blockio logical_block_size='4096' physical_block_size='4096'/>
</disk>
# rbd
<disk type='network' device='disk'>
  <driver name='qemu' type='raw'/>
  <auth username='admin'><secret type='ceph' uuid='cepp secret uuid'/></auth>
  <source protocol='rbd' name='ceph_libvirt_pool/vd{{ vm_last_disk }}-{{ vm_uuid }}.raw'>
    <host name='ipaddr' port='6789'/>
  </source>
  <target dev='vd{{ vm_last_disk }}' bus='virtio'/>
</disk>
# context iso
<disk type='network' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <auth username='admin'><secret type='ceph' uuid='cepp secret uuid'/></auth>
  <source protocol='rbd' name='ceph_libvirt_pool/cdrom-{{ vm_uuid }}.iso'>
    <host name='ipaddr' port='6789'/>
  </source>
  <target dev='sda' bus='scsi'/>
  <readonly/>
</disk>
<disk type='file' device='cdrom'>
   <driver name='qemu' type='raw'/>
   <source file='{{ store_path }}'/>
   <readonly/>
   <target dev='sda' bus='scsi'/>
</disk>
# meta-iso.tpl
<disk type='network' device='cdrom'>
   <driver name='qemu' type='raw'/>
   <source protocol="https" name="/{{ vm_uuid }}.iso" query="foo=bar&amp;baz=flurb">
     <host name="kvm.registry.local" port="80"/>
     # <ssl verify="no"/>
   </source>
   <target dev='sd{{ vm_last_disk }}' bus='sata'/>
   <readonly/>
</disk>
# host usb dev
<hostdev mode='subsystem' type='usb'>
  <source>
    <address bus='${BUSNUM}' device='${DEVNUM}' />
  </source>
</hostdev>
# # virtiofs share host to guest "mount -t virtiofs mount_tag /mnt/mount/path"
# # echo 'mount_tag /mnt/mount/path virtiofs defaults 0 0' >>/etc/fstab
# # virtiofs need sharemem
# <memoryBacking>
#   <source type='memfd'/>
#   <access mode='shared'/>
# </memoryBacking>
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs'/>
  <source dir='path to source folder on host'/>
  <target dir='mount_tag'/>
</filesystem>
# net tpl demo
# use libvirt defined bridge
<interface type='network'>
  <source network='br_mgmt.2430'/>
  <model type='virtio'/>
  <virtualport type='openvswitch'/>
  <driver name='vhost' queues='8'/>
</interface>
# # if use libvirt not defined bridge
# <interface type='bridge'>
#   <source bridge='br-ext'/>
#   <model type='virtio'/>
#   <driver name='vhost' queues='8'/>
# </interface>
# <interface type='ethernet'>
#   <target dev='calic0a8fe0a'/>
#   <model type='virtio'/>
# </interface>
# $ usb redirect device
# <redirdev bus='usb' type='tcp'>
#   <source mode='connect' host='127.0.0.1' service='4000'/>
# </redirdev>
# <redirdev bus='usb' type='tcp'>
#   <source mode='bind' host='127.0.0.1' service='4000'/>
# </redirdev>
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
        -t|--tpl    *   <file>    device tpl file
        -u|--uuid   *   <uuid>    vm uuid
        --persistent              persistent
        -e|--env        <key>=<val> addition keyval pair
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
  ${SCRIPTNAME} -t disk.j2 -u uuid -e format=raw -e store_path=/storage/disk.raw
  Insert cdrom:
    attach-disk guest01 /root/disc1.iso hdc --driver file --type cdrom --mode readonly
    attach-disk guest01 --type cdrom --mode readonly /os.iso sda --source-protocol http --source-host-name vmm.registry.local
  Change media:
    attach-disk guest01 /root/disc2.iso hdc --driver file --type cdrom --mode readonly
  Eject cdrom:
    attach-disk guest01 " "             hdc --driver file --type cdrom --mode readonly
EOF
    exit 1
}
set_last_disk() {
    local disks=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o")
    local kvmhost="${1}"
    local kvmport="${2}"
    local kvmuser="${3}"
    local uuid=${4}
    local prefix=${5}
    local last_disk=
    local xml=$(virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" dumpxml ${uuid} 2>/dev/null)
    [ -z "${xml}" ] && return 9
    for i in ${disks[@]}; do
        #last_disk=$(printf "$xml" | xmllint --xpath "string(/domain/devices/disk[$i]/target/@dev)" -)
        printf "$xml" | xmlstarlet sel -t -v "/domain/devices/disk[*]/target/@dev" 2>/dev/null | grep -q "${prefix}${i}" || {
            echo "${i}"
            return 0
        }
    done
    return 7
}
domain_live_arg() {
    local kvmhost="${1}"
    local kvmport="${2}"
    local kvmuser="${3}"
    local uuid=${4}
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" domstate ${uuid} 2>/dev/null | grep -iq "running" && echo "--live" || echo ""
}
main() {
    declare -A tpl_env
    local kvmhost="" kvmuser="" kvmport="" kvmpass=""
    local tpl="" uuid="" persistent=""
    local opt_short="K:U:P:t:u:e:"
    local opt_long="kvmhost:,kvmuser:,kvmport:,kvmpass:,tpl:,uuid:,persistent,env:,"
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
            --persistent)   shift; persistent=--persistent;;
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
    require j2 xmlstarlet virsh
    defined QUIET || LOGFILE="-a /dev/stderr"
    [ ! -z "${uuid}" ] && [ ! -z "${tpl}" ] || usage "uuid/tpl must input"
    [ -z ${kvmpass} ]  || set_sshpass "${kvmpass}"
    local live=$(domain_live_arg "${kvmhost}" "${kvmport}" "${kvmuser}" "${uuid}")
    info_msg "${uuid}(${live:-shut off}) attach device\n"
    local last_disk=""
    local bus=$(xmlstarlet sel -t -v "/disk/target/@bus" "${tpl}" 2>/dev/null) || true
    case "${bus}" in
        sata|scsi)
            last_disk=$(set_last_disk "${kvmhost}" "${kvmport}" "${kvmuser}" "${uuid}" "sd") || exit_msg "${uuid} get last disk ERROR\n"
            ;;
        virtio)
            last_disk=$(set_last_disk "${kvmhost}" "${kvmport}" "${kvmuser}" "${uuid}" "vd") || exit_msg "${uuid} get last disk ERROR\n"
            ;;
        *)  break;;
    esac
    cat <<EOF | tee ${LOGFILE} | j2 --format=yaml ${tpl} | tee ${LOGFILE} | \
    virsh_wrap "${kvmhost}" "${kvmport}" "${kvmuser}" attach-device --domain ${uuid} --file /dev/stdin ${persistent} ${live} || exit_msg "${uuid} attach ERROR\n"

vm_uuid: "${uuid}"
vm_last_disk: "${last_disk}"
$(for _k in $(array_print_label tpl_env); do
echo "$_k: \"$(array_get tpl_env $_k)\""
done)
EOF
    info_msg "${uuid} attach OK\n"
    return 0
}
main "$@"
