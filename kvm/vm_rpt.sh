#!/usr/bin/env bash

amdvcpu=$(awk -F, '/AMD64/{sum+=$8} END{print sum;} ' ${1})
amdvmem=$(awk -F, '/AMD64/{sum+=$9} END{print sum;} ' ${1})
armvcpu=$(awk -F, '/ARM64/{sum+=$8} END{print sum;} ' ${1})
armvmem=$(awk -F, '/ARM64/{sum+=$9} END{print sum;} ' ${1})
X86CPU=$(awk -F, '{print $1 $2 $4}' ${1} | sort | uniq | awk -F'|' '/AMD64/{sum+=$3} END{print sum;} ' ${1})
X86MEM=$(awk -F, '{print $1 $2 $4}' ${1} | sort | uniq | awk -F'|' '/AMD64/{sum+=$4} END{print sum;} ' ${1})
ARMCPU=$(awk -F, '{print $1 $2 $4}' ${1} | sort | uniq | awk -F'|' '/ARM64/{sum+=$3} END{print sum;} ' ${1})
ARMMEM=$(awk -F, '{print $1 $2 $4}' ${1} | sort | uniq | awk -F'|' '/ARM64/{sum+=$4} END{print sum;} ' ${1})
echo "X86物理机CPU: ${X86CPU}C 内存: ${X86MEM}G"
echo "ARM物理机CPU: ${ARMCPU}C 内存: ${ARMMEM}G"
echo "X86虚拟机CPU: ${amdvcpu}C 内存: ${amdvmem}G"
echo "ARM虚拟机CPU: ${armvcpu}C 内存: ${armvmem}G"
echo "物理机IP    : 虚拟机数量"
for key in $(tail -n +2 ${1} | awk -F, '{print $2}' | sort -t. -k 3,3n -k 4,4n | uniq); do
    echo -n "$key ："
    grep ",${key}," ${1} | wc -l
done

