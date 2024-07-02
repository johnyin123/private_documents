#!/usr/bin/env bash
fname=${1:? must input}

echo -n "ARM物理机："
cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-arm"))' | jq -s length
echo -n "ARM物理CPU："
cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-arm"))' | jq '.totalcpu' | awk '{sum+=$1} END{print sum;}'
echo -n "ARM物理MEM(MiB)："
cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-arm"))' | jq '.totalmem' | awk '{sum+=$1} END{print sum;}'
echo -n "X86物理机："
cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-x86"))' | jq -s length
echo -n "X86物理CPU："
cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-x86"))' | jq '.totalcpu' | awk '{sum+=$1} END{print sum;}'
echo -n "X86物理MEM(MiB)："
cat ${fname} | jq '.hosts[] | select(.name | startswith("kvm-x86"))' | jq '.totalmem' | awk '{sum+=$1} END{print sum;}'
echo -n "ARM虚拟机："
cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-arm"))' | jq '.totalvm' | awk '{sum+=$1} END{print sum;}'
echo -n "ARM虚拟机CPU："
cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-arm"))' | jq '.curcpu' | awk '{sum+=$1} END{print sum;}'
echo -n "ARM虚拟机MEM(MiB)："
cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-arm"))' | jq '.curmem' | awk '{sum+=$1} END{print sum;}'
echo -n "ARM虚拟机DISK(MiB)："
cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-arm"))' | jq '.capblk' | awk '{sum+=$1} END{print sum;}'
echo -n "X86虚拟机："
cat ${fname} | jq '.hosts | .[] | select(.name | startswith("kvm-x86"))' | jq '.totalvm' | awk '{sum+=$1} END{print sum;}'
echo -n "X86虚拟机CPU："
cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-x86"))' | jq '.curcpu' | awk '{sum+=$1} END{print sum;}'
echo -n "X86虚拟机MEM(MiB)："
cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-x86"))' | jq '.curmem' | awk '{sum+=$1} END{print sum;}'
echo -n "X86虚拟机DISK(MiB)："
cat ${fname} | jq '.vms[] | select(.host | startswith("kvm-x86"))' | jq '.capblk' | awk '{sum+=$1} END{print sum;}'
# jq '.hosts | .[] | {uri, totalvm}'
cat ${fname} | jq '.hosts | .[] | .uri, .totalvm'
