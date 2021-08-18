##!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("virt-tplmodify.sh - 9bf43e0 - 2021-01-25T07:29:47+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
cat <<EOF
${SCRIPTNAME} 
        -n|--interface          interface name(eth0/eth1)
        -r|--route              routes -r "default via xxx" -r "10.0.0.0/24 via xxx"
        -m|--mask               netmask or prefix
        -i|--ipaddr        *    ipv4 address
        -H|--hostname           guest os hostname
        -t|--template      *    telplate disk for upload
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
exit 1
}

change_vm_centos7() {
    local mnt_point=$1
    local iface=$2
    local ipaddr=$3
    local prefix=$4
    local route=$5

    try touch ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-${iface} || return 1
    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-${iface} <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="${iface}"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=${ipaddr}
PREFIX=${prefix}
EOF
    try touch ${mnt_point}/etc/sysconfig/network-scripts/route-${iface} || return 2
    cat > ${mnt_point}/etc/sysconfig/network-scripts/route-${iface} <<-EOF
$(array_print $route)
EOF
    return 0
}

mount_tpl() {
    local mnt_point=$1
    local tpl_img=$2
    mkdir -p ${mnt_point}
    # SectorSize * StartSector
    SectorSize=$(parted ${tpl_img} unit s print | awk '/Sector size/{print $4}' | awk -F "B" '{print $1}')
    sst=$(parted ${tpl_img} unit s print | awk '/ 1  /{print $2}')
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

main() {
    local disk_tpl=
    local guest_hostname="guestos"
    local guest_ipaddr=
    local guest_prefix=24
    local iface="eth0"
    declare -a guest_route=()
    local opt_short="r:n:m:i:H:t:"
    local opt_long="route:,interface:,mask:,ipaddr:,hostname:,template:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -r|--route)     shift; array_append guest_route "${1:?guest route need input}";shift ;;
            -n|--interface) shift; iface=${1:?interface name need input};shift ;;
            -m|--mask)      shift; guest_prefix=${1:?guest net mask need input};shift;
                is_ipv4_netmask "${guest_prefix}" && guest_prefix=$(mask2cidr ${guest_prefix})
                ;;
            -i|--ipaddr)    shift; guest_ipaddr=${1:?guest ip address need input};shift ;;
            -H|--hostname)  shift; guest_hostname=${1:?guest hostname need input};shift ;;
            -t|--template)  shift; disk_tpl=${1:?disk template need input};shift ;;
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
        [[ ! -x $(which $i) ]] && { exit_msg "$i no found"; }
    done

    info_msg "chage ${disk_tpl}:"
    info_msg "       ip: ${guest_ipaddr}/${guest_prefix}"
    info_msg " hostname: ${guest_hostname}"
    info_msg "    route: $(array_print guest_route)"
    local mnt_point=/tmp/vm_rootfs_tmp
    file_exists ${disk_tpl} || exit_msg "template file ${disk_tpl} no found\n"
    mount_tpl "${mnt_point}" "${disk_tpl}" || exit_msg "mount file ${disk_tpl} error\n"
    change_vm_centos7 "${mnt_point}" "${iface}" "${guest_ipaddr}" "${guest_prefix}" guest_route || error_msg "change vm file ${disk_tpl} error\n"
    try echo "${guest_hostname}" \> ${mnt_point}/etc/hostname || error_msg "change hostname error\n"
    try touch ${mnt_point}/etc/hosts || error_msg "change hosts error\n"
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${guest_hostname}
${ipaddr}   ${guest_hostname}
EOF
    try rm -f ${mnt_point}/etc/ssh/ssh_host_*
    try rm -fr ${mnt_point}/var/log/*
    try umount "${mnt_point}"
    return 0
}
main "$@"
