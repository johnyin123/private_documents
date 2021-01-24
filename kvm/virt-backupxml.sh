#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("virt-backupxml.sh - initversion - 2021-01-25T07:29:48+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
VIRSH_OPT="-k 300 -K 5 -q"
#ControlMaster auto
#ControlPath  ~/.ssh/sockets/%r@%h-%p

fake_virsh() {
    local usr_srv_port=$1;shift 1
    try virsh -c qemu+ssh://${usr_srv_port}/system ${VIRSH_OPT} ${*}
}

speedup_ssh_begin() {
    local user=$1
    local host=$2
    local port=$3
    exec 5> >(ssh -tt -o StrictHostKeyChecking=no -p${port} ${user}@${host} > /dev/null 2>&1)
    info_msg "START .........\n"
}
cleanup() {
    speedup_ssh_end "" "" ""
    echo "EXIT!!!"
}

trap cleanup TERM
trap cleanup INT

speedup_ssh_end() {
    local user=$1
    local host=$2
    local port=$3
    echo "exit" >&5
    exec 5<&-
    wait
    info_msg "END .........\n"
}
get_vmip() {
    local user=$1
    local host=$2
    local port=$3
    local dom
    local nic
    local name
    local mac
    local protocol
    local address
    declare -A stats
    for dom in $(fake_virsh "${user}@${host}:${port}" list --uuid --all --state-running)
    do
        empty_kv stats
        read_kv stats <<< $(fake_virsh "${user}@${host}:${port}" domstats ${dom} | grep -v "Domain:" | sed "s/^ *//g")
        local os="WINDOW"
        fake_virsh ${user}@${host}:${port} domfsinfo ${dom} | grep --color=never -E -q "ext|jfs|xfs|nfs" && os="LINUX"
        local desc="$(fake_virsh ${user}@${host}:${port} desc ${dom})"
        local maxcpu=$(array_get stats 'vcpu.maximum')
        local cpu=$(array_get stats 'vcpu.current')
        local maxmem=$(array_get stats 'balloon.maximum')
        local mem=$(array_get stats 'balloon.current')
        local storage=0
        for ((i=0;i<$(array_get stats "block.count");i++))
        do
            let storage=storage+$(array_get stats "block.$i.physical")
        done
        mem=$(human_readable_disk_size $(($mem*1024)))
        maxmem=$(human_readable_disk_size $(($maxmem*1024)))
        storage=$(human_readable_disk_size $storage)
        echo -n "${dom},${os},${desc:-NA},${cpu}C,${mem},${maxcpu}C,${maxmem},${storage}|$(array_get stats "block.count"),"
        fake_virsh "${user}@${host}:${port}" domifaddr --source agent --full ${dom} \
            | grep -e "ipv4" \
            | grep -v -e "00:00:00:00:00:00" -e "127.0.0.1" \
            | grep -o "..:..:..:..:..:...*$" \
            | while read mac protocol address; do
                    echo -n "$address,"  # | sed "s/ *//g"
              done
        echo ""
    done
    return 0
}

main() {
#    exec 2> >(tee "error_log_$(date -Iseconds).txt")
    CFG_INI=${1:-}; shift || (exit_msg "conf must input\n";)
    [[ -r "${CFG_INI}" ]] || {
        cat >"${CFG_INI}" <<-EOF
#ip  sshport
10.4.38.2 60022 BJ
10.4.38.3 60022 DL
EOF
        exit_msg "Created ${CFG_INI} using defaults.  Please review it/configure before running again.\n"
    }
    echo "tag,HOSTIP,serial,prod|prd_time|cpus|mems,dom,os,desc,cpu,mem,maxcpu,maxmem,storage|block_count,(address,)*"
    cat "${CFG_INI}" | grep -v -e "^\ *#.*$" -e  "^\ *$" | while read ip port tag; do
        try rm -rf ${ip}.bak
        try mv ${ip} ${ip}.bak
        try mkdir -p ${ip}
        speedup_ssh_begin root "${ip}" ${port}
        try "rsync -avzP -e \"ssh -p${port}\" root@${ip}:/etc/libvirt/qemu ${ip} > /dev/null 2>&1"
        local xml=$(fake_virsh "root@${ip}:${port}" sysinfo)
        local out=$(fake_virsh "root@${ip}:${port}" nodeinfo)
        local manufacturer=$(printf "%s" "$xml" | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='manufacturer']")
        local prod=$(printf "%s" "$xml" | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='product']")
        local serial=$(printf "%s" "$xml"  | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='serial']")
        local dt=$(printf "%s" "$xml"  | xmlstarlet sel -t -v "/sysinfo/bios/entry[@name='date']")
        local cpus=$(printf "$out" | grep "CPU(s):" | awk '{print $2}')
        local mems=$(printf "$out" | grep "Memory size:" | awk '{print $3}')
        let mems=mems*1024
        mems=$(human_readable_disk_size $mems)
        # for it in $(fake_virsh "root@${ip}:${port}" pool-list --all --name)
        # do
        #     echo "${ip}  pool  $it"
        # done
        # for it in $(fake_virsh "root@${ip}:${port}" net-list --all --name)
        # do
        #     echo "${ip}  net   $it"
        # done
        get_vmip root "${ip}" ${port} | while read -r line; do
            echo "${tag},${ip},${serial},${manufacturer} ${prod}|${dt}|${cpus}C|${mems},$line"
        done 

        speedup_ssh_end root "${ip}" ${port}
    done
    #find . -type d -name networks | xargs -i@ rm -rf @
    #find . -type d -name autostart| xargs -i@ rm -rf @
    return 0
}
main "$@"


