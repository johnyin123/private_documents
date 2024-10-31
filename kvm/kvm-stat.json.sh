#!/usr/bin/env bash
fname=${1:? must input}
{
echo "### Overview"
echo "|指标|数值|"
echo "|:-|-:|"
echo "|ARM物理机|$(cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-arm"))' | jq -s length)|"
echo "|ARM物理CPU|$(cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-arm"))' | jq '.totalcpu' | awk '{sum+=$1} END{print sum;}')|"
echo "|ARM物理MEM|$(cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-arm"))' | jq '.totalmem' | awk '{sum+=$1} END{print sum;}')|"
echo "|X86物理机|$(cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-x86"))' | jq -s length)|"
echo "|X86物理CPU|$(cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-x86"))' | jq '.totalcpu' | awk '{sum+=$1} END{print sum;}')|"
echo "|X86物理MEM|$(cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-x86"))' | jq '.totalmem' | awk '{sum+=$1} END{print sum;}')|"
echo "|ARM虚拟机|$(cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-arm"))' | jq '.totalvm' | awk '{sum+=$1} END{print sum;}')|"
echo "|ARM虚拟机CPU|$(cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-arm"))' | jq '.curcpu' | awk '{sum+=$1} END{print sum;}')|"
echo "|ARM虚拟机MEM|$(cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-arm"))' | jq '.curmem' | awk '{sum+=$1} END{print sum;}')|"
echo "|ARM虚拟机DISK|$(cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-arm"))' | jq '.capblk' | awk '{sum+=$1} END{print sum;}')|"
echo "|X86虚拟机|$(cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-x86"))' | jq '.totalvm' | awk '{sum+=$1} END{print sum;}')|"
echo "|X86虚拟机CPU|$(cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-x86"))' | jq '.curcpu' | awk '{sum+=$1} END{print sum;}')|"
echo "|X86虚拟机MEM|$(cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-x86"))' | jq '.curmem' | awk '{sum+=$1} END{print sum;}')|"
echo "|X86虚拟机DISK|$(cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-x86"))' | jq '.capblk' | awk '{sum+=$1} END{print sum;}')|"
# jq '.hosts | .[] | {uri, totalvm}'
# cat ${fname} | jq -cr '.hosts | .[] | .uri, .totalvm'
echo "### 物理机统计"
echo "|IP地址|VM数量|"
echo "|:-|-:|"
for srv in $(cat ${fname} | jq -cr '.hosts | .[] | .uri'); do
    echo "|${srv}|$(cat ${fname} | jq ".hosts[] | select(.uri | startswith(\"$srv\"))" | jq '.totalvm')" | sed -e "s|qemu+ssh://root@||g"  -e "s|:60022/system||g"
done
} | pandoc --pdf-engine wkhtmltopdf -o ${fname}.pdf
