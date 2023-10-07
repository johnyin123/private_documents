##!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("2274c31[2023-07-17T13:24:15+08:00]:virt-tplmodify.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
cat <<EOF
${SCRIPTNAME}
        -n|--interface          interface name(eth0/eth1), default=eth0
        -r|--gateway            gateway -r "192.168.1.1"
        -i|--ipaddr             ipv4 address(192.168.1.2/24)
        --ip6addr               ipv6 address(2001::/96)
        --ip6gateway            ipv6 gateway
        -H|--hostname           guest os hostname
        -t|--template      *    telplate disk for modify
        -p|--partnum            temlate partition number, default auto detect
        -P|--partition    *     disk partition for modify
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
    local partnum=${3:-}
    file_exists ${tpl_img} || return 1
    # SectorSize * StartSector
    SectorSize=$(parted ${tpl_img} unit s print | awk '/Sector size/{print $4}' | awk -F "B" '{print $1}')
    local sst=0
    [ -z "${partnum}" ] && \
        sst=$(parted ${tpl_img} unit s print | awk "/ext4|xfs/{print \$2}") || \
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
    local ip6addr=$6
    local ip6prefix=$7
    local ip6gateway=$8
    file_exists ${root_dir}/etc/os-release || return 1
    source <(grep -E "^\s*(VERSION_ID|ID)=" ${root_dir}/etc/os-release)
    case "${ID:-}" in
        debian)
            cat << EOF | tee ${root_dir}/etc/network/interfaces
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback
EOF
            mkdir -p ${root_dir}/etc/network/interfaces.d
            cat << EOF | tee ${root_dir}/etc/network/interfaces.d/${iface}
allow-hotplug ${iface}
EOF
            [ -z "${ipaddr}" ] || {
            cat << EOF | tee -a ${root_dir}/etc/network/interfaces.d/${iface}
iface ${iface} inet static
    address ${ipaddr}/${prefix}
    ${gateway:+gateway ${gateway}}
EOF
            }
            [ -z "${ip6addr}" ] || {
            cat << EOF | tee -a ${root_dir}/etc/network/interfaces.d/${iface}
iface ${iface} inet6 static
    address ${ip6addr}/${ip6prefix}
    ${ip6gateway:+gateway ${ip6gateway}}
EOF
            }
            ;;
        centos|rocky|openEuler|kylin)
            [ -z "${ip6addr}" ] \
                && echo "IPV6INIT=no" > ${root_dir}/etc/sysconfig/network-scripts/ifcfg-${iface} \
                || echo "IPV6INIT=yes" > ${root_dir}/etc/sysconfig/network-scripts/ifcfg-${iface}
            cat <<EOF | tee -a ${root_dir}/etc/sysconfig/network-scripts/ifcfg-${iface}
DEVICE="${iface}"
ONBOOT="yes"
BOOTPROTO="none"
${ipaddr:+IPADDR=${ipaddr}}
${prefix:+PREFIX=${prefix}}
${gateway:+GATEWAY=${gateway}}
${ip6addr:+IPV6ADDR=${ip6addr}/${ip6prefix}}
${ip6gateway:+IPV6_DEFAULTGW=${ip6gateway}}
EOF
            ;;
        *)
            echo "UNKNOWN OS!!!!!!!!!!"
    esac
    return 0
}

main() {
    local disk_tpl=""
    local partnum=""
    local guest_hostname="guestos"
    local guest_ipaddr=""
    local guest_prefix=""
    local guest_gateway=""
    local guest_ip6addr=""
    local guest_ip6prefix=""
    local guest_ip6gateway=""
    local partition=""
    local iface="eth0"
    local opt_short="r:n:i:H:t:p:P:"
    local opt_long="gateway:,interface:,ipaddr:,ip6addr:,ip6gateway:,hostname:,template:,partnum:,partition:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -r|--gateway)   shift; guest_gateway=${1};shift ;;
            -n|--interface) shift; iface=${1};shift ;;
            -i|--ipaddr)    shift; IFS='/' read -r guest_ipaddr guest_prefix <<< "${1}"; shift ;;
            --ip6addr)      shift; IFS='/' read -r guest_ip6addr guest_ip6prefix <<< "${1}"; shift ;;
            --ip6gateway)   shift; guest_ip6gateway=${1};shift ;;
            -H|--hostname)  shift; guest_hostname=${1};shift ;;
            -t|--template)  shift; disk_tpl=${1};shift ;;
            -p|--partnum)   shift; partnum=${1};shift ;;
            -P|--partition) shift; partition=${1};shift ;;
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
    [ -z "${disk_tpl}" ] && [ -z "${partition}" ] && usage "template/partition must input"
    [ -z "${disk_tpl}" ] || [ -z "${partition}" ] || usage "template or partition must input"
    require mount umount parted
    info_msg "chage ${disk_tpl}:\n"
    info_msg "       ip: ${guest_ipaddr}/${guest_prefix}\n"
    info_msg " hostname: ${guest_hostname}\n"
    info_msg "  gateway: ${guest_gateway}\n"
    local mnt_point=$(temp_folder "" "rootfs")
    [ -z "${disk_tpl}" ] || mount_tpl "${mnt_point}" "${disk_tpl}" "${partnum}" || exit_msg "mount file ${disk_tpl} error\n"
    [ -z "${partition}" ] || mount ${partition} "${mnt_point}" || exit_msg "mount partiton ${partition} error\n"
    change_vm "${mnt_point}" "${iface}" "${guest_ipaddr}" "${guest_prefix}" "${guest_gateway}" "${guest_ip6addr}" "${guest_ip6prefix}" "${guest_ip6gateway}" || { try umount -R -v "${mnt_point}"; exit_msg "change vm ${partition}${disk_tpl} error\n"; }
    try echo "${guest_hostname}" \> ${mnt_point}/etc/hostname || error_msg "change hostname error\n"
    try touch ${mnt_point}/etc/hosts && {
        cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${guest_hostname}
${guest_ipaddr:+${guest_ipaddr}   ${guest_hostname}}
${guest_ip6addr:+${guest_ip6addr}   ${guest_hostname}}
EOF
    }
    # try rm -f ${mnt_point}/etc/ssh/ssh_host_*
    # try rm -fr ${mnt_point}/var/log/*
    try umount -R -v "${mnt_point}"
    info_msg "ALL DONE\n"
    return 0
}
auto_su "$@"
main "$@"
