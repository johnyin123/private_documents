#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
netns_exists() {
    local ns_name="$1"
    # Check if a namespace named $ns_name exists.
    # Note: Namespaces with a veth pair are listed with '(id: 0)' (or something). We need to remove this before lookin
    ip netns list | sed 's/ *(id: [0-9]\+)$//' | grep --quiet --fixed-string --line-regexp "${ns_name}"
}

setup_ns() {
    local ns_name="$1"
    local ipv4_cidr="$2"
    local out_br="$3"
    local gateway=${4:-}
    try ip netns add ${ns_name}
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo
    try ip netns exec ${ns_name} ip link set lo up

    try ip link add ${ns_name}0 type veth peer name ${ns_name}1
    try ip link set ${ns_name}0 master ${out_br}
    try ip link set ${ns_name}0 up

    try ip link set ${ns_name}1 netns ${ns_name}
    try ip netns exec ${ns_name} ip link set ${ns_name}1 name eth0 up
    try ip netns exec ${ns_name} ip addr add ${ipv4_cidr} dev eth0
    [[ -z ${gateway} ]] || try ip netns exec ${ns_name} ip route add default via ${gateway} 
}

cleanup_ns() {
    local ns_name="$1"
    try ip netns del ${ns_name} || true
    try ip link delete ${ns_name}0 || true
}

setup_overlayfs() {
    local lower="$1"
    local rootmnt="$2"
    try mount -t tmpfs tmpfs -o size=1M ${rootmnt}
    try mkdir -p ${rootmnt}/upper ${rootmnt}/work ${rootmnt}/rootfs
    try mount -t overlay overlay -o lowerdir=${lower},upperdir=${rootmnt}/upper,workdir=${rootmnt}/work ${rootmnt}/rootfs
}

cleanup_overlayfs() {
    local rootmnt="$1"
    try umount ${rootmnt}/rootfs || true
    try umount ${rootmnt} || true
}

readonly CGROUPS='cpu,cpuacct,memory'
ns_cg_run() {
    local rootfs="$1"
    local ns_name="$2"
    local cpu_share="$3"
    local mem_limit="$4"
    local cmd="$5"
    try cgcreate -g "${CGROUPS}:/${ns_name}"
    try cgset -r cpu.shares="${cpu_share}" "${ns_name}"
    try cgset -r memory.limit_in_bytes="$((mem_limit * 1000000))" "${ns_name}"
    info_msg "cgexec -g ${CGROUPS}:${ns_name} ${cmd}\n"
    cgexec -g "${CGROUPS}:${ns_name}" \
        ip netns exec "${ns_name}" \
        unshare -fmuip --mount-proc \
        chroot "${rootfs}" \
        /bin/bash -s <<EOSHELL 2>&1 | tee "${ns_name}.log" || true
/bin/mount -t proc proc /proc
/bin/mkdir -p /run/sshd
${cmd}
EOSHELL
}

ns_cg_enter() {
    local rootfs="$1"
    local ns_name="$2"
	#cid="$(ps o ppid,pid | grep "^$(ps o pid,cmd | grep -E "^\ *[0-9]+ unshare.*$1" | awk '{print $1}')" | awk '{print $2}')"
	#[[ ! "$cid" =~ ^\ *[0-9]+$ ]] && echo "Container '$1' exists but is not running" && exit 1
	#nsenter -t "$cid" -m -u -i -n -p chroot "$btrfs_path/$1" "${@:2}"
    nsenter -t "${ns_name}" -m -u -i -n -p chroot "${rootfs}" "${@:2}"
}

usage() {
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
    opt_long+="quite,log:,dryrun,version,help"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; exit_msg "${SCRIPTNAME} version\n";;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              error_msg "Unexpected option: $1.\n"; usage;;
        esac
    done
    is_user_root || exit_msg "root user need!!\n"
    local random="$(shuf -i 168201-168254 -n 1)"
    local ns_name="NS_${random}"
    local ipv4_cidr=192.168.168.169/24
    local gateway="${ipv4_cidr%.*}.1"
    local out_br="br-ext"
    local lower="/"
    local overlay="/root/cg_${random}"
    local cpu_share=512
    local mem_limit=512
    local cmd="/sbin/sshd -D -e"
    try mkdir -p "${overlay}"
    #btrfs subvolume snapshot "$btrfs_path/$1" "$btrfs_path/${cg_id}" > /dev/null
    #echo 'nameserver 202.107.117.11' > "$btrfs_path/${cg_id}"/etc/resolv.conf
    #echo "$cmd" > "$btrfs_path/${cg_id}/${cg_id}.cmd"

    netns_exists "${ns_name}" && exit_msg "${ns_name} exist!!\n"
    setup_ns "${ns_name}" "${ipv4_cidr}" "${out_br}" "${gateway}" || { cleanup_ns "${ns_name}"||true; exit_msg "${ns_name} setup error!\n"; }
    setup_overlayfs "${lower}" "${overlay}" && {
        ns_cg_run "${overlay}/rootfs" "${ns_name}" "${cpu_share}" "${mem_limit}" "${cmd}" || true
    }
    cleanup_overlayfs "${overlay}"
    cleanup_ns "${ns_name}"
    try rm -fr "${overlay}"
    return 0
}
main "$@"
