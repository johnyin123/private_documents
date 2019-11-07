#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################

usage() {
cat <<EOF
${SCRIPTNAME} 
    -r|--route                               routes -r "default via xxx" -r "10.0.0.0/24 via xxx"
    -m|--mask                                netmask or prefix
    -i|--ipaddr            *                 ipv4 address
    -H|--hostname                            guest os hostname
    -t|--template          *                 telplate disk for upload
    -q|--quiet
    -l|--log <int>                           log level
    -d|--dryrun                              dryrun
    -h|--help                                display this help and exit
EOF
exit 1
}

change_vm_centos7() {
    local mnt_point=$1
    local hostname=$2
    local ipaddr=$3
    local prefix=$4
    local route=$5

    try touch ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 || return 1
    cat > ${mnt_point}/etc/sysconfig/network-scripts/ifcfg-eth0 <<-EOF
NM_CONTROLLED=no
IPV6INIT=no
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="none"
IPADDR=${ipaddr}
PREFIX=${prefix}
EOF
    try touch ${mnt_point}/etc/sysconfig/network-scripts/route-eth0 || return 2
    cat > ${mnt_point}/etc/sysconfig/network-scripts/route-eth0 <<-EOF
$(array_print $route)
EOF
    try touch ${mnt_point}/etc/hosts || return 3
    cat > ${mnt_point}/etc/hosts <<-EOF
127.0.0.1   localhost ${hostname}
${ipaddr}    ${hostname}
EOF
    try echo "${guest_hostname}" \> ${mnt_point}/etc/hostname || return 4
    try rm -f ${mnt_point}/etc/ssh/ssh_host_*
    try rm -fr ${mnt_point}/var/log/*
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
}

main() {
    local disk_tpl=
    local guest_hostname="guestos"
    local guest_ipaddr=
    local guest_prefix=24
    declare -a guest_route=()

    while test $# -gt 0
    do
        local opt="$1"
        shift
        case "${opt}" in
            -r|--route)
                array_append guest_route "${1:?guest route need input}";shift 1
                ;;
            -m|--mask)
                guest_prefix=${1:?guest net mask need input};shift 1
                is_ipv4_netmask "${guest_prefix}" && guest_prefix=$(mask2cidr ${guest_prefix})
                ;;
            -i|--ipaddr)
                guest_ipaddr=${1:?guest ip address need input};shift 1
                ;;
            -H|--hostname)
                guest_hostname=${1:?guest hostname need input};shift 1
                ;;
            -t|--template)
                disk_tpl=${1:?disk template need input};shift 1
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
            -h | --help | *)
                usage
                ;;
        esac
    done
    [[ -z "${disk_tpl}" ]] && usage
    [[ -z "${guest_ipaddr}" ]] && usage

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
    change_vm_centos7 "${mnt_point}" "${guest_hostname}" "${guest_ipaddr}" "${guest_prefix}" guest_route || error_msg "change vm file ${disk_tpl} error\n"
    try umount "${mnt_point}"
    return 0
}
main "$@"
