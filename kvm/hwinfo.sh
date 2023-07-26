#!/usr/bin/env bash
VIRSH_OPT="-k 300 -K 5 -q"
LC_ALL=C
LANG=C
fake_virsh() {
    local usr_srv_port=$1;shift 1
    virsh -c qemu+ssh://${usr_srv_port}/system ${VIRSH_OPT} ${*}
}
cat all.ini | grep -v -e "^\ *#.*$" -e  "^\ *$" | while read ip port tag; do
    echo -n "${ip}   "
    fake_virsh  "root@${ip}:${port}" nodeinfo
done | awk -F: '/CPU model:/  { printf("ipaddr   %s",$2) } /CPU\(s\):/ { printf("%s",$2) } /Memory size:/ {  printf("%s\n",$2) }' | awk '{cpu[$2]+=$3; mem[$2]+=$4} END { for(j in cpu) printf("CPU %s: %d\n", j, cpu[j]); for(j in cpu) printf("MEM %s: %dGiB\n", j, mem[j]/1024/1024) }'

