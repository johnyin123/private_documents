#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
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
        local maxcpu=$(array_get stats 'vcpu.maximum')
        local cpu=$(array_get stats 'vcpu.current')
        local maxmem=$(array_get stats 'balloon.maximum')
        local mem=$(array_get stats 'balloon.current')
        local storage=0
        for ((i=0;i<$(array_get stats "block.count");i++))
        do
            let storage=storage+$(array_get stats "block.$i.capacity")
        done
        mem=$(human_readable_disk_size $(($mem*1024)))
        maxmem=$(human_readable_disk_size $(($maxmem*1024)))
        storage=$(human_readable_disk_size $storage)
        echo -n "${dom},${cpu}C,${mem},${maxcpu}C,${maxmem},${storage}|$(array_get stats "block.count"),"
        fake_virsh "${user}@${host}:${port}" domifaddr --source agent --full ${dom} \
            | grep -e "ipv4" \
            | grep -v -e "00:00:00:00:00:00" -e "127.0.0.1" \
            | while read name mac protocol address; do
                    echo -n "$name|$address|$mac,"  # | sed "s/ *//g"
              done
        echo ""
    done
    return 0
}

main() {
    #BJ PROD
    local node="10.4.38.2 10.4.38.3 10.4.38.4 10.4.38.5 10.4.38.6 10.4.38.7 10.4.38.8 10.4.38.9 10.4.38.10 10.4.38.11 10.4.38.12 10.4.38.13  10.4.38.14 10.4.38.15"
    #DL XK/ZB
    node="$node 10.5.38.100 10.5.38.101 10.5.38.102 10.5.38.103 10.5.38.104 10.5.38.105 10.5.38.106 10.5.38.107"
    #BJ BIGDATA
    node="$node 10.3.60.2 10.3.60.3 10.3.60.4 10.3.60.5 10.3.60.6 10.3.60.7 10.3.60.8"
    echo "HOSTIP,serial,prod|prd_time|cpus|mems,dom,cpu,mem,maxcpu,maxmem,storage|block_count,(name|address|mac,)*"
    for n in ${node}
    do
        rm -rf ${n}
        mkdir -p ${n}
        speedup_ssh_begin root "${n}" 60022
        try "rsync -avzP -e \"ssh -p60022\" root@${n}:/etc/libvirt/qemu ${n} > /dev/null 2>&1"
        local xml=$(fake_virsh "root@${n}:60022" sysinfo)
        local out=$(fake_virsh "root@${n}:60022" nodeinfo)
        local manufacturer=$(printf "%s" "$xml" | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='manufacturer']")
        local prod=$(printf "%s" "$xml" | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='product']")
        local serial=$(printf "%s" "$xml"  | xmlstarlet sel -t -v "/sysinfo/system/entry[@name='serial']")
        local dt=$(printf "%s" "$xml"  | xmlstarlet sel -t -v "/sysinfo/bios/entry[@name='date']")
        local cpus=$(printf "$out" | grep "CPU(s):" | awk '{print $2}')
        local mems=$(printf "$out" | grep "Memory size:" | awk '{print $3}')
        let mems=mems*1024
        mems=$(human_readable_disk_size $mems)
        # for it in $(fake_virsh "root@${n}:60022" pool-list --all --name)
        # do
        #     echo "${n}  pool  $it"
        # done
        # for it in $(fake_virsh "root@${n}:60022" net-list --all --name)
        # do
        #     echo "${n}  net   $it"
        # done
        get_vmip root "${n}" 60022 | while read -r line; do
            echo "${n},${serial},${manufacturer} ${prod}|${dt}|${cpus}C|${mems},$line"
        done 

        speedup_ssh_end root "${n}" 60022
    done
    find . -type d -name networks | xargs -i@ rm -rf @
    find . -type d -name autostart| xargs -i@ rm -rf @
    return 0
}
main "$@"


