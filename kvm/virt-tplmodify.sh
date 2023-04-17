##!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("b1aa13c[2023-04-17T08:38:29+08:00]:virt-tplmodify.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
cat <<EOF
${SCRIPTNAME}
        -n|--interface          interface name(eth0/eth1), default=eth0
        -r|--gateway            gateway -r "192.168.1.1"
        -i|--ipaddr        *    ipv4 address(192.168.1.2/24)
        -H|--hostname           guest os hostname
        -t|--template      *    telplate disk for modify
        -p|--partnum            temlate partition number, default=1
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
exit 1
}

mount_tpl() {
    local mnt_point=$1
    local tpl_img=$2
    local partnum=${3}
    mkdir -p ${mnt_point}
    # SectorSize * StartSector
    SectorSize=$(parted ${tpl_img} unit s print | awk '/Sector size/{print $4}' | awk -F "B" '{print $1}')
    sst=$(parted ${tpl_img} unit s print | awk "/ ${partnum}  /{print \$2}")
    StartSector=${sst:0:${#sst}-1}
    OffSet=$(($StartSector*$SectorSize))
    try mount -o loop,offset=${OffSet} ${tpl_img} ${mnt_point}
    #  server:
    #  # qemu-nbd  -v -x tpl -f raw linux.tpl
    #
    #  client:
    #  # modprobe nbd max_part=8
    #  # nbd-client -N tpl 10.32.147.16
    #  # mount /dev/nbd0p1
    #  # nbd-client -d /dev/nbd0
}

change_vm() {
    local root_dir=$1
    local iface=$2
    local ipaddr=$3
    local prefix=$4
    local gateway=$5
    file_exists ${root_dir}/etc/os-release || return 1
    source <(grep -E "^\s*(VERSION_ID|ID)=" ${root_dir}/etc/os-release)
    case "${ID:-}" in
        debian)
            cat << EOF | tee ${root_dir}/etc/network/interfaces
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback
EOF

            cat << EOF | tee ${root_dir}/etc/network/interfaces.d/${iface}
allow-hotplug ${iface}
iface ${iface} inet static
    address ${ipaddr}/${prefix}
    ${gateway:+gateway ${gateway}}
EOF
            ;;
        centos|rocky|openEuler|kylin)
            cat <<EOF | tee ${root_dir}/etc/sysconfig/network-scripts/ifcfg-${iface}
IPV6INIT=no
DEVICE="${iface}"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=${ipaddr}
PREFIX=${prefix}
${gateway:+GATEWAY=${gateway}}
EOF
            ;;
        *)
            echo "UNKNOWN OS!!!!!!!!!!"
    esac
    return 0
}

main() {
    local disk_tpl=
    local partnum=1
    local guest_hostname="guestos"
    local guest_ipaddr=
    local guest_prefix=
    local iface="eth0"
    local guest_gateway=
    local opt_short="r:n:i:H:t:p:"
    local opt_long="gateway:,interface:,ipaddr:,hostname:,template:,partnum:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -r|--gateway)   shift; guest_gateway=${1:?guest default gateway need input};shift ;;
            -n|--interface) shift; iface=${1:?interface name need input};shift ;;
            -i|--ipaddr)    shift; IFS='/' read -r guest_ipaddr guest_prefix <<< "${1:?guest ip address need input}"; shift ;;
            -H|--hostname)  shift; guest_hostname=${1:?guest hostname need input};shift ;;
            -t|--template)  shift; disk_tpl=${1:?disk template need input};shift ;;
            -p|--partnum)   shift; partnum=${1};shift ;;
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
    [[ -z "${disk_tpl}" ]] && usage "template must input"
    [[ -z "${guest_ipaddr}" ]] && usage "ipaddr must input"

    is_user_root || exit_msg "root need!\n"
    for i in mount umount parted
    do
        [[ ! -x $(which $i) ]] && { exit_msg "$i no found\n"; }
    done

    info_msg "chage ${disk_tpl}:\n"
    info_msg "       ip: ${guest_ipaddr}/${guest_prefix}\n"
    info_msg " hostname: ${guest_hostname}\n"
    info_msg "    gateway: $(array_print guest_gateway)\n"
    local mnt_point=/tmp/vm_rootfs_tmp
    file_exists ${disk_tpl} || exit_msg "template file ${disk_tpl} no found\n"
    mount_tpl "${mnt_point}" "${disk_tpl}" "${partnum}" || exit_msg "mount file ${disk_tpl} error\n"
    change_vm "${mnt_point}" "${iface}" "${guest_ipaddr}" "${guest_prefix}" "${guest_gateway}" || { try umount "${mnt_point}"; exit_msg "change vm file ${disk_tpl} error\n"; }
    try echo "${guest_hostname}" \> ${mnt_point}/etc/hostname || error_msg "change hostname error\n"
    try touch ${mnt_point}/etc/hosts && {
        cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${guest_hostname}
${guest_ipaddr}   ${guest_hostname}
EOF
    }
    # try rm -f ${mnt_point}/etc/ssh/ssh_host_*
    # try rm -fr ${mnt_point}/var/log/*
    try umount "${mnt_point}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
