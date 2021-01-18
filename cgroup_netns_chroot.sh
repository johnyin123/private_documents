#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("cgroup_netns_chroot.sh - 28e7a8c - 2021-01-17T13:52:59+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
init_ns_env() {
    local ns_name="$1"
    local ipv4_cidr="$2"
    local out_br="$3"
    local gateway=${4:-}
    setup_ns "${ns_name}"
    setup_veth "${ns_name}0" "${ns_name}1"

    bridge_add_link ${out_br} ${ns_name}0

    maybe_netns_addlink "${ns_name}1" "${ns_name}" "eth0"
    maybe_netns_run "ip addr add ${ipv4_cidr} dev eth0" "${ns_name}"
    [[ -z ${gateway} ]] || maybe_netns_run "ip route add default via ${gateway}" "${ns_name}"
}

deinit_ns_env() {
    local ns_name="$1"
    cleanup_ns ${ns_name}
    cleanup_link ${ns_name}0
}

readonly CGROUPS='cpu,cpuacct,memory'
ns_cg_run() {
    local rootfs="$1"
    local ns_name="$2"
    local cpu_share="$3"
    local mem_limit="$4"
    local cmd="$5"
    local precmd="
    /bin/mount -t proc proc /proc
    /bin/mount -n -t tmpfs none /dev
    /bin/mknod -m 622 /dev/console c 5 1
    /bin/mknod -m 666 /dev/null c 1 3
    /bin/mknod -m 666 /dev/zero c 1 5
    /bin/mknod -m 666 /dev/ptmx c 5 2
    /bin/mknod -m 666 /dev/tty c 5 0
    /bin/mknod -m 444 /dev/random c 1 8
    /bin/mknod -m 444 /dev/urandom c 1 9
    /bin/chown root:tty /dev/{console,ptmx,tty}
    /bin/mkdir /dev/pts
    /bin/mount -t devpts -o gid=4,mode=620 none /dev/pts
    /bin/mkdir -p /run/sshd
    /bin/hostname chroot-${ns_name}
"
    try cgcreate -g "${CGROUPS}:/${ns_name}"
    try cgset -r cpu.shares="${cpu_share}" "${ns_name}"
    try cgset -r memory.limit_in_bytes="$((mem_limit * 1000000))" "${ns_name}"
    info_msg "cgexec -g ${CGROUPS}:${ns_name} ${cmd}\n"
    maybe_dryrun cgexec -g "${CGROUPS}:${ns_name}" \
        ip netns exec "${ns_name}" \
        unshare -fmuip --mount-proc \
        chroot "${rootfs}" \
            /usr/bin/env -i \
            SHELL=/bin/bash \
            HOME=/root \
            TERM=${TERM} \
            /bin/bash -s <<EOSHELL
${precmd}
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
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <options> cmd
    default cmd "/sbin/sshd -D -e"
        -n|--ns     * namespace
        -i|--ip       ipv4 cidr <default 192.168.168.169/24>
        -g|--gw       gateway   <default 192.168.168.1>
        -b|--bridge * bridge
        -r|--rootfs   orig rootfs <default />
        -o|--overlay  overlay directory
        -c|--cpu      cpu share <default 512>
        -m|--mem      mem limit <default 512>
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local ns_name= ipv4_cidr="192.168.168.169/24" gateway= out_br= lower="/" overlay= cpu_share=512 mem_limit=512

    local opt_short="n:i:g:b:r:o:c:m:"
    local opt_long="ns:,ip:,gw:,bridge:,rootfs:,overlay:,cpu:,mem:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -n | --ns)      shift; ns_name=${1}; shift;;
            -i | --ip)      shift; ipv4_cidr=${1}; shift;;
            -g | --gw)      shift; gateway=${1}; shift;;
            -b | --bridge)  shift; out_br=${1}; shift;;
            -r | --rootfs)  shift; lower=${1}; shift;;
            -o | --overlay) shift; overlay=${1}; shift;;
            -c | --cpu)     shift; cpu_share=${1}; shift;;
            -m | --mem)     shift; mem_limit=${1}; shift;;
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
    local cmd=${*:-"/sbin/sshd -D -e"}
    gateway=${gateway:-"${ipv4_cidr%.*}.1"}
    #ns_name=${ns_name:-"ns_$(shuf -i 168201-168254 -n 1)"}
    overlay=${overlay:-"${DIRNAME}/${ns_name}"}
    [[ -z "${ns_name}" ]] && usage "ns_name must input"
    [[ -z "${out_br}" ]] && usage "bridge must input"
    {
        echo "cmd       = $cmd"
        echo "ns_name   = $ns_name"
        echo "ipv4_cidr = $ipv4_cidr"
        echo "gateway   = $gateway"
        echo "out_br    = $out_br"
        echo "lower     = $lower"
        echo "overlay   = $overlay"
        echo "cpu_share = $cpu_share"
        echo "mem_limit = $mem_limit"
    } | vinfo_msg
    is_user_root || exit_msg "root user need!!\n"
    require cgcreate cgset cgexec unshare chroot ip
    try mkdir -p "${overlay}"
    netns_exists "${ns_name}" && exit_msg "netns ${ns_name} exist!!\n"
    bridge_exists "${out_br}" || exit_msg "bridge ${out_br} not exist!!\n"
    init_ns_env "${ns_name}" "${ipv4_cidr}" "${out_br}" "${gateway}" || { deinit_ns_env "${ns_name}"||true; exit_msg "${ns_name} setup error!\n"; }
    setup_overlayfs "${lower}" "${overlay}" && {
        trap "echo 'CTRL+C!!!!'" SIGINT
        ns_cg_run "${overlay}/rootfs" "${ns_name}" "${cpu_share}" "${mem_limit}" "${cmd}" || true
    }
    cleanup_overlayfs "${overlay}"
    deinit_ns_env "${ns_name}"
    try rm -fr "${overlay}"
    return 0
}
main "$@"
